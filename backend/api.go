package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type contextKey string

const userIDContextKey contextKey = "userID"

type apiError struct {
	Error string `json:"error"`
}

func (a *application) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /readyz", a.handleReady)
	mux.HandleFunc("POST /api/auth/register", a.handleRegister)
	mux.HandleFunc("POST /api/auth/login", a.handleLogin)
	mux.Handle("GET /api/auth/me", a.auth(http.HandlerFunc(a.handleMe)))
	mux.Handle("GET /api/profile", a.auth(http.HandlerFunc(a.handleProfile)))
	mux.Handle("PATCH /api/profile", a.auth(http.HandlerFunc(a.handleUpdateProfile)))
	mux.Handle("GET /api/users", a.auth(http.HandlerFunc(a.handleUsers)))
	mux.Handle("GET /api/chats", a.auth(http.HandlerFunc(a.handleListChats)))
	mux.Handle("POST /api/chats/direct", a.auth(http.HandlerFunc(a.handleCreateDirectChat)))
	mux.Handle("POST /api/chats/groups", a.auth(http.HandlerFunc(a.handleCreateGroupChat)))
	mux.Handle("POST /api/chats/communities", a.auth(http.HandlerFunc(a.handleCreateCommunity)))
	mux.Handle("GET /api/chats/{chatID}/messages", a.auth(http.HandlerFunc(a.handleMessages)))
	mux.Handle("GET /api/statuses", a.auth(http.HandlerFunc(a.handleListStatuses)))
	mux.Handle("POST /api/statuses", a.auth(http.HandlerFunc(a.handleCreateStatus)))
	mux.Handle("POST /api/statuses/{statusID}/view", a.auth(http.HandlerFunc(a.handleViewStatus)))
	mux.Handle("POST /api/media/upload", a.auth(http.HandlerFunc(a.handleUploadMedia)))
	mux.Handle("GET /api/calls", a.auth(http.HandlerFunc(a.handleCallHistory)))
	mux.Handle("GET /api/calls/incoming", a.auth(http.HandlerFunc(a.handleIncomingCalls)))
	mux.Handle("GET /api/calls/ice-config", a.auth(http.HandlerFunc(a.handleCallICEConfig)))
	mux.Handle("POST /api/calls", a.auth(http.HandlerFunc(a.handleCreateCall)))
	mux.Handle("POST /api/calls/{callID}/signal", a.auth(http.HandlerFunc(a.handleCallSignal)))
	mux.Handle("GET /api/calls/{callID}/signals", a.auth(http.HandlerFunc(a.handleCallSignals)))
	mux.Handle("POST /api/calls/{callID}/end", a.auth(http.HandlerFunc(a.handleEndCall)))
	mux.HandleFunc("GET /ws/{chatID}", a.handleWebSocket)
	return a.cors(mux)
}

func (a *application) handleReady(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.db.PingContext(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, "database is unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (a *application) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			if !a.originAllowed(origin) {
				writeError(w, http.StatusForbidden, "origin is not allowed")
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Add("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *application) configureOrigins(value string) {
	a.origins = make(map[string]struct{})
	for _, entry := range strings.Split(value, ",") {
		origin := strings.TrimSpace(strings.TrimRight(entry, "/"))
		if origin == "*" {
			a.allowAll = true
		} else if origin != "" {
			a.origins[origin] = struct{}{}
		}
	}
}

func (a *application) originAllowed(origin string) bool {
	if origin == "" {
		return true
	}
	if a.allowAll {
		return true
	}
	if _, ok := a.origins[origin]; ok {
		return true
	}
	parsed, err := url.Parse(origin)
	if err != nil {
		return false
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return false
	}
	host := parsed.Hostname()
	return host == "localhost" || host == "127.0.0.1" || host == "::1"
}

func (a *application) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		userID, err := a.userIDFromToken(token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "authentication required")
			return
		}
		ctx := context.WithValue(r.Context(), userIDContextKey, userID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func authenticatedUserID(r *http.Request) string {
	userID, _ := r.Context().Value(userIDContextKey).(string)
	return userID
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dst); err != nil {
		return errors.New("invalid JSON request")
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		return errors.New("request must contain only one JSON object")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, apiError{Error: message})
}
