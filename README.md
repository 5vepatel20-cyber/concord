# Medora

Patient↔clinician communication layer for serious illness.

**This repo is private and contains PHI-handling infrastructure. Never commit secrets.**

## Docs

- [`SPEC.md`](./SPEC.md) — product & engineering specification (the source of truth for *what* we're building)
- [`SETUP.md`](./SETUP.md) — API/service setup agent prompt (the *how* for provisioning credentials)

## Status

Active development. Flutter web app + Vercel-deployed Node backend + Next.js landing page.

## Layout

```
.
├── app/                 # Flutter web app (Riverpod, go_router, Supabase)
│   ├── lib/
│   │   ├── core/        # config, monitoring (PostHog), notifications, result types
│   │   ├── data/        # repositories, Supabase provider
│   │   ├── features/    # screens by domain (landing, auth, documents, symptoms...)
│   │   ├── theme/       # design tokens, typography
│   │   └── widgets/     # shared widgets (share card, etc.)
│   └── ...
├── backend/             # Node/TS serverless API (Vercel Functions)
│   ├── api/             # endpoint handlers (decode, chat, symptoms...)
│   └── _lib/            # shared lib (auth, AI providers, Supabase, Sentry...)
├── landing/             # Next.js 14 marketing landing page
├── .env.example
├── .env.local           # real secrets, gitignored
├── .gitignore
├── README.md
├── SETUP.md
└── SPEC.md
```

## Quick start

```bash
# Flutter app
cd app && flutter run -d chrome --web-server --port 8080

# Backend (local)
cd backend && npm run dev

# Landing page
cd landing && npm run dev
```

## Key conventions

- Flutter: Riverpod, go_router, `package:http` via repositories, Inter font
- Backend: Node/TS ESM, Vercel Functions, Zod validation, Zod schemas per endpoint
- Analytics: PostHog always initialized for anonymous viral-funnel events; `personProfiles: identifiedOnly`
- Auth: Supabase; viral wedge (decode) works without login
- AI: Claude (primary, Anthropic SDK), Vertex AI (BAA-covered), Gemini (fallback)
