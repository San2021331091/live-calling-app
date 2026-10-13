# Voxa

Voxa is a Flutter messaging and calling app backed by a Go API and PostgreSQL. The backend provides phone/password authentication, JWT-protected APIs, direct and group/community conversations, persisted message history, and real-time WebSocket delivery.

## Requirements

- Go 1.23.4 or later
- PostgreSQL 13 or later
- Redis 7 or later (local or hosted)
- Flutter and Dart 3.8.1 or later
- Android emulator, iOS simulator, or a physical device

## Start the backend

Create a PostgreSQL database named `voxa`, then copy `backend/.env.example` to `backend/.env`. Set `DATABASE_URL` to the database connection string and replace `JWT_SECRET` with a private random value of at least 32 characters. For example, generate one with `openssl rand -hex 32`.

Set `REDIS_URL` in `backend/.env` to your Redis connection URL, such as
`redis://localhost:6379/0` or your provider's authenticated URL. Use `rediss://`
when your provider enables TLS. Keep credentials in the ignored `.env` file.

From the repository root, run:

```powershell
Set-Location backend
go run .
```

At startup the backend checks its PostgreSQL connection and applies any pending SQL files in `backend/migrations/`. This creates the `users`, `chats`, `chat_members`, and `messages` tables; the migration history is kept in `schema_migrations`. No manual table setup is required.

The backend checks PostgreSQL and Redis at startup. The API listens on port `8080` by default. `GET /` checks that the service is running and `GET /readyz` checks both connections.

## Run the Flutter app

Start the backend first. From a second terminal, run:

```powershell
Set-Location frontend\voxa
if (!(Test-Path .env)) { Copy-Item .env.example .env }
flutter run
```

The frontend reads `API_BASE_URL` from `frontend/voxa/.env`. That local file is ignored by Git; `.env.example` is the committed template. `10.0.2.2` is the Android emulator address for the host machine. For a physical device, edit `.env` to use the computer's LAN address, for example `http://192.168.1.20:8080`. For Flutter Web or desktop, use the backend's reachable address, commonly `http://localhost:8080`.

The debug Android manifest permits local cleartext HTTP for development. Configure HTTPS for deployed builds; do not expose the development API over an untrusted network. Set `CORS_ORIGINS` to a comma-separated list of trusted web app origins when deploying.

## One-to-one audio and video calls

Direct audio and video calls use Flutter WebRTC. The backend creates call records, delivers SDP/ICE signals to the other participant, and polls for incoming calls while the app is open. Apply the database migrations by restarting the backend. Group calls are not supported; they require a media-server/SFU architecture.

Call history and status transitions remain durable in PostgreSQL's `calls` table.
Redis caches call records for 5 seconds and incoming-call lists (including empty
lists) for 2 seconds. Creation, answer, and hangup invalidate those caches. Cache
misses read PostgreSQL; generation checks prevent an in-flight database read from
repopulating a cache invalidated by another request. If invalidation fails, the
short TTL bounds the lifetime of existing cached values.

New SDP offers, answers, and ICE candidates are stored only in Redis, in separate
queues for each call recipient. Atomic writes preserve the numeric sequence and
100-signal pagination used by the Flutter app. Queues expire 10 minutes after the
last write; new writes also prune old entries. Hangup clears both queues. Redis
loss can interrupt call setup, and signaling returns HTTP 503 when Redis is
unavailable; signals never fall back to PostgreSQL. Existing rows in the legacy
`call_signals` table are left untouched, but the application no longer reads or
writes that table. Calls in progress during the switch must be restarted.

Run `go test ./...` to check signaling order, expiry, participant isolation,
cache invalidation, and active-call hangup. To verify the configured Redis with
temporary isolated keys, run `$env:VOXA_REDIS_INTEGRATION_TEST='1'; go test -run
TestConfiguredRedisIntegration -v` in `backend`. This test removes only its own
keys; it never flushes the Redis database.

The client uses Google's public STUN servers by default. These servers help peers discover network routes at no extra setup, but STUN alone cannot guarantee calls through symmetric NATs, carrier-grade NATs, or restrictive firewalls. For reliable calls across those networks, a TURN relay is required; configure a TURN service such as coturn with shared-secret authentication. Set comma-separated `TURN_URLS` (for example, `turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349`) and a random `TURN_SHARED_SECRET` of at least 32 characters in `backend/.env`. Configure coturn with the same shared secret. The backend issues short-lived TURN credentials to authenticated clients; do not put TURN shared secrets or permanent TURN credentials in the Flutter `.env`.

## Authentication and messaging

- Create an account or sign in with an international phone number and password. The backend normalizes phone numbers, hashes passwords with bcrypt, and returns a 24-hour JWT.
- Tokens are stored using the platform's secure storage and sent as Bearer tokens to protected HTTP endpoints.
- Users can start direct chats with registered accounts, create groups, and create categorized communities with selected members.
- Group/community creators can rename or delete their conversations. Users can edit or delete their own status captions and manage phone contacts through the device contacts app.
- Chat history is persisted in PostgreSQL. Each conversation uses an authenticated WebSocket at `/ws/{chatId}`; send `{"type":"message","content":"Hello"}` to save and broadcast a message to the conversation's connected members.
- The REST API exposes `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/auth/me`, `GET /api/users`, `GET /api/chats`, `POST /api/chats/direct`, `POST /api/chats/groups`, `POST /api/chats/communities`, and `GET /api/chats/{chatId}/messages`. Protected endpoints require `Authorization: Bearer <token>`.

## Flutter project

The app source is in [`frontend/voxa`](./frontend/voxa). Run `flutter pub get` there after cloning. The chat and contact lists load registered accounts and conversations from the backend; direct, group, and community text messages use the same persisted WebSocket chat service.

## Current interface and verification

The home screen opens on Chats and provides bottom navigation for Updates,
Communities, and Calls. Conversation search and All/Direct/Groups filters operate
on backend conversations. The inbox refreshes every five seconds while the app
is active and refreshes when returning from a conversation. Pull to refresh and
connection errors remain visible.

Startup checks a stored session immediately. Valid sessions open the inbox;
expired sessions return to sign in, and connection failures provide a retry.
Messages clear their drafts only after a matching server confirmation that the
message was saved. A confirmation is not a delivery or read receipt. After a
confirmation timeout, check the conversation before retrying to avoid duplicates.

Group permission toggles and disappearing-message settings remain unavailable.
Profile, group, and community photos now upload through ImgBB and persist their URLs in PostgreSQL. The conversation overview reports loaded message counts and
the latest message; it does not generate AI summaries. No sample conversations,
contacts, statuses, or call records are added.

Media sharing requires the ImgBB and Cloudinary configuration described in
`frontend/voxa/.env.example`. Cross-network calling requires a working TURN
configuration. Background push notifications require the Firebase setup below.
End-to-end encryption, read receipts, and WhatsApp feature parity are not implemented. Validate calls and
media on physical devices before deploying.

Run `go test ./...` and `go vet ./...` in `backend`. Run `flutter analyze --no-pub`
and `flutter test --no-pub` in `frontend/voxa`. The Flutter tests cover startup,
server-confirmed sends, rejected sends, disconnected sends, and media previews.

## Current behavior and verification

The home screen opens on Chats and uses bottom navigation for Updates, Communities, and Calls. The inbox refreshes from the backend every five seconds while the app is active, supports conversation search and direct/group filters, and refreshes when returning from a conversation. Saved sessions are validated at startup; a connection error offers Retry without erasing the saved token.

Text drafts clear only after the backend broadcasts the persisted message with its client correlation ID. A timeout or disconnect keeps the draft and asks the user to check history before retrying, because a message may have reached the database before confirmation was lost. Restart the backend alongside this frontend update so the confirmation protocol is available. This confirms server persistence; delivery and read receipts are not implemented.

Unsupported local-only group permission/disappearing-message settings have been removed. Names, profile bios, conversations, statuses, and calls continue to use the backend. Conversation overview reports counts from loaded history, without inferred topics. Chat screens load the latest 100 messages; Search and Media/Links/Docs paginate through older saved history. Background incoming-call notifications require Firebase configuration. End-to-end encryption is not implemented. Media uploads require the configured ImgBB/Cloudinary providers, and cross-network calls may require TURN.

Verification commands:

```powershell
# backend/
go test ./...
# frontend/voxa/
flutter analyze --no-pub
flutter test --no-pub
```

If Windows Application Control blocks a test executable, use an SDK allowed by
the machine policy or run the corresponding Android integration test on an emulator.

## Media editing

Photo and video attachments in direct/group chats and status updates open the editor before upload. Add text with the text tool, insert emoji stickers with the emoji tool, and drag either overlay to position it. Double-tap an overlay to remove it. Text size applies to the latest overlay; drawing supports color selection and undo. Photo exports include the displayed overlays, rotation, and optional square crop. Captions are sent with the attachment.

Android video edits are exported as MP4 files with trim boundaries, optional audio removal, and burned-in text/emoji/drawing overlays. Unedited videos can be shared directly; edited video export currently requires Android. Video editing uses Media3 1.9.2 to match the installed video player dependency. A fresh APK installation is required for the new native exporter; hot reload alone cannot install the Android channel.

## Documents and chat deletion

Document selection accepts any file type. Documents up to 15 MB use authenticated multipart uploads to `POST /api/files` and persist in PostgreSQL; image/video uploads retain their existing providers. File links contain a signature scoped to that file, and Android opens them through the browser for download. Restart the backend to apply migration 009.

Use **Delete chat** in a direct/group chat menu, or hold a conversation in the inbox. This hides the conversation and clears previous history for the current account; other participants keep their copies. A new message brings the conversation back. **Clear history** keeps the conversation in the inbox. Group deletion remains a separate creator-only action. Mute persists the preference for in-app and FCM message alerts; it does not silence incoming calls.

Database regression checks use isolated fixtures in a rolled-back transaction: `VOXA_INTEGRATION_TEST=1 go test ./...`. Android editor and rename checks run with `flutter test integration_test/chat_regression_test.dart -d emulator-5554`.


## Photos and chat themes

Tap your profile photo to choose or take a photo, edit the current photo, or remove
it. The existing editor opens with a square crop and supports rotation, drawing,
text, and stickers before upload. Group/community creation offers the same photo
control. Creators can change existing conversation photos from the header or
**Edit photo** menu. ImgBB stores the image; PostgreSQL stores its HTTPS URL.

Choose **Chat theme** in a conversation menu. **Just me** saves a personal theme
on your membership. Group/community creators can also set a **Shared theme**,
which becomes the default for members without a personal override. Choose
**Use shared theme** to clear that override. Direct chats support personal themes.
Available themes change the conversation background, outgoing bubbles, and header.
Updates persist across app restarts; connected group members receive an appearance
refresh event. Restart the backend to apply migration 010 before using this app.

Appearance checks are included in `VOXA_INTEGRATION_TEST=1 go test ./...` and in
`flutter test integration_test/chat_regression_test.dart -d emulator-5554`.

## Firebase Cloud Messaging (Android)

FCM delivery is implemented but disabled until you supply your Firebase configuration.
The app still builds and runs without it. Open **Notifications** in the home menu
to see registration status, retry, or open Android notification settings.

1. In your Firebase project, add an Android app with package name
   `com.example.voxa` (or change the Android application ID and register that ID).
   Save its `google-services.json` to `frontend/voxa/android/app/google-services.json`.
2. Enable the Firebase Cloud Messaging API for that project. Give the backend
   service account permission to send FCM messages (Firebase Cloud Messaging API
   Admin role). Store its private JSON key at
   `backend/secrets/firebase-service-account.json`, or use Application Default
   Credentials on your server (unset `GOOGLE_APPLICATION_CREDENTIALS` when using
   credentials supplied by the hosting environment). Never put this private key in Flutter assets.
3. Configure `backend/.env`:

   ```dotenv
   FCM_ENABLED=true
   FIREBASE_PROJECT_ID=your-firebase-project-id
   GOOGLE_APPLICATION_CREDENTIALS=secrets/firebase-service-account.json
   ```

4. Restart with `go run .` from `backend` to apply migration 011 and start the
   sender. Rebuild/install the Android app with `flutter run`; hot reload cannot
   install Firebase's native configuration. Sign in and allow notifications.
   Use a device/emulator with Google Play services.
5. Test with two accounts/devices: put the receiving app in the background, send
   a message, tap its notification, then try an incoming call. Muting a chat must
   suppress new message alerts. Decline/end a call before tapping its old alert
   to verify that it does not open an active call. Also test token refresh,
   sign-out/account switching, permission denial, and reopening after termination.

The authenticated `POST /api/devices/push` endpoint binds an installation/token
to the signed-in user; `DELETE /api/devices/push/{installationID}` revokes it.
Tokens update on sign-in, token rotation, and app resume. Sign-out revokes the
server registration or Firebase token before removing the session; if both
services are unreachable, reconnect and retry sign-out.

PostgreSQL stores device tokens and a short-lived notification outbox, created
atomically when a message or call is saved. Messages skip the sender and muted
members. Delivery rechecks membership, mute, hidden/cleared history, device
ownership, and ringing-call status. Failed deliveries retry up to five times;
message jobs expire after five minutes and call jobs after two. Invalid tokens
are removed; registrations inactive for 30 days expire. Cleanup runs even when
FCM sending is disabled. Call signaling stays in Redis.

Background notifications use generic lock-screen text. Taps load the current
conversation or check that a call is still ringing before showing Accept/Decline.
Foreground messages use the existing in-app alert. Android has separate Messages
and Incoming calls channels. These are ordinary push alerts, not a full-screen
system calling UI; already displayed call alerts can remain after hangup.
Delivery is best effort and retries can duplicate an alert. Force-stopping the
app in Android settings prevents delivery until it is manually reopened.

This repository currently has no iOS runner. The shared sender includes APNs
payloads, but an iOS target, Firebase plist, Push Notifications capability, and
Firebase APNs credentials must be configured on macOS before testing iOS.
Web/desktop push is not configured.

Checks: `go test ./...`, `go vet ./...`,
`VOXA_INTEGRATION_TEST=1 go test -run TestPushQueueIntegration` (after migration),
`flutter analyze --no-pub`, and
`flutter test integration_test/push_notification_test.dart -d emulator-5554`.
The database test rolls back its fixtures and uses a fake sender; it does not
send real pushes. End-to-end delivery requires the actual Firebase files above.

References: [Firebase Android setup](https://firebase.google.com/docs/android/setup),
[Admin SDK credentials](https://firebase.google.com/docs/admin/setup),
and [Flutter message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).
