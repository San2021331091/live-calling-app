package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

type aiSearchResult struct {
	Kind        string `json:"kind"`
	Title       string `json:"title"`
	URL         string `json:"url"`
	Preview     string `json:"preview,omitempty"`
	Video       string `json:"video,omitempty"`
	Credit      string `json:"credit,omitempty"`
	Snippet     string `json:"snippet,omitempty"`
	PublishedAt string `json:"published_at,omitempty"`
}

// Search only calls fixed provider endpoints, never URLs supplied by users/results.
func aiSearch(ctx context.Context, client *http.Client, mode, query string) (string, []aiSearchResult, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	if mode == "web" {
		return tavilySearch(ctx, client, query)
	}
	endpoint := ""
	if mode == "photos" {
		endpoint = "https://api.pexels.com/v1/search?per_page=6&query=" + url.QueryEscape(query)
	}
	if mode == "videos" {
		endpoint = "https://api.pexels.com/v1/videos/search?per_page=6&query=" + url.QueryEscape(query)
	}
	if endpoint == "" {
		return "", nil, errAIUnavailable
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return "", nil, errAIUnavailable
	}
	req.Header.Set("User-Agent", "VoxaAI/1.0")
	if mode != "web" {
		key := strings.TrimSpace(os.Getenv("PEXELS_API_KEY"))
		if key == "" {
			return "Media search is not configured yet. Please try again later.", []aiSearchResult{}, nil
		}
		req.Header.Set("Authorization", key)
	}
	response, err := client.Do(req)
	if err != nil {
		return "Search is unavailable right now. Please try again shortly.", []aiSearchResult{}, nil
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return "The search provider is unavailable or its usage limit has been reached. Please try again later.", []aiSearchResult{}, nil
	}
	decoder := json.NewDecoder(io.LimitReader(response.Body, 2<<20))
	return decodePexels(decoder, mode)
}

var errSearchNotConfigured = errors.New("search not configured")
var errSearchUnavailable = errors.New("search unavailable")

func tavilySearch(ctx context.Context, client *http.Client, query string) (string, []aiSearchResult, error) {
	key := strings.TrimSpace(os.Getenv("TAVILY_API_KEY"))
	if key == "" {
		return "", nil, errSearchNotConfigured
	}
	body, _ := json.Marshal(map[string]any{"query": query, "search_depth": "basic", "max_results": 3, "topic": "general", "include_published_date": true, "include_answer": false, "include_raw_content": false, "auto_parameters": false, "safe_search": true})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.tavily.com/search", bytes.NewReader(body))
	if err != nil {
		return "", nil, errSearchUnavailable
	}
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", "application/json")
	response, err := client.Do(req)
	if err != nil {
		return "", nil, errSearchUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", nil, errSearchUnavailable
	}
	return decodeTavily(json.NewDecoder(io.LimitReader(response.Body, 2<<20)))
}

func decodeTavily(decoder *json.Decoder) (string, []aiSearchResult, error) {
	var data struct {
		Results []struct {
			Title, URL, Content string
			PublishedDate       string `json:"published_date"`
		}
	}
	if err := decoder.Decode(&data); err != nil {
		return "", nil, errSearchUnavailable
	}
	results := []aiSearchResult{}
	for _, r := range data.Results {
		link := allowedSearchURL(r.URL)
		if link == "" || strings.TrimSpace(r.Content) == "" {
			continue
		}
		parsed, _ := url.Parse(link)
		snippet := []rune(strings.TrimSpace(r.Content))
		if len(snippet) > 2400 {
			snippet = snippet[:2400]
		}
		result := aiSearchResult{Kind: "web", Title: r.Title, URL: link, Credit: parsed.Hostname(), Snippet: string(snippet), PublishedAt: r.PublishedDate}
		results = append(results, result)
		if len(results) == 3 {
			break
		}
	}
	if len(results) == 0 {
		return "No relevant web results were found. Try a more specific question.", results, nil
	}
	return "Relevant web sources were found.", results, nil
}

func allowedSearchURL(raw string, hosts ...string) string {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Hostname() == "" || u.Port() != "" {
		return ""
	}
	if len(hosts) == 0 {
		return raw
	}
	for _, host := range hosts {
		if strings.EqualFold(u.Hostname(), host) {
			return raw
		}
	}
	return ""
}

func decodePexels(decoder *json.Decoder, mode string) (string, []aiSearchResult, error) {
	var data struct {
		Photos []struct {
			Alt, URL, Photographer string
			Src                    struct{ Medium string }
		}
		Videos []struct {
			URL, Image string
			User       struct{ Name string }
			Files      []struct {
				Link  string
				Width int
				Type  string `json:"file_type"`
			} `json:"video_files"`
		}
	}
	if err := decoder.Decode(&data); err != nil {
		return "", nil, errAIUnavailable
	}
	results := []aiSearchResult{}
	for _, p := range data.Photos {
		link := allowedSearchURL(p.URL, "www.pexels.com", "pexels.com")
		preview := allowedSearchURL(p.Src.Medium, "images.pexels.com")
		if link == "" || preview == "" {
			continue
		}
		results = append(results, aiSearchResult{Kind: "photo", Title: p.Alt, URL: link, Preview: preview, Credit: p.Photographer})
		if len(results) == 6 {
			break
		}
	}
	for _, v := range data.Videos {
		link := allowedSearchURL(v.URL, "www.pexels.com", "pexels.com")
		preview := allowedSearchURL(v.Image, "images.pexels.com")
		if link == "" || preview == "" {
			continue
		}
		video := ""
		width := 0
		for _, f := range v.Files {
			if f.Type == "video/mp4" && f.Width > 0 && (width == 0 || f.Width < width) {
				if candidate := allowedSearchURL(f.Link, "videos.pexels.com", "player.vimeo.com", "vod-progressive.akamaized.net"); candidate != "" {
					video = candidate
					width = f.Width
				}
			}
		}
		results = append(results, aiSearchResult{Kind: "video", Title: "Video by " + v.User.Name, URL: link, Preview: preview, Video: video, Credit: v.User.Name})
		if len(results) == 6 {
			break
		}
	}
	if len(results) == 0 {
		return "No matching results. Try a shorter or different search.", results, nil
	}
	return "Here are your " + mode + ". Tap a result to view it; creator credits are shown below.", results, nil
}
