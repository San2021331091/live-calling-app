package backend

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/joho/godotenv"
)

func TestGroundedAIUsesHistoryAndLookup(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		var request struct{ Messages []aiChatMessage }
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		if len(request.Messages) < 4 || request.Messages[1].Content != "Who is the current PM of Bangladesh?" {
			t.Error("follow-up history lost")
		}
		reply := `{"search_query":"current prime minister of India"}`
		if calls == 1 && !strings.Contains(request.Messages[0].Content, time.Now().UTC().Format("2006-01-02")) {
			t.Error("current date missing")
		}
		if calls == 2 {
			if !strings.Contains(request.Messages[len(request.Messages)-1].Content, "Source fact") || !strings.Contains(request.Messages[0].Content, "untrusted") {
				t.Error("lookup evidence or trust boundary missing")
			}
			reply = "The source says this, but I cannot verify its current validity."
		}
		json.NewEncoder(w).Encode(map[string]any{"choices": []any{map[string]any{"message": map[string]string{"content": reply}}}})
	}))
	defer server.Close()
	history := []aiChatMessage{{"system", voxaAIPrompt}, {"user", "Who is the current PM of Bangladesh?"}, {"assistant", "An old unverified answer"}, {"user", "What about India?"}}
	lookup := func(_ context.Context, _ *http.Client, mode, query string) (string, []aiSearchResult, error) {
		if mode != "web" || query != "current prime minister of India" {
			t.Error("follow-up search was not resolved")
		}
		return "Source fact", []aiSearchResult{{Kind: "web", URL: "https://example.com/source", Credit: "Example", Snippet: "Source fact", PublishedAt: "2026-10-13"}}, nil
	}
	reply, sources, err := requestGroundedAIReply(context.Background(), server.Client(), server.URL, "test-only", defaultAIModel, history, lookup)
	if err != nil || calls != 2 || len(sources) != 1 || !strings.Contains(reply, "cannot verify") {
		t.Fatal("grounded response failed")
	}
	if history[0].Content != voxaAIPrompt {
		t.Fatal("caller history mutated")
	}
}

func TestAISearchAnswerIsPlainTextAndUsesStructuredEvidence(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request struct {
			Messages []aiChatMessage
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatal(err)
		}
		if len(request.Messages) != 2 || !strings.Contains(request.Messages[0].Content, "without Markdown") ||
			!strings.Contains(request.Messages[1].Content, "verified source fact") ||
			!strings.Contains(request.Messages[1].Content, "https://example.com/source") {
			t.Error("search evidence or plain-text answer instructions missing")
		}
		w.Write([]byte(`{"choices":[{"message":{"content":"The verified answer is concise and clear."}}]}`))
	}))
	defer server.Close()

	answer, err := requestAISearchAnswer(
		context.Background(),
		server.Client(),
		server.URL,
		"test-only",
		defaultAIModel,
		"What happened?",
		[]aiSearchResult{{Kind: "web", Title: "Source", URL: "https://example.com/source", Snippet: "verified source fact"}},
	)
	if err != nil || answer != "The verified answer is concise and clear." {
		t.Fatalf("unexpected summarized answer: %q, %v", answer, err)
	}
}

func TestGroundedAINoEvidenceDoesNotGuess(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.Write([]byte(`{"choices":[{"message":{"content":"{\"search_query\":\"current PM Bangladesh\"}"}}]}`))
	}))
	defer server.Close()
	lookup := func(context.Context, *http.Client, string, string) (string, []aiSearchResult, error) {
		return "No relevant results", []aiSearchResult{}, nil
	}
	reply, sources, err := requestGroundedAIReply(context.Background(), server.Client(), server.URL, "test-only", defaultAIModel, []aiChatMessage{{"system", voxaAIPrompt}, {"user", "Who is PM now?"}}, lookup)
	if err != nil || calls != 1 || len(sources) != 0 || !strings.Contains(reply, "No relevant sources") {
		t.Fatal("empty lookup must not fall back to model memory")
	}
}

func TestAIRoutingValidation(t *testing.T) {
	for _, input := range []string{`not json`, `{}`, `{"answer":"old answer","search_query":"latest"}`, `{"search_query":"` + strings.Repeat("a", 301) + `"}`} {
		if _, err := decodeAIRoute(input); err == nil {
			t.Fatal("invalid routing accepted")
		}
	}
	if r, err := decodeAIRoute(`{"answer":"Hello from VoxaAI"}`); err != nil || r.Answer == "" {
		t.Fatal("ordinary chat rejected")
	}
}

func TestRegularChatDoesNotSearch(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Model string }
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Model != defaultAIModel {
			t.Error("regular chat must use configured Nemotron model")
		}
		w.Write([]byte(`{"choices":[{"message":{"content":"{\"answer\":\"Hello from VoxaAI\"}"}}]}`))
	}))
	defer server.Close()
	lookup := func(context.Context, *http.Client, string, string) (string, []aiSearchResult, error) {
		t.Error("regular chat called search")
		return "", nil, nil
	}
	reply, results, err := requestGroundedAIReply(context.Background(), server.Client(), server.URL, "test-only", defaultAIModel, []aiChatMessage{{"system", voxaAIPrompt}, {"user", "Hello"}}, lookup)
	if err != nil || reply != "Hello from VoxaAI" || len(results) != 0 {
		t.Fatal("regular chat failed")
	}
}

func TestAIGroundingLive(t *testing.T) {
	if os.Getenv("VOXA_AI_GROUNDING_LIVE_TEST") != "1" {
		t.Skip("set VOXA_AI_GROUNDING_LIVE_TEST=1 for a live contextual lookup")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("configuration unavailable")
	}
	t.Setenv("TAVILY_API_KEY", values["TAVILY_API_KEY"])
	history := []aiChatMessage{{"system", voxaAIPrompt}, {"user", "Who is the current prime minister of Bangladesh?"}, {"assistant", "This earlier response was not verified."}, {"user", "What about India? Please check the latest information."}}
	searched := false
	lookup := func(ctx context.Context, client *http.Client, mode, query string) (string, []aiSearchResult, error) {
		searched = true
		if !strings.Contains(strings.ToLower(query), "india") {
			t.Error("country was not resolved from follow-up")
		}
		if !strings.Contains(strings.ToLower(query), "minister") {
			t.Error("topic was not resolved from history")
		}
		return aiSearch(ctx, client, mode, query)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Second)
	defer cancel()
	reply, sources, err := requestGroundedAIReply(ctx, http.DefaultClient, "https://openrouter.ai/api/v1/chat/completions", values["OPENROUTER_API_KEY"], defaultAIModel, history, lookup)
	if err != nil {
		t.Fatal(aiPublicError(err))
	}
	if !searched || len(sources) == 0 || reply == "" {
		t.Fatal("live chat did not perform contextual lookup")
	}
	t.Log("Live Chat resolved the follow-up country/topic and returned lookup sources")
}
