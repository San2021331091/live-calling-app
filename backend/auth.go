package main

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
)

var nonDigit = regexp.MustCompile(`\D`)
var invalidPhoneCharacter = regexp.MustCompile(`[^+0-9().\s-]`)
var uuidPattern = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

type user struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Phone     string `json:"phone"`
	AvatarURL string `json:"avatar_url,omitempty"`
	Bio       string `json:"bio,omitempty"`
}

type authRequest struct {
	Name     string `json:"name"`
	Phone    string `json:"phone"`
	Password string `json:"password"`
}

func (a *application) handleRegister(w http.ResponseWriter, r *http.Request) {
	var request authRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	request.Name = strings.TrimSpace(request.Name)
	phone, ok := normalizePhone(request.Phone)
	if utf8.RuneCountInString(request.Name) < 1 || utf8.RuneCountInString(request.Name) > 80 {
		writeError(w, http.StatusBadRequest, "name must contain 1 to 80 characters")
		return
	}
	if !ok {
		writeError(w, http.StatusBadRequest, "enter a valid phone number")
		return
	}
	if utf8.RuneCountInString(request.Password) < 6 || utf8.RuneCountInString(request.Password) > 72 {
		writeError(w, http.StatusBadRequest, "password must contain 6 to 72 characters")
		return
	}

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(request.Password), bcrypt.DefaultCost)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create account")
		return
	}
	var created user
	err = a.db.QueryRowContext(r.Context(),
		`INSERT INTO users (display_name, phone, password_hash)
		 VALUES ($1, $2, $3)
		 RETURNING id::text, display_name, phone`,
		request.Name, phone, string(passwordHash),
	).Scan(&created.ID, &created.Name, &created.Phone)
	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "an account with this phone number already exists")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not create account")
		return
	}

	a.writeAuthResponse(w, created)
}

func (a *application) handleLogin(w http.ResponseWriter, r *http.Request) {
	var request authRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	phone, ok := normalizePhone(request.Phone)
	if !ok || request.Password == "" {
		writeError(w, http.StatusUnauthorized, "phone number or password is incorrect")
		return
	}

	var authenticated user
	var passwordHash string
	err := a.db.QueryRowContext(r.Context(),
		`SELECT id::text, display_name, phone, password_hash
		 FROM users WHERE phone = $1`,
		phone,
	).Scan(&authenticated.ID, &authenticated.Name, &authenticated.Phone, &passwordHash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(request.Password)) != nil {
		writeError(w, http.StatusUnauthorized, "phone number or password is incorrect")
		return
	}
	a.writeAuthResponse(w, authenticated)
}

func (a *application) handleMe(w http.ResponseWriter, r *http.Request) {
	profile, err := a.loadProfile(r.Context(), authenticatedUserID(r))
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, "account no longer exists")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load account")
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

func (a *application) handleProfile(w http.ResponseWriter, r *http.Request) {
	profile, err := a.loadProfile(r.Context(), authenticatedUserID(r))
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, "account no longer exists")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not load profile")
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

func (a *application) handleUpdateProfile(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Name      string `json:"name"`
		Phone     string `json:"phone"`
		Bio       string `json:"bio"`
		AvatarURL string `json:"avatar_url"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	updates := make([]string, 0, 4)
	args := make([]any, 0, 5)
	userID := authenticatedUserID(r)

	if request.Name != "" {
		name := strings.TrimSpace(request.Name)
		if utf8.RuneCountInString(name) < 1 || utf8.RuneCountInString(name) > 80 {
			writeError(w, http.StatusBadRequest, "name must contain 1 to 80 characters")
			return
		}
		updates = append(updates, "display_name = $"+strconv.Itoa(len(args)+1))
		args = append(args, name)
	}
	if request.Phone != "" {
		phone, ok := normalizePhone(request.Phone)
		if !ok {
			writeError(w, http.StatusBadRequest, "enter a valid phone number")
			return
		}
		updates = append(updates, "phone = $"+strconv.Itoa(len(args)+1))
		args = append(args, phone)
	}
	if request.Bio != "" {
		bio := strings.TrimSpace(request.Bio)
		if utf8.RuneCountInString(bio) > 240 {
			writeError(w, http.StatusBadRequest, "bio must contain at most 240 characters")
			return
		}
		updates = append(updates, "bio = $"+strconv.Itoa(len(args)+1))
		args = append(args, bio)
	}
	if request.AvatarURL != "" {
		avatarURL := strings.TrimSpace(request.AvatarURL)
		if utf8.RuneCountInString(avatarURL) > 2048 {
			writeError(w, http.StatusBadRequest, "avatar URL is too long")
			return
		}
		updates = append(updates, "avatar_url = $"+strconv.Itoa(len(args)+1))
		args = append(args, avatarURL)
	}
	if len(updates) == 0 {
		writeError(w, http.StatusBadRequest, "no profile fields supplied")
		return
	}
	args = append(args, userID)
	query := `UPDATE users SET ` + strings.Join(updates, ", ") + ` WHERE id = $` + strconv.Itoa(len(args)) + ` RETURNING id::text, display_name, phone, COALESCE(avatar_url, ''), COALESCE(bio, '')`
	var profile user
	err := a.db.QueryRowContext(r.Context(), query, args...).Scan(&profile.ID, &profile.Name, &profile.Phone, &profile.AvatarURL, &profile.Bio)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, "account no longer exists")
		return
	}
	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "an account with this phone number already exists")
			return
		}
		writeError(w, http.StatusInternalServerError, "could not update profile")
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

func (a *application) loadProfile(ctx context.Context, userID string) (user, error) {
	var profile user
	err := a.db.QueryRowContext(ctx,
		`SELECT id::text, display_name, phone, COALESCE(avatar_url, ''), COALESCE(bio, '') FROM users WHERE id = $1`,
		userID,
	).Scan(&profile.ID, &profile.Name, &profile.Phone, &profile.AvatarURL, &profile.Bio)
	return profile, err
}

func (a *application) writeAuthResponse(w http.ResponseWriter, authenticated user) {
	token, err := a.createToken(authenticated.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create access token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": token,
		"token_type":   "Bearer",
		"user":         authenticated,
	})
}

func (a *application) createToken(userID string) (string, error) {
	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
		Issuer:    "voxa",
		Subject:   userID,
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(24 * time.Hour)),
	})
	return token.SignedString(a.jwtSecret)
}

func (a *application) userIDFromToken(token string) (string, error) {
	parsed, err := jwt.ParseWithClaims(token, &jwt.RegisteredClaims{}, func(token *jwt.Token) (any, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, errors.New("unexpected token signing method")
		}
		return a.jwtSecret, nil
	}, jwt.WithIssuer("voxa"))
	if err != nil {
		return "", err
	}
	claims, ok := parsed.Claims.(*jwt.RegisteredClaims)
	if !ok || !parsed.Valid || !uuidPattern.MatchString(claims.Subject) {
		return "", errors.New("invalid access token")
	}
	return claims.Subject, nil
}

func normalizePhone(value string) (string, bool) {
	if invalidPhoneCharacter.MatchString(value) {
		return "", false
	}
	digits := nonDigit.ReplaceAllString(value, "")
	if len(digits) < 6 || len(digits) > 15 {
		return "", false
	}
	return "+" + digits, true
}

func isUniqueViolation(err error) bool {
	var postgresError *pgconn.PgError
	return errors.As(err, &postgresError) && postgresError.Code == "23505"
}
