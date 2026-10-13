package backend

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/joho/godotenv"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

type application struct {
	db        *sql.DB
	callRedis *callRedis
	jwtSecret []byte
	origins   map[string]struct{}
	allowAll  bool
	hub       *messageHub
	push      pushSender
	inlineAI  bool
	aiClient  *http.Client
}

func RunServer() {
	if err := godotenv.Load(); err != nil && !os.IsNotExist(err) {
		log.Fatalf("load environment: %v", err)
	}

	ctx, cancel := databaseTimeout()
	defer cancel()
	app, cleanup, err := newApplication(ctx, configuredDatabaseURL(), true)
	if err != nil {
		log.Fatal(err)
	}
	defer cleanup()

	pushCtx, stopPush := context.WithCancel(context.Background())
	defer stopPush()
	if app.push != nil {
		log.Print("FCM notifications enabled")
	} else {
		log.Print("FCM notifications disabled; configure Firebase and FCM_ENABLED to enable")
	}
	go app.runPushWorker(pushCtx)
	app.runAIWorker(pushCtx)

	server := app.routes()
	address := ":" + envOr("PORT", "8080")
	log.Printf("Voxa API listening on %s", address)
	if err := server.Listen(address); err != nil {
		log.Fatalf("run Fiber API server: %v", err)
	}
}

func newApplication(ctx context.Context, databaseURL string, applyMigrations bool) (*application, func(), error) {
	if databaseURL == "" {
		return nil, nil, errors.New("DATABASE_URL is required")
	}
	jwtSecret := os.Getenv("JWT_SECRET")
	if len(jwtSecret) < 32 {
		return nil, nil, errors.New("JWT_SECRET must contain at least 32 characters")
	}
	redisURL := strings.TrimSpace(os.Getenv("REDIS_URL"))
	if redisURL == "" {
		return nil, nil, errors.New("REDIS_URL is required for call signaling")
	}
	callStore, err := newCallRedis(redisURL)
	if err != nil {
		return nil, nil, err
	}
	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		_ = callStore.client.Close()
		return nil, nil, errors.New("could not configure PostgreSQL")
	}
	cleanup := func() {
		_ = db.Close()
		_ = callStore.client.Close()
	}
	maxOpenConnections, maxIdleConnections := 20, 5
	if os.Getenv("VERCEL") == "1" {
		maxOpenConnections, maxIdleConnections = 5, 1
	}
	db.SetMaxOpenConns(maxOpenConnections)
	db.SetMaxIdleConns(maxIdleConnections)
	db.SetConnMaxLifetime(30 * time.Minute)
	if err := db.PingContext(ctx); err != nil {
		cleanup()
		return nil, nil, errors.New("connect to PostgreSQL")
	}
	if err := callStore.ping(ctx); err != nil {
		cleanup()
		return nil, nil, errors.New("connect to Redis: call service is unavailable")
	}
	if applyMigrations {
		if err := migrate(ctx, db); err != nil {
			cleanup()
			return nil, nil, err
		}
	}
	app := &application{
		db:        db,
		callRedis: callStore,
		jwtSecret: []byte(jwtSecret),
		hub:       newMessageHub(),
	}
	app.configureOrigins(os.Getenv("CORS_ORIGINS"))
	app.push, err = configuredPushSender(ctx)
	if err != nil {
		log.Printf("FCM notifications disabled: %v", err)
		app.push = nil
	}
	return app, cleanup, nil
}

func databaseTimeout() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

func migrate(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version TEXT PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
	)`); err != nil {
		return fmt.Errorf("create migration history: %w", err)
	}

	migrations, err := fs.ReadDir(migrationFiles, "migrations")
	if err != nil {
		return fmt.Errorf("list database migrations: %w", err)
	}
	for _, migrationFile := range migrations {
		if migrationFile.IsDir() || !strings.HasSuffix(migrationFile.Name(), ".sql") {
			continue
		}
		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("begin migration %s: %w", migrationFile.Name(), err)
		}
		var applied bool
		err = tx.QueryRowContext(ctx,
			`SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`,
			migrationFile.Name(),
		).Scan(&applied)
		if err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("check migration %s: %w", migrationFile.Name(), err)
		}
		if !applied {
			migration, err := migrationFiles.ReadFile("migrations/" + migrationFile.Name())
			if err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("read migration %s: %w", migrationFile.Name(), err)
			}
			if _, err := tx.ExecContext(ctx, string(migration)); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("apply migration %s: %w", migrationFile.Name(), err)
			}
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO schema_migrations (version) VALUES ($1)`,
				migrationFile.Name(),
			); err != nil {
				_ = tx.Rollback()
				return fmt.Errorf("record migration %s: %w", migrationFile.Name(), err)
			}
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migration %s: %w", migrationFile.Name(), err)
		}
	}
	return nil
}

func envOr(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func configuredDatabaseURL() string {
	contents, err := os.ReadFile(".env")
	if err != nil && !os.IsNotExist(err) {
		log.Printf("load .env: %v", err)
	}
	return configuredDatabaseURLFrom(os.Getenv("DATABASE_URL"), string(contents))
}

func configuredDatabaseURLFrom(env string, dotenv string) string {
	if value := strings.TrimSpace(env); value != "" {
		return value
	}
	for _, line := range strings.Split(dotenv, "\n") {
		value := strings.TrimSpace(line)
		if value == "" || strings.HasPrefix(value, "#") {
			continue
		}
		if key, rawValue, found := strings.Cut(value, "="); found && strings.TrimSpace(key) == "DATABASE_URL" {
			return strings.Trim(strings.TrimSpace(rawValue), `"'`)
		}
		if strings.HasPrefix(value, "postgres://") || strings.HasPrefix(value, "postgresql://") {
			return value
		}
	}
	return ""
}
