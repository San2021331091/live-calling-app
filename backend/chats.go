package main

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

type chat struct {
	ID             string     `json:"id"`
	Name           string     `json:"name"`
	IsGroup        bool       `json:"is_group"`
	IsCommunity    bool       `json:"is_community"`
	CommunityType  string     `json:"community_type,omitempty"`
	PeerID         string     `json:"peer_id,omitempty"`
	PeerPhone      string     `json:"peer_phone,omitempty"`
	CurrentMessage string     `json:"current_message"`
	LastMessageAt  *time.Time `json:"last_message_at,omitempty"`
}

type message struct {
	ID        string    `json:"id"`
	ChatID    string    `json:"chat_id"`
	SenderID  string    `json:"sender_id"`
	Sender    string    `json:"sender"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
	IsMe      bool      `json:"is_me"`
}

func (a *application) handleUsers(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("query"))
	if utf8.RuneCountInString(query) > 80 {
		writeError(w, http.StatusBadRequest, "search query is too long")
		return
	}
	rows, err := a.db.QueryContext(r.Context(),
		`SELECT id::text, display_name, phone
		 FROM users
		 WHERE id <> $1 AND ($2 = '' OR display_name ILIKE '%' || $2 || '%' OR phone ILIKE '%' || $2 || '%')
		 ORDER BY display_name
		 LIMIT 100`,
		authenticatedUserID(r), query,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load users")
		return
	}
	defer rows.Close()

	users := make([]user, 0)
	for rows.Next() {
		var item user
		if err := rows.Scan(&item.ID, &item.Name, &item.Phone); err != nil {
			writeError(w, http.StatusInternalServerError, "could not load users")
			return
		}
		users = append(users, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not load users")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": users})
}

func (a *application) handleListChats(w http.ResponseWriter, r *http.Request) {
	rows, err := a.db.QueryContext(r.Context(),
		`SELECT c.id::text, c.kind, c.community_type,
		        CASE WHEN c.kind <> 'direct' THEN c.title ELSE peer.display_name END,
		        peer.id::text, peer.phone, COALESCE(latest.content, ''),
		        latest.created_at
		 FROM chats c
		 JOIN chat_members mine ON mine.chat_id = c.id AND mine.user_id = $1
		 LEFT JOIN LATERAL (
		     SELECT u.id, u.display_name, u.phone
		     FROM chat_members other_member
		     JOIN users u ON u.id = other_member.user_id
		     WHERE other_member.chat_id = c.id AND other_member.user_id <> $1
		     ORDER BY other_member.joined_at
		     LIMIT 1
		 ) peer ON true
		 LEFT JOIN LATERAL (
		     SELECT content, created_at
		     FROM messages
		     WHERE chat_id = c.id
		     ORDER BY created_at DESC
		     LIMIT 1
		 ) latest ON true
		 ORDER BY COALESCE(latest.created_at, c.created_at) DESC`,
		authenticatedUserID(r),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load chats")
		return
	}
	defer rows.Close()

	chats := make([]chat, 0)
	for rows.Next() {
		var item chat
		var kind string
		var communityType sql.NullString
		var peerID, peerPhone sql.NullString
		var lastMessageAt sql.NullTime
		if err := rows.Scan(
			&item.ID, &kind, &communityType, &item.Name, &peerID, &peerPhone,
			&item.CurrentMessage, &lastMessageAt,
		); err != nil {
			writeError(w, http.StatusInternalServerError, "could not load chats")
			return
		}
		item.IsGroup = kind != "direct"
		item.IsCommunity = kind == "community"
		if communityType.Valid {
			item.CommunityType = communityType.String
		}
		if peerID.Valid {
			item.PeerID = peerID.String
			item.PeerPhone = peerPhone.String
		}
		if lastMessageAt.Valid {
			createdAt := lastMessageAt.Time
			item.LastMessageAt = &createdAt
		}
		chats = append(chats, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not load chats")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"chats": chats})
}

func (a *application) handleCreateDirectChat(w http.ResponseWriter, r *http.Request) {
	var request struct {
		UserID string `json:"user_id"`
		Phone  string `json:"phone"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	var peer user
	if request.UserID != "" {
		if !uuidPattern.MatchString(request.UserID) {
			writeError(w, http.StatusBadRequest, "invalid user ID")
			return
		}
		err := a.db.QueryRowContext(r.Context(),
			`SELECT id::text, display_name, phone FROM users WHERE id = $1`,
			request.UserID,
		).Scan(&peer.ID, &peer.Name, &peer.Phone)
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "user not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "could not find user")
			return
		}
	} else {
		phone, ok := normalizePhone(request.Phone)
		if !ok {
			writeError(w, http.StatusBadRequest, "enter a valid phone number")
			return
		}
		err := a.db.QueryRowContext(r.Context(),
			`SELECT id::text, display_name, phone FROM users WHERE phone = $1`,
			phone,
		).Scan(&peer.ID, &peer.Name, &peer.Phone)
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "no Voxa account uses this phone number")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "could not find user")
			return
		}
	}

	me := authenticatedUserID(r)
	if peer.ID == me {
		writeError(w, http.StatusBadRequest, "you cannot start a chat with yourself")
		return
	}
	keyIDs := []string{me, peer.ID}
	sort.Strings(keyIDs)
	directKey := keyIDs[0] + ":" + keyIDs[1]

	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not start chat")
		return
	}
	defer tx.Rollback()
	var chatID string
	err = tx.QueryRowContext(r.Context(),
		`INSERT INTO chats (kind, direct_key, created_by)
		 VALUES ('direct', $1, $2)
		 ON CONFLICT (direct_key) DO NOTHING
		 RETURNING id::text`,
		directKey, me,
	).Scan(&chatID)
	if errors.Is(err, sql.ErrNoRows) {
		err = tx.QueryRowContext(r.Context(),
			`SELECT id::text FROM chats WHERE direct_key = $1`,
			directKey,
		).Scan(&chatID)
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not start chat")
		return
	}
	for _, memberID := range []string{me, peer.ID} {
		if _, err := tx.ExecContext(r.Context(),
			`INSERT INTO chat_members (chat_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
			chatID, memberID,
		); err != nil {
			writeError(w, http.StatusInternalServerError, "could not start chat")
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not start chat")
		return
	}
	writeJSON(w, http.StatusOK, chat{ID: chatID, Name: peer.Name, PeerID: peer.ID, PeerPhone: peer.Phone})
}

func (a *application) handleCreateGroupChat(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Name    string   `json:"name"`
		Members []string `json:"members"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	a.createMultiMemberChat(w, r, request.Name, "", request.Members, "group")
}

func (a *application) handleCreateCommunity(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Name    string   `json:"name"`
		Type    string   `json:"type"`
		Members []string `json:"members"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	a.createMultiMemberChat(w, r, request.Name, request.Type, request.Members, "community")
}

func (a *application) createMultiMemberChat(
	w http.ResponseWriter,
	r *http.Request,
	name string,
	communityType string,
	memberIDs []string,
	kind string,
) {
	name = strings.TrimSpace(name)
	communityType = strings.TrimSpace(communityType)
	if utf8.RuneCountInString(name) < 1 || utf8.RuneCountInString(name) > 80 {
		writeError(w, http.StatusBadRequest, "group name must contain 1 to 80 characters")
		return
	}
	if kind == "community" && (utf8.RuneCountInString(communityType) < 1 ||
		utf8.RuneCountInString(communityType) > 40) {
		writeError(w, http.StatusBadRequest, "community type must contain 1 to 40 characters")
		return
	}
	if len(memberIDs) > 255 {
		writeError(w, http.StatusBadRequest, "a group can contain at most 256 members")
		return
	}
	memberSet := make(map[string]struct{}, len(memberIDs)+1)
	memberSet[authenticatedUserID(r)] = struct{}{}
	for _, memberID := range memberIDs {
		if !uuidPattern.MatchString(memberID) {
			writeError(w, http.StatusBadRequest, "invalid member ID")
			return
		}
		memberSet[memberID] = struct{}{}
	}
	if len(memberSet) < 2 {
		writeError(w, http.StatusBadRequest, "a group needs at least one other member")
		return
	}

	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create group")
		return
	}
	defer tx.Rollback()
	var chatID string
	if kind == "community" {
		err = tx.QueryRowContext(r.Context(),
			`INSERT INTO chats (kind, title, community_type, created_by)
			 VALUES ('community', $1, $2, $3) RETURNING id::text`,
			name, communityType, authenticatedUserID(r),
		).Scan(&chatID)
	} else {
		err = tx.QueryRowContext(r.Context(),
			`INSERT INTO chats (kind, title, created_by)
			 VALUES ('group', $1, $2) RETURNING id::text`,
			name, authenticatedUserID(r),
		).Scan(&chatID)
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create group")
		return
	}
	for memberID := range memberSet {
		result, err := tx.ExecContext(r.Context(),
			`INSERT INTO chat_members (chat_id, user_id)
			 SELECT $1, id FROM users WHERE id = $2`,
			chatID, memberID,
		)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "could not add group members")
			return
		}
		inserted, err := result.RowsAffected()
		if err != nil || inserted != 1 {
			writeError(w, http.StatusBadRequest, "one or more group members no longer exist")
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not create group")
		return
	}
	writeJSON(w, http.StatusCreated, chat{
		ID: chatID, Name: name, IsGroup: true,
		IsCommunity: kind == "community", CommunityType: communityType,
	})
}

func (a *application) handleMessages(w http.ResponseWriter, r *http.Request) {
	chatID := r.PathValue("chatID")
	if !uuidPattern.MatchString(chatID) {
		writeError(w, http.StatusBadRequest, "invalid chat ID")
		return
	}
	if err := a.requireChatMember(r.Context(), chatID, authenticatedUserID(r)); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusForbidden, "you are not a member of this chat")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not check chat membership")
		return
	}

	rows, err := a.db.QueryContext(r.Context(),
		`SELECT m.id::text, m.chat_id::text, m.sender_id::text,
		        u.display_name, m.content, m.created_at
		 FROM (
		     SELECT id, chat_id, sender_id, content, created_at
		     FROM messages WHERE chat_id = $1
		     ORDER BY created_at DESC, id DESC
		     LIMIT 100
		 ) m
		 JOIN users u ON u.id = m.sender_id
		 ORDER BY m.created_at, m.id`,
		chatID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load messages")
		return
	}
	defer rows.Close()

	messages := make([]message, 0)
	me := authenticatedUserID(r)
	for rows.Next() {
		var item message
		if err := rows.Scan(
			&item.ID, &item.ChatID, &item.SenderID, &item.Sender,
			&item.Content, &item.CreatedAt,
		); err != nil {
			writeError(w, http.StatusInternalServerError, "could not load messages")
			return
		}
		item.IsMe = item.SenderID == me
		messages = append(messages, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not load messages")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"messages": messages})
}

func (a *application) requireChatMember(ctx context.Context, chatID, userID string) error {
	var member bool
	err := a.db.QueryRowContext(ctx,
		`SELECT EXISTS (
		     SELECT 1 FROM chat_members WHERE chat_id = $1 AND user_id = $2
		 )`,
		chatID, userID,
	).Scan(&member)
	if err != nil {
		return err
	}
	if !member {
		return sql.ErrNoRows
	}
	return nil
}
