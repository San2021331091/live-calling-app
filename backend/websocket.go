package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/gorilla/websocket"
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
	payload, _ := json.Marshal(map[string]string{"type": "error", "error": message})
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

func (a *application) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if token == "" {
		token = strings.TrimSpace(r.URL.Query().Get("access_token"))
	}
	userID, err := a.userIDFromToken(token)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	chatID := r.PathValue("chatID")
	if !uuidPattern.MatchString(chatID) {
		writeError(w, http.StatusBadRequest, "invalid chat ID")
		return
	}
	if err := a.requireChatMember(r.Context(), chatID, userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusForbidden, "you are not a member of this chat")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not check chat membership")
		return
	}

	upgrader := websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin:     func(r *http.Request) bool { return a.originAllowed(r.Header.Get("Origin")) },
	}
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	client := &wsClient{
		chatID: chatID,
		userID: userID,
		conn:   conn,
		send:   make(chan []byte, 32),
	}
	a.hub.register(client)
	defer func() {
		a.hub.unregister(client)
		_ = conn.Close()
	}()

	go client.writePump()
	conn.SetReadLimit(1 << 20)
	_ = conn.SetReadDeadline(time.Now().Add(pongTimeout))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongTimeout))
	})

	for {
		var incoming struct {
			Type    string `json:"type"`
			Content string `json:"content"`
		}
		if err := conn.ReadJSON(&incoming); err != nil {
			break
		}
		if incoming.Type != "message" {
			a.hub.sendError(client, "unsupported WebSocket event")
			continue
		}
		content := strings.TrimSpace(incoming.Content)
		if content == "" || utf8.RuneCountInString(content) > maxMessageRunes {
			a.hub.sendError(client, "message must contain 1 to 5000 characters")
			continue
		}
		var saved message
		err := a.db.QueryRowContext(r.Context(),
			`INSERT INTO messages (chat_id, sender_id, content)
			 VALUES ($1, $2, $3)
			 RETURNING id::text, chat_id::text, sender_id::text, content, created_at`,
			chatID, userID, content,
		).Scan(&saved.ID, &saved.ChatID, &saved.SenderID, &saved.Content, &saved.CreatedAt)
		if err != nil {
			a.hub.sendError(client, "message could not be saved")
			continue
		}
		err = a.db.QueryRowContext(r.Context(),
			`SELECT display_name FROM users WHERE id = $1`,
			userID,
		).Scan(&saved.Sender)
		if err != nil {
			a.hub.sendError(client, "message could not be delivered")
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
