package main

import (
	"database/sql"
	"errors"
	"net/http"
	"net/url"
	"unicode/utf8"
)

func validAvatarURL(value string) bool {
	if value == "" {
		return true
	}
	u, err := url.Parse(value)
	return err == nil && utf8.RuneCountInString(value) <= 2048 && u.Scheme == "https" && u.Hostname() != "" && u.User == nil
}

func validChatTheme(value string) bool {
	switch value {
	case "classic", "ocean", "rose", "lavender", "sand":
		return true
	}
	return false
}

func (a *application) handleChatAppearance(w http.ResponseWriter, r *http.Request) {
	chatID := r.PathValue("chatID")
	if !uuidPattern.MatchString(chatID) {
		writeError(w, http.StatusBadRequest, "invalid chat ID")
		return
	}
	var name, avatar, theme, personal, shared string
	err := a.db.QueryRowContext(r.Context(), `SELECT
	 CASE WHEN c.kind = 'direct' THEN COALESCE(peer.display_name, '') ELSE c.title END,
	 CASE WHEN c.kind = 'direct' THEN COALESCE(peer.avatar_url, '') ELSE c.avatar_url END,
	 COALESCE(NULLIF(m.theme, ''), c.theme), m.theme, c.theme
	 FROM chats c JOIN chat_members m ON m.chat_id = c.id AND m.user_id = $2
	 LEFT JOIN LATERAL (SELECT u.display_name, u.avatar_url FROM chat_members other
	 JOIN users u ON u.id = other.user_id WHERE other.chat_id = c.id AND other.user_id <> $2 LIMIT 1) peer ON true
	 WHERE c.id = $1`, chatID, authenticatedUserID(r)).Scan(&name, &avatar, &theme, &personal, &shared)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusForbidden, "you are not a member of this chat")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load chat appearance")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"name": name, "avatar_url": avatar, "theme": theme, "personal_theme": personal, "shared_theme": shared})
}

func (h *messageHub) appearanceChanged(chatID, userID string) {
	if h == nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for client := range h.clients[chatID] {
		if userID != "" && client.userID != userID {
			continue
		}
		select {
		case client.send <- []byte(`{"type":"appearance_changed"}`):
		default:
		}
	}
}
