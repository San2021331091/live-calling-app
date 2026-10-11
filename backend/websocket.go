package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/fasthttp/websocket"
	"github.com/gofiber/fiber/v2"
	fiberwebsocket "github.com/gofiber/websocket/v2"
)

const (
	maxMessageRunes = 5000
	writeTimeout    = 10 * time.Second
	pongTimeout     = 60 * time.Second
	pingInterval    = 50 * time.Second
)

type wsClient struct {
	chatID string
	userID string
	conn   *websocket.Conn
	send   chan []byte
}

type messageHub struct {
	mu      sync.Mutex
	clients map[string]map[*wsClient]struct{}
}

func newMessageHub() *messageHub {
	return &messageHub{clients: make(map[string]map[*wsClient]struct{})}
}

func (h *messageHub) register(client *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[client.chatID] == nil {
		h.clients[client.chatID] = make(map[*wsClient]struct{})
	}
	h.clients[client.chatID][client] = struct{}{}
}

func (h *messageHub) unregister(client *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if members := h.clients[client.chatID]; members != nil {
		if _, exists := members[client]; exists {
			delete(members, client)
			close(client.send)
		}
		if len(members) == 0 {
			delete(h.clients, client.chatID)
		}
	}
}

func (h *messageHub) closeChat(chatID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	members := h.clients[chatID]
	delete(h.clients, chatID)
	for client := range members {
		close(client.send)
	}
}

func (h *messageHub) broadcast(chatID string, saved message) {
	h.mu.Lock()
	defer h.mu.Unlock()
	members := h.clients[chatID]
	for client := range members {
		saved.IsMe = saved.SenderID == client.userID
		payload, err := json.Marshal(map[string]any{"type": "message", "message": saved})
		if err != nil {
			continue
		}
		select {
		case client.send <- payload:
		default:
			delete(members, client)
			close(client.send)
		}
	}
	if len(members) == 0 {
		delete(h.clients, chatID)
	}
}

func (h *messageHub) sendError(client *wsClient, message string) {
	h.sendRequestError(client, message, "")
}

func (h *messageHub) historyCleared(chatID, userID string, cutoff time.Time) {
	payload, _ := json.Marshal(map[string]any{"type": "history_cleared", "cleared_before": cutoff})
	h.mu.Lock()
	defer h.mu.Unlock()
	for client := range h.clients[chatID] {
		if client.userID == userID {
			select {
			case client.send <- payload:
			default:
			}
		}
	}
}

func (h *messageHub) sendRequestError(client *wsClient, message, clientID string) {
	payload, _ := json.Marshal(map[string]string{"type": "error", "error": message, "client_id": clientID})
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, connected := h.clients[client.chatID][client]; !connected {
		return
	}
	select {
	case client.send <- payload:
	default:
	}
}

func (a *application) authorizeChatWebSocket(c *fiber.Ctx) error {
	if !fiberwebsocket.IsWebSocketUpgrade(c) {
		return c.Status(fiber.StatusUpgradeRequired).JSON(apiError{Error: "WebSocket upgrade required"})
	}
	token := strings.TrimSpace(strings.TrimPrefix(c.Get("Authorization"), "Bearer "))
	if token == "" {
		token = strings.TrimSpace(c.Query("access_token"))
	}
	userID, err := a.userIDFromToken(token)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(apiError{Error: "authentication required"})
	}
	chatID := c.Params("chatID")
	if !uuidPattern.MatchString(chatID) {
		return c.Status(fiber.StatusBadRequest).JSON(apiError{Error: "invalid chat ID"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), writeTimeout)
	defer cancel()
	if err := a.requireChatMember(ctx, chatID, userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.Status(fiber.StatusForbidden).JSON(apiError{Error: "you are not a member of this chat"})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(apiError{Error: "could not check chat membership"})
	}

	c.Locals("chatID", chatID)
	c.Locals("userID", userID)
	return c.Next()
}

func (a *application) handleWebSocket(conn *fiberwebsocket.Conn) {
	chatID := conn.Params("chatID")
	userID, ok := conn.Locals("userID").(string)
	if !ok || userID == "" {
		return
	}
	client := &wsClient{
		chatID: chatID,
		userID: userID,
		conn:   conn.Conn,
		send:   make(chan []byte, 32),
	}
	a.hub.register(client)
	writerDone := make(chan struct{})
	defer func() {
		a.hub.unregister(client)
		<-writerDone
		_ = conn.Close()
	}()

	go func() {
		defer close(writerDone)
		client.writePump()
	}()
	conn.SetReadLimit(1 << 20)
	_ = conn.SetReadDeadline(time.Now().Add(pongTimeout))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongTimeout))
	})

	for {
		var incoming struct {
			Type     string `json:"type"`
			Content  string `json:"content"`
			ClientID string `json:"client_id"`
		}
		if err := conn.ReadJSON(&incoming); err != nil {
			break
		}
		if incoming.Type != "message" {
			a.hub.sendRequestError(client, "unsupported WebSocket event", incoming.ClientID)
			continue
		}
		content := strings.TrimSpace(incoming.Content)
		if content == "" || utf8.RuneCountInString(content) > maxMessageRunes {
			a.hub.sendRequestError(client, "message must contain 1 to 5000 characters", incoming.ClientID)
			continue
		}
		if len(incoming.ClientID) > 100 {
			a.hub.sendError(client, "invalid client message ID")
			continue
		}
		var saved message
		saved.ClientID = incoming.ClientID
		ctx, cancel := context.WithTimeout(context.Background(), writeTimeout)
		err := a.db.QueryRowContext(ctx,
			`INSERT INTO messages (chat_id, sender_id, content)
			 VALUES ($1, $2, $3)
			 RETURNING id::text, chat_id::text, sender_id::text, content, created_at`,
			chatID, userID, content,
		).Scan(&saved.ID, &saved.ChatID, &saved.SenderID, &saved.Content, &saved.CreatedAt)
		cancel()
		if err != nil {
			a.hub.sendRequestError(client, "message could not be saved", incoming.ClientID)
			continue
		}
		ctx, cancel = context.WithTimeout(context.Background(), writeTimeout)
		err = a.db.QueryRowContext(ctx,
			`SELECT display_name FROM users WHERE id = $1`,
			userID,
		).Scan(&saved.Sender)
		cancel()
		if err != nil {
			a.hub.sendRequestError(client, "message could not be delivered", incoming.ClientID)
			continue
		}
		saved.IsMe = true
		a.hub.broadcast(chatID, saved)
	}
}

func (c *wsClient) writePump() {
	ticker := time.NewTicker(pingInterval)
	defer func() {
		ticker.Stop()
		_ = c.conn.Close()
	}()

	for {
		select {
		case payload, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeTimeout))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, payload); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeTimeout))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
