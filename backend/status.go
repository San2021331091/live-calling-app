package main

import (
	"database/sql"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"
)

type statusRecord struct {
	ID      string    `json:"id"`
	Name    string    `json:"name"`
	Image   string    `json:"image"`
	Time    time.Time `json:"time"`
	Seen    bool      `json:"seen"`
	IsVideo bool      `json:"is_video"`
	Caption string    `json:"caption,omitempty"`
	IsMine  bool      `json:"is_mine"`
}

func (a *application) handleListStatuses(w http.ResponseWriter, r *http.Request) {
	userID := authenticatedUserID(r)
	_, _ = a.db.ExecContext(r.Context(), `DELETE FROM statuses WHERE expires_at <= now()`)
	rows, err := a.db.QueryContext(r.Context(),
		`SELECT s.id::text, u.display_name, s.media_url, s.created_at, s.media_type, s.caption,
		        (s.user_id = $1),
		        EXISTS (SELECT 1 FROM status_views v WHERE v.status_id = s.id AND v.viewer_id = $1)
		 FROM statuses s JOIN users u ON u.id = s.user_id
		 WHERE s.expires_at > now() AND (
		     s.user_id = $1 OR EXISTS (
		         SELECT 1 FROM chat_members mine
		         JOIN chat_members contact ON contact.chat_id = mine.chat_id
		         WHERE mine.user_id = $1 AND contact.user_id = s.user_id
		     )
		 )
		 ORDER BY s.created_at DESC LIMIT 100`, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load statuses")
		return
	}
	defer rows.Close()

	statuses := make([]statusRecord, 0)
	for rows.Next() {
		var item statusRecord
		var mediaType string
		if err := rows.Scan(&item.ID, &item.Name, &item.Image, &item.Time, &mediaType, &item.Caption, &item.IsMine, &item.Seen); err != nil {
			writeError(w, http.StatusInternalServerError, "could not load statuses")
			return
		}
		item.IsVideo = mediaType == "video"
		statuses = append(statuses, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not load statuses")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"statuses": statuses})
}

func (a *application) handleCreateStatus(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Image   string `json:"image"`
		IsVideo bool   `json:"is_video"`
		Caption string `json:"caption"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	imageURL := strings.TrimSpace(request.Image)
	parsed, err := url.ParseRequestURI(imageURL)
	if err != nil || (parsed.Scheme != "https" && parsed.Scheme != "http") || parsed.Host == "" || utf8.RuneCountInString(imageURL) > 2048 {
		writeError(w, http.StatusBadRequest, "status image must be a valid HTTP URL")
		return
	}
	if utf8.RuneCountInString(request.Caption) > 500 {
		writeError(w, http.StatusBadRequest, "status caption is too long")
		return
	}
	mediaType := "image"
	if request.IsVideo {
		mediaType = "video"
	}
	var item statusRecord
	var storedType string
	err = a.db.QueryRowContext(r.Context(),
		`INSERT INTO statuses (user_id, media_url, media_type, caption)
		 SELECT id, $2, $3, $4 FROM users WHERE id = $1
		 RETURNING id::text, media_url, created_at, media_type, caption`,
		authenticatedUserID(r), imageURL, mediaType, strings.TrimSpace(request.Caption),
	).Scan(&item.ID, &item.Image, &item.Time, &storedType, &item.Caption)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusUnauthorized, "account no longer exists")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not save status")
		return
	}
	if err := a.db.QueryRowContext(r.Context(),
		`SELECT display_name FROM users WHERE id = $1`, authenticatedUserID(r),
	).Scan(&item.Name); err != nil {
		writeError(w, http.StatusInternalServerError, "could not load account name")
		return
	}
	item.IsMine = true
	item.IsVideo = storedType == "video"
	writeJSON(w, http.StatusCreated, item)
}

func (a *application) handleViewStatus(w http.ResponseWriter, r *http.Request) {
	statusID := r.PathValue("statusID")
	if !uuidPattern.MatchString(statusID) {
		writeError(w, http.StatusBadRequest, "invalid status ID")
		return
	}
	viewerID := authenticatedUserID(r)
	var accessible bool
	err := a.db.QueryRowContext(r.Context(),
		`SELECT EXISTS (
		     SELECT 1 FROM statuses s
		     WHERE s.id = $1 AND s.user_id <> $2 AND s.expires_at > now()
		       AND EXISTS (
		           SELECT 1 FROM chat_members mine
		           JOIN chat_members contact ON contact.chat_id = mine.chat_id
		           WHERE mine.user_id = $2 AND contact.user_id = s.user_id
		       )
		 )`, statusID, viewerID,
	).Scan(&accessible)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not check status access")
		return
	}
	if !accessible {
		writeError(w, http.StatusNotFound, "status not found")
		return
	}
	_, err = a.db.ExecContext(r.Context(),
		`INSERT INTO status_views (status_id, viewer_id) VALUES ($1, $2)
		 ON CONFLICT (status_id, viewer_id) DO NOTHING`, statusID, viewerID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not mark status as viewed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"seen": true})
}
