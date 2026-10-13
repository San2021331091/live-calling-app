package backend

import (
	"database/sql"
	"encoding/json"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/joho/godotenv"
)

// Only temporary users/chats are touched; cleanup deletes exactly these fixtures.
func TestHTTPChatIntegration(t *testing.T) {
	if os.Getenv("VOXA_INTEGRATION_TEST") != "1" {
		t.Skip("set VOXA_INTEGRATION_TEST=1")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("configuration unavailable")
	}
	db, err := sql.Open("pgx", values["DATABASE_URL"])
	if err != nil {
		t.Fatal("database unavailable")
	}
	defer db.Close()
	owner, member, outsider, chatID := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	for _, id := range []string{owner, member, outsider} {
		if _, err = db.Exec(`INSERT INTO users(id,display_name,phone,password_hash) VALUES($1,'HTTP chat verification',$2,'test-only')`, id, "+"+strings.ReplaceAll(id, "-", "")[:14]); err != nil {
			t.Fatal(err)
		}
		defer db.Exec(`DELETE FROM users WHERE id=$1`, id)
	}
	if _, err = db.Exec(`INSERT INTO chats(id,kind,title,created_by) VALUES($1,'group','HTTP chat verification',$2)`, chatID, owner); err != nil {
		t.Fatal(err)
	}
	defer db.Exec(`DELETE FROM chats WHERE id=$1`, chatID)
	for _, id := range []string{owner, member} {
		if _, err = db.Exec(`INSERT INTO chat_members(chat_id,user_id) VALUES($1,$2)`, chatID, id); err != nil {
			t.Fatal(err)
		}
	}
	app := &application{db: db, hub: newMessageHub(), jwtSecret: []byte(strings.Repeat("test-only", 4))}
	server := app.routes(false)
	defer server.Shutdown()
	request := func(userID, method, path, body string, status int) map[string]json.RawMessage {
		t.Helper()
		r := httptest.NewRequest(method, "/api/chats/"+chatID+path, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		if userID != "" {
			token, _ := app.createToken(userID)
			r.Header.Set("Authorization", "Bearer "+token)
		}
		response, err := server.Test(r, 15000)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		var result map[string]json.RawMessage
		json.NewDecoder(response.Body).Decode(&result)
		if response.StatusCode != status {
			t.Fatalf("%s %s: status=%d want=%d body=%s", method, path, response.StatusCode, status, result["error"])
		}
		return result
	}
	id := uuid.NewString()
	body := `{"content":"Hello over HTTP","client_id":"` + id + `"}`
	request("", "POST", "/messages", body, 401)
	request(outsider, "POST", "/messages", body, 403)
	request(outsider, "GET", "/events", "", 403)
	request(owner, "POST", "/messages", body, 200)
	request(owner, "POST", "/messages", body, 200)
	request(owner, "POST", "/messages", strings.Replace(body, "Hello over HTTP", "Different content", 1), 409)
	got := request(member, "GET", "/events", "", 200)
	var messages []message
	if err = json.Unmarshal(got["messages"], &messages); err != nil {
		t.Fatal(err)
	}
	if len(messages) != 1 || messages[0].ID != id || messages[0].IsMe {
		t.Fatal("idempotency or recipient delivery failed")
	}
	if _, err = db.Exec(`INSERT INTO messages(chat_id,sender_id,content,created_at) SELECT $1,$2,'Burst '||n,clock_timestamp() FROM generate_series(1,105) n`, chatID, owner); err != nil {
		t.Fatal(err)
	}
	got = request(member, "GET", "/events?after_id="+id, "", 200)
	json.Unmarshal(got["messages"], &messages)
	if len(messages) != 100 || string(got["has_more"]) != "true" {
		t.Fatal("burst first page missing")
	}
	got = request(member, "GET", "/events?after_id="+messages[99].ID, "", 200)
	json.Unmarshal(got["messages"], &messages)
	if len(messages) != 5 || string(got["has_more"]) != "false" {
		t.Fatal("burst second page missing")
	}
	request(member, "DELETE", "/messages", "", 200)
	got = request(member, "GET", "/events", "", 200)
	if string(got["messages"]) != "[]" || string(got["cleared_before"]) == "null" {
		t.Fatal("personal history clear not respected")
	}
	got = request(owner, "GET", "/events", "", 200)
	json.Unmarshal(got["messages"], &messages)
	if len(messages) != 100 {
		t.Fatal("member clear affected owner")
	}
	t.Log("HTTP send/receive, authorization, duplicate protection, burst pagination and personal clear passed")
}
