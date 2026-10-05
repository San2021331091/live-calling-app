# Voxa

Voxa is a Flutter messaging and calling app backed by a Go API and PostgreSQL. The backend provides phone/password authentication, JWT-protected APIs, direct and group/community conversations, persisted message history, and real-time WebSocket delivery.

## Requirements

- Go 1.23.4 or later
- PostgreSQL 13 or later
- Flutter and Dart 3.8.1 or later
- Android emulator, iOS simulator, or a physical device

## Start the backend

Create a PostgreSQL database named `voxa`, then copy `backend/.env.example` to `backend/.env`. Set `DATABASE_URL` to the database connection string and replace `JWT_SECRET` with a private random value of at least 32 characters. For example, generate one with `openssl rand -hex 32`.

From the repository root, run:

```powershell
Set-Location backend
go run .
```

At startup the backend checks its PostgreSQL connection and applies any pending SQL files in `backend/migrations/`. This creates the `users`, `chats`, `chat_members`, and `messages` tables; the migration history is kept in `schema_migrations`. No manual table setup is required.

The API listens on port `8080` by default. `GET /healthz` checks that the service is running and `GET /readyz` checks its database connection.

## Run the Flutter app

Start the backend first. From a second terminal, run:

```powershell
Set-Location frontend\voxa
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` is the Android emulator address for the host machine. For a physical device, replace it with the computer's LAN address, for example `http://192.168.1.20:8080`. For Flutter Web or desktop, use the address where the backend is reachable, commonly `http://localhost:8080`.

The debug Android manifest permits local cleartext HTTP for development. Configure HTTPS for deployed builds; do not expose the development API over an untrusted network. Set `CORS_ORIGINS` to a comma-separated list of trusted web app origins when deploying.

## Authentication and messaging

- Create an account or sign in with an international phone number and password. The backend normalizes phone numbers, hashes passwords with bcrypt, and returns a 24-hour JWT.
- Tokens are stored using the platform's secure storage and sent as Bearer tokens to protected HTTP endpoints.
- Users can start direct chats with registered accounts, create groups, and create categorized communities with selected members.
- Chat history is persisted in PostgreSQL. Each conversation uses an authenticated WebSocket at `/ws/{chatId}`; send `{"type":"message","content":"Hello"}` to save and broadcast a message to the conversation's connected members.
- The REST API exposes `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/auth/me`, `GET /api/users`, `GET /api/chats`, `POST /api/chats/direct`, `POST /api/chats/groups`, `POST /api/chats/communities`, and `GET /api/chats/{chatId}/messages`. Protected endpoints require `Authorization: Bearer <token>`.

## Flutter project

The app source is in [`frontend/voxa`](./frontend/voxa). Run `flutter pub get` there after cloning. The chat and contact lists load registered accounts and conversations from the backend; direct, group, and community text messages use the same persisted WebSocket chat service.
