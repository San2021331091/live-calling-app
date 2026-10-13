package handler

import (
	"context"
	"log"
	"net/http"
	"sync"
	"time"

	"backend"
)

var (
	handlerOnce sync.Once
	apiHandler  http.Handler
	handlerErr  error
)

func Handler(w http.ResponseWriter, r *http.Request) {
	handlerOnce.Do(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		apiHandler, handlerErr = backend.NewVercelHandler(ctx)
	})
	if handlerErr != nil {
		log.Printf("initialize Vercel API function: %v", handlerErr)
		http.Error(w, "API initialization failed", http.StatusServiceUnavailable)
		return
	}
	request := requestWithOriginalPath(r)
	apiHandler.ServeHTTP(w, request)
}

func requestWithOriginalPath(r *http.Request) *http.Request {
	request := r.Clone(r.Context())
	urlCopy := *request.URL
	query := urlCopy.Query()
	if originalPath := query.Get("__vercel_path"); originalPath != "" {
		urlCopy.Path = originalPath
		urlCopy.RawPath = ""
		query.Del("__vercel_path")
		urlCopy.RawQuery = query.Encode()
	}
	request.URL = &urlCopy
	return request
}
