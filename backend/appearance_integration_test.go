package backend

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/joho/godotenv"
)

// All fixtures and updates are rolled back. Start the backend first to apply migration 010.
func TestChatAppearanceIntegration(t *testing.T) {
	if os.Getenv("VOXA_INTEGRATION_TEST") != "1" {
		t.Skip("set VOXA_INTEGRATION_TEST=1 to test PostgreSQL")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("could not read database configuration")
	}
	db, err := sql.Open("pgx", values["DATABASE_URL"])
	if err != nil {
		t.Fatal("could not configure database")
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	if _, err := db.Exec("BEGIN"); err != nil {
		t.Fatal(err)
	}
	defer db.Exec("ROLLBACK")
	app := &application{db: db, hub: newMessageHub()}
	owner, member, outsider := uuid.NewString(), uuid.NewString(), uuid.NewString()
	for _, id := range []string{owner, member, outsider} {
		if _, err := db.Exec(`INSERT INTO users(id,display_name,phone,password_hash) VALUES($1,'Appearance test',$2,'test-only')`, id, "+"+strings.ReplaceAll(id, "-", "")[:14]); err != nil {
			t.Fatal(err)
		}
	}
	request := func(handler http.HandlerFunc, chatID, userID, method, body string, status int) map[string]any {
		t.Helper()
		r := httptest.NewRequest(method, "/", strings.NewReader(body))
		r.SetPathValue("chatID", chatID)
		r = r.WithContext(context.WithValue(r.Context(), userIDContextKey, userID))
		w := httptest.NewRecorder()
		handler(w, r)
		if w.Code != status {
			t.Fatalf("status=%d want=%d body=%s", w.Code, status, w.Body.String())
		}
		var result map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	for _, kind := range []string{"group", "community"} {
		id := uuid.NewString()
		var category any
		if kind == "community" {
			category = "Other"
		}
		if _, err := db.Exec(`INSERT INTO chats(id,kind,title,community_type,created_by) VALUES($1,$2,'Original',$3,$4)`, id, kind, category, owner); err != nil {
			t.Fatal(err)
		}
		for _, userID := range []string{owner, member} {
			if _, err := db.Exec(`INSERT INTO chat_members(chat_id,user_id) VALUES($1,$2)`, id, userID); err != nil {
				t.Fatal(err)
			}
		}
		request(app.handleUpdateGroupChat, id, member, "PATCH", `{"avatar_url":"https://example.com/unauthorized.png"}`, 403)
		request(app.handleUpdateGroupChat, id, member, "PATCH", `{"theme":"ocean"}`, 403)
		request(app.handleChatPreferences, id, outsider, "PATCH", `{"theme":"rose"}`, 403)
		request(app.handleChatAppearance, id, outsider, "GET", "", 403)
		request(app.handleUpdateGroupChat, id, owner, "PATCH", `{"avatar_url":"javascript:bad"}`, 400)
		request(app.handleChatPreferences, id, member, "PATCH", `{"theme":"invalid"}`, 400)
		request(app.handleUpdateGroupChat, id, owner, "PATCH", `{"name":"Updated","avatar_url":"https://example.com/photo.png","theme":"ocean"}`, 200)
		request(app.handleChatPreferences, id, member, "PATCH", `{"muted":true,"theme":"rose"}`, 200)
		appearance := request(app.handleChatAppearance, id, member, "GET", "", 200)
		if appearance["theme"] != "rose" || appearance["shared_theme"] != "ocean" || appearance["name"] != "Updated" || appearance["avatar_url"] != "https://example.com/photo.png" {
			t.Fatal("appearance did not persist", appearance)
		}
		request(app.handleUpdateGroupChat, id, owner, "PATCH", `{"theme":"sand"}`, 200)
		if got := request(app.handleChatAppearance, id, member, "GET", "", 200); got["theme"] != "rose" {
			t.Fatal("shared change overwrote personal choice", got)
		}
		request(app.handleChatPreferences, id, member, "PATCH", `{"theme":""}`, 200)
		if got := request(app.handleChatAppearance, id, member, "GET", "", 200); got["theme"] != "sand" || got["personal_theme"] != "" {
			t.Fatal("reset did not follow shared theme", got)
		}
		var muted bool
		if err := db.QueryRow(`SELECT muted FROM chat_members WHERE chat_id=$1 AND user_id=$2`, id, member).Scan(&muted); err != nil || !muted {
			t.Fatal("theme update changed mute setting", err)
		}
		request(app.handleUpdateGroupChat, id, owner, "PATCH", `{"avatar_url":""}`, 200)
		if got := request(app.handleChatAppearance, id, member, "GET", "", 200); got["avatar_url"] != "" || got["name"] != "Updated" {
			t.Fatal("photo removal changed other fields", got)
		}
	}
	request(app.handleUpdateProfile, "", owner, "PATCH", `{"avatar_url":"https://example.com/profile.png","bio":"About"}`, 200)
	profile := request(app.handleMe, "", owner, "GET", "", 200)
	if profile["avatar_url"] != "https://example.com/profile.png" {
		t.Fatal("profile photo did not persist")
	}
	request(app.handleUpdateProfile, "", owner, "PATCH", `{"avatar_url":"","bio":""}`, 200)
	profile = request(app.handleMe, "", owner, "GET", "", 200)
	if profile["avatar_url"] != nil || profile["bio"] != nil {
		t.Fatal("profile fields were not cleared", profile)
	}
}
