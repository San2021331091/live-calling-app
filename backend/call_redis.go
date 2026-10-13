package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

const (
	callCacheTTL     = 5 * time.Second
	incomingCacheTTL = 2 * time.Second
	signalTTL        = 10 * time.Minute
)

var errCallRedis = errors.New("call service is unavailable")

type callRedis struct{ client *redis.Client }

func newCallRedis(rawURL string) (*callRedis, error) {
	options, err := redis.ParseURL(rawURL)
	if err != nil {
		return nil, errors.New("REDIS_URL must be a valid redis:// or rediss:// connection URL")
	}
	options.DialTimeout = 3 * time.Second
	options.ReadTimeout = 2 * time.Second
	options.WriteTimeout = 2 * time.Second
	options.ContextTimeoutEnabled = true
	// A signal write must not be replayed after an ambiguous network failure.
	options.MaxRetries = -1
	return &callRedis{client: redis.NewClient(options)}, nil
}

func (s *callRedis) ping(ctx context.Context) error {
	if s == nil {
		return errCallRedis
	}
	if err := s.client.Ping(ctx).Err(); err != nil {
		return errCallRedis
	}
	return nil
}

func callKey(id string) string     { return "voxa:call:{" + id + "}" }
func incomingKey(id string) string { return "voxa:incoming:{" + id + "}" }

// A generation prevents a slow database read from repopulating an invalidated
// cache. The generation outlives the bounded database query by a wide margin.
func (s *callRedis) cached(ctx context.Context, key string, dest any) (bool, string, error) {
	if s == nil {
		return false, "", errCallRedis
	}
	values, err := s.client.MGet(ctx, key, key+":generation").Result()
	if err != nil {
		return false, "", errCallRedis
	}
	generation, _ := values[1].(string)
	if values[0] == nil {
		return false, generation, nil
	}
	value, ok := values[0].(string)
	if !ok || json.Unmarshal([]byte(value), dest) != nil {
		return false, generation, errCallRedis
	}
	return true, generation, nil
}

var cacheFill = redis.NewScript(`
if (redis.call('GET', KEYS[2]) or '') ~= ARGV[1] then return 0 end
redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3])
return 1
`)

func (s *callRedis) remember(ctx context.Context, key, generation string, value any, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if err := cacheFill.Run(ctx, s.client, []string{key, key + ":generation"}, generation, string(data), ttl.Milliseconds()).Err(); err != nil {
		return errCallRedis
	}
	return nil
}

var cacheInvalidate = redis.NewScript(`
redis.call('SET', KEYS[2], ARGV[1], 'EX', 60)
redis.call('DEL', KEYS[1])
return 1
`)

func (s *callRedis) invalidate(ctx context.Context, key string) error {
	if s == nil {
		return errCallRedis
	}
	if err := cacheInvalidate.Run(ctx, s.client, []string{key, key + ":generation"}, uuid.NewString()).Err(); err != nil {
		return errCallRedis
	}
	return nil
}

func (a *application) invalidateCall(ctx context.Context, call callRecord) {
	if err := a.callRedis.invalidate(ctx, callKey(call.ID)); err != nil {
		log.Print("call status cache invalidation failed; cache expires within 5 seconds")
	}
	if err := a.callRedis.invalidate(ctx, incomingKey(call.CalleeID)); err != nil {
		log.Print("incoming call cache invalidation failed; cache expires within 2 seconds")
	}
}

func (a *application) loadCall(ctx context.Context, id string) (callRecord, error) {
	var call callRecord
	hit, generation, err := a.callRedis.cached(ctx, callKey(id), &call)
	if err != nil {
		return call, err
	}
	if !hit {
		queryCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		defer cancel()
		err = a.db.QueryRowContext(queryCtx, `SELECT id::text, caller_id::text, callee_id::text, kind, status, started_at, ended_at FROM calls WHERE id = $1`, id).Scan(&call.ID, &call.CallerID, &call.CalleeID, &call.Kind, &call.Status, &call.StartedAt, &call.EndedAt)
		if err != nil {
			return call, err
		}
		if err = a.callRedis.remember(ctx, callKey(id), generation, call, callCacheTTL); err != nil {
			return call, err
		}
	}
	// Even a cached ringing record must stop accepting signals at its deadline.
	if call.Status == "started" && time.Since(call.StartedAt) >= 2*time.Minute {
		call.Status = "missed"
	}
	return call, nil
}

func (c callRecord) peer(userID string) (string, bool) {
	if c.CallerID == userID {
		return c.CalleeID, true
	}
	if c.CalleeID == userID {
		return c.CallerID, true
	}
	return "", false
}

type callSignal struct {
	Sequence int64           `json:"sequence"`
	SenderID string          `json:"sender_id"`
	Type     string          `json:"type"`
	Payload  json.RawMessage `json:"payload"`
}

// Sequence assignment and insertion are atomic: concurrent ICE writes cannot
// arrive out of order and be skipped by the client's numeric cursor. Redis TIME
// seeds a new counter so expiry does not reset a continuing call's cursor to 1.
var appendCallSignal = redis.NewScript(`
local now = redis.call('TIME')
local seq = math.max(tonumber(now[1]) * 1000000 + tonumber(now[2]), tonumber(redis.call('GET', KEYS[1]) or '0') + 1)
local seqText = string.format('%.0f', seq)
local member = seqText .. ':' .. ARGV[1]
redis.call('SET', KEYS[1], seqText, 'EX', ARGV[2])
redis.call('ZADD', KEYS[2], seq, member)
redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', seq - tonumber(ARGV[2]) * 1000000)
redis.call('EXPIRE', KEYS[2], ARGV[2])
return seqText
`)

func (s *callRedis) appendSignal(ctx context.Context, id, targetID string, signal callSignal) (int64, error) {
	if s == nil {
		return 0, errCallRedis
	}
	data, err := json.Marshal(signal)
	if err != nil {
		return 0, err
	}
	result, err := appendCallSignal.Run(ctx, s.client, []string{callKey(id) + ":sequence", callKey(id) + ":signals:" + targetID}, string(data), int64(signalTTL/time.Second)).Text()
	if err != nil {
		return 0, errCallRedis
	}
	return strconv.ParseInt(result, 10, 64)
}

func (s *callRedis) signals(ctx context.Context, id, targetID string, after int64) ([]callSignal, error) {
	if s == nil {
		return nil, errCallRedis
	}
	values, err := s.client.ZRangeByScoreWithScores(ctx, callKey(id)+":signals:"+targetID, &redis.ZRangeBy{Min: "(" + strconv.FormatInt(after, 10), Max: "+inf", Count: 100}).Result()
	if err != nil {
		return nil, errCallRedis
	}
	signals := make([]callSignal, 0, len(values))
	for _, value := range values {
		member, ok := value.Member.(string)
		prefix := strconv.FormatInt(int64(value.Score), 10) + ":"
		var signal callSignal
		if !ok || len(member) < len(prefix) || member[:len(prefix)] != prefix || json.Unmarshal([]byte(member[len(prefix):]), &signal) != nil {
			return nil, fmt.Errorf("invalid cached call signal")
		}
		signal.Sequence = int64(value.Score)
		signals = append(signals, signal)
	}
	return signals, nil
}

func (s *callRedis) clearSignals(ctx context.Context, call callRecord) error {
	if s == nil {
		return errCallRedis
	}
	// Keep the sequence until TTL to preserve monotonic cursors across retries.
	return s.client.Del(ctx, callKey(call.ID)+":signals:"+call.CallerID, callKey(call.ID)+":signals:"+call.CalleeID).Err()
}
