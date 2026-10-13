package backend

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/joho/godotenv"
)

func TestAIProvider(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		body   string
		want   error
	}{
		{"reply", 200, `{"choices":[{"message":{"content":"Hello from VoxaAI"}}]}`, nil},
		{"limit", 429, `{"error":"private provider detail"}`, errAIRateLimit},
		{"unauthorized", 401, `{"error":"private provider detail"}`, errAIUnavailable},
		{"empty", 200, `{"choices":[]}`, errAIUnavailable},
		{"malformed", 200, `not JSON`, errAIUnavailable},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer test-only" || r.Method != "POST" {
					t.Error("invalid provider authentication")
				}
				var body struct {
					Model    string
					Messages []aiChatMessage
				}
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Error(err)
				}
				if body.Model != defaultAIModel || len(body.Messages) != 2 || body.Messages[0].Role != "system" {
					t.Error("model or assistant instructions missing")
				}
				w.WriteHeader(tc.status)
				w.Write([]byte(tc.body))
			}))
			defer server.Close()
			reply, err := requestAIReply(context.Background(), server.Client(), server.URL, "test-only", defaultAIModel, []aiChatMessage{{"system", voxaAIPrompt}, {"user", "Hello"}})
			if !errors.Is(err, tc.want) {
				t.Fatalf("unexpected error: %v", err)
			}
			if err == nil && reply != "Hello from VoxaAI" {
				t.Fatal("reply missing")
			}
			if strings.Contains(aiPublicError(err), "private") {
				t.Fatal("provider error leaked")
			}
		})
	}
	if _, err := requestAIReply(context.Background(), nil, "", "", "paid-model", nil); !errors.Is(err, errAIUnavailable) {
		t.Fatal("paid model accepted")
	}
}

// Uses only rolled-back fixtures; no real conversations are sent to a provider.
func TestAIHistoryIsolationIntegration(t *testing.T) {
	if os.Getenv("VOXA_INTEGRATION_TEST") != "1" {
		t.Skip("set VOXA_INTEGRATION_TEST=1 after migration 012")
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
	db.SetMaxOpenConns(1)
	if _, err = db.Exec("BEGIN"); err != nil {
		t.Fatal(err)
	}
	defer db.Exec("ROLLBACK")
	owner, other := uuid.NewString(), uuid.NewString()
	for _, id := range []string{owner, other} {
		if _, err = db.Exec(`INSERT INTO users(id,display_name,phone,password_hash) VALUES($1,'AI test',$2,'test-only')`, id, "+"+strings.ReplaceAll(id, "-", "")[:14]); err != nil {
			t.Fatal(err)
		}
		if _, err = db.Exec(`INSERT INTO ai_turns(user_id,client_id,prompt,reply,status) VALUES($1,$2,$3,'Test answer','complete')`, id, uuid.NewString(), id); err != nil {
			t.Fatal(err)
		}
	}
	app := &application{db: db}
	messages, err := app.aiHistory(context.Background(), owner, 1<<62, "Current question")
	if err != nil {
		t.Fatal(err)
	}
	if len(messages) != 4 || messages[1].Content != owner || messages[3].Content != "Current question" {
		t.Fatal("history isolation/order failed")
	}
	for _, m := range messages {
		if strings.Contains(m.Content, other) {
			t.Fatal("another account's history leaked")
		}
	}
	r := httptest.NewRequest("GET", "/api/ai/conversation", nil)
	r = r.WithContext(context.WithValue(r.Context(), userIDContextKey, other))
	w := httptest.NewRecorder()
	app.handleAIConversation(w, r)
	if w.Code != 200 || strings.Contains(w.Body.String(), owner) || !strings.Contains(w.Body.String(), other) {
		t.Fatal("conversation API isolation failed")
	}
}

// Explicit opt-in makes one free provider request with a synthetic greeting.
func TestAILiveProvider(t *testing.T) {
	if os.Getenv("VOXA_AI_LIVE_TEST") != "1" {
		t.Skip("set VOXA_AI_LIVE_TEST=1 to check configured OpenRouter credentials")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("configuration unavailable")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Second)
	defer cancel()
	reply, err := requestAIReply(ctx, http.DefaultClient, "https://openrouter.ai/api/v1/chat/completions", values["OPENROUTER_API_KEY"], defaultAIModel, []aiChatMessage{{"system", voxaAIPrompt}, {"user", "Introduce yourself in one short sentence."}})
	if err != nil {
		t.Fatal(aiPublicError(err))
	}
	if !strings.Contains(strings.ToLower(reply), "voxa") {
		t.Fatal("assistant did not identify as VoxaAI")
	}
	t.Log("Free model returned a reply identifying as VoxaAI")
}

// Exercise the running local server with temporary accounts, then delete them.
func TestAILiveConversation(t *testing.T) {
	if os.Getenv("VOXA_AI_E2E_TEST") != "1" {
		t.Skip("set VOXA_AI_E2E_TEST=1 with the local server running")
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
	app := &application{jwtSecret: []byte(values["JWT_SECRET"])}
	owner, outsider := uuid.NewString(), uuid.NewString()
	for _, id := range []string{owner, outsider} {
		if _, err = db.Exec(`INSERT INTO users(id,display_name,phone,password_hash) VALUES($1,'Temporary AI verification',$2,'test-only')`, id, "+"+strings.ReplaceAll(id, "-", "")[:14]); err != nil {
			t.Fatal(err)
		}
		defer db.Exec(`DELETE FROM users WHERE id=$1`, id)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	request := func(id, method, path, body string, status int) map[string]json.RawMessage {
		t.Helper()
		r, err := http.NewRequest(method, "http://127.0.0.1:8080"+path, strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		if id != "" {
			token, err := app.createToken(id)
			if err != nil {
				t.Fatal(err)
			}
			r.Header.Set("Authorization", "Bearer "+token)
		}
		r.Header.Set("Content-Type", "application/json")
		res, err := client.Do(r)
		if err != nil {
			t.Fatal("local API unavailable")
		}
		defer res.Body.Close()
		if res.StatusCode != status {
			t.Fatalf("%s %s returned %d; want %d", method, path, res.StatusCode, status)
		}
		var result map[string]json.RawMessage
		if err := json.NewDecoder(res.Body).Decode(&result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	request("", "GET", "/api/ai/conversation", "", 401)
	initial := request(owner, "GET", "/api/ai/conversation", "", 200)
	if string(initial["available"]) != "true" {
		t.Fatal("worker unavailable")
	}
	message := `{"client_id":"` + uuid.NewString() + `","message":"Introduce yourself in one short sentence."}`
	request(owner, "POST", "/api/ai/messages", message, 202)
	request(owner, "POST", "/api/ai/messages", message, 200)
	other := request(outsider, "GET", "/api/ai/conversation", "", 200)
	if string(other["turns"]) != "[]" {
		t.Fatal("conversation leaked to another account")
	}
	deadline := time.Now().Add(115 * time.Second)
	for {
		result := request(owner, "GET", "/api/ai/conversation", "", 200)
		var turns []aiTurn
		if err := json.Unmarshal(result["turns"], &turns); err != nil {
			t.Fatal(err)
		}
		if len(turns) != 1 {
			t.Fatal("idempotency failed")
		}
		if turns[0].Status == "failed" {
			t.Fatal(turns[0].Error)
		}
		if turns[0].Status == "complete" {
			if !strings.Contains(strings.ToLower(turns[0].Reply), "voxa") {
				t.Fatal("assistant identity missing")
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("worker did not finish")
		}
		time.Sleep(time.Second)
	}
	request(owner, "DELETE", "/api/ai/conversation", "", 200)
	if got := request(owner, "GET", "/api/ai/conversation", "", 200); string(got["turns"]) != "[]" {
		t.Fatal("history not cleared")
	}
	t.Log("Authenticated send, duplicate protection, worker reply, account isolation and clear passed")
	if os.Getenv("VOXA_AI_SEARCH_LIVE_TEST") == "1" {
		for _, mode := range []string{"photos", "videos", "web", "chat"} {
			query := "forest"
			if mode == "web" || mode == "chat" {
				query = "current prime minister of Bangladesh"
			}
			body := `{"client_id":"` + uuid.NewString() + `","message":"` + query + `","mode":"` + mode + `"}`
			request(owner, "POST", "/api/ai/messages", body, 202)
			until := time.Now().Add(100 * time.Second)
			for {
				result := request(owner, "GET", "/api/ai/conversation", "", 200)
				var turns []aiTurn
				if err := json.Unmarshal(result["turns"], &turns); err != nil {
					t.Fatal(err)
				}
				if len(turns) != 1 {
					t.Fatal("search history count incorrect")
				}
				if turns[0].Status == "complete" {
					var sources []aiSearchResult
					if err := json.Unmarshal(turns[0].Results, &sources); err != nil || len(sources) == 0 || turns[0].Mode != mode {
						t.Fatal("search results did not persist")
					}
					if mode == "chat" {
						cited := false
						for _, source := range sources {
							if strings.Contains(turns[0].Reply, source.URL) {
								cited = true
							}
						}
						if !cited {
							t.Fatal("current-information answer did not cite a retrieved source")
						}
						t.Log("Bangladesh PM question returned an answer citing retrieved sources")
					}
					break
				}
				if turns[0].Status == "failed" || time.Now().After(until) {
					t.Fatal("search worker failed")
				}
				time.Sleep(time.Second)
			}
			request(owner, "DELETE", "/api/ai/conversation", "", 200)
			t.Log(mode + " results persisted and were deleted successfully")
		}
	}
}
