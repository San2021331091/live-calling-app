package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"os"
	"strconv"
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
	request.Type = strings.TrimSpace(request.Type)
	if request.Type != "offer" && request.Type != "answer" && request.Type != "ice" {
		writeError(w, http.StatusBadRequest, "signal type must be offer, answer, or ice")
		return
	}
	var peerID string
	err := a.db.QueryRowContext(r.Context(),
		`SELECT CASE WHEN caller_id = $2 THEN callee_id ELSE caller_id END::text
		 FROM calls WHERE id = $1 AND (caller_id = $2 OR callee_id = $2)
		              AND status IN ('started', 'active')`,
		callID, authenticatedUserID(r),
	).Scan(&peerID)
	if err != nil {
		if err == sql.ErrNoRows {
			writeError(w, http.StatusForbidden, "call is unavailable or you are not a participant")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not validate call signal")
		return
	}
	if request.TargetID != "" && request.TargetID != peerID {
		writeError(w, http.StatusBadRequest, "target must be the other call participant")
		return
	}
	var payload []byte
	if len(request.Payload) == 0 {
		payload = []byte(`{}`)
	} else {
		payload = request.Payload
	}
	var sequence int64
	err = a.db.QueryRowContext(r.Context(),
		`INSERT INTO call_signals (call_id, sender_id, target_id, signal_type, payload)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING sequence`,
		callID, authenticatedUserID(r), peerID, request.Type, payload,
	).Scan(&sequence)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not record call signal")
		return
	}
	if request.Type == "answer" {
		if _, err := a.db.ExecContext(r.Context(),
			`UPDATE calls SET status = 'active'
			 WHERE id = $1 AND status = 'started'`,
			callID,
		); err != nil {
			writeError(w, http.StatusInternalServerError, "could not mark call as active")
			return
		}
	}
	writeJSON(w, http.StatusAccepted, map[string]any{"sequence": sequence, "type": request.Type, "call_id": callID})
}

func (a *application) handleIncomingCalls(w http.ResponseWriter, r *http.Request) {
	if _, err := a.db.ExecContext(r.Context(),
		`UPDATE calls SET status = 'missed', ended_at = now()
		 WHERE callee_id = $1 AND status = 'started'
		       AND started_at <= now() - interval '2 minutes'`,
		authenticatedUserID(r),
	); err != nil {
		writeError(w, http.StatusInternalServerError, "could not expire unanswered calls")
		return
	}
	rows, err := a.db.QueryContext(r.Context(),
		`SELECT c.id::text, c.caller_id::text, c.callee_id::text, c.kind, c.status,
		        c.started_at, u.id::text, u.display_name
		 FROM calls c JOIN users u ON u.id = c.caller_id
		 WHERE c.callee_id = $1 AND c.status = 'started'
		       AND c.started_at > now() - interval '2 minutes'
		 ORDER BY c.started_at DESC
		 LIMIT 10`,
		authenticatedUserID(r),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not check incoming calls")
		return
	}
	defer rows.Close()

	calls := make([]callRecord, 0, 2)
	for rows.Next() {
		var call callRecord
		if err := rows.Scan(
			&call.ID, &call.CallerID, &call.CalleeID, &call.Kind, &call.Status,
			&call.StartedAt, &call.PeerID, &call.PeerName,
		); err != nil {
			writeError(w, http.StatusInternalServerError, "could not read incoming calls")
			return
		}
		calls = append(calls, call)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not read incoming calls")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"calls": calls})
}

func (a *application) handleCallICEConfig(w http.ResponseWriter, _ *http.Request) {
	iceServers := []map[string]any{
		{"urls": "stun:stun.l.google.com:19302"},
		{"urls": "stun:stun1.l.google.com:19302"},
		{"urls": "stun:stun2.l.google.com:19302"},
		{"urls": "stun:stun3.l.google.com:19302"},
		{"urls": "stun:stun4.l.google.com:19302"},
	}
	rawTurnURLs := strings.FieldsFunc(os.Getenv("TURN_URLS"), func(r rune) bool {
		return r == ',' || r == '\n'
	})
	turnURLs := make([]string, 0, len(rawTurnURLs))
	for _, turnURL := range rawTurnURLs {
		if turnURL = strings.TrimSpace(turnURL); turnURL != "" {
			turnURLs = append(turnURLs, turnURL)
		}
	}
	if len(turnURLs) > 0 {
		sharedSecret := os.Getenv("TURN_SHARED_SECRET")
		if len(sharedSecret) < 32 {
			writeError(w, http.StatusServiceUnavailable, "TURN server is configured without a valid shared secret")
			return
		}
		username := strconv.FormatInt(time.Now().Add(time.Hour).Unix(), 10)
		mac := hmac.New(sha1.New, []byte(sharedSecret))
		_, _ = mac.Write([]byte(username))
		credential := base64.StdEncoding.EncodeToString(mac.Sum(nil))
		for _, turnURL := range turnURLs {
			if !strings.HasPrefix(turnURL, "turn:") && !strings.HasPrefix(turnURL, "turns:") {
				writeError(w, http.StatusInternalServerError, "TURN_URLS entries must use the turn: or turns: scheme")
				return
			}
			iceServers = append(iceServers, map[string]any{
				"urls": turnURL, "username": username, "credential": credential,
			})
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"ice_servers": iceServers})
}

func (a *application) handleCallSignals(w http.ResponseWriter, r *http.Request) {
	callID := r.PathValue("callID")
	if !uuidPattern.MatchString(callID) {
		writeError(w, http.StatusBadRequest, "invalid call ID")
		return
	}
	after, err := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
	if err != nil || after < 0 {
		writeError(w, http.StatusBadRequest, "after must be a non-negative signal sequence")
		return
	}
	var callStatus string
	err = a.db.QueryRowContext(r.Context(),
		`SELECT status FROM calls
		 WHERE id = $1 AND (caller_id = $2 OR callee_id = $2)`,
		callID, authenticatedUserID(r),
	).Scan(&callStatus)
	if err != nil {
		if err == sql.ErrNoRows {
			writeError(w, http.StatusForbidden, "you are not part of this call")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not validate call")
		return
	}
	rows, err := a.db.QueryContext(r.Context(),
		`SELECT s.sequence, s.sender_id::text, s.signal_type, s.payload
		 FROM call_signals s
		 JOIN calls c ON c.id = s.call_id
		 WHERE s.call_id = $1 AND s.sequence > $2
		       AND (c.caller_id = $3 OR c.callee_id = $3)
		       AND (s.target_id IS NULL OR s.target_id = $3)
		       AND s.sender_id <> $3
		 ORDER BY s.sequence ASC
		 LIMIT 100`,
		callID, after, authenticatedUserID(r),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load call signals")
		return
	}
	defer rows.Close()

	signals := make([]map[string]any, 0, 8)
	for rows.Next() {
		var sequence int64
		var senderID, signalType string
		var payload json.RawMessage
		if err := rows.Scan(&sequence, &senderID, &signalType, &payload); err != nil {
			writeError(w, http.StatusInternalServerError, "could not read call signals")
			return
		}
		signals = append(signals, map[string]any{
			"sequence": sequence, "sender_id": senderID, "type": signalType, "payload": payload,
		})
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "could not read call signals")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": callStatus, "signals": signals})
}

func (a *application) handleEndCall(w http.ResponseWriter, r *http.Request) {
	callID := r.PathValue("callID")
	if !uuidPattern.MatchString(callID) {
		writeError(w, http.StatusBadRequest, "invalid call ID")
		return
	}
	var request struct {
		Status string `json:"status"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	status := strings.TrimSpace(request.Status)
	if status != "ended" && status != "missed" {
		writeError(w, http.StatusBadRequest, "call status must be ended or missed")
		return
	}
	var updatedStatus string
	err := a.db.QueryRowContext(r.Context(),
		`UPDATE calls SET status = $3, ended_at = now()
		 WHERE id = $1 AND (caller_id = $2 OR callee_id = $2) AND status = 'started'
		       AND ($3 <> 'missed' OR callee_id = $2)
		 RETURNING status`,
		callID, authenticatedUserID(r), status,
	).Scan(&updatedStatus)
	if err != nil {
		if err == sql.ErrNoRows {
			writeError(w, http.StatusConflict, "call has already ended or cannot be declined")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not end call")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": updatedStatus})
}
