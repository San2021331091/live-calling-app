package backend

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"time"
)

// Leave room for cold-start initialization, persistence and the response within
// the 60-second Vercel function limit. Never start unawaited background work.
const inlineAITimeout = 40 * time.Second

type aiExecer interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

func (a *application) expireAITurns(ctx context.Context, db aiExecer, userID string) error {
	_, err := db.ExecContext(ctx, `UPDATE ai_turns SET status='failed',
	 error='VoxaAI could not finish this reply. Please send your question again.',lease_until=NULL,updated_at=now()
	 WHERE user_id=$1 AND ((status='processing' AND (lease_until<now() OR (lease_until IS NULL AND updated_at<now()-interval '120 seconds')))
	 OR (status='queued' AND created_at<now()-interval '120 seconds'))`, userID)
	return err
}

func (a *application) finishInlineAITurn(w http.ResponseWriter, r *http.Request, id int64, userID, prompt, mode string) {
	// A dropped phone connection must not discard a reply we can still save.
	// Work remains bounded and awaited inside this function invocation.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), inlineAITimeout)
	reply, results, err := a.generateAIReply(ctx, strings.TrimSpace(os.Getenv("OPENROUTER_API_KEY")), aiModel(), id, userID, prompt, mode)
	cancel()
	status, errorText := "complete", ""
	if err != nil {
		status, errorText = "failed", aiPublicError(err)
	}
	if results == nil {
		results = []aiSearchResult{}
	}
	encoded, _ := json.Marshal(results)
	saveCtx, saveCancel := context.WithTimeout(context.WithoutCancel(r.Context()), 3*time.Second)
	defer saveCancel()
	// A clear or expired lease must not resurrect a removed/replaced reply.
	_, saveErr := a.db.ExecContext(saveCtx, `UPDATE ai_turns SET reply=$2,status=$3,error=$4,lease_until=NULL,updated_at=now(),results=$5
	 WHERE id=$1 AND status='processing' AND attempts=1`, id, reply, status, errorText, string(encoded))
	if saveErr != nil {
		writeError(w, 500, "Could not confirm the saved reply. Refresh the conversation before retrying.")
		return
	}
	writeJSON(w, 200, map[string]any{"saved": true, "status": status})
}

func (a *application) generateAIReply(ctx context.Context, key, model string, id int64, userID, prompt, mode string) (string, []aiSearchResult, error) {
	client := a.aiClient
	if client == nil {
		client = http.DefaultClient
	}
	const endpoint = "https://openrouter.ai/api/v1/chat/completions"
	if mode == "web" {
		_, results, err := aiSearch(ctx, client, mode, prompt)
		if err != nil {
			return "", results, err
		}
		if len(results) == 0 {
			return "No relevant web results were found. Try a more specific question.", results, nil
		}
		reply, err := requestAISearchAnswer(ctx, client, endpoint, key, model, prompt, results)
		return reply, results, err
	}
	if mode != "chat" {
		return aiSearch(ctx, client, mode, prompt)
	}
	history, err := a.aiHistory(ctx, userID, id, prompt)
	if err != nil {
		return "", nil, err
	}
	return requestGroundedAIReply(ctx, client, endpoint, key, model, history, aiSearch)
}
