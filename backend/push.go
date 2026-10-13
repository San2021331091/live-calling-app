package backend

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

type pushSender interface {
	Send(context.Context, *messaging.Message) (string, error)
}

func configuredPushSender(ctx context.Context) (pushSender, error) {
	enabled := strings.TrimSpace(os.Getenv("FCM_ENABLED"))
	if enabled == "" || enabled == "false" {
		return nil, nil
	}
	if enabled != "true" {
		return nil, errors.New("FCM_ENABLED must be true or false")
	}
	project := strings.TrimSpace(os.Getenv("FIREBASE_PROJECT_ID"))
	if project == "" {
		return nil, errors.New("FIREBASE_PROJECT_ID is required when FCM is enabled")
	}
	var options []option.ClientOption
	if credentialsJSON := strings.TrimSpace(os.Getenv("FIREBASE_SERVICE_ACCOUNT_JSON")); credentialsJSON != "" {
		options = append(options, option.WithCredentialsJSON([]byte(credentialsJSON)))
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: project}, options...)
	if err != nil {
		return nil, errors.New("Firebase initialization failed; check server credentials")
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, errors.New("Firebase Messaging initialization failed; check Application Default Credentials")
	}
	return client, nil
}

func (a *application) handleRegisterPush(w http.ResponseWriter, r *http.Request) {
	if a.push == nil {
		writeError(w, http.StatusServiceUnavailable, "push notifications are not configured on the server")
		return
	}
	var req struct {
		InstallationID string `json:"installation_id"`
		Token          string `json:"token"`
		Platform       string `json:"platform"`
	}
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, 400, err.Error())
		return
	}
	if !uuidPattern.MatchString(req.InstallationID) || len(req.Token) < 16 || len(req.Token) > 4096 ||
		strings.ContainsAny(req.Token, " \r\n\t") || (req.Platform != "android" && req.Platform != "ios") {
		writeError(w, http.StatusBadRequest, "invalid push device registration")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, 500, "could not register notifications")
		return
	}
	defer tx.Rollback()
	// Serialize token transfer and account changes without exposing either token.
	_, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(710011)`)
	if err == nil {
		_, err = tx.ExecContext(ctx, `DELETE FROM push_devices WHERE
          (token = $1 AND installation_id <> $2) OR
          (installation_id = $2 AND user_id <> $3)`, req.Token, req.InstallationID, authenticatedUserID(r))
	}
	if err == nil {
		_, err = tx.ExecContext(ctx, `INSERT INTO push_devices(installation_id,user_id,token,platform)
          VALUES($1,$2,$3,$4) ON CONFLICT(installation_id) DO UPDATE SET
          user_id = EXCLUDED.user_id, token = EXCLUDED.token, platform = EXCLUDED.platform, updated_at = now()`,
			req.InstallationID, authenticatedUserID(r), req.Token, req.Platform)
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		writeError(w, 500, "could not register notifications")
		return
	}
	writeJSON(w, 200, map[string]bool{"registered": true})
}

func (a *application) handleDeletePush(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("installationID")
	if !uuidPattern.MatchString(id) {
		writeError(w, 400, "invalid installation ID")
		return
	}
	_, err := a.db.ExecContext(r.Context(), `DELETE FROM push_devices WHERE installation_id = $1 AND user_id = $2`, id, authenticatedUserID(r))
	if err != nil {
		writeError(w, 500, "could not unregister notifications")
		return
	}
	writeJSON(w, 200, map[string]bool{"registered": false})
}

type pushJob struct {
	id      int64
	attempt int
}

// Claim with a lease: another process can retry after a worker/server crash.
func (a *application) claimPush(ctx context.Context) (pushJob, error) {
	var job pushJob
	err := a.db.QueryRowContext(ctx, `UPDATE push_jobs SET available_at = now() + interval '60 seconds', attempts = attempts + 1
      WHERE id = (SELECT id FROM push_jobs WHERE available_at <= now() AND expires_at > now() AND attempts < 5
        ORDER BY available_at, id FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING id, attempts`).Scan(&job.id, &job.attempt)
	return job, err
}

func (a *application) runPushWorker(ctx context.Context) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	lastCleanup := time.Time{}
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		if time.Since(lastCleanup) > time.Minute {
			cleanupCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			_, err := a.db.ExecContext(cleanupCtx, `DELETE FROM push_jobs WHERE expires_at <= now() OR (attempts >= 5 AND available_at <= now())`)
			if err == nil {
				_, err = a.db.ExecContext(cleanupCtx, `DELETE FROM push_devices WHERE updated_at < now() - interval '30 days'`)
			}
			cancel()
			if err != nil {
				log.Print("push queue cleanup failed")
			}
			lastCleanup = time.Now()
		}
		if a.push == nil {
			continue
		}
		for i := 0; i < 20; i++ {
			sendCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
			job, err := a.claimPush(sendCtx)
			if err == nil {
				a.deliverPush(sendCtx, job)
			}
			cancel()
			if err != nil {
				if !errors.Is(err, sql.ErrNoRows) {
					log.Print("push queue claim failed")
				}
				break
			}
		}
	}
}

func (a *application) loadPush(ctx context.Context, id int64) (*messaging.Message, string, error) {
	var device, token, user, chat, call, message string
	var expires time.Time
	// Recheck membership, mute, call state, and device ownership at delivery time.
	err := a.db.QueryRowContext(ctx, `SELECT d.installation_id, d.token, j.user_id,
      COALESCE(m.chat_id::text,''), COALESCE(j.call_id::text,''), COALESCE(j.message_id::text,''), j.expires_at
      FROM push_jobs j JOIN push_devices d ON d.installation_id = j.installation_id AND d.user_id = j.user_id
      LEFT JOIN messages m ON m.id = j.message_id
      LEFT JOIN chat_members cm ON cm.chat_id = m.chat_id AND cm.user_id = j.user_id
      LEFT JOIN calls c ON c.id = j.call_id AND c.callee_id = j.user_id
      WHERE j.id = $1 AND j.expires_at > now() AND (
        (m.id IS NOT NULL AND NOT cm.muted AND NOT cm.hidden AND (cm.cleared_before IS NULL OR m.created_at > cm.cleared_before))
        OR (c.id IS NOT NULL AND c.status = 'started'))`, id).Scan(&device, &token, &user, &chat, &call, &message, &expires)
	if err != nil {
		return nil, "", err
	}
	return buildPush(token, user, chat, call, message, strconv.FormatInt(id, 10), expires), device, nil
}

func buildPush(token, user, chat, call, message, event string, expires time.Time) *messaging.Message {
	kind, channel, tag, body, sound := "chat_message", "voxa_messages", "chat_"+chat, "You have a new message", "default"
	if call != "" {
		kind, channel, tag, body, sound = "incoming_call", "voxa_calls_default", "call_"+call, "You have an incoming call. Tap to answer.", "default"
	}
	ttl := time.Until(expires)
	if ttl < 0 {
		ttl = 0
	}
	// Generic lock-screen text avoids exposing message content on shared devices.
	return &messaging.Message{
		Token:        token,
		Notification: &messaging.Notification{Title: "Voxa", Body: body},
		Data:         map[string]string{"type": kind, "recipient_id": user, "chat_id": chat, "call_id": call, "message_id": message, "event_id": event},
		Android: &messaging.AndroidConfig{Priority: "high", TTL: &ttl, Notification: &messaging.AndroidNotification{
			ChannelID: channel, Tag: tag, Icon: "ic_notification", Sound: sound}},
		APNS: &messaging.APNSConfig{Headers: map[string]string{"apns-push-type": "alert", "apns-priority": "10", "apns-expiration": strconv.FormatInt(expires.Unix(), 10)},
			Payload: &messaging.APNSPayload{Aps: &messaging.Aps{Sound: "default"}}},
	}
}

func (a *application) deliverPush(ctx context.Context, job pushJob) {
	msg, device, err := a.loadPush(ctx, job.id)
	if err == nil {
		_, err = a.push.Send(ctx, msg)
	}
	// Use a fresh bounded context to release the lease even if sending timed out.
	dbCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err == nil || errors.Is(err, sql.ErrNoRows) || messaging.IsUnregistered(err) {
		if msg != nil && messaging.IsUnregistered(err) {
			// Never remove a refreshed registration based on an older token's error.
			if _, deleteErr := a.db.ExecContext(dbCtx, `DELETE FROM push_devices WHERE installation_id = $1 AND token = $2`, device, msg.Token); deleteErr != nil {
				log.Print("push device cleanup failed")
			}
		}
		if _, deleteErr := a.db.ExecContext(dbCtx, `DELETE FROM push_jobs WHERE id = $1`, job.id); deleteErr != nil {
			log.Print("push acknowledgement failed")
		}
		return
	}
	delay := time.Duration(1<<job.attempt) * time.Second
	if _, retryErr := a.db.ExecContext(dbCtx, `UPDATE push_jobs SET available_at = now() + $2 * interval '1 second' WHERE id = $1`, job.id, int(delay.Seconds())); retryErr != nil {
		log.Print("push retry scheduling failed")
	}
	log.Printf("push delivery failed; job=%d attempt=%d (check Firebase configuration/connectivity)", job.id, job.attempt)
}
