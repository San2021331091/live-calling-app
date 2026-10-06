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
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/adaptor"
	"github.com/gofiber/fiber/v2/middleware/recover"
)

type contextKey string

const userIDContextKey contextKey = "userID"

type apiError struct {
	Error string `json:"error"`
}

func (a *application) routes() *fiber.App {
	server := fiber.New(fiber.Config{
		AppName:      "Voxa API",
		BodyLimit:    20 * 1024 * 1024,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 30 * time.Second,
	})
	server.Use(recover.New())
	server.Use(func(c *fiber.Ctx) error {
		origin := c.Get("Origin")
		if origin != "" {
			if !a.originAllowed(origin) {
				return c.Status(fiber.StatusForbidden).JSON(apiError{Error: "origin is not allowed"})
			}
			c.Set("Access-Control-Allow-Origin", origin)
			c.Append("Vary", "Origin")
			c.Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			c.Set("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS")
		}
		if c.Method() == fiber.MethodOptions {
			return c.SendStatus(fiber.StatusNoContent)
		}
		return c.Next()
	})

	register := func(method, path string, handler http.Handler, params ...string) {
		server.Add(method, path, func(c *fiber.Ctx) error {
			adapted := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				for _, name := range params {
					r.SetPathValue(name, c.Params(name))
				}
				handler.ServeHTTP(w, r)
			})
			return adaptor.HTTPHandler(adapted)(c)
		})
	}
	register("GET", "/healthz", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}))
	register("GET", "/readyz", http.HandlerFunc(a.handleReady))
	register("POST", "/api/auth/register", http.HandlerFunc(a.handleRegister))
	register("POST", "/api/auth/login", http.HandlerFunc(a.handleLogin))
	register("GET", "/api/auth/me", a.auth(http.HandlerFunc(a.handleMe)))
	register("GET", "/api/profile", a.auth(http.HandlerFunc(a.handleProfile)))
	register("PATCH", "/api/profile", a.auth(http.HandlerFunc(a.handleUpdateProfile)))
	register("GET", "/api/users", a.auth(http.HandlerFunc(a.handleUsers)))
	register("GET", "/api/chats", a.auth(http.HandlerFunc(a.handleListChats)))
	register("POST", "/api/chats/direct", a.auth(http.HandlerFunc(a.handleCreateDirectChat)))
	register("POST", "/api/chats/groups", a.auth(http.HandlerFunc(a.handleCreateGroupChat)))
	register("POST", "/api/chats/communities", a.auth(http.HandlerFunc(a.handleCreateCommunity)))
	register("GET", "/api/chats/:chatID/messages", a.auth(http.HandlerFunc(a.handleMessages)), "chatID")
	register("GET", "/api/statuses", a.auth(http.HandlerFunc(a.handleListStatuses)))
	register("POST", "/api/statuses", a.auth(http.HandlerFunc(a.handleCreateStatus)))
	register("POST", "/api/statuses/:statusID/view", a.auth(http.HandlerFunc(a.handleViewStatus)), "statusID")
	register("POST", "/api/media/upload", a.auth(http.HandlerFunc(a.handleUploadMedia)))
	register("GET", "/api/calls", a.auth(http.HandlerFunc(a.handleCallHistory)))
	register("GET", "/api/calls/incoming", a.auth(http.HandlerFunc(a.handleIncomingCalls)))
	register("GET", "/api/calls/ice-config", a.auth(http.HandlerFunc(a.handleCallICEConfig)))
	register("POST", "/api/calls", a.auth(http.HandlerFunc(a.handleCreateCall)))
	register("POST", "/api/calls/:callID/signal", a.auth(http.HandlerFunc(a.handleCallSignal)), "callID")
	register("GET", "/api/calls/:callID/signals", a.auth(http.HandlerFunc(a.handleCallSignals)), "callID")
	register("POST", "/api/calls/:callID/end", a.auth(http.HandlerFunc(a.handleEndCall)), "callID")
	register("GET", "/ws/:chatID", http.HandlerFunc(a.handleWebSocket), "chatID")
	return server
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
