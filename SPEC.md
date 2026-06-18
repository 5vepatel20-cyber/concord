# Concord — Master Specification

**Version:** 2.0 · **Updated:** 2026-06-17 · **Status:** Planning (pre-build)
**This is the single source of truth.** It consolidates and supersedes the earlier `SPEC.md`
(Medora-named) and folds in `BRAND.md` (brand) and `MEDORA_API_SETUP_PROMPT.md` (provisioning), which
remain as operational companions.

> **Concord** is a clinical-grade companion for people in serious illness. It captures symptoms
> thoroughly, turns them into doctor-ready intelligence, and suggests evidence-based habits to support
> treatment. The thing it does — structured patient-reported symptoms that reach the care team — is the
> thing proven in JAMA (Basch 2017) to extend cancer survival ~5 months and cut ER visits.

---

## Table of contents
1. Executive summary
2. The thesis — why this works (evidence, regulation, market, competition)
3. Strategy — beachhead & 3-phase business model
4. Brand & visual system (Concord / Atlas)
5. Product architecture
6. Tech stack & services — full bill of materials
7. Complete data model
8. Feature specs by epic
9. Atlas — the AI system
10. Security, privacy & HIPAA
11. Infrastructure & CI/CD
12. Reuse map — Swift → Flutter
13. Phased roadmap
14. Decisions — locked & open
15. Appendix

Priority tags: **P0** (Phase-1 MVP) · **P1** (Phase-1 nice-to-have) · **P2** (Phase-2 provider) ·
**P3** (Phase-3 platform). Feature IDs (e.g. `SYM-03`) are stable for issues/PRs.

---

## 1. Executive summary

Concord (formerly Medora) is an iOS-first **Flutter** app + a **Node/TS** backend that helps patients
on active cancer treatment log symptoms in a clinically valid way, share a scannable report with their
oncologist, decode confusing medical documents, and get evidence-based habit guidance from an AI
companion, **Atlas**. The business monetizes in Phase 2 by turning the patient-reported data into a
clinician product reimbursed through existing CMS pathways (RTM codes + the Enhancing Oncology Model),
and in Phase 3 via trial matching and de-identified real-world data.

The hackathon prototype proved the concept but (a) stored symptoms as unstructured free text that never
reached the report or AI, (b) used a weak on-device model with hardcoded keys, and (c) had a generic
visual identity. This spec rebuilds it as a clinical-grade, reimbursable, branded product.

---

## 2. The thesis — why this works

**Clinical proof (rare for a health app):** The Basch et al. JAMA 2017 trial randomized 766 metastatic
cancer patients on chemo; electronic symptom reporting with nurse alerts produced **median survival
31.2 vs 26.0 months** (~5 months, larger than many drugs), fewer ER visits, better quality of life.
The Texas Two-Step study replicated the benefit in community oncology. *The core action Concord
enables is the action proven to extend life.*

**Regulatory tailwinds:**
- **CMS Enhancing Oncology Model (EOM)** *requires* participating oncology practices to collect
  electronic patient-reported outcomes (ePROs) and pays them ~$110/beneficiary/month.
- **Remote Therapeutic Monitoring (RTM)** CPT codes 98975/98980/98981 reimburse ~$20 setup +
  ~$50/patient/month for monitoring patient-reported data.

**Market:** ePRO market ~$950M (2024) → ~$2.2–2.9B by 2030–31 (~15% CAGR), oncology the largest
segment. Adjacent caregiver-app market $1.4B → $3.7B.

**Competitive white space:** consumer trackers (Bearable, Guava) are loved but don't monetize or reach
the doctor; clinical ePRO platforms (Navigating Cancer, Noona, Thyme Care $1B) make money but sell
enterprise into EHRs. **Nobody owns the patient-loved + clinician-grade + reimbursable bridge.** That's
Concord.

---

## 3. Strategy

**Beachhead (LOCKED):** any patient on **active chemotherapy** across the 7 EOM cancer types (breast,
chronic leukemia, small-intestine/colorectal, lung, lymphoma, multiple myeloma, prostate). Shared
PRO-CTCAE chemo-toxicity symptom panel with condition tweaks. Expand to broader chronic illness later.

**Three-phase business:**
- **Phase 1 (0–6 mo) — Own the patient.** Free app. Best-in-class structured symptom logging +
  doctor-ready report + decode-my-documents. Win one oncologist champion. *No revenue; buying trust,
  data, distribution.*
- **Phase 2 (6–18 mo) — Bill the provider.** Clinician dashboard + alerting. Monetize via RTM
  (~$50/patient/mo) and EOM ePRO compliance.
- **Phase 3 (18 mo+) — Sell the insight.** Trial matching (ClinicalTrials.gov already integrated) +
  de-identified real-world data for pharma (the Outcomes4Me model).

**Clinical spine:** all symptom capture is built on **PRO-CTCAE** (NCI's validated patient-reported
adverse-event instrument — the one the survival studies used). This is what makes the data
clinical-grade and EOM-aligned rather than a diary.

---

## 4. Brand & visual system (Concord / Atlas)

Full detail in `BRAND.md`; the essentials:

- **App name:** **Concord** (patient + clinician on one shared source of truth).
- **AI companion:** **Atlas** (carries the full picture; interprets, flags, suggests habits; never
  diagnoses/prescribes; defers to the clinician).
- **Tagline:** *You and your doctor, on the same page.*
- **Personality:** precise · thorough · trustworthy · a capable instrument, **not** a calm/wellness app.
  Optimized first for **clinician credibility**.
- **Direction:** "Clinical Trust", **light-first** (Apple Health / One Medical feel).
- **Color tokens:** Concord Blue `#1668E0`, Blue Pressed `#0F4FB0`, Blue Tint `#EAF1FD`; Ink `#0F1B2D`,
  Body `#2B3A4F`, Slate `#5E6B7E`, Hint `#9AA6B6`; Mist `#F4F7FA`, Surface `#FFFFFF`, Hairline
  `#E2E8F0`; semantic Stable `#16A974`, Caution `#E8A33D`, Warn `#F2683C`, Severe `#E5484D`.
- **Severity ramp (PRO-CTCAE 0–3):** None `#16A974` → Mild `#E8A33D` → Moderate `#F2683C` → Severe
  `#E5484D`. Never color-only; always pair with grade label.
- **Type:** **Inter**, tabular numerals for all clinical data. Scale in BRAND.md.
- **App icon:** blue rounded tile + white open-"C" arc + pulse tick.
- **Implementation:** one Flutter `ThemeData` + a design-tokens file; reference everywhere. The
  doctor-report PDF re-skins to the Concord header.
- **Naming due-diligence:** "Concord" has unrelated users; `.com` taken → plan `concordhealth.app` /
  `getconcord.app`; trademark search (Nice class 9/44) before launch. Bundle id TBD `com.concord.app`.

---

## 5. Product architecture

**Topology: thin Flutter client + trusted Node backend. No secret ships in the app.**

```
┌────────────────────────┐      ┌───────────────────────────┐     ┌────────────────────────┐
│  Flutter app (iOS-first│─────▶│  Concord Backend (Node/TS  │────▶│  Supabase Postgres     │
│  Android-ready)        │      │  on Vercel serverless)     │     │  + Auth + Storage + RLS│
│  - HealthKit/Health    │◀─────│  - PRO-CTCAE scoring       │     └────────────────────────┘
│    Connect via `health`│      │  - alert engine            │     ┌────────────────────────┐
│  - offline queue       │      │  - AI proxy (keys server)  │────▶│  LLM provider (swappable│
│  - local notifications │      │  - report assembly         │     │  Gemini free → BAA later│
└───────────┬────────────┘      │  - clinician API (Phase 2) │     └────────────────────────┘
            │                   └───────────┬───────────────┘     ┌────────────────────────┐
   git push │                               │                     │  Clinician web app     │
            ▼                               └────────────────────▶│  (Next.js, Phase 2)    │
┌────────────────────────┐                                        └────────────────────────┘
│ Codemagic cloud-Mac CI │  builds & signs iOS + Android, uploads to TestFlight / Play
└────────────────────────┘
```

**Client (Flutter/Dart):** chosen because the primary developer works on **Windows** with no daily Mac
access. Flutter lets him build the whole app on Windows and test on an Android emulator; iOS
builds/signing/TestFlight run automatically on **Codemagic** (cloud Mac) on git push. The owner's Mac
is optional backup. Android comes nearly for free if/when wanted. HealthKit access via the `health`
plugin (also wraps Android Health Connect); rare advanced HealthKit features may need a small native
Swift shim.

**Backend (Node/TS on Vercel):** holds all secrets, runs PRO-CTCAE scoring + the alert engine, proxies
the AI. **Serverless constraints baked in:** AI responses **stream** (supported); long report
generation is a streamed endpoint or a queued job (Inngest/QStash), never a long-lived process.
Vercel free Hobby tier is non-commercial → Pro (~$20/mo) at commercial launch.

**Database:** Supabase Postgres + Auth + Storage with **Row-Level Security**.

**Cross-cutting principles:** no secret in the binary · offline-first symptom capture · PHI
minimization (explicit de-id boundary before any Phase-3 data product) · everything clinical is
structured + coded (free text alongside, never instead).

---

## 6. Tech stack & services — full bill of materials

**Runtime services (the product needs these in prod):**

| Service | Purpose | Provision | Cost (P1) | Phase |
|---|---|---|---|---|
| **Google Gemini** (AI Studio) | Atlas chat, report writing, doc decode. 2.5 Flash (~250/day) + 2.5 Pro (~100/day). Free, no card. | You (key) | Free | P1 |
| **Supabase** | Postgres + Auth + Storage + RLS (project exists) | You (keys) | Free→$25/mo | P1 |
| **Apple Developer** | HealthKit, push, TestFlight, App Store (**already owned**) | You (keys only) | owned | P1 |
| **Vercel** | Hosts the Node backend (**already owned**) | You (token) | Free Hobby→$20/mo | P1 |
| **Codemagic** | Cloud-Mac CI: build/sign iOS+Android, upload to TestFlight/Play | You (connect) | Free tier | P1 |
| **Resend** | Transactional email (invites, alerts) | You (key) | Free→~$20/mo | P1 |
| **Sentry** | Backend + app error/crash monitoring | You (DSNs) | Free tier | P1 |
| **PostHog** | Privacy-first analytics | You (key) | Free tier | P1 |
| **Domain + DNS** | `api.concord…`, email domain | You | ~$12/yr | P1 |
| **RxNorm / RxNav** (NLM) | Medication coding | none (public) | Free | P1 |
| **ClinicalTrials.gov** | Trial search (already integrated) | none (public) | Free | P1 |
| **HealthKit / Health Connect** | Health metrics (on-device) | via Apple acct | Free | P1 |
| **Twilio** | SMS urgent caregiver alerts | You | usage | P2 |
| **Paid AI + BAA** (Vertex/Anthropic/Bedrock) | HIPAA-eligible AI before real PHI | You | usage | P1-exit/P2 |
| **AWS Textract** | Server-side OCR (P1 uses on-device first) | You | usage | P2 |

**Net:** the user already owns Apple Developer + Vercel, so **no paid signup is required to start** —
every remaining service has a free, cardless tier. Provisioning runbook: `MEDORA_API_SETUP_PROMPT.md`
(paste into a fresh agent to be walked through it).

**Build/dev tooling:** Flutter SDK + Dart (Windows), Node 20 + pnpm, Supabase CLI, Vercel CLI, `gh`,
Codemagic (CI). Optional MCPs to accelerate dev: Supabase MCP, Sentry MCP.

**Critical security action (now):** rotate/delete the exposed Featherless key in
`Medora/FeatherlessAIClient.swift` (public repo) and the Supabase key in `SupabaseClient.swift`. Both
leave the binary; the AI moves to the server proxy.

---

## 7. Complete data model

Legend: 🆕 new · ♻️ refactor of existing.

### 7.1 Identity & profile
- **`user`** ♻️ — id (uuid, Supabase auth), email, full_name, **date_of_birth** (replaces age),
  sex_at_birth, locale (en/es/fr/de/zh/hi), **role** (`patient`|`caregiver`|`clinician`|`admin`).
- **`patient_profile`** 🆕 — user_id, primary_diagnosis_id→`condition`, diagnosis_date, cancer_stage,
  treatment_status (`active_treatment`|`surveillance`|`remission`|`palliative`), height/weight,
  timezone.
- **`condition`** 🆕 — controlled vocab: display_name, icd10_code, category
  (`oncology`|`cardiometabolic`|`autoimmune`|`respiratory`|`mental_health`|`other`), pro_ctcae_panel_id.
- **`care_relationship`** 🆕 — patient_id, member_user_id, relationship, permissions (jsonb:
  can_log/can_view_reports/receives_alerts), status (`pending`|`active`|`revoked`).

### 7.2 Clinical core — PRO-CTCAE (the centerpiece) 🆕
- **`symptom_term`** — PRO-CTCAE item library (~78 terms): pro_ctcae_code, display_name, body_system,
  attributes (subset of {frequency, severity, interference, presence, amount}), plain_language (per
  locale).
- **`symptom_panel`** — condition-specific subset (term_ids[]); don't show 124 items to everyone.
- **`symptom_report`** ♻️ (replaces `{symptom_text, created_at}`) — patient_id, reported_at,
  recall_window (`now`|`past_7_days`), source (`self`|`caregiver`|`voice`), free_text, audio_url.
- **`symptom_response`** 🆕 — report_id, term_id, frequency/severity/interference/presence/amount
  (0–4), **composite_grade (0–3, derived)**, body_location.
- **`symptom_alert`** 🆕 — patient_id, report_id, rule_id, severity_level (`info`|`urgent`|`emergency`),
  status (`open`|`acknowledged`|`resolved`), acknowledged_by, timestamps.
- **`alert_rule`** 🆕 — term_id, condition (jsonb threshold, e.g. `severity>=3 OR worsened>=2 grades vs
  7-day baseline`), severity_level, escalation (jsonb).

### 7.3 Medications & adherence
- **`medication`** ♻️ — rxnorm_code, display_name, dose/unit, route, schedule (jsonb incl. **chemo
  cycles**), source (`manual`|`healthkit`|`document_extracted`|`clinician`), active.
- **`medication_event`** 🆕 (replaces boolean done) — medication_id, scheduled_for, status
  (`taken`|`skipped`|`missed`|`taken_late`), logged_at.
- **`task`** ♻️ — title, due_at, category (`appointment`|`measurement`|`lifestyle`|`admin`), status,
  source (`manual`|`ai_proposed`|`clinician`).

### 7.4 Health metrics
- **`health_metric_sample`** ♻️ (today: live HealthKit, never persisted) — type
  (steps/sleep/hr/bp_sys/bp_dia/glucose/calories/weight), value/unit, measured_at, source. *Decision:
  persist **daily aggregates** server-side (not raw) for clinician view + phone-independent reports.*

### 7.5 Documents & reports
- **`document`** 🆕 — kind (`discharge_summary`|`lab_result`|`imaging`|`visit_note`|`other`),
  storage_url (encrypted), ocr_text, ai_plain_summary, extracted_values (jsonb labs w/ flags).
- **`report`** ♻️ — kind (`visit_prep`|`interval_summary`|`shared_with_clinician`), date_range,
  **structured_payload** (jsonb behind the visual report), narrative (secondary), pdf_url,
  shared_with[].

### 7.6 Trials
- **`trial_match`** 🆕 — nct_id, match_score, status (`suggested`|`saved`|`contacted`|`dismissed`).

---

## 8. Feature specs by epic

### 8.1 Onboarding & profile (`ONB`)
| ID | Pri | Feature |
|---|---|---|
| ONB-01 | P0 | Coded condition selection → loads the right PRO-CTCAE panel (replaces free-text list) |
| ONB-02 | P0 | Diagnosis detail (date, stage, treatment status, regimen); branches by category |
| ONB-03 | P0 | Date-of-birth (not age) for reference ranges |
| ONB-04 | P1 | Care-team invite (promote care partner to `care_relationship`, scoped permissions) |
| ONB-05 | P1 | Treatment-calendar setup (chemo cycle schedule → aligns check-in prompts) |
| ONB-06 | P0 | Consent & disclaimers (versioned, "not a medical device" language) |
| ONB-07 | P0 | HealthKit/Health-Connect permission priming (per-metric rationale) |

### 8.2 Structured symptom logging (`SYM`) — highest priority
| ID | Pri | Feature |
|---|---|---|
| SYM-01 | P0 | PRO-CTCAE data model + seeded term library |
| SYM-02 | P0 | Quick-log flow (<30s): panel card stack, frequency/severity/interference chips |
| SYM-03 | P0 | Daily check-in push aligned to treatment cycle; one-tap deep link |
| SYM-04 | P0 | Composite grading 0–3 (server fn) |
| SYM-05 | P0 | Free-text + voice note attached to the structured report (keep speech input) |
| SYM-06 | P1 | Rolling 7-day baseline + worsening (Δgrade) detection → feeds alerts/report |
| SYM-07 | P1 | Symptom history: per-symptom sparkline + calendar heatmap |
| SYM-08 | P1 | Caregiver proxy logging (`source=caregiver`) |
| SYM-09 | P0 | Offline capture + sync (local queue → backend) |
| SYM-10 | P1 | Home-screen widget quick-log → structured flow (Flutter `home_widget` + native) |
| SYM-11 | P2 | Body-map for pain location |

### 8.3 Alerting & escalation (`ALRT`)
| ID | Pri | Feature |
|---|---|---|
| ALRT-01 | P1 | Rule engine evaluates on each submit → `symptom_alert` |
| ALRT-02 | P1 | Default oncology rule set (severe diarrhea, uncontrolled pain/nausea, fever-adjacent, SI flags) |
| ALRT-03 | P0 | Patient-side safety guidance on severe self-report ("call your team / 911 if…") — guidance, not diagnosis |
| ALRT-04 | P1 | Caregiver notification on urgent alerts (per permissions) |
| ALRT-05 | P2 | Clinician alert inbox (ack/resolve + audit) |
| ALRT-06 | P2 | Escalation policy (who/order/timeout) per practice |

### 8.4 Doctor-ready report (`RPT`)
| ID | Pri | Feature |
|---|---|---|
| RPT-01 | P0 | Structured payload: symptom heatmap by day, worst 3 episodes, med adherence %, vitals trends, new/worsening flags |
| RPT-02 | P0 | **Include symptom data** (fixes the core gap — today the report omits symptoms) |
| RPT-03 | P0 | Visual one-pager (Concord-skinned PDF/preview) optimized for a 20-second physician glance |
| RPT-04 | P1 | Short Atlas executive summary grounded in real symptom data |
| RPT-05 | P1 | Visit-prep mode: "questions to ask" + "what changed since last visit" |
| RPT-06 | P1 | Share-to-clinician (secure link / portal / email; track `shared_with`) |
| RPT-07 | P0 | Background generation + completion notification (keep the pattern; serverless-safe) |
| RPT-08 | P1 | PRO-CTCAE attribution for clinician credibility / EOM alignment |

### 8.5 Decode-my-documents (`DOC`)
| ID | Pri | Feature |
|---|---|---|
| DOC-01 | P1 | Capture: scan / photo / PDF / share-sheet import → `document` |
| DOC-02 | P1 | OCR + structured lab extraction (on-device first; Textract later) |
| DOC-03 | P1 | Plain-language summary at chosen reading level |
| DOC-04 | P1 | Abnormal-value flagging (e.g. low ANC during chemo → infection-risk note + guidance) |
| DOC-05 | P1 | Doc → proposed coded meds/tasks (evolve the existing checklist skill) |
| DOC-06 | P2 | Doc → suggested questions for the care team |

### 8.6 Atlas — AI companion (`ATLAS`, was AURA)
| ID | Pri | Feature |
|---|---|---|
| ATLAS-01 | P0 | Gemini via **server proxy** (swappable provider interface) |
| ATLAS-02 | P0 | Inject recent graded symptoms + trends into context (today omitted) |
| ATLAS-03 | P1 | Inject active meds + adherence |
| ATLAS-04 | P2 | RAG over symptom history / documents / reports |
| ATLAS-05 | P0 | Safety guardrails (health-only, no diagnosis/prescription, crisis escalation, red-team) |
| ATLAS-06 | P2 | Citations / sources for clinical info |
| ATLAS-07 | P1 | Audience/reading-level tone control (keep) |

### 8.7 Medications & adherence (`MED`)
| ID | Pri | Feature |
|---|---|---|
| MED-01 | P1 | Coded `medication` (RxNorm autocomplete) |
| MED-02 | P1 | `medication_event` adherence (taken/skipped/missed/late) |
| MED-03 | P1 | Cyclical chemo schedules (on/off days) |
| MED-04 | P1 | HealthKit med import → coded meds |
| MED-05 | P0 | Reminders (local notifications) tied to outcomes |
| MED-06 | P1 | Adherence % flows into the report |
| MED-07 | P2 | Side-effect-to-watch notes linked to symptom panel |

### 8.8 Health metrics (`HK`)
| ID | Pri | Feature |
|---|---|---|
| HK-01 | P0 | Keep `health`-plugin reads (steps/sleep/hr/bp/glucose/calories/meds + 30-day history) |
| HK-02 | P1 | Persist daily aggregates server-side |
| HK-03 | P1 | Manual vitals entry (BP cuff, weight, temp) |
| HK-04 | P2 | Reference-range flagging by age/sex |
| HK-05 | P3 | Device integrations (Dexcom, BP cuffs, scales) |

### 8.9 Clinical trials (`TRIAL`)
| ID | Pri | Feature |
|---|---|---|
| TRIAL-01 | P1 | Keep ClinicalTrials.gov search + location filter |
| TRIAL-02 | P2 | Biomarker-aware matching; persist `trial_match` |
| TRIAL-03 | P2 | Save / track / contact lifecycle |
| TRIAL-04 | P3 | Pharma sponsorship hooks |

### 8.10 Caregiver (`CARE`)
| ID | Pri | Feature |
|---|---|---|
| CARE-01 | P1 | Caregiver accounts + permission scopes |
| CARE-02 | P1 | Proxy logging & viewing |
| CARE-03 | P1 | Caregiver alert routing |
| CARE-04 | P2 | Multi-caregiver task coordination |

### 8.11 Clinician / provider product (`CLIN`) — Phase 2 revenue
Separate **Next.js web app** on the same Postgres (distinct RLS role).
| ID | Pri | Feature |
|---|---|---|
| CLIN-01 | P2 | Clinician auth, practice model, patient panels |
| CLIN-02 | P2 | Roster / status board (who's worsening, open alerts) |
| CLIN-03 | P2 | Alert inbox + ack/resolve (audited) |
| CLIN-04 | P2 | Patient detail: PRO-CTCAE trends, meds, vitals, documents |
| CLIN-05 | P2 | **RTM time tracking + billing/superbill export** (core monetization) |
| CLIN-06 | P2 | EOM ePRO compliance reporting |
| CLIN-07 | P2 | Secure messaging to patient (audited) |
| CLIN-08 | P3 | EHR/FHIR integration (Epic/athenahealth) |

---

## 9. Atlas — the AI system (`AI`)
| ID | Pri | Item |
|---|---|---|
| AI-01 | P0 | Server-side AI proxy: keys server-side, rate limits, logging, cost caps |
| AI-02 | P0 | **Gemini** (2.5 Flash chat/low-latency, 2.5 Pro reports) behind a **swappable provider interface** |
| AI-03 | P1 | Prompt library + versioning (Atlas chat, report, doc-summary, visit-prep) |
| AI-04 | P1 | Structured output (JSON/tool-use) for lab extraction, task proposals, report payloads |
| AI-05 | P1 | Evaluation harness (accuracy, refusals, hallucination, reading level) |
| AI-06 | P0 | Guardrails & red-team (crisis, no-diagnosis, jailbreak, PII) |
| AI-07 | P2 | RAG infra (embeddings over user docs/history) |
| AI-08 | P1 | Cost & latency monitoring + fallbacks (e.g. Groq backup) |

**PHI rule:** free Gemini trains on prompts and has no BAA → **synthetic/test data only** while on
free tier. Before any real patient data reaches the model, switch the proxy to a HIPAA-eligible BAA
provider (Google Vertex / Anthropic / AWS Bedrock). The swappable interface makes this a config change.

---

## 10. Security, privacy & HIPAA (`SEC`)
| ID | Pri | Item |
|---|---|---|
| SEC-01 | **P0 now** | Remove hardcoded secrets; rotate exposed Featherless key |
| SEC-02 | P0 | Server-side secret management |
| SEC-03 | P0 | Postgres Row-Level Security |
| SEC-04 | P0 | TLS in transit; at-rest encryption (DB + document storage) |
| SEC-05 | P1 | Auth hardening (MFA option, session expiry, biometric app lock) |
| SEC-06 | P2 | Audit logging (every PHI access) |
| SEC-07 | P2 | HIPAA posture: BAAs (Supabase Team, AI provider, push, analytics); risk assessment |
| SEC-08 | P0 | Versioned consent + granular sharing + revocation |
| SEC-09 | P3 | De-identification pipeline (safe-harbor) for RWD |
| SEC-10 | P0 | "Not a medical device" guardrails (stay in FDA CDS/wellness enforcement-discretion; legal review) |
| SEC-11 | P1 | App-store privacy labels; full account/data deletion + export |

---

## 11. Infrastructure & CI/CD (`INF`)
| ID | Pri | Item |
|---|---|---|
| INF-01 | P0 | Node/TS backend on Vercel + CI/CD |
| INF-02 | P0 | DB migrations framework (Supabase CLI) |
| INF-03 | P1 | Environments (dev/staging/prod) |
| INF-04 | P0 | **Codemagic** pipeline: build/sign iOS+Android on cloud Mac → TestFlight/Play on push |
| INF-05 | P1 | APNs / FCM push pipeline (P1 local notifications; P2 server push via FCM) |
| INF-06 | P1 | Error monitoring (Sentry) + crash reporting |
| INF-07 | P1 | Privacy-respecting analytics (PostHog) |
| INF-08 | P1 | Automated tests (Dart unit/widget + backend unit; PRO-CTCAE scoring tests) |
| INF-09 | P2 | Clinician web app hosting (Vercel) |
| INF-10 | P2 | Backups & disaster recovery |

---

## 12. Reuse map — Swift → Flutter

The existing SwiftUI app becomes a **reference**, reimplemented in Dart. Logic and prompts port; UI is
rebuilt with the Concord design system.

| Existing (Swift) | Verdict | Action in Flutter rebuild |
|---|---|---|
| `healthstore.swift` | **Reference (high value)** | Reimplement via `health` plugin; this file is the spec for which metrics/queries to reproduce |
| `ChecklistView/Store` | Reference | Rebuild as MED epic (coded meds + adherence events, server-backed) |
| `SymptomLogView/Store` | Replace concept | Rebuild on PRO-CTCAE (SYM); keep voice + widget entry points |
| `ReportStore/Renderer` | Reference | Keep background-job + notification pattern (serverless-safe); new visual payload + Concord skin |
| `FeatherlessAIClient` | Replace | Server-side Gemini proxy (swappable); keep streaming UX |
| `AIChatView` | Reference | Rebuild as Atlas with new context builder + guardrails |
| `SummarizeView` | Reference | Split report vs. document-decode (DOC) |
| `ClinicalTrialsService/View` | Reference | Rebuild; deepen later (TRIAL) |
| `CalendarExportManager` | Reference | Re-implement (Flutter calendar plugin) |
| `SpeechRecognizer` | Reference | Flutter speech-to-text plugin |
| `LocationManager` | Reference | Flutter geolocation plugin |
| `Localization.swift` | Reference | Flutter i18n (keep 6 languages) + PRO-CTCAE plain-language |
| `AuthStore`/`SupabaseClient` | Replace | supabase_flutter SDK; profile/care-partner → real tables + RLS; no key in binary |
| `MedoraWidget` | Reference | Flutter `home_widget` + per-platform native |
| `Theme/MainTabView/ProfileView` | Reference | Rebuild shell with Concord `ThemeData` |

---

## 13. Phased roadmap

**Phase 1 — Own the patient (0–6 mo).** SEC-01/02 (secrets out, rotate key — *first, this week*) →
backend skeleton on Vercel + AI proxy (AI-01/02) + Supabase schema/RLS (SEC-03) + Codemagic CI
(INF-04) → **SYM** (PRO-CTCAE logging, offline, daily check-in) → **RPT** (visual report incl.
symptoms) → **ATLAS** (Gemini + symptom context + guardrails) → **DOC** (decode docs) → ONB coded
onboarding + consent → MED coded meds/adherence → HK reads → ALRT-03 patient guidance → Concord brand
system. *Exit:* retained weekly loggers + ≥1 oncologist says "I want my patients on this."

**Phase 2 — Bill the provider (6–18 mo).** CLIN web app (dashboard, alert inbox, RTM billing, EOM
compliance) → full ALRT engine + escalation → CARE roles/proxy/routing → SEC-06/07 (audit, HIPAA/BAAs,
**switch AI to BAA provider**) → HK server aggregates + manual vitals. *Exit:* first paying practice;
RTM superbills; EOM ePRO demonstrated.

**Phase 3 — Sell the insight (18 mo+).** TRIAL biomarker matching + pharma hooks → AI-07 RAG → SEC-09
de-identification + RWD products → CLIN-08 FHIR/EHR → HK device ecosystem. *Exit:* first pharma
trial-recruitment / RWD contract.

---

## 14. Decisions

### Locked
1. **Beachhead:** any active-chemo patient (7 EOM cancer types).
2. **Mobile framework:** Flutter (dev has no Mac → Windows-native dev; Codemagic cloud-Mac CI for iOS).
3. **Backend:** Node/TS on Vercel (serverless; stream AI, queue long jobs).
4. **Database:** Supabase Postgres + Auth + Storage + RLS.
5. **AI (build phase):** Google Gemini free tier behind a swappable proxy; BAA provider before real PHI.
6. **Hosting:** Vercel (already owned). **CI:** Codemagic.
7. **Brand:** Concord (app) / Atlas (AI); "Clinical Trust", light-first; Inter; tokens in §4 / BRAND.md.
8. **Accounts:** Apple Developer + Vercel already owned → no paid signup to start.

### Open (need a call before/while building)
1. HealthKit persistence: recommend **daily aggregates** server-side, no raw samples.
2. PRO-CTCAE licensing/attribution terms (NCI item library + localized plain-language).
3. Report rendering location: client preview (offline) + server render for shared reports.
4. Regulatory line: legal review keeping alerting/guidance in FDA enforcement-discretion zone.
5. Final domain + bundle id (`concordhealth.app` / `com.concord.app`?) + trademark check.
6. Push: confirm Firebase Cloud Messaging for Phase-2 server push (FCM covers iOS+Android).

---

## 15. Appendix

### Existing codebase snapshot (cloned 2026-06-15)
- Stack: SwiftUI iOS + Widget; Supabase (auth + `symptoms` table); Featherless AI (Qwen3-4B);
  ClinicalTrials.gov; EventKit; PDFKit; Speech; ~9,446 LOC Swift.
- Confirmed gaps: symptoms are free-text and **never reach the report or AI** (ReportStore punts on
  them); AI is weak + **hardcoded keys** (public repo); no backend; profile lives in auth metadata; no
  RLS; clinical data in UserDefaults.
- Strengths to carry as references: strong HealthKit layer, background-report + notification pattern,
  trials search, 6-language localization, voice input, home-screen widget, care-partner capture.

### Companion documents
- `BRAND.md` — full brand & visual system.
- `MEDORA_API_SETUP_PROMPT.md` — paste-into-fresh-agent provisioning runbook.
- `SPEC.md` — **superseded** by this document (kept for history).

### Glossary
PRO-CTCAE (NCI patient-reported adverse-event instrument) · EOM (CMS Enhancing Oncology Model) · RTM
(Remote Therapeutic Monitoring CPT codes) · ePRO (electronic patient-reported outcome) · RWD
(real-world data) · BAA (Business Associate Agreement, HIPAA) · ANC (absolute neutrophil count).
