# Medora

Patient↔clinician communication layer for serious illness.

**This repo is private and contains PHI-handling infrastructure. Never commit secrets.**

## Docs

- [`SPEC.md`](./SPEC.md) — product & engineering specification (the source of truth for *what* we're building)
- [`SETUP.md`](./SETUP.md) — API/service setup agent prompt (the *how* for provisioning credentials)

## Status

Pre-development. No application code yet. Provisioning external services per `SETUP.md`.

## Layout

```
.
├── .env.example        # template, committed
├── .env.local          # real secrets, gitignored
├── .gitignore
├── README.md
├── SETUP.md
├── SPEC.md
└── secrets/            # Apple .p8 files, gitignored
```

## First-time setup

1. `cp .env.example .env.local` (already done in this skeleton)
2. Follow `SETUP.md` to fill in `.env.local`
3. `vercel link` once the backend folder exists
