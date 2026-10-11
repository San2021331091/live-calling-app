package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"io"
	"mime"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

const maxFileBytes = 15 << 20

// The key grants access to this single file, without exposing an account token.
func (a *application) fileKey(id string) string {
	mac := hmac.New(sha256.New, a.jwtSecret)
	mac.Write([]byte("voxa-file:" + id))
	return hex.EncodeToString(mac.Sum(nil))
}

func (a *application) handleUploadFile(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxFileBytes+(1<<20))
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "select a file up to 15 MB")
		return
	}
	if r.MultipartForm != nil {
		defer r.MultipartForm.RemoveAll()
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "file is required")
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxFileBytes+1))
	if err != nil || len(data) == 0 || len(data) > maxFileBytes {
		writeError(w, http.StatusBadRequest, "file must contain 1 byte to 15 MB")
		return
	}
	name := strings.TrimSpace(filepath.Base(strings.ReplaceAll(header.Filename, "\\", "/")))
	if name == "" || utf8.RuneCountInString(name) > 240 {
		writeError(w, http.StatusBadRequest, "invalid file name")
		return
	}
	contentType := http.DetectContentType(data)
	if contentType == "application/octet-stream" {
		if typed := mime.TypeByExtension(filepath.Ext(name)); typed != "" {
			contentType = typed
		}
	}
	var id string
	err = a.db.QueryRowContext(r.Context(), `INSERT INTO shared_files(owner_id,file_name,content_type,content) VALUES($1,$2,$3,$4) RETURNING id::text`, authenticatedUserID(r), name, contentType, data).Scan(&id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not store file")
		return
	}
	path := "/api/files/" + id + "?key=" + url.QueryEscape(a.fileKey(id))
	writeJSON(w, http.StatusCreated, map[string]any{"file_name": name, "size": len(data), "media_url": path})
}

func (a *application) handleDownloadFile(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("fileID")
	if !uuidPattern.MatchString(id) || !hmac.Equal([]byte(r.URL.Query().Get("key")), []byte(a.fileKey(id))) {
		writeError(w, http.StatusForbidden, "file access denied")
		return
	}
	var name, contentType string
	var data []byte
	var created time.Time
	err := a.db.QueryRowContext(r.Context(), `SELECT file_name,content_type,content,created_at FROM shared_files WHERE id=$1`, id).Scan(&name, &contentType, &data, &created)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "file not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load file")
		return
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "private, max-age=3600")
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": name}))
	http.ServeContent(w, r, name, created, bytes.NewReader(data))
}
