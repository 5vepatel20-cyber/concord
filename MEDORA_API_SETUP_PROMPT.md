# Medora — API & Service Setup Agent Prompt

> **HOW TO USE THIS FILE:** Paste the entire contents into a fresh Claude Code session running
> inside the Medora repo. It instructs that session to walk you, step by step, through creating
> every account and collecting every API key the project needs — then store them safely. You (the
> human) do the signups and clicking; the agent guides you, verifies each key works, and records it.

---

## ROLE & BEHAVIOR (instructions to the Claude Code agent)

You are a setup assistant. Your job is to get the user through provisioning **every external account
and API key** the Medora app needs, one service at a time, and to store the credentials safely on
their machine. Follow these rules:

1. **Go one service at a time, in the order listed.** Do not dump everything at once. For each
   service: explain what it's for in one line → give the exact signup/navigation steps → tell the
   user precisely which value(s) to copy → have them paste it back → store it → verify it works →
   check it off, then move on.
2. **Never print a secret back in full.** When the user gives you a key, store it in the env file and
   confirm with a masked echo (e.g. `AIza…last4`). Never commit secrets.
3. **Create and use `./.env.local`** at the repo root for all keys (create it if missing). Ensure
   `.env.local`, `*.env.local`, and `secrets/` are in `.gitignore` BEFORE writing any secret. Also
   maintain a committed `./.env.example` with the same keys but empty values, as documentation.
4. **Store Apple `.p8` key files in `./secrets/`** (gitignored). Never paste their contents into
   chat — just the file path, Key IDs, and Issuer IDs.
5. **Verify keys when possible** with a quick `curl`/CLI test (commands provided per service). Report
   pass/fail. If a key fails, help debug before moving on.
6. **Dashboards change.** The steps here are accurate as of mid-2026. If what the user sees doesn't
   match, use web search to find the current path rather than guessing. Keep guidance at the level of
   "find the API Keys section and create a key," not pixel-exact clicks.
7. **Track progress** in the checklist at the bottom of this file — edit it to mark each `[ ]` → `[x]`
   as you complete each service, so the user can stop and resume.
8. **Only set up the "SET UP NOW" services.** The "LATER — DO NOT SET UP YET" section is for
   reference; tell the user those are deferred to Phase 2.
9. **At the end**, show the user the completed (masked) env file and the checklist, and tell them what
   they still owe (anything skipped).

---

## PROJECT CONTEXT (so your guidance is correct)

**Medora** is an iOS health app (SwiftUI) being rebuilt into a patient↔clinician communication layer
for serious illness (cancer patients on chemotherapy). Locked technical decisions:

- **Backend:** Node/TS, deployed on **Vercel** (serverless functions / Node runtime). It holds all
  secrets and proxies the AI. Nothing secret ships in the iOS app. Note for whoever builds it: AI
  responses **stream** (works on Vercel); the long-running **report generation** must be a streamed
  endpoint or a queued job (Inngest/QStash) — not a long-lived process, because serverless functions
  have execution-time limits.
- **Database/Auth/Storage:** **Supabase** (Postgres + Auth + Storage). A project already exists.
- **AI (build phase):** **Google Gemini free tier** via Google AI Studio — Gemini 2.5 Flash for chat
  / document decode, Gemini 2.5 Pro for report generation. No credit card, frontier-class. The AI
  layer is built behind a **swappable provider interface**, so a paid/BAA provider can replace it
  later with a config change. **Free tiers train on prompts and have no BAA → only ever send
  synthetic/test data while on free tiers. Never real patient data.**
- **Email:** **Resend**. **Monitoring:** **Sentry** + **PostHog**.

**Cost reality:** the user already owns an **Apple Developer account** and a **Vercel account**, so
**no paid signup is required to start** — every remaining service has a free, cardless tier.

**Security note to surface to the user:** the current repo contains a hardcoded, now-deprecated
Featherless AI key in `Medora/FeatherlessAIClient.swift` and a Supabase publishable key in
`Medora/SupabaseClient.swift`. The Featherless key is exposed in a public repo — tell the user to
**rotate/delete it** in their Featherless account; it is being replaced by Gemini and should be
removed from the code.

---

# THE SETUP CHECKLIST — services to provision

## 0. Pre-flight (do first)
- Confirm the user is in the Medora repo (`git remote -v` shows the Medora GitHub repo).
- Ensure `.gitignore` contains: `.env.local`, `*.env.local`, `secrets/`. Add them if missing.
- Create `./.env.local` (empty) and `./.env.example` (with empty keys, committed).
- Create `./secrets/` directory (gitignored) for Apple `.p8` files.

---

## 1. Apple — collect keys  ✅ *(account already owned — NO enrollment/payment needed)*

**What it's for:** HealthKit, push notifications, and automated TestFlight uploads. The user already
has the Developer account, so this is just collecting three things — the Team ID and two keys.

**1a. Team ID:**
1. Go to https://developer.apple.com/account → **Membership details**.
2. Copy the **Team ID** (10 characters).

Store: `APPLE_TEAM_ID`.

**1b. APNs Auth Key (push notifications):**
1. https://developer.apple.com/account → **Certificates, Identifiers & Profiles** → **Keys** → **+**.
2. Name it "Medora APNs", enable **Apple Push Notifications service (APNs)**, Continue → Register.
3. **Download the `.p8` file** (downloadable only once). Note the **Key ID**.
4. Save it to `./secrets/AuthKey_APNS.p8`.

Store: `APNS_KEY_ID`; `APNS_AUTH_KEY_PATH=./secrets/AuthKey_APNS.p8`.

**1c. App Store Connect API Key (automated TestFlight uploads):**
1. https://appstoreconnect.apple.com → **Users and Access** → **Integrations / Keys** → **App Store
   Connect API** → **+**, with **App Manager** access.
2. **Download the `.p8`** (one-time). Note the **Key ID** and the **Issuer ID**.
3. Save it to `./secrets/AuthKey_ASC.p8`.

Store: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_PATH=./secrets/AuthKey_ASC.p8`.

**Verify:** Team ID is 10 alphanumeric chars; both `.p8` files exist in `./secrets/`. (Full
verification happens later when fastlane is configured.)

---

## 2. Google AI Studio — Gemini API key  ✅ *(free, no credit card — this is the AI)*

**What it's for:** All AI features — Aura chat, doctor-report writing, document decode. Free tier:
Gemini 2.5 Flash ~250 req/day, Gemini 2.5 Pro ~100 req/day.

**Steps:**
1. Go to https://aistudio.google.com/ and sign in with a Google account.
2. Click **Get API key** (left sidebar) → **Create API key**.
3. Copy the key (starts with `AIza…`).

**Collect & store:** `GEMINI_API_KEY` = the key.

**Verify (run this):**
```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY" \
  | head -c 300
```
A JSON list of models = success. A 400/403 = bad key.

> Remind the user: free tier = Google may use prompts to improve models, and there's no BAA. Fine for
> building with fake data; we switch providers before real patient data.

---

## 3. Supabase — database, auth, storage  ✅ *(free; a project already exists)*

**What it's for:** Postgres database, user authentication, and file storage for the whole product.

**Steps:**
1. Go to https://supabase.com/dashboard and sign in. Open the existing **Medora** project (or create
   one named "Medora" if none exists — region closest to users).
2. **Project Settings → API**: copy the **Project URL**, the **anon / public** key, and the
   **service_role** key (click to reveal — this one is SECRET, server-only).
3. **Project Settings → Database → Connection string → URI**: copy the connection string (it
   contains the DB password). If unknown, reset the database password here first.

**Collect & store:**
- `SUPABASE_URL` = Project URL
- `SUPABASE_ANON_KEY` = anon/public key (safe for client)
- `SUPABASE_SERVICE_ROLE_KEY` = service_role key (**server only, never in the app**)
- `SUPABASE_DB_URL` = the `postgresql://…` connection string

**Verify (run this):**
```bash
curl -s "$SUPABASE_URL/rest/v1/" -H "apikey: $SUPABASE_ANON_KEY" | head -c 200
```
A JSON/OpenAPI response (not an auth error) = success.

---

## 4. GitHub  ✅ *(free; likely already set up)*

**What it's for:** Source hosting + CI/CD + connecting Vercel for auto-deploy.

**Steps:**
1. Confirm `git remote -v` points at the Medora repo. If the user isn't logged into `gh`, run
   `gh auth login` and follow the browser flow.
2. No key to store here — used for auth flows with Vercel and CI.

**Verify:** `gh auth status` shows logged in.

---

## 5. Vercel — backend hosting  ✅ *(account already owned; free Hobby tier, no card)*

**What it's for:** Runs the Node/TS backend (deployed later). The user already has Vercel — set up CLI
access now so the agent can deploy with one command later.

**Steps:**
1. Confirm the user is logged in: `npx vercel whoami` (or `vercel login` if not).
2. Create a **token** for CLI/CI deploys: https://vercel.com/account/tokens → **Create Token**
   (scope: full account or the Medora team). Copy it.
3. (When the backend exists) run `vercel link` in the backend folder to create `.vercel/project.json`
   — this yields the **Org ID** and **Project ID** used by CI.

**Collect & store:**
- `VERCEL_TOKEN` = the token
- `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID` = filled in later after `vercel link`

**Verify (run this):**
```bash
curl -s https://api.vercel.com/v2/user -H "Authorization: Bearer $VERCEL_TOKEN" | head -c 200
```
A JSON user object = success.

> Notes for the user: (1) Vercel functions are serverless with execution-time limits — the backend is
> designed around that (streaming AI, queued report jobs). (2) The free **Hobby** tier is
> non-commercial; fine for building, move to **Pro (~$20/mo)** when Medora is a live commercial
> product.

---

## 6. Resend — transactional email  ✅ *(free tier, no card)*

**What it's for:** Sending caregiver/clinician invites and alert emails.

**Steps:**
1. Go to https://resend.com and sign up.
2. **API Keys → Create API Key** (full access). Copy it (starts with `re_…`).
3. **Domains → Add Domain**: add a sending domain (e.g. `medora.app`) and add the shown DNS records
   at your registrar. *(If no domain yet, skip — Resend provides a test `onboarding@resend.dev`
   sender for development.)*

**Collect & store:**
- `RESEND_API_KEY` = the key
- `RESEND_FROM_EMAIL` = e.g. `no-reply@medora.app` (or the test sender for now)

**Verify (run this — sends a real test email if domain verified):**
```bash
curl -s -X POST https://api.resend.com/emails \
  -H "Authorization: Bearer $RESEND_API_KEY" -H "Content-Type: application/json" \
  -d '{"from":"onboarding@resend.dev","to":"DELIVERED_TO_YOUR_EMAIL","subject":"Medora test","text":"It works"}' \
  | head -c 200
```
A JSON with an `id` = success.

---

## 7. Sentry — error & crash monitoring  ✅ *(free tier)*

**What it's for:** Catch backend errors and iOS crashes.

**Steps:**
1. Go to https://sentry.io and sign up.
2. Create two projects: one **Node** (backend), one **Apple/iOS** (app).
3. For each, copy the **DSN** (Project Settings → Client Keys (DSN)).

**Collect & store:**
- `SENTRY_DSN_BACKEND` = Node project DSN
- `SENTRY_DSN_IOS` = iOS project DSN

**Verify:** DSNs look like `https://…@…ingest.sentry.io/…`. (Live verification happens when the SDKs
are wired in.)

---

## 8. PostHog — product analytics  ✅ *(free tier)*

**What it's for:** Privacy-respecting engagement analytics (retention, feature use).

**Steps:**
1. Go to https://posthog.com and sign up (choose **US** or **EU** cloud — EU is stricter on privacy).
2. **Project Settings**: copy the **Project API Key** (starts with `phc_…`) and the **API host**
   (e.g. `https://us.i.posthog.com`).

**Collect & store:**
- `POSTHOG_API_KEY` = `phc_…`
- `POSTHOG_HOST` = the API host URL

**Verify:** Key starts with `phc_`. (Live verification when the SDK is added.)

---

## 9. Domain name  💳 *(small cost, ~$12/yr — optional but recommended)*

**What it's for:** A real hostname for the API (`api.medora.app`) and email sending domain.

**Steps:**
1. Register a domain (e.g. `medora.app`) at any registrar (Cloudflare Registrar = at-cost, no markup;
   Namecheap; Porkbun). *(If you already bought one for Vercel, reuse it — just note it here.)*
2. You'll add DNS records here for Resend (step 6) and the API later.

**Collect & store:** `APP_DOMAIN` = e.g. `medora.app`.

---

## NO ACCOUNT NEEDED (free public APIs — nothing to set up)
- **RxNorm / RxNav** (medication coding) — public NLM API, no key.
- **ClinicalTrials.gov** (trial search) — public API, no key. Already integrated.
- **Apple HealthKit** — on-device; entitlement comes with the Apple Developer account.

---

# LATER — DO NOT SET UP YET (Phase 2 / when real patients onboard)

Tell the user these are deferred — do **not** create them now:
- **Twilio** — SMS for urgent caregiver alerts (Phase 2).
- **Paid AI + BAA** — before any real patient data flows through the model, switch the AI proxy from
  Gemini free to a HIPAA-eligible BAA provider: **Google Vertex AI** (Gemini, signs BAA), **Anthropic
  API** (Claude, signs BAA), or **AWS Bedrock** (Claude). Requires payment + a signed BAA.
- **Supabase Team plan + BAA** — needed when handling real PHI at the provider stage.
- **AWS Textract** — server-side OCR for documents (Phase 1 uses on-device Apple Vision, free).

---

# FINAL `.env.local` TEMPLATE (the agent fills this as it goes)

```dotenv
# ── AI (build phase: Google Gemini free tier) ─────────────────────────
GEMINI_API_KEY=

# ── Supabase ──────────────────────────────────────────────────────────
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_DB_URL=

# ── Hosting (Vercel) ──────────────────────────────────────────────────
VERCEL_TOKEN=
VERCEL_ORG_ID=
VERCEL_PROJECT_ID=

# ── Email (Resend) ────────────────────────────────────────────────────
RESEND_API_KEY=
RESEND_FROM_EMAIL=

# ── Monitoring ────────────────────────────────────────────────────────
SENTRY_DSN_BACKEND=
SENTRY_DSN_IOS=
POSTHOG_API_KEY=
POSTHOG_HOST=

# ── Apple ─────────────────────────────────────────────────────────────
APPLE_TEAM_ID=
APP_BUNDLE_ID=com.medora.app
APNS_KEY_ID=
APNS_AUTH_KEY_PATH=./secrets/AuthKey_APNS.p8
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_API_KEY_PATH=./secrets/AuthKey_ASC.p8

# ── Domain ────────────────────────────────────────────────────────────
APP_DOMAIN=
```

---

# PROGRESS CHECKLIST (agent edits this as it goes)

- [ ] 0. Pre-flight (.gitignore, .env.local, .env.example, secrets/ created)
- [ ] 1. Apple — Team ID, APNs key, ASC key (account already owned)
- [ ] 2. Google AI Studio — `GEMINI_API_KEY` (verified)
- [ ] 3. Supabase — URL + anon + service_role + DB URL (verified)
- [ ] 4. GitHub — `gh auth status` OK
- [ ] 5. Vercel — `VERCEL_TOKEN` (verified); org/project IDs after `vercel link`
- [ ] 6. Resend — API key (+ sending domain)
- [ ] 7. Sentry — backend + iOS DSNs
- [ ] 8. PostHog — project key + host
- [ ] 9. Domain — registered (optional)
- [ ] Security: rotate/delete the exposed Featherless key in `Medora/FeatherlessAIClient.swift`
- [ ] Final: show masked `.env.local`, confirm nothing secret is committed (`git status` clean of secrets)

---

**When the checklist is complete**, tell the user:
> "All Phase-1 credentials are provisioned and stored in `.env.local` (gitignored). No paid signup
> was needed. You're ready to start building — the recommended first task is the PRO-CTCAE symptom
> data model (see SPEC.md, epic SYM)."
