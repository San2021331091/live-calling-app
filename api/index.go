package handler

import (
	"net/http"

	backendapi "github.com/San2021331091/live-calling-app/vercel/backend/api"
)

func Handler(w http.ResponseWriter, r *http.Request) {
	backendapi.Handler(w, r)
}
