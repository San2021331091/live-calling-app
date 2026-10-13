package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/adaptor"
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

func TestRewrittenRequestPreservesQueryThroughFiber(t *testing.T) {
	app := fiber.New()
	app.Get("/api/calls/:callID/signals", func(c *fiber.Ctx) error {
		return c.JSON(map[string]string{"after": c.Query("after")})
	})
	handler := adaptor.FiberApp(app)
	for _, after := range []string{"0", "1791913332759001"} {
		for _, staleURI := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/staleURI=%t", after, staleURI), func(t *testing.T) {
				query := url.Values{"__vercel_path": {"/api/calls/test-call/signals"}, "after": {after}}
				request := httptest.NewRequest(http.MethodGet, "/api?"+query.Encode(), nil)
				if staleURI {
					request.RequestURI = "/api/calls/test-call/signals"
				}
				originalURI := request.RequestURI
				originalURL := request.URL.String()
				rewritten := requestWithOriginalPath(request)
				response := httptest.NewRecorder()
				handler.ServeHTTP(response, rewritten)
				if response.Code != http.StatusOK {
					t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
				}
				var result map[string]string
				if err := json.Unmarshal(response.Body.Bytes(), &result); err != nil {
					t.Fatal(err)
				}
				if result["after"] != after {
					t.Fatalf("after = %q, want %q", result["after"], after)
				}
				if request.RequestURI != originalURI || request.URL.String() != originalURL {
					t.Fatal("original request was mutated")
				}
				if rewritten.URL.Query().Has("__vercel_path") {
					t.Fatal("internal rewrite parameter was forwarded")
				}
			})
		}
	}
}

func TestRequestWithOriginalRootPath(t *testing.T) {
	request := httptest.NewRequest("GET", "/api?__vercel_path=/", nil)
	rewritten := requestWithOriginalPath(request)
	if rewritten.URL.Path != "/" {
		t.Fatalf("request path = %q, want /", rewritten.URL.Path)
	}
	if got := rewritten.URL.Query().Get("__vercel_path"); got != "" {
		t.Fatalf("rewrite query parameter was not removed: %q", got)
	}
}
