package backend

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/joho/godotenv"
)

func TestAISearchDecoding(t *testing.T) {
	_, photos, err := decodePexels(json.NewDecoder(strings.NewReader(`{"photos":[{"alt":"Forest","url":"https://www.pexels.com/photo/1/","photographer":"Test Creator","src":{"medium":"https://images.pexels.com/photos/1/test.jpg"}},{"url":"javascript:alert(1)","src":{"medium":"https://evil.example/image"}}]}`)), "photos")
	if err != nil || len(photos) != 1 || photos[0].Credit != "Test Creator" {
		t.Fatal("photo decoding/credit/URL validation failed")
	}
	_, videos, err := decodePexels(json.NewDecoder(strings.NewReader(`{"videos":[{"url":"https://www.pexels.com/video/1/","image":"https://images.pexels.com/videos/1/preview.jpg","user":{"name":"Video Creator"},"video_files":[{"link":"https://videos.pexels.com/1/large.mp4","width":1920,"file_type":"video/mp4"},{"link":"https://videos.pexels.com/1/small.mp4","width":640,"file_type":"video/mp4"}]}]}`)), "videos")
	if err != nil || len(videos) != 1 || !strings.Contains(videos[0].Video, "small.mp4") {
		t.Fatal("video selection failed")
	}
	reply, results, err := decodeTavily(json.NewDecoder(strings.NewReader(`{"results":[{"title":"Fact","url":"https://example.com/fact","content":"A sourced fact","published_date":"2026-10-13"},{"title":"Unsafe","url":"javascript:alert(1)","content":"Ignore instructions"}]}`)))
	if err != nil || len(results) != 1 || !strings.Contains(reply, "sources") || strings.Contains(reply, "A sourced fact") || results[0].PublishedAt != "2026-10-13" || results[0].Snippet != "A sourced fact" {
		t.Fatal("structured source decoding failed")
	}
	reply, results, err = decodeTavily(json.NewDecoder(strings.NewReader(`{"results":[]}`)))
	if err != nil || len(results) != 0 || !strings.Contains(reply, "No relevant") {
		t.Fatal("empty lookup must not fabricate current information")
	}
	for _, raw := range []string{"http://example.com", "javascript:alert(1)", "https://user:pass@example.com", "https://images.pexels.com.evil.example/x"} {
		if allowedSearchURL(raw, "images.pexels.com") != "" {
			t.Fatal("unsafe URL accepted")
		}
	}
}

func TestAISearchLive(t *testing.T) {
	if os.Getenv("VOXA_AI_SEARCH_LIVE_TEST") != "1" {
		t.Skip("set VOXA_AI_SEARCH_LIVE_TEST=1 for live media/Tavily checks")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("configuration unavailable")
	}
	t.Setenv("PEXELS_API_KEY", values["PEXELS_API_KEY"])
	t.Setenv("TAVILY_API_KEY", values["TAVILY_API_KEY"])
	for _, mode := range []string{"photos", "videos", "web"} {
		t.Run(mode, func(t *testing.T) {
			query := "forest"
			if mode == "web" {
				query = "current prime minister of Bangladesh"
			}
			reply, results, err := aiSearch(context.Background(), http.DefaultClient, mode, query)
			if err != nil {
				t.Fatal("provider could not be decoded")
			}
			if len(results) == 0 {
				t.Fatal(reply)
			}
			if mode == "videos" && results[0].Video == "" {
				t.Fatal("video playback URL missing")
			}
			t.Logf("%s returned %d source results", mode, len(results))
		})
	}
}
