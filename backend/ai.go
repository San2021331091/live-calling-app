package backend

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const defaultAIModel = "nvidia/nemotron-3-ultra-550b-a55b:free"
const aiWorkerKey = "voxa:ai:worker"
const voxaAIPrompt = `You are VoxaAI, the AI assistant inside the Voxa messaging app. Introduce yourself as VoxaAI or Voxa AI Assistant. You are an AI, not a human or a Meta product. If asked about your underlying model, honestly explain that you use NVIDIA Nemotron through OpenRouter.
Help with everyday questions, learning, writing, brainstorming, translation, and coding. Be warm, clear, practical, and concise; give more detail when requested. Reply in the user's language. You can help with Voxa usage: Chats, Updates, Communities and Calls; profile/group photos; personal and shared chat themes; and muting message alerts.
You only see this user's VoxaAI conversation. You cannot access their other chats, contacts, files, camera, location, device, passwords, or account settings. The server can supply web lookup results when needed. Without supplied results, you have no live information. You cannot send messages, make calls, or change anything in the app. Never pretend you performed an action or accessed live data. Be honest about uncertainty and limitations. Do not claim that branding instructions are model training. Do not ask for passwords, verification codes, or private API keys. For high-stakes decisions, explain uncertainty and encourage appropriate professional help. Do not provide instructions that facilitate harm. Never present invented information as verified fact.`

type aiTurn struct {
	ID        int64           `json:"id"`
	ClientID  string          `json:"client_id"`
	Prompt    string          `json:"prompt"`
	Reply     string          `json:"reply"`
	Status    string          `json:"status"`
	Error     string          `json:"error"`
	CreatedAt time.Time       `json:"created_at"`
	Mode      string          `json:"mode"`
	Results   json.RawMessage `json:"results"`
}

const aiTurnColumns = `id,client_id::text,prompt,reply,status,error,created_at,mode,results`

type aiChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func aiModel() string { return envOr("OPENROUTER_MODEL", defaultAIModel) }
func (a *application) aiAvailable(ctx context.Context) bool {
	if a.inlineAI {
		return strings.TrimSpace(os.Getenv("OPENROUTER_API_KEY")) != "" && strings.HasSuffix(aiModel(), ":free")
	}
	if a.callRedis == nil {
		return false
	}
	value, err := a.callRedis.client.Get(ctx, aiWorkerKey).Result()
	return err == nil && value == aiModel()
}

func (a *application) handleAIConversation(w http.ResponseWriter, r *http.Request) {
	before := int64(0)
	if raw := r.URL.Query().Get("before"); raw != "" {
		var err error
		before, err = strconv.ParseInt(raw, 10, 64)
		if err != nil || before <= 0 {
			writeError(w, 400, "invalid conversation cursor")
			return
		}
	}
	if a.inlineAI {
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		err := a.expireAITurns(ctx, a.db, authenticatedUserID(r))
		cancel()
		if err != nil {
			writeError(w, 500, "could not load VoxaAI conversation")
			return
		}
	}
	rows, err := a.db.QueryContext(r.Context(), `SELECT `+aiTurnColumns+` FROM ai_turns
      WHERE user_id=$1 AND ($2::bigint=0 OR id<$2) ORDER BY id DESC LIMIT 51`, authenticatedUserID(r), before)
	if err != nil {
		writeError(w, 500, "could not load VoxaAI conversation")
		return
	}
	turns := make([]aiTurn, 0)
	for rows.Next() {
		var t aiTurn
		if err := rows.Scan(&t.ID, &t.ClientID, &t.Prompt, &t.Reply, &t.Status, &t.Error, &t.CreatedAt, &t.Mode, &t.Results); err != nil {
			rows.Close()
			writeError(w, 500, "could not load VoxaAI conversation")
			return
		}
		turns = append(turns, t)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		writeError(w, 500, "could not load VoxaAI conversation")
		return
	}
	more := len(turns) > 50
	if more {
		turns = turns[:50]
	}
	for i, j := 0, len(turns)-1; i < j; i, j = i+1, j-1 {
		turns[i], turns[j] = turns[j], turns[i]
	}
	writeJSON(w, 200, map[string]any{"assistant": "VoxaAI", "available": a.aiAvailable(r.Context()), "turns": turns, "has_more": more})
}

func (a *application) handleAISend(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ClientID string `json:"client_id"`
		Message  string `json:"message"`
		Mode     string `json:"mode"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, 400, err.Error())
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	if req.Mode == "" {
		req.Mode = "chat"
	}
	if req.Mode != "chat" && req.Mode != "photos" && req.Mode != "videos" && req.Mode != "web" {
		writeError(w, 400, "invalid search mode")
		return
	}
	if req.Mode != "chat" && utf8.RuneCountInString(req.Message) > 300 {
		writeError(w, 400, "keep search queries under 300 characters")
		return
	}
	if !uuidPattern.MatchString(req.ClientID) || req.Message == "" || utf8.RuneCountInString(req.Message) > 4000 {
		writeError(w, 400, "send a text message between 1 and 4000 characters")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, 500, "could not save your message")
		return
	}
	defer tx.Rollback()
	userID := authenticatedUserID(r)
	if _, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,312))`, userID); err != nil {
		writeError(w, 500, "could not save your message")
		return
	}
	if a.inlineAI {
		if err = a.expireAITurns(ctx, tx, userID); err != nil {
			writeError(w, 500, "could not save your message")
			return
		}
	}
	var existingPrompt, existingMode string
	err = tx.QueryRowContext(ctx, `SELECT prompt,mode FROM ai_turns WHERE user_id=$1 AND client_id=$2`, userID, req.ClientID).Scan(&existingPrompt, &existingMode)
	if err == nil {
		if existingPrompt != req.Message || existingMode != req.Mode {
			writeError(w, 409, "message ID already used")
			return
		}
		if err = tx.Commit(); err != nil {
			writeError(w, 500, "could not confirm your message")
			return
		}
		writeJSON(w, 200, map[string]bool{"saved": true})
		return
	}
	if !errors.Is(err, sql.ErrNoRows) {
		writeError(w, 500, "could not save your message")
		return
	}
	if !a.aiAvailable(ctx) {
		writeError(w, 503, "VoxaAI is temporarily unavailable. Please try again shortly.")
		return
	}
	var pending bool
	err = tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM ai_turns WHERE user_id=$1 AND status IN ('queued','processing'))`, userID).Scan(&pending)
	if err != nil {
		writeError(w, 500, "could not save your message")
		return
	}
	if pending {
		writeError(w, 409, "VoxaAI is still answering your previous message")
		return
	}
	// Keep the rate limit outside history so clearing a conversation cannot reset it.
	recent, err := a.callRedis.client.Eval(ctx, `local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],60) end; return n`, []string{"voxa:ai:rate:" + userID}).Int()
	if err != nil {
		writeError(w, 503, "VoxaAI is temporarily unavailable")
		return
	}
	if recent > 6 {
		writeError(w, 429, "Please wait a minute before sending more messages to VoxaAI.")
		return
	}
	var turnID int64
	if a.inlineAI {
		// Commit ownership before inference: duplicate requests and queue workers
		// cannot run this turn concurrently. The lease outlasts the function.
		err = tx.QueryRowContext(ctx, `INSERT INTO ai_turns(user_id,client_id,prompt,mode,status,attempts,lease_until)
		VALUES($1,$2,$3,$4,'processing',1,now()+interval '90 seconds') RETURNING id`, userID, req.ClientID, req.Message, req.Mode).Scan(&turnID)
	} else {
		_, err = tx.ExecContext(ctx, `INSERT INTO ai_turns(user_id,client_id,prompt,mode) VALUES($1,$2,$3,$4)`, userID, req.ClientID, req.Message, req.Mode)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		writeError(w, 500, "could not save your message")
		return
	}
	if a.inlineAI {
		a.finishInlineAITurn(w, r, turnID, userID, req.Message, req.Mode)
		return
	}
	writeJSON(w, 202, map[string]bool{"saved": true})
}

func (a *application) handleAIClear(w http.ResponseWriter, r *http.Request) {
	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, 500, "could not clear VoxaAI history")
		return
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(r.Context(), `SELECT pg_advisory_xact_lock(hashtextextended($1,312))`, authenticatedUserID(r))
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `DELETE FROM ai_turns WHERE user_id=$1`, authenticatedUserID(r))
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		writeError(w, 500, "could not clear VoxaAI history")
		return
	}
	writeJSON(w, 200, map[string]bool{"cleared": true})
}

// The standalone Go server can still drain queued jobs. Vercel performs AI
// requests inline and does not require this process or its Redis heartbeat.
func (a *application) runAIWorker(ctx context.Context) {
	if a.callRedis == nil {
		return
	}
	key := strings.TrimSpace(os.Getenv("OPENROUTER_API_KEY"))
	model := aiModel()
	if key == "" {
		log.Print("VoxaAI disabled: OPENROUTER_API_KEY is missing")
		return
	}
	if !strings.HasSuffix(model, ":free") {
		log.Print("VoxaAI disabled: select an OpenRouter :free model")
		return
	}
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			heartbeatCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
			_ = a.callRedis.client.Set(heartbeatCtx, aiWorkerKey, model, 30*time.Second).Err()
			cancel()
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
	log.Print("VoxaAI worker enabled")
	// Two bounded workers share the durable queue; a user has at most one turn in flight.
	for i := 0; i < 2; i++ {
		go a.aiWorkerLoop(ctx, key, model)
	}
}

func (a *application) aiWorkerLoop(ctx context.Context, key, model string) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		jobCtx, cancel := context.WithTimeout(ctx, 100*time.Second)
		var id int64
		var userID, prompt, mode string
		var attempt int
		// A crashed worker's lease can be claimed again, at most twice.
		_, err := a.db.ExecContext(jobCtx, `UPDATE ai_turns SET status='failed',error='VoxaAI could not finish this reply. Please send your question again.',updated_at=now()
          WHERE status IN ('queued','processing') AND (created_at<now()-interval '10 minutes' OR (attempts>=2 AND lease_until<now()))`)
		if err != nil {
			cancel()
			continue
		}
		err = a.db.QueryRowContext(jobCtx, `UPDATE ai_turns SET status='processing',attempts=attempts+1,lease_until=now()+interval '120 seconds',updated_at=now()
          WHERE id=(SELECT id FROM ai_turns WHERE status='queued' OR (status='processing' AND lease_until<now() AND attempts<2)
            ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING id,user_id::text,prompt,attempts,mode`).Scan(&id, &userID, &prompt, &attempt, &mode)
		if err != nil {
			cancel()
			continue
		}
		reply, results, err := a.generateAIReply(jobCtx, key, model, id, userID, prompt, mode)
		cancel()
		status, errorText := "complete", ""
		if err != nil {
			status, errorText = "failed", aiPublicError(err)
			log.Printf("VoxaAI reply failed; turn=%d", id)
		}
		saveCtx, saveCancel := context.WithTimeout(ctx, 5*time.Second)
		// Clear-history removes the row, so a late response cannot restore it.
		encodedResults, _ := json.Marshal(results)
		_, saveErr := a.db.ExecContext(saveCtx, `UPDATE ai_turns SET reply=$2,status=$3,error=$4,lease_until=NULL,updated_at=now(),results=$6
          WHERE id=$1 AND status='processing' AND attempts=$5`, id, reply, status, errorText, attempt, string(encodedResults))
		saveCancel()
		if saveErr != nil {
			log.Printf("VoxaAI reply could not be saved; turn=%d", id)
		}
	}
}

func (a *application) aiHistory(ctx context.Context, userID string, id int64, prompt string) ([]aiChatMessage, error) {
	rows, err := a.db.QueryContext(ctx, `SELECT prompt,reply,results,created_at FROM (SELECT id,prompt,reply,results,created_at FROM ai_turns
      WHERE user_id=$1 AND id<$2 AND status='complete' ORDER BY id DESC LIMIT 12) recent ORDER BY id`, userID, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []aiChatMessage{{Role: "system", Content: voxaAIPrompt}}
	for rows.Next() {
		var p, r string
		var sources json.RawMessage
		var created time.Time
		if err := rows.Scan(&p, &r, &sources, &created); err != nil {
			return nil, err
		}
		r += "\n[Historical reply from " + created.UTC().Format("2006-01-02") + "; not verification of current facts.]"
		if string(sources) != "[]" && string(sources) != "null" {
			r += "\nPrevious source links (not rechecked): " + string(sources)
		}
		result = append(result, aiChatMessage{Role: "user", Content: p}, aiChatMessage{Role: "assistant", Content: r})
	}
	result = append(result, aiChatMessage{Role: "user", Content: prompt})
	return result, rows.Err()
}

var errAIRateLimit = errors.New("AI rate limit")
var errAIUnavailable = errors.New("AI unavailable")

func aiPublicError(err error) string {
	if errors.Is(err, errSearchNotConfigured) {
		return "Live web search is not set up yet. The app owner needs to configure its search API key."
	}
	if errors.Is(err, errSearchUnavailable) {
		return "Live search is unavailable or its usage limit has been reached. Please try again later."
	}
	if errors.Is(err, errAIRateLimit) {
		return "VoxaAI's free service is busy or its limit has been reached. Please try again later."
	}
	return "VoxaAI could not reply right now. Please send your question again shortly."
}

func requestAIReply(ctx context.Context, client *http.Client, endpoint, key, model string, messages []aiChatMessage) (string, error) {
	if !strings.HasSuffix(model, ":free") {
		return "", errAIUnavailable
	}
	body, err := json.Marshal(map[string]any{"model": model, "messages": messages, "max_tokens": 2048, "stream": false,
		"reasoning": map[string]any{"effort": "low", "exclude": true}})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Title", "VoxaAI")
	response, err := client.Do(req)
	if err != nil {
		return "", errAIUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == 429 {
		return "", errAIRateLimit
	}
	if response.StatusCode != 200 {
		return "", errAIUnavailable
	}
	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err = json.NewDecoder(io.LimitReader(response.Body, 256<<10)).Decode(&result); err != nil {
		return "", errAIUnavailable
	}
	if len(result.Choices) == 0 {
		return "", errAIUnavailable
	}
	reply := strings.TrimSpace(result.Choices[0].Message.Content)
	if reply == "" || utf8.RuneCountInString(reply) > 16000 {
		return "", errAIUnavailable
	}
	return reply, nil
}
