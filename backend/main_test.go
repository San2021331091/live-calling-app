package main

import (
	"encoding/json"
	"testing"
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

	hub.broadcast("chat", message{ID: "message", SenderID: "sender"})
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
			if event.Type != "message" || event.Message.IsMe != test.isMe {
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
