package backend

import (
	"context"
	"database/sql"
	"errors"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/google/uuid"
	"github.com/joho/godotenv"
)

type fakePushSender struct {
	sent []*messaging.Message
	err  error
}

func (f *fakePushSender) Send(_ context.Context, msg *messaging.Message) (string, error) {
	f.sent = append(f.sent, msg)
	return "test", f.err
}

func TestPushConfiguration(t *testing.T) {
	t.Setenv("FCM_ENABLED", "false")
	if sender, err := configuredPushSender(context.Background()); sender != nil || err != nil {
		t.Fatal("disabled FCM must not require credentials")
	}
	t.Setenv("FCM_ENABLED", "invalid")
	if _, err := configuredPushSender(context.Background()); err == nil {
		t.Fatal("invalid flag accepted")
	}
	t.Setenv("FCM_ENABLED", "true")
	t.Setenv("FIREBASE_PROJECT_ID", "demo-project")
	t.Setenv("GOOGLE_APPLICATION_CREDENTIALS", "does-not-exist.json")
	if sender, err := configuredPushSender(context.Background()); sender != nil || err == nil {
		t.Fatal("missing Firebase credentials must report a configuration error")
	}
	t.Setenv("FCM_ENABLED", "true")
	t.Setenv("FIREBASE_PROJECT_ID", "")
	if _, err := configuredPushSender(context.Background()); err == nil {
		t.Fatal("missing project accepted")
	}
}

func TestPushRegistrationValidation(t *testing.T) {
	app := &application{}
	w := httptest.NewRecorder()
	app.handleRegisterPush(w, httptest.NewRequest("POST", "/", strings.NewReader(`{}`)))
	if w.Code != 503 {
		t.Fatal("disabled notifications must report unavailable")
	}
	app.push = &fakePushSender{}
	for _, body := range []string{`{`, `{}`, `{"installation_id":"invalid","token":"1234567890123456","platform":"android"}`} {
		w = httptest.NewRecorder()
		app.handleRegisterPush(w, httptest.NewRequest("POST", "/", strings.NewReader(body)))
		if w.Code != 400 {
			t.Fatalf("invalid registration returned %d", w.Code)
		}
	}
}

func TestPushPayload(t *testing.T) {
	expiry := time.Now().Add(time.Minute)
	for _, call := range []string{"", "call"} {
		msg := buildPush("token", "recipient", "chat", call, "message", "event", expiry)
		if msg.Data["recipient_id"] != "recipient" || msg.Notification == nil || msg.Token != "token" {
			t.Fatal("missing notification routing")
		}
		if *msg.Android.TTL <= 0 || *msg.Android.TTL > time.Minute {
			t.Fatal("notification outlives event")
		}
		if msg.APNS.Headers["apns-push-type"] != "alert" {
			t.Fatal("APNs alert configuration missing")
		}
		if call != "" && (msg.Data["type"] != "incoming_call" || msg.Android.Notification.ChannelID != "voxa_calls") {
			t.Fatal("call uses wrong channel")
		}
	}
}

// Private transaction, fake FCM sender, no notifications sent to real devices.
// Apply migration 011 by starting the server first.
func TestPushQueueIntegration(t *testing.T) {
	if os.Getenv("VOXA_INTEGRATION_TEST") != "1" {
		t.Skip("set VOXA_INTEGRATION_TEST=1 to test PostgreSQL")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("could not load database configuration")
	}
	db, err := sql.Open("pgx", values["DATABASE_URL"])
	if err != nil {
		t.Fatal("could not configure database")
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	if _, err = db.Exec("BEGIN"); err != nil {
		t.Fatal(err)
	}
	defer db.Exec("ROLLBACK")
	exec := func(query string, args ...any) {
		t.Helper()
		if _, err := db.Exec(query, args...); err != nil {
			t.Fatal(err)
		}
	}
	count := func(query string, args ...any) int {
		t.Helper()
		var n int
		if err := db.QueryRow(query, args...).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	sender, recipient, muted, outsider := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	devices := map[string]string{}
	for _, user := range []string{sender, recipient, muted, outsider} {
		exec(`INSERT INTO users(id,display_name,phone,password_hash) VALUES($1,'Push test',$2,'test-only')`, user, "+"+strings.ReplaceAll(user, "-", "")[:14])
		device := uuid.NewString()
		devices[user] = device
		exec(`INSERT INTO push_devices(installation_id,user_id,token,platform) VALUES($1,$2,$3,'android')`, device, user, "test-"+device)
	}
	chat := uuid.NewString()
	exec(`INSERT INTO chats(id,kind,title,created_by) VALUES($1,'group','Push test',$2)`, chat, sender)
	for _, user := range []string{sender, recipient, muted} {
		exec(`INSERT INTO chat_members(chat_id,user_id,muted) VALUES($1,$2,$3)`, chat, user, user == muted)
	}
	insertMessage := func() int64 {
		t.Helper()
		id := uuid.NewString()
		exec(`INSERT INTO messages(id,chat_id,sender_id,content) VALUES($1,$2,$3,'Private content')`, id, chat, sender)
		if n := count(`SELECT count(*) FROM push_jobs WHERE message_id=$1`, id); n != 1 {
			t.Fatalf("expected only unmuted recipient, got %d", n)
		}
		var job int64
		if err := db.QueryRow(`SELECT id FROM push_jobs WHERE message_id=$1`, id).Scan(&job); err != nil {
			t.Fatal(err)
		}
		return job
	}
	fake := &fakePushSender{}
	app := &application{db: db, push: fake}
	job := insertMessage()
	msg, _, err := app.loadPush(context.Background(), job)
	if err != nil || msg.Data["recipient_id"] != recipient || strings.Contains(msg.Notification.Body, "Private content") {
		t.Fatal("incorrect recipient or exposed preview", err)
	}
	exec(`UPDATE chat_members SET muted=true WHERE chat_id=$1 AND user_id=$2`, chat, recipient)
	app.deliverPush(context.Background(), pushJob{id: job, attempt: 1})
	if len(fake.sent) != 0 || count(`SELECT count(*) FROM push_jobs WHERE id=$1`, job) != 0 {
		t.Fatal("muted queued message was delivered")
	}
	exec(`UPDATE chat_members SET muted=false WHERE chat_id=$1 AND user_id=$2`, chat, recipient)
	job = insertMessage()
	fake.err = errors.New("transient failure")
	app.deliverPush(context.Background(), pushJob{id: job, attempt: 1})
	if count(`SELECT count(*) FROM push_jobs WHERE id=$1 AND available_at > now()`, job) != 1 {
		t.Fatal("failed send was not retained for retry")
	}
	fake.err = nil
	app.deliverPush(context.Background(), pushJob{id: job, attempt: 2})
	if count(`SELECT count(*) FROM push_jobs WHERE id=$1`, job) != 0 {
		t.Fatal("successful send not acknowledged")
	}
	job = insertMessage()
	exec(`UPDATE push_jobs SET expires_at=now()-interval '1 second' WHERE id=$1`, job)
	if _, _, err := app.loadPush(context.Background(), job); !errors.Is(err, sql.ErrNoRows) {
		t.Fatal("expired message deliverable")
	}
	call := uuid.NewString()
	exec(`INSERT INTO calls(id,caller_id,callee_id,kind,status) VALUES($1,$2,$3,'audio','started')`, call, sender, recipient)
	if count(`SELECT count(*) FROM push_jobs WHERE call_id=$1`, call) != 1 {
		t.Fatal("incoming call was not queued")
	}
	var callJob int64
	if err := db.QueryRow(`SELECT id FROM push_jobs WHERE call_id=$1`, call).Scan(&callJob); err != nil {
		t.Fatal(err)
	}
	if msg, _, err := app.loadPush(context.Background(), callJob); err != nil || msg.Data["type"] != "incoming_call" {
		t.Fatal("call payload missing", err)
	}
	exec(`UPDATE calls SET status='ended' WHERE id=$1`, call)
	if _, _, err := app.loadPush(context.Background(), callJob); !errors.Is(err, sql.ErrNoRows) {
		t.Fatal("ended call deliverable")
	}
	job = insertMessage()
	exec(`UPDATE push_devices SET user_id=$1 WHERE installation_id=$2`, outsider, devices[recipient])
	if _, _, err := app.loadPush(context.Background(), job); !errors.Is(err, sql.ErrNoRows) {
		t.Fatal("old account notification leaked after device transfer")
	}
	exec(`DELETE FROM push_devices WHERE installation_id=$1`, devices[recipient])
	if count(`SELECT count(*) FROM push_jobs WHERE installation_id=$1`, devices[recipient]) != 0 {
		t.Fatal("logout left pending notifications")
	}
}
