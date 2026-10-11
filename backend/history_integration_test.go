package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"github.com/joho/godotenv"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

// Uses one private PostgreSQL session and rolls back every fixture and edit.
func TestChatHistoryIntegration(t *testing.T) {
	if os.Getenv("VOXA_INTEGRATION_TEST") != "1" {
		t.Skip("set VOXA_INTEGRATION_TEST=1 to test PostgreSQL")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("could not load database configuration")
	}
	db, err := sql.Open("pgx", values["DATABASE_URL"])
	if err != nil {
		t.Fatal("could not configure database")
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	// A single pool connection keeps the SQL transaction private to this test.
	if _, err = db.Exec("BEGIN"); err != nil {
		t.Fatal("could not begin test transaction")
	}
	defer db.Exec("ROLLBACK")
	app := &application{db: db, hub: newMessageHub()}
	ids := []string{"123e4567-e89b-42d3-a456-426614174080", "123e4567-e89b-42d3-a456-426614174081", "123e4567-e89b-42d3-a456-426614174082"}
	for index, id := range ids {
		_, err = db.Exec(`INSERT INTO users(id,display_name,phone,password_hash) VALUES($1,'Regression test',$2,'test-only')`, id, "+99000000"+string(rune('0'+index)))
		if err != nil {
			t.Fatal("could not create isolated test user", err)
		}
	}
	const chatID = "123e4567-e89b-42d3-a456-426614174083"
	_, err = db.Exec(`INSERT INTO chats(id,kind,title,created_by) VALUES($1,'group','Before rename',$2)`, chatID, ids[0])
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range ids[:2] {
		if _, err = db.Exec(`INSERT INTO chat_members(chat_id,user_id) VALUES($1,$2)`, chatID, id); err != nil {
			t.Fatal(err)
		}
	}
	_, err = db.Exec(`INSERT INTO messages(chat_id,sender_id,content,created_at) SELECT $1,$2,'Saved message ' || n,clock_timestamp() - interval '1 day' + n * interval '1 second' FROM generate_series(1,105) n`, chatID, ids[1])
	if err != nil {
		t.Fatal(err)
	}
	request := func(handler http.HandlerFunc, method, path, user, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		r.SetPathValue("chatID", chatID)
		r = r.WithContext(context.WithValue(r.Context(), userIDContextKey, user))
		w := httptest.NewRecorder()
		handler(w, r)
		return w
	}
	history := func(user, cursor string) []message {
		path := "/?before_id=" + cursor
		w := request(app.handleMessages, "GET", path, user, "")
		if w.Code != 200 {
			t.Fatalf("history status %d: %s", w.Code, w.Body.String())
		}
		var result struct {
			Messages []message `json:"messages"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		return result.Messages
	}
	page := history(ids[0], "")
	if len(page) != 100 || len(history(ids[0], page[0].ID)) != 5 {
		t.Fatal("history pagination lost messages")
	}
	w := request(app.handleUpdateGroupChat, "PATCH", "/", ids[0], `{"name":"Renamed group"}`)
	if w.Code != 200 {
		t.Fatalf("rename failed: %s", w.Body.String())
	}
	var name string
	if err = db.QueryRow(`SELECT title FROM chats WHERE id=$1`, chatID).Scan(&name); err != nil || name != "Renamed group" {
		t.Fatal("group rename did not persist")
	}
	if request(app.handleUpdateGroupChat, "PATCH", "/", ids[1], `{"name":"Unauthorized"}`).Code != 403 {
		t.Fatal("non-creator renamed group")
	}
	if request(app.handleClearChatHistory, "DELETE", "/", ids[2], "").Code != 403 {
		t.Fatal("non-member cleared history")
	}
	if request(app.handleClearChatHistory, "DELETE", "/", ids[0], "").Code != 200 {
		t.Fatal("clear failed")
	}
	if len(history(ids[0], "")) != 0 || len(history(ids[1], "")) != 100 {
		t.Fatal("clear affected the wrong user's history")
	}
	if request(app.handleChatPreferences, "PATCH", "/", ids[0], `{"muted":true}`).Code != 200 {
		t.Fatal("mute did not save")
	}
	var muted bool
	if err = db.QueryRow(`SELECT muted FROM chat_members WHERE chat_id=$1 AND user_id=$2`, chatID, ids[0]).Scan(&muted); err != nil || !muted {
		t.Fatal("mute not persisted")
	}
	if _, err = db.Exec(`INSERT INTO messages(chat_id,sender_id,content,created_at) VALUES($1,$2,'After clearing',clock_timestamp()+interval '1 second')`, chatID, ids[1]); err != nil {
		t.Fatal(err)
	}
	if len(history(ids[0], "")) != 1 {
		t.Fatal("clear hid new messages")
	}
	w = request(app.handleListChats, "GET", "/", ids[0], "")
	if w.Code != 200 {
		t.Fatalf("chat listing failed: %s", w.Body.String())
	}
	var listing struct {
		Chats []chat `json:"chats"`
	}
	if err = json.Unmarshal(w.Body.Bytes(), &listing); err != nil {
		t.Fatal(err)
	}
	if len(listing.Chats) != 1 || listing.Chats[0].Name != "Renamed group" || !listing.Chats[0].Muted || listing.Chats[0].CurrentMessage != "After clearing" {
		t.Fatal("chat summary or preferences are stale")
	}
	hub := newMessageHub()
	own := &wsClient{chatID: chatID, userID: ids[0], send: make(chan []byte, 1)}
	peer := &wsClient{chatID: chatID, userID: ids[1], send: make(chan []byte, 1)}
	hub.register(own)
	hub.register(peer)
	defer hub.unregister(own)
	defer hub.unregister(peer)
	hub.historyCleared(chatID, ids[0], time.Now())
	if len(own.send) != 1 || len(peer.send) != 0 {
		t.Fatal("clear event leaked to another participant")
	}
}
