package handler

import (
	"net/http"

	backendapi "backend/api"
)

func Handler(w http.ResponseWriter, r *http.Request) {
	backendapi.Handler(w, r)
}
