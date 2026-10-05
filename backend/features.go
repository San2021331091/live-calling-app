package main

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
)

type mediaUploadRequest struct {
	FileName    string `json:"file_name"`
	ContentType string `json:"content_type"`
	Data        string `json:"data"`
}

type callRecord struct {
	ID        string     `json:"id"`
	CallerID  string     `json:"caller_id"`
	CalleeID  string     `json:"callee_id"`
	Kind      string     `json:"kind"`
	Status    string     `json:"status"`
	StartedAt time.Time  `json:"started_at"`
	EndedAt   *time.Time `json:"ended_at,omitempty"`
	PeerID    string     `json:"peer_id,omitempty"`
	PeerName  string     `json:"peer_name,omitempty"`
}

func (a *application) handleUploadMedia(w http.ResponseWriter, r *http.Request) {
	var request mediaUploadRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	payload := strings.TrimSpace(request.Data)
	if payload == "" {
		writeError(w, http.StatusBadRequest, "media content is required")
		return
	}
	decoded, err := base64.StdEncoding.DecodeString(payload)
	if err != nil {
		writeError(w, http.StatusBadRequest, "media data must be valid base64")
		return
	}
	if len(decoded) == 0 || len(decoded) > 5<<20 {
		writeError(w, http.StatusBadRequest, "media must be between 1 byte and 5 MB")
		return
	}
	contentType := strings.TrimSpace(request.ContentType)
	if contentType == "" {
		contentType = http.DetectContentType(decoded)
	}
	if utf8.RuneCountInString(request.FileName) > 120 {
		writeError(w, http.StatusBadRequest, "file name is too long")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"file_name":    strings.TrimSpace(request.FileName),
		"content_type": contentType,
		"size":         len(decoded),
		"media_url":    "data:" + contentType + ";base64," + base64.StdEncoding.EncodeToString(decoded),
	})
}

func (a *application) handleCallHistory(w http.ResponseWriter, r *http.Request) {
	rows, err := a.db.QueryContext(r.Context(),
		`SELECT c.id::text, c.caller_id::text, c.callee_id::text,
		        c.kind, c.status, c.started_at, c.ended_at,
		        peer.id::text, COALESCE(peer.display_name, '')
		 FROM calls c
		 LEFT JOIN users peer ON peer.id = CASE WHEN c.caller_id = $1 THEN c.callee_id ELSE c.caller_id END
		 WHERE c.caller_id = $1 OR c.callee_id = $1
		 ORDER BY c.started_at DESC
		 LIMIT 100`,
		authenticatedUserID(r),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load call history")
		return
	}
	defer rows.Close()

	calls := make([]callRecord, 0, 32)
	me := authenticatedUserID(r)
	for rows.Next() {
		var call callRecord
		var endedAt sql.NullTime
		var peerID sql.NullString
		var peerName string
		if err := rows.Scan(&call.ID, &call.CallerID, &call.CalleeID, &call.Kind, &call.Status, &call.StartedAt, &endedAt, &peerID, &peerName); err != nil {
			writeError(w, http.StatusInternalServerError, "could not load call history")
			return
		}
		if endedAt.Valid {
			ended := endedAt.Time
			call.EndedAt = &ended
		}
		if call.CallerID == me {
			call.PeerID = call.CalleeID
		} else {
			call.PeerID = call.CallerID
		}
		if peerID.Valid {
			call.PeerID = peerID.String
		}
		call.PeerName = peerName
		calls = append(calls, call)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not load call history")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"calls": calls})
}

func (a *application) handleCreateCall(w http.ResponseWriter, r *http.Request) {
	var request struct {
		PeerID string `json:"peer_id"`
		Kind   string `json:"kind"`
		Status string `json:"status"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	peerID := strings.TrimSpace(request.PeerID)
	if !uuidPattern.MatchString(peerID) {
		writeError(w, http.StatusBadRequest, "invalid peer ID")
		return
	}
	if peerID == authenticatedUserID(r) {
		writeError(w, http.StatusBadRequest, "you cannot call yourself")
		return
	}
	callKind := strings.TrimSpace(request.Kind)
	if callKind == "" {
		callKind = "audio"
	}
	if callKind != "audio" && callKind != "video" {
		writeError(w, http.StatusBadRequest, "call kind must be audio or video")
		return
	}
	status := strings.TrimSpace(request.Status)
	if status == "" {
		status = "started"
	}
	if status != "started" && status != "missed" && status != "ended" {
		writeError(w, http.StatusBadRequest, "call status is invalid")
		return
	}
	var exists bool
	if err := a.db.QueryRowContext(r.Context(), `SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)`, peerID).Scan(&exists); err != nil {
		writeError(w, http.StatusInternalServerError, "could not validate peer")
		return
	}
	if !exists {
		writeError(w, http.StatusNotFound, "peer not found")
		return
	}
	var call callRecord
	err := a.db.QueryRowContext(r.Context(),
		`INSERT INTO calls (caller_id, callee_id, kind, status)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id::text, caller_id::text, callee_id::text, kind, status, started_at, ended_at`,
		authenticatedUserID(r), peerID, callKind, status,
	).Scan(&call.ID, &call.CallerID, &call.CalleeID, &call.Kind, &call.Status, &call.StartedAt, &call.EndedAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create call record")
		return
	}
	call.PeerID = peerID
	writeJSON(w, http.StatusCreated, call)
}

func (a *application) handleCallSignal(w http.ResponseWriter, r *http.Request) {
	callID := r.PathValue("callID")
	if !uuidPattern.MatchString(callID) {
		writeError(w, http.StatusBadRequest, "invalid call ID")
		return
	}
	var request struct {
		Type     string          `json:"type"`
		TargetID string          `json:"target_id"`
		Payload  json.RawMessage `json:"payload"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(request.Type) == "" {
		request.Type = "offer"
	}
	var allowed bool
	err := a.db.QueryRowContext(r.Context(),
		`SELECT EXISTS (
			SELECT 1 FROM calls
			WHERE id = $1 AND (caller_id = $2 OR callee_id = $2)
		)`, callID, authenticatedUserID(r),
	).Scan(&allowed)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not validate call signal")
		return
	}
	if !allowed {
		writeError(w, http.StatusForbidden, "you are not part of this call")
		return
	}
	if request.TargetID != "" && !uuidPattern.MatchString(request.TargetID) {
		writeError(w, http.StatusBadRequest, "invalid target user ID")
		return
	}
	var payload []byte
	if len(request.Payload) == 0 {
		payload = []byte(`{}`)
	} else {
		payload = request.Payload
	}
	var signalID string
	err = a.db.QueryRowContext(r.Context(),
		`INSERT INTO call_signals (call_id, sender_id, target_id, signal_type, payload)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id::text`,
		callID, authenticatedUserID(r), request.TargetID, request.Type, payload,
	).Scan(&signalID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not record call signal")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{"id": signalID, "type": request.Type, "call_id": callID})
}
