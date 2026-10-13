package handler

import (
	"net/http/httptest"
	"testing"
)

func TestRequestWithOriginalPath(t *testing.T) {
	request := httptest.NewRequest("GET", "/api?__vercel_path=%2Fapi%2Fchats&limit=20", nil)
	rewritten := requestWithOriginalPath(request)
	if rewritten.URL.Path != "/api/chats" {
		t.Fatalf("request path = %q, want /api/chats", rewritten.URL.Path)
	}
	if got := rewritten.URL.Query().Get("limit"); got != "20" {
		t.Fatalf("request query limit = %q, want 20", got)
	}
	if got := rewritten.URL.Query().Get("__vercel_path"); got != "" {
		t.Fatalf("rewrite query parameter was not removed: %q", got)
	}
}
