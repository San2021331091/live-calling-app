package backend

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
)

// HTTP delivery uses the same messages and notification triggers as WebSockets.
func (a *application) handleHTTPMessage(w http.ResponseWriter, r *http.Request) {
	chatID, userID := r.PathValue("chatID"), authenticatedUserID(r)
	var body struct {
		Content  string `json:"content"`
		ClientID string `json:"client_id"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeError(w, 400, "invalid message")
		return
	}
	body.Content = strings.TrimSpace(body.Content)
	if !uuidPattern.MatchString(chatID) || !uuidPattern.MatchString(body.ClientID) || body.Content == "" || utf8.RuneCountInString(body.Content) > maxMessageRunes {
		writeError(w, 400, "invalid message ID or message length")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, 500, "could not save message")
		return
	}
	defer tx.Rollback()
	var name string
	err = tx.QueryRowContext(ctx, `SELECT u.display_name FROM chat_members cm JOIN users u ON u.id=cm.user_id WHERE cm.chat_id=$1 AND cm.user_id=$2`, chatID, userID).Scan(&name)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 403, "you are not a member of this chat")
		return
	}
	if err != nil {
		writeError(w, 500, "could not check membership")
		return
	}
	result, err := tx.ExecContext(ctx, `INSERT INTO messages(id,chat_id,sender_id,content)
 SELECT $1,$2,$3,$4 WHERE EXISTS(SELECT 1 FROM chat_members WHERE chat_id=$2 AND user_id=$3)
 ON CONFLICT(id) DO NOTHING`, body.ClientID, chatID, userID, body.Content)
	if err != nil {
		writeError(w, 500, "message could not be saved")
		return
	}
	inserted, _ := result.RowsAffected()
	var saved message
	err = tx.QueryRowContext(ctx, `SELECT id::text,chat_id::text,sender_id::text,content,created_at FROM messages WHERE id=$1 AND chat_id=$2 AND sender_id=$3`, body.ClientID, chatID, userID).Scan(&saved.ID, &saved.ChatID, &saved.SenderID, &saved.Content, &saved.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && saved.Content != body.Content) {
		writeError(w, 409, "message ID already used or membership changed")
		return
	}
	if err != nil {
		writeError(w, 500, "could not confirm message")
		return
	}
	if inserted > 0 {
		if _, err = tx.ExecContext(ctx, `UPDATE chat_members SET hidden=false WHERE chat_id=$1`, chatID); err != nil {
			writeError(w, 500, "could not restore chat")
			return
		}
	}
	if err = tx.Commit(); err != nil {
		writeError(w, 500, "could not confirm message")
		return
	}
	saved.ClientID = body.ClientID
	saved.Sender = name
	saved.IsMe = true
	if inserted > 0 && a.hub != nil {
		a.hub.broadcast(chatID, saved)
	}
	writeJSON(w, 200, map[string]any{"type": "message", "message": saved})
}

func (a *application) handleHTTPChatEvents(w http.ResponseWriter, r *http.Request) {
	chatID, userID := r.PathValue("chatID"), authenticatedUserID(r)
	after := r.URL.Query().Get("after_id")
	if !uuidPattern.MatchString(chatID) || (after != "" && !uuidPattern.MatchString(after)) {
		writeError(w, 400, "invalid chat or cursor")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	var cleared sql.NullTime
	err := a.db.QueryRowContext(ctx, `SELECT cleared_before FROM chat_members WHERE chat_id=$1 AND user_id=$2`, chatID, userID).Scan(&cleared)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 403, "you are not a member of this chat")
		return
	}
	if err != nil {
		writeError(w, 500, "could not load chat")
		return
	}
	var cursor any
	if after != "" {
		cursor = after
	}
	rows, err := a.db.QueryContext(ctx, `SELECT m.id::text,m.chat_id::text,m.sender_id::text,u.display_name,m.content,m.created_at
 FROM (SELECT id,chat_id,sender_id,content,created_at FROM messages
 WHERE chat_id=$1 AND EXISTS(SELECT 1 FROM chat_members WHERE chat_id=$1 AND user_id=$2)
 AND created_at>COALESCE($3::timestamptz,'-infinity'::timestamptz)
 AND ($4::uuid IS NULL OR (created_at,id)>(SELECT created_at,id FROM messages WHERE id=$4 AND chat_id=$1))
 ORDER BY CASE WHEN $4::uuid IS NULL THEN created_at END DESC,
 CASE WHEN $4::uuid IS NULL THEN id END DESC, created_at,id LIMIT 100) m
 JOIN users u ON u.id=m.sender_id ORDER BY m.created_at,m.id`, chatID, userID, cleared, cursor)
	if err != nil {
		writeError(w, 500, "could not load chat messages")
		return
	}
	defer rows.Close()
	items := make([]message, 0)
	for rows.Next() {
		var item message
		if err = rows.Scan(&item.ID, &item.ChatID, &item.SenderID, &item.Sender, &item.Content, &item.CreatedAt); err != nil {
			writeError(w, 500, "could not load chat messages")
			return
		}
		item.IsMe = item.SenderID == userID
		items = append(items, item)
	}
	if rows.Err() != nil {
		writeError(w, 500, "could not load chat messages")
		return
	}
	var cutoff any
	if cleared.Valid {
		cutoff = cleared.Time
	}
	writeJSON(w, 200, map[string]any{"messages": items, "cleared_before": cutoff, "has_more": after != "" && len(items) == 100})
}
