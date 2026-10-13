package backend

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/alicebob/miniredis/v2"
	"github.com/google/uuid"
	"github.com/joho/godotenv"
)

func testCallRedis(t *testing.T) (*callRedis, *miniredis.Miniredis) {
	t.Helper()
	server := miniredis.RunT(t)
	store, err := newCallRedis("redis://" + server.Addr())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.client.Close() })
	return store, server
}

func TestRedisSignalsOrderingIsolationAndExpiry(t *testing.T) {
	store, server := testCallRedis(t)
	ctx := context.Background()
	callID := uuid.NewString()
	var wg sync.WaitGroup
	for i := 0; i < 125; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := store.appendSignal(ctx, callID, "callee", callSignal{SenderID: "caller", Type: "ice", Payload: json.RawMessage(`{"candidate":"test"}`)}); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if t.Failed() {
		return
	}
	first, err := store.signals(ctx, callID, "callee", 0)
	if err != nil || len(first) != 100 {
		t.Fatalf("first page: count=%d err=%v", len(first), err)
	}
	last := int64(0)
	for _, signal := range first {
		if signal.Sequence <= last || signal.SenderID != "caller" || string(signal.Payload) != `{"candidate":"test"}` {
			t.Fatalf("invalid signal: %+v", signal)
		}
		last = signal.Sequence
	}
	second, err := store.signals(ctx, callID, "callee", last)
	if err != nil || len(second) != 25 {
		t.Fatalf("second page: count=%d err=%v", len(second), err)
	}
	for _, signal := range second {
		if signal.Sequence <= last {
			t.Fatal("unordered or duplicate cursor")
		}
		last = signal.Sequence
	}
	for _, target := range []struct{ call, user string }{{callID, "caller"}, {callID, "outsider"}, {uuid.NewString(), "callee"}} {
		signals, err := store.signals(ctx, target.call, target.user, 0)
		if err != nil || len(signals) != 0 {
			t.Fatal("signals leaked to another call or recipient")
		}
	}
	server.FastForward(signalTTL + time.Second)
	if len(server.Keys()) != 0 {
		t.Fatalf("signal keys did not expire: %v", server.Keys())
	}
	// After expiry, a new ICE negotiation must still be visible after the old cursor.
	seq, err := store.appendSignal(ctx, callID, "callee", callSignal{SenderID: "caller", Type: "ice", Payload: json.RawMessage(`{}`)})
	if err != nil || seq <= last {
		t.Fatalf("cursor reset after expiry: %d <= %d (%v)", seq, last, err)
	}
}

func TestCallCacheInvalidationRejectsStaleFill(t *testing.T) {
	store, server := testCallRedis(t)
	ctx := context.Background()
	key := callKey(uuid.NewString())
	var call callRecord
	hit, generation, err := store.cached(ctx, key, &call)
	if err != nil || hit {
		t.Fatal("expected empty cache", err)
	}
	if err := store.invalidate(ctx, key); err != nil {
		t.Fatal(err)
	}
	if err := store.remember(ctx, key, generation, callRecord{Status: "started"}, callCacheTTL); err != nil {
		t.Fatal(err)
	}
	hit, generation, err = store.cached(ctx, key, &call)
	if err != nil || hit {
		t.Fatal("stale database read repopulated invalidated cache", err)
	}
	if err := store.remember(ctx, key, generation, callRecord{Status: "ended"}, callCacheTTL); err != nil {
		t.Fatal(err)
	}
	hit, _, err = store.cached(ctx, key, &call)
	if err != nil || !hit || call.Status != "ended" {
		t.Fatal("fresh cache fill failed", err)
	}
	server.FastForward(callCacheTTL + time.Second)
	hit, _, err = store.cached(ctx, key, &call)
	if err != nil || hit {
		t.Fatal("call cache did not expire", err)
	}
}

func callTestApp(t *testing.T) (*application, sqlmock.Sqlmock, *miniredis.Miniredis) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	store, server := testCallRedis(t)
	return &application{db: db, callRedis: store}, mock, server
}

func callRequest(handler http.HandlerFunc, callID, user, method, path, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	r.SetPathValue("callID", callID)
	r = r.WithContext(context.WithValue(r.Context(), userIDContextKey, user))
	w := httptest.NewRecorder()
	handler(w, r)
	return w
}

func TestCallSignalHandlersUseRedisAndRejectOutsiders(t *testing.T) {
	app, mock, server := callTestApp(t)
	id, caller, callee := uuid.NewString(), uuid.NewString(), uuid.NewString()
	mock.ExpectQuery("SELECT id::text, caller_id::text").WithArgs(id).WillReturnRows(sqlmock.NewRows([]string{"id", "caller_id", "callee_id", "kind", "status", "started_at", "ended_at"}).AddRow(id, caller, callee, "audio", "started", time.Now(), nil))
	w := callRequest(app.handleCallSignal, id, caller, "POST", "/", `{"type":"offer","payload":{"sdp":"test"}}`)
	if w.Code != http.StatusAccepted {
		t.Fatalf("signal: %d %s", w.Code, w.Body.String())
	}
	for i := 0; i < 3; i++ {
		w = callRequest(app.handleCallSignals, id, callee, "GET", "/?after=0", "")
		if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"sdp":"test"`) {
			t.Fatalf("poll: %d %s", w.Code, w.Body.String())
		}
	}
	w = callRequest(app.handleCallSignals, id, uuid.NewString(), "GET", "/?after=0", "")
	if w.Code != http.StatusForbidden {
		t.Fatal("outsider could read signals", w.Code)
	}
	w = callRequest(app.handleCallSignal, id, uuid.NewString(), "POST", "/", `{"type":"ice","payload":{}}`)
	if w.Code != http.StatusForbidden {
		t.Fatal("outsider could write signals", w.Code)
	}
	w = callRequest(app.handleCallSignal, id, caller, "POST", "/", `{"type":"answer","payload":{}}`)
	if w.Code != http.StatusForbidden {
		t.Fatal("caller could answer its own call", w.Code)
	}
	w = callRequest(app.handleCallSignal, id, caller, "POST", "/", `{"type":"ice","target_id":"outsider","payload":{}}`)
	if w.Code != http.StatusBadRequest {
		t.Fatal("invalid target was accepted", w.Code)
	}
	// Only the first authorization read is allowed to reach PostgreSQL.
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
	server.Close()
	w = callRequest(app.handleCallSignal, id, caller, "POST", "/", `{"type":"ice","payload":{}}`)
	if w.Code != http.StatusServiceUnavailable {
		t.Fatal("Redis outage did not fail closed", w.Code)
	}
}

func TestActiveCallEndInvalidatesCacheAndClearsSignals(t *testing.T) {
	app, mock, _ := callTestApp(t)
	ctx := context.Background()
	call := callRecord{ID: uuid.NewString(), CallerID: uuid.NewString(), CalleeID: uuid.NewString(), Status: "active", StartedAt: time.Now()}
	if err := app.callRedis.remember(ctx, callKey(call.ID), "", call, callCacheTTL); err != nil {
		t.Fatal(err)
	}
	if err := app.callRedis.remember(ctx, incomingKey(call.CalleeID), "", []callRecord{call}, incomingCacheTTL); err != nil {
		t.Fatal(err)
	}
	for _, user := range []string{call.CallerID, call.CalleeID} {
		if _, err := app.callRedis.appendSignal(ctx, call.ID, user, callSignal{Type: "ice", Payload: json.RawMessage(`{}`)}); err != nil {
			t.Fatal(err)
		}
	}
	mock.ExpectQuery("UPDATE calls SET status = \\$3, ended_at = now\\(\\).*status IN \\('started', 'active'\\)").WithArgs(call.ID, call.CallerID, "ended").WillReturnRows(sqlmock.NewRows([]string{"id", "caller_id", "callee_id", "status"}).AddRow(call.ID, call.CallerID, call.CalleeID, "ended"))
	w := callRequest(app.handleEndCall, call.ID, call.CallerID, "POST", "/", `{"status":"ended"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("end call: %d %s", w.Code, w.Body.String())
	}
	var calls []callRecord
	if hit, _, err := app.callRedis.cached(ctx, incomingKey(call.CalleeID), &calls); err != nil || hit {
		t.Fatal("incoming cache survived end", err)
	}
	for _, user := range []string{call.CallerID, call.CalleeID} {
		if signals, err := app.callRedis.signals(ctx, call.ID, user, 0); err != nil || len(signals) != 0 {
			t.Fatal("signals survived end", err)
		}
	}
	mock.ExpectQuery("SELECT id::text, caller_id::text").WithArgs(call.ID).WillReturnRows(sqlmock.NewRows([]string{"id", "caller_id", "callee_id", "kind", "status", "started_at", "ended_at"}).AddRow(call.ID, call.CallerID, call.CalleeID, "audio", "ended", call.StartedAt, time.Now()))
	w = callRequest(app.handleCallSignals, call.ID, call.CalleeID, "GET", "/?after=0", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status":"ended"`) || !strings.Contains(w.Body.String(), `"signals":[]`) {
		t.Fatalf("terminal poll: %d %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestIncomingCallsCacheEmptyResultsAndExpiry(t *testing.T) {
	app, mock, server := callTestApp(t)
	user := uuid.NewString()
	expectPoll := func() {
		mock.ExpectExec("UPDATE calls SET status = 'missed'").WithArgs(user).WillReturnResult(sqlmock.NewResult(0, 0))
		mock.ExpectQuery("SELECT c.id::text").WithArgs(user).WillReturnRows(sqlmock.NewRows([]string{"id", "caller_id", "callee_id", "kind", "status", "started_at", "peer_id", "peer_name"}))
	}
	expectPoll()
	for i := 0; i < 3; i++ {
		w := callRequest(app.handleIncomingCalls, "", user, "GET", "/", "")
		if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"calls":[]`) {
			t.Fatalf("incoming: %d %s", w.Code, w.Body.String())
		}
	}
	server.FastForward(incomingCacheTTL + time.Second)
	expectPoll()
	w := callRequest(app.handleIncomingCalls, "", user, "GET", "/", "")
	if w.Code != http.StatusOK {
		t.Fatal(w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// Opt-in smoke test uses unique keys and removes only its own data. Never FLUSHDB.
func TestConfiguredRedisIntegration(t *testing.T) {
	if os.Getenv("VOXA_REDIS_INTEGRATION_TEST") != "1" {
		t.Skip("set VOXA_REDIS_INTEGRATION_TEST=1 to check configured Redis")
	}
	values, err := godotenv.Read(".env")
	if err != nil {
		t.Fatal("could not read Redis configuration")
	}
	store, err := newCallRedis(values["REDIS_URL"])
	if err != nil {
		t.Fatal(err)
	}
	defer store.client.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := store.ping(ctx); err != nil {
		t.Fatal(err)
	}
	id := uuid.NewString()
	defer store.client.Del(context.Background(), callKey(id), callKey(id)+":generation", callKey(id)+":sequence", callKey(id)+":signals:integration-test")
	seq, err := store.appendSignal(ctx, id, "integration-test", callSignal{SenderID: "test", Type: "ice", Payload: json.RawMessage(`{"test":true}`)})
	if err != nil {
		t.Fatal(err)
	}
	signals, err := store.signals(ctx, id, "integration-test", 0)
	if err != nil || len(signals) != 1 || signals[0].Sequence != seq {
		t.Fatal("Redis signal round trip failed", err)
	}
	if ttl := store.client.TTL(ctx, callKey(id)+":signals:integration-test").Val(); ttl <= 0 || ttl > signalTTL {
		t.Fatal("missing signal expiry", ttl)
	}
	if err := store.invalidate(ctx, callKey(id)); err != nil {
		t.Fatal(err)
	}
	var call callRecord
	_, generation, err := store.cached(ctx, callKey(id), &call)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.remember(ctx, callKey(id), generation, callRecord{ID: id, Status: "active"}, callCacheTTL); err != nil {
		t.Fatal(err)
	}
	if hit, _, err := store.cached(ctx, callKey(id), &call); err != nil || !hit || call.ID != id {
		t.Fatal("Redis call cache round trip failed", err)
	}
}
