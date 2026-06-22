# concord

Concord - clinical-grade cancer care companion (Flutter iOS app). See SPEC.md.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Run on web (browser dev loop)

Primary dev loop on Windows — Chrome serves as the iOS Simulator stand-in
(no iOS Simulator on this host, and Codemagic handles real iOS builds).

```powershell
.\tool\run_web.ps1
```

This reads `app/.env`, forwards the values as `--dart-define` to
`flutter run -d chrome --web-port=8080`, and opens
`http://localhost:8080`. Hot reload is on by default — press `r` in the
terminal to reload, `q` to quit.

**Seeded test user** (provisioned via `backend/scripts/seed_dev_user.ts`,
email pre-confirmed, role=patient):

```
email:    dev@concord.test
password: concord-dev-2026
```

The credentials are also pinned in `app/.env.test` (gitignored) for tools
that need to surface them.

**What works in the browser:**
- Sign in / sign up / forgot password (Supabase auth)
- Quick-log a symptom → `POST /api/symptoms/submit` (PRO-CTCAE scoring)
- Chat with Atlas → `POST /api/atlas/chat` (Gemini SSE stream)
- Manage medications → `GET/POST /api/medications`
- View recent reports → Supabase `symptom_report` + `symptom_response`

**What's stubbed on web (no-op or throws UnsupportedError):**
- Daily-check-in + medication reminders (`flutter_local_notifications` —
  no web implementation)
- HealthKit / Health Connect reads (Apple/Android-only)
- On iOS/Android, these are full; on web they're silently no-op so the
  app still boots.

