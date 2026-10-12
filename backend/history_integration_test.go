package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"github.com/fasthttp/websocket"
	"github.com/joho/godotenv"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
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
	if _, err = db.Exec(`INSERT INTO messages(chat_id,sender_id,content,created_at) VALUES($1,$2,'After clearing',clock_timestamp())`, chatID, ids[1]); err != nil {
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

	if request(app.handleDeleteInboxChat, "DELETE", "/", ids[2], "").Code != 403 {
		t.Fatal("non-member deleted chat")
	}
	if request(app.handleDeleteInboxChat, "DELETE", "/", ids[0], "").Code != 200 {
		t.Fatal("inbox delete failed")
	}
	w = request(app.handleListChats, "GET", "/", ids[0], "")
	if err = json.Unmarshal(w.Body.Bytes(), &listing); err != nil || len(listing.Chats) != 0 {
		t.Fatal("deleted chat remains in inbox")
	}
	w = request(app.handleListChats, "GET", "/", ids[1], "")
	if err = json.Unmarshal(w.Body.Bytes(), &listing); err != nil || len(listing.Chats) != 1 {
		t.Fatal("delete removed peer's chat")
	}
	if len(history(ids[0], "")) != 0 {
		t.Fatal("delete retained old history")
	}
	app.jwtSecret = []byte("private-regression-test-secret")
	routes := app.routes()
	token, err := app.createToken(ids[0])
	if err != nil {
		t.Fatal(err)
	}
	for _, filename := range []string{"report.pdf", "notes.txt", "archive.zip"} {
		prefix := "%PDF-1.7\n"
		if filename == "notes.txt" {
			prefix = "Document regression text\n"
		}
		if filename == "archive.zip" {
			prefix = "PK\x03\x04"
		}
		payload := append([]byte(prefix), bytes.Repeat([]byte("x"), 2<<20)...)
		var body bytes.Buffer
		form := multipart.NewWriter(&body)
		part, err := form.CreateFormFile("file", filename)
		if err != nil {
			t.Fatal(err)
		}
		part.Write(payload)
		form.Close()
		r := httptest.NewRequest("POST", "/api/files", &body)
		r.Header.Set("Content-Type", form.FormDataContentType())
		r = r.WithContext(context.WithValue(r.Context(), userIDContextKey, ids[0]))
		r.Header.Set("Authorization", "Bearer "+token)
		response, err := routes.Test(r, -1)
		if err != nil {
			t.Fatal(err)
		}
		uploaded := httptest.NewRecorder()
		uploaded.Code = response.StatusCode
		uploaded.Body.ReadFrom(response.Body)
		response.Body.Close()
		if uploaded.Code != 201 {
			t.Fatalf("upload failed: %s", uploaded.Body.String())
		}
		var result struct {
			URL string `json:"media_url"`
		}
		if err := json.Unmarshal(uploaded.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		link, err := url.Parse(result.URL)
		if err != nil {
			t.Fatal(err)
		}
		get := httptest.NewRequest("GET", result.URL, nil)
		get.SetPathValue("fileID", strings.TrimPrefix(link.Path, "/api/files/"))
		downloaded := httptest.NewRecorder()
		app.handleDownloadFile(downloaded, get)
		if downloaded.Code != 200 || !bytes.Equal(downloaded.Body.Bytes(), payload) {
			t.Fatal("file roundtrip lost bytes")
		}
		get.URL.RawQuery = "key=invalid"
		denied := httptest.NewRecorder()
		app.handleDownloadFile(denied, get)
		if denied.Code != 403 {
			t.Fatal("invalid file key accepted")
		}
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() { _ = routes.Listener(listener) }()
	defer routes.Shutdown()
	headers := http.Header{"Authorization": {"Bearer " + token}}
	connection, _, err := websocket.DefaultDialer.Dial("ws://"+listener.Addr().String()+"/ws/"+chatID, headers)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if err = connection.WriteJSON(map[string]string{"type": "message", "content": "After inbox deletion", "client_id": "regression-resurface"}); err != nil {
		t.Fatal(err)
	}
	connection.SetReadDeadline(time.Now().Add(10 * time.Second))
	var event map[string]any
	if err = connection.ReadJSON(&event); err != nil {
		t.Fatal(err)
	}
	if event["type"] != "message" {
		t.Fatalf("message was not saved: %v", event)
	}
	var hidden bool
	if err = db.QueryRow(`SELECT hidden FROM chat_members WHERE chat_id=$1 AND user_id=$2`, chatID, ids[0]).Scan(&hidden); err != nil || hidden {
		t.Fatal("new message did not restore inbox chat")
	}
	connection.Close()
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
