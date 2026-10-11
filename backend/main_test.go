package main

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/fasthttp/websocket"
)

func TestConfiguredDatabaseURL(t *testing.T) {
	tests := []struct {
		name     string
		env      string
		dotenv   string
		expected string
	}{
		{name: "environment variable", env: "postgres://env/database", dotenv: "postgres://file/database", expected: "postgres://env/database"},
		{name: "dotenv key value", dotenv: `DATABASE_URL="postgres://file/database"`, expected: "postgres://file/database"},
		{name: "plain postgres URL", dotenv: "postgresql://file/database", expected: "postgresql://file/database"},
		{name: "missing URL", dotenv: "JWT_SECRET=ignored", expected: ""},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := configuredDatabaseURLFrom(test.env, test.dotenv); got != test.expected {
				t.Fatalf("configuredDatabaseURLFrom() = %q, want %q", got, test.expected)
			}
		})
	}
}

func TestNormalizePhone(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
		valid bool
	}{
		{name: "international format", input: "+1 (555) 123-4567", want: "+15551234567", valid: true},
		{name: "digits only", input: "880123456789", want: "+880123456789", valid: true},
		{name: "too short", input: "12345", valid: false},
		{name: "too long", input: "1234567890123456", valid: false},
		{name: "letters", input: "555abc1234", valid: false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, valid := normalizePhone(test.input)
			if got != test.want || valid != test.valid {
				t.Fatalf("normalizePhone(%q) = (%q, %v), want (%q, %v)",
					test.input, got, valid, test.want, test.valid)
			}
		})
	}
}

func TestJWTSubjectValidation(t *testing.T) {
	app := &application{jwtSecret: []byte("test-secret-with-at-least-32-characters")}
	const userID = "123e4567-e89b-42d3-a456-426614174000"

	token, err := app.createToken(userID)
	if err != nil {
		t.Fatalf("createToken() error = %v", err)
	}
	got, err := app.userIDFromToken(token)
	if err != nil {
		t.Fatalf("userIDFromToken() error = %v", err)
	}
	if got != userID {
		t.Fatalf("userIDFromToken() = %q, want %q", got, userID)
	}
	if _, err := app.userIDFromToken(token + "invalid"); err == nil {
		t.Fatal("userIDFromToken() accepted a modified token")
	}
}

func TestMessageHubBroadcast(t *testing.T) {
	hub := newMessageHub()
	first := &wsClient{chatID: "chat", userID: "sender", send: make(chan []byte, 1)}
	second := &wsClient{chatID: "chat", userID: "recipient", send: make(chan []byte, 1)}
	hub.register(first)
	hub.register(second)

	hub.broadcast("chat", message{ID: "message", SenderID: "sender", ClientID: "send-123"})
	for name, test := range map[string]struct {
		client *wsClient
		isMe   bool
	}{
		"first":  {client: first, isMe: true},
		"second": {client: second, isMe: false},
	} {
		select {
		case payload := <-test.client.send:
			var event struct {
				Type    string  `json:"type"`
				Message message `json:"message"`
			}
			if err := json.Unmarshal(payload, &event); err != nil {
				t.Fatalf("%s client received invalid JSON: %v", name, err)
			}
			if event.Type != "message" || event.Message.IsMe != test.isMe || event.Message.ClientID != "send-123" {
				t.Fatalf("%s client received incorrect event: %#v", name, event)
			}
		default:
			t.Fatalf("%s client did not receive broadcast", name)
		}
	}

	hub.unregister(first)
	hub.broadcast("chat", message{ID: "next", SenderID: "sender"})
	var event struct {
		Type    string  `json:"type"`
		Message message `json:"message"`
	}
	if err := json.Unmarshal(<-second.send, &event); err != nil {
		t.Fatalf("remaining client received invalid JSON: %v", err)
	}
	if event.Message.ID != "next" || event.Message.IsMe {
		t.Fatalf("remaining client received incorrect event: %#v", event)
	}
}

func TestChatWebSocketRouteUpgradesConnection(t *testing.T) {
	const (
		userID = "123e4567-e89b-42d3-a456-426614174000"
		chatID = "123e4567-e89b-42d3-a456-426614174001"
	)
	app := &application{
		db:        sql.OpenDB(websocketMemberConnector{}),
		jwtSecret: []byte("test-secret-with-at-least-32-characters"),
		hub:       newMessageHub(),
	}
	t.Cleanup(func() { _ = app.db.Close() })

	token, err := app.createToken(userID)
	if err != nil {
		t.Fatalf("createToken() error = %v", err)
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen() error = %v", err)
	}
	server := app.routes()
	go func() { _ = server.Listener(listener) }()
	t.Cleanup(func() { _ = server.Shutdown() })

	headers := make(http.Header)
	headers.Set("Authorization", "Bearer "+token)
	dialer := websocket.Dialer{HandshakeTimeout: 2 * time.Second}
	url := "ws://" + listener.Addr().String() + "/ws/" + chatID
	conn, response, err := dialer.Dial(url, headers)
	if err != nil {
		if response != nil {
			t.Fatalf("WebSocket handshake returned %s: %v", response.Status, err)
		}
		t.Fatalf("WebSocket handshake error = %v", err)
	}
	_ = conn.Close()
}

type websocketMemberConnector struct{}

func (websocketMemberConnector) Connect(context.Context) (driver.Conn, error) {
	return websocketMemberConn{}, nil
}

func (websocketMemberConnector) Driver() driver.Driver {
	return websocketMemberDriver{}
}

type websocketMemberDriver struct{}

func (websocketMemberDriver) Open(string) (driver.Conn, error) {
	return websocketMemberConn{}, nil
}

type websocketMemberConn struct{}

func (websocketMemberConn) Prepare(string) (driver.Stmt, error) {
	return nil, errors.New("unexpected prepared statement")
}

func (websocketMemberConn) Close() error { return nil }

func (websocketMemberConn) Begin() (driver.Tx, error) {
	return nil, errors.New("unexpected transaction")
}

func (websocketMemberConn) QueryContext(
	context.Context,
	string,
	[]driver.NamedValue,
) (driver.Rows, error) {
	return &websocketMemberRows{}, nil
}

type websocketMemberRows struct {
	read bool
}

func (*websocketMemberRows) Columns() []string { return []string{"member"} }

func (*websocketMemberRows) Close() error { return nil }

func (rows *websocketMemberRows) Next(values []driver.Value) error {
	if rows.read {
		return io.EOF
	}
	rows.read = true
	values[0] = true
	return nil
}

func TestDeleteCORSPreflight(t *testing.T) {
	app := &application{}
	app.configureOrigins("https://voxa.example")
	request := httptest.NewRequest(http.MethodOptions, "/api/statuses/example", nil)
	request.Header.Set("Origin", "https://voxa.example")
	request.Header.Set("Access-Control-Request-Method", http.MethodDelete)
	response, err := app.routes().Test(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", response.StatusCode)
	}
	if !strings.Contains(response.Header.Get("Access-Control-Allow-Methods"), "DELETE") {
		t.Fatal("delete requests are blocked by CORS preflight")
	}
}

func TestMessageHubCorrelatesRejectedSend(t *testing.T) {
	hub := newMessageHub()
	client := &wsClient{chatID: "chat", userID: "user", send: make(chan []byte, 1)}
	hub.register(client)
	defer hub.unregister(client)
	hub.sendRequestError(client, "could not save", "client-123")
	var event map[string]string
	if err := json.Unmarshal(<-client.send, &event); err != nil {
		t.Fatal(err)
	}
	if event["client_id"] != "client-123" || event["type"] != "error" {
		t.Fatalf("uncorrelated error: %v", event)
	}
}

func TestChatWebSocketRejectsNonUpgradeRequest(t *testing.T) {
	app := &application{
		jwtSecret: []byte("test-secret-with-at-least-32-characters"),
		hub:       newMessageHub(),
	}
	request := httptest.NewRequest(
		http.MethodGet,
		"/ws/123e4567-e89b-42d3-a456-426614174001",
		nil,
	)
	response, err := app.routes().Test(request)
	if err != nil {
		t.Fatalf("route test error = %v", err)
	}
	if response.StatusCode != http.StatusUpgradeRequired {
		t.Fatalf("status = %d, want %d", response.StatusCode, http.StatusUpgradeRequired)
	}
}

func TestCORSPreflightAllowsDeletingStatusesAndGroups(t *testing.T) {
	app := &application{}
	request := httptest.NewRequest(http.MethodOptions, "/api/statuses/status-id", nil)
	request.Header.Set("Origin", "http://localhost:3000")
	request.Header.Set("Access-Control-Request-Method", "DELETE")
	response, err := app.routes().Test(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		t.Fatalf("status = %d", response.StatusCode)
	}
	if !strings.Contains(response.Header.Get("Access-Control-Allow-Methods"), "DELETE") {
		t.Fatal("DELETE is missing from allowed methods")
	}
}

func TestMessageRejectionIncludesClientID(t *testing.T) {
	hub := newMessageHub()
	client := &wsClient{chatID: "chat", userID: "sender", send: make(chan []byte, 1)}
	hub.register(client)
	hub.sendRequestError(client, "message could not be saved", "send-123")
	var event map[string]string
	if err := json.Unmarshal(<-client.send, &event); err != nil {
		t.Fatal(err)
	}
	if event["type"] != "error" || event["client_id"] != "send-123" {
		t.Fatalf("incorrect rejection: %v", event)
	}
	hub.unregister(client)
}
