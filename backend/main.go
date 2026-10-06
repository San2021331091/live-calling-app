package main

import (
	"context"
	"database/sql"
	"embed"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/joho/godotenv"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

type application struct {
	db        *sql.DB
	jwtSecret []byte
	origins   map[string]struct{}
	allowAll  bool
	hub       *messageHub
}

func main() {
	if err := godotenv.Load(); err != nil && !os.IsNotExist(err) {
		log.Fatalf("load environment: %v", err)
	}

	databaseURL := configuredDatabaseURL()
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}
	jwtSecret := os.Getenv("JWT_SECRET")
	if len(jwtSecret) < 32 {
		log.Fatal("JWT_SECRET must contain at least 32 characters")
	}

	db, err := sql.Open("pgx", databaseURL)
	if err != nil {
		log.Fatalf("configure PostgreSQL: %v", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	ctx, cancel := databaseTimeout()
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		log.Fatalf("connect to PostgreSQL: %v", err)
	}
	if err := migrate(ctx, db); err != nil {
		log.Fatalf("run database migrations: %v", err)
	}

	app := &application{
		db:        db,
		jwtSecret: []byte(jwtSecret),
		hub:       newMessageHub(),
	}
	app.configureOrigins(os.Getenv("CORS_ORIGINS"))

	server := &http.Server{
		Addr:              ":" + envOr("PORT", "8080"),
		Handler:           app.routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("Voxa API listening on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("run API server: %v", err)
	}
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
