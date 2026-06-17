# Medora — Product & Engineering Specification

**Version:** 1.0 (master spec)
**Last updated:** 2026-06-15
**Status:** Planning — supersedes hackathon scope
**Owner:** sansar

> The thing Medora does — structured patient-reported symptoms that reach the care team — is the
> thing proven in JAMA (Basch 2017) to extend cancer survival ~5 months and cut ER visits. This spec
> turns the hackathon demo into that clinically-grounded, reimbursable product.

---

## 0. How to read this document

This is a **feature- and function-level specification** of everything required to take Medora from
hackathon prototype to a real product. It is organized as:

1. **Strategy recap & the system we're building** (§1)
2. **Target architecture** — the structural shift required (§2)
3. **Complete data model** — every entity & schema, including the PRO-CTCAE clinical core (§3)
4. **Feature specs by epic** — each with user stories, functional requirements, screens,
   functions/services to build, data touched, and acceptance criteria (§4–§13)
5. **Clinician/provider product** (§14)
6. **AI/ML system** (§15)
7. **Security, privacy, HIPAA compliance** (§16)
8. **Infrastructure & DevOps** (§17)
9. **Reuse map** — keep / refactor / replace against the current codebase (§18)
10. **Phased roadmap** — what ships when (§19)
11. **Open decisions** (§20)

Each feature carries a stable ID (e.g. `SYM-03`) so it can be referenced in issues/PRs.
Priority tags: **P0** (Phase-1 MVP), **P1** (Phase-1 nice-to-have), **P2** (Phase-2 provider),
**P3** (Phase-3 platform).

---

## 1. Strategy recap & the system we're building

**Reframe:** Medora is not a symptom tracker (a feature). It is the **patient↔clinician
communication layer for serious illness** (a reimbursable system).

**Beachhead (LOCKED):** **any patient on active chemotherapy**, across the 7 EOM cancer types
(breast, chronic leukemia, small intestine/colorectal, lung, lymphoma, multiple myeloma, prostate).
Broader top-of-funnel than a single tumor type; the symptom panel is the shared chemo-toxicity core
(PRO-CTCAE) with condition tweaks. Expand to broader chronic illness later.

**Three-phase business:**
- **Phase 1 (0–6 mo):** Own the patient. Free app. Best-in-class structured symptom logging +
  doctor-ready visit report + decode-my-documents. Win one oncologist champion.
- **Phase 2 (6–18 mo):** Bill the provider. Clinician dashboard + alerting. Monetize via RTM CPT
  codes (~$50/patient/mo) and CMS Enhancing Oncology Model ePRO mandate.
- **Phase 3 (18 mo+):** Sell the insight. Trial matching (already have ClinicalTrials.gov) +
  de-identified real-world data for pharma.

**Clinical spine:** all symptom capture is built on **PRO-CTCAE** (NCI's validated patient-reported
adverse-event instrument — the exact one the survival studies used). This is the single change that
turns "diary" into "clinical-grade."

---

## 2. Target architecture

### 2.1 The structural shift

Current: a SwiftUI app that talks **directly** to Supabase and to the Featherless AI API with
**hardcoded keys**, persisting clinical-ish data in `UserDefaults`. This cannot scale, cannot be
made HIPAA-compliant, and leaks secrets.

Target: a **thin client + trusted backend** topology.

```
┌─────────────────┐     ┌──────────────────────────┐     ┌─────────────────────┐
│  iOS app        │────▶│  Medora Backend (Node/TS  │────▶│  Postgres (Supabase │
│  (SwiftUI)      │     │  on Vercel)              │     │  or RDS) + RLS      │
│  - HealthKit    │◀────│  - auth/session           │     └─────────────────────┘
│  - local cache  │     │  - PRO-CTCAE scoring      │     ┌─────────────────────┐
│  - offline queue│     │  - alert engine           │     │  LLM provider        │
└─────────────────┘     │  - AI proxy (keys server) │────▶│  (Gemini free tier   │
        │               │  - report renderer (opt)  │     │   build → Claude via │
        ▼               │  - clinician API          │     │   Vertex/Bedrock w/  │
┌─────────────────┐     │  - queued report jobs     │     │   BAA pre-Phase-2)   │
│  Widget / Push  │     └──────────────────────────┘     └─────────────────────┘
└─────────────────┘              │
                                 ▼
                        ┌─────────────────────┐
                        │  Clinician web app  │
                        │  (Next.js)          │
                        └─────────────────────┘
```

### 2.2 Component inventory

| Component | Tech (proposed) | Why |
|---|---|---|
| iOS client | SwiftUI (existing) | Keep; refactor data layer |
| Backend API | **Node/TS on Vercel (LOCKED)** | Serverless functions hold all secrets, run PRO-CTCAE scoring/alerts, proxy AI. Long-running report jobs via queue (Inngest/QStash) — not long-lived processes. Talks to Postgres + AI provider. |
| Database | Postgres (Supabase) + Row-Level Security | Already in use; formalize schema + RLS |
| AI gateway | **Build:** server-side proxy to **Google Gemini** (free tier) via AI Studio. **Pre-Phase-2:** swap to **Claude via Vertex AI / AWS Bedrock** behind a BAA. | Move keys off-device; frontier model; swappable provider interface so the swap is a config change. **Free tier has no BAA → only synthetic/test data during build.** |
| Clinician app | Next.js + the same Postgres (separate RLS role) | Provider dashboard (Phase 2) |
| Push | APNs (via backend) | Care-team → patient & report alerts |
| File storage | Supabase Storage / S3 (encrypted) | Uploaded documents, generated PDFs |
| Analytics | PostHog (self-host or EU) / privacy-first | Engagement without PHI leakage |

### 2.3 Cross-cutting principles

- **No secret ships in the binary.** All third-party API keys live server-side.
- **Offline-first symptom capture.** A sick patient may have no signal; logging must queue locally
  and sync. (`OFFLINE-01`)
- **PHI minimization.** De-identification boundary is explicit and tested before any Phase-3 data
  product touches it.
- **Everything clinical is structured + coded.** Free text is allowed *alongside* coded data, never
  *instead of* it.

---

## 3. Complete data model

Legend: 🆕 new · ♻️ refactor of existing · `pk` primary key · `fk` foreign key.

### 3.1 Identity & profile

**`user`** ♻️ (today: Supabase Auth metadata only)
| field | type | notes |
|---|---|---|
| id `pk` | uuid | Supabase auth uid |
| email | text | |
| full_name | text | |
| date_of_birth | date | replaces free `age` int — needed for clinical context |
| sex_at_birth | enum | clinical relevance for reference ranges |
| created_at | timestamptz | |
| locale | text | one of en/es/fr/de/zh/hi (existing) |
| role | enum | `patient` \| `caregiver` \| `clinician` \| `admin` 🆕 |

**`patient_profile`** 🆕 (promote out of auth metadata)
| field | type | notes |
|---|---|---|
| user_id `pk fk` | uuid | |
| primary_diagnosis_id `fk` | uuid | → `condition` (coded, not free text) |
| diagnosis_date | date | |
| cancer_stage | text | nullable; for oncology cohort |
| treatment_status | enum | `active_treatment` \| `surveillance` \| `remission` \| `palliative` |
| height_cm / weight_kg | numeric | for dosing context, BSA |
| timezone | text | alert scheduling |

**`condition`** 🆕 — controlled vocabulary (seed with EOM cancer types + common chronic)
| field | type |
|---|
| id `pk` | uuid |
| display_name | text |
| icd10_code | text |
| category | enum (`oncology`\|`cardiometabolic`\|`autoimmune`\|`respiratory`\|`mental_health`\|`other`) |
| pro_ctcae_panel_id `fk` | uuid → which symptom panel applies |

> Migration note: today's `managing: [String]` free-text list (Heart Health, Diabetes, Cancer, …)
> maps to seeded `condition` rows. Keep an `other_text` escape hatch.

**`care_relationship`** 🆕 (today: care partner buried in auth metadata)
| field | type | notes |
|---|---|---|
| id `pk` | uuid | |
| patient_id `fk` | uuid | |
| member_user_id `fk` | uuid | the caregiver / clinician |
| relationship | enum | `spouse`\|`child`\|`parent`\|`friend`\|`clinician`\|`care_navigator` |
| permissions | jsonb | granular: can_log, can_view_reports, receives_alerts |
| status | enum | `pending`\|`active`\|`revoked` |

### 3.2 Clinical core — PRO-CTCAE symptom system 🆕 (the centerpiece)

**`symptom_term`** — the PRO-CTCAE item library (~78 terms / ~124 items)
| field | type | notes |
|---|---|---|
| id `pk` | uuid | |
| pro_ctcae_code | text | official NCI item code |
| display_name | text | e.g. "Nausea" |
| body_system | enum | GI / neuro / derm / constitutional / psych / pain / etc. |
| attributes | text[] | subset of {frequency, severity, interference, presence, amount} |
| plain_language | text | patient-friendly phrasing per locale |

**`symptom_panel`** — condition-specific subset of terms (don't show 124 items to everyone)
| field | type |
|---|
| id `pk` | uuid |
| name | text (e.g. "Breast cancer / chemo core panel") |
| term_ids | uuid[] |

**`symptom_report`** ♻️ (replaces today's `{symptom_text, created_at}`)
| field | type | notes |
|---|---|---|
| id `pk` | uuid | |
| patient_id `fk` | uuid | |
| reported_at | timestamptz | |
| recall_window | enum | `now` \| `past_7_days` (PRO-CTCAE standard) |
| source | enum | `self` \| `caregiver` \| `voice` |
| free_text | text | optional narrative (keeps existing UX) |
| audio_url | text | optional, from voice capture |

**`symptom_response`** 🆕 — one row per term per report (the structured payload)
| field | type | notes |
|---|---|---|
| id `pk` | uuid | |
| report_id `fk` | uuid | |
| term_id `fk` | uuid | |
| frequency | smallint (0–4) | nullable per term attributes |
| severity | smallint (0–4) | |
| interference | smallint (0–4) | |
| presence | bool | |
| amount | smallint | |
| composite_grade | smallint (0–3) | **derived** by scoring fn (`PRO-01`) |
| body_location | text | nullable (for pain) |

**`symptom_alert`** 🆕 — fired when thresholds crossed (the clinical magic)
| field | type | notes |
|---|---|---|
| id `pk` | uuid | |
| patient_id `fk` | uuid | |
| report_id `fk` | uuid | |
| rule_id `fk` | uuid | which threshold rule fired |
| severity_level | enum | `info`\|`urgent`\|`emergency` |
| status | enum | `open`\|`acknowledged`\|`resolved` |
| acknowledged_by `fk` | uuid | clinician/nurse (Phase 2) |
| created_at / resolved_at | timestamptz | |

**`alert_rule`** 🆕 — configurable thresholds (per panel / per practice in Phase 2)
| field | type | example |
|---|---|---|
| id `pk` | uuid | |
| term_id `fk` | uuid | Nausea |
| condition | jsonb | `severity >= 3 OR (worsened_by >= 2 grades vs 7-day baseline)` |
| severity_level | enum | `urgent` |
| escalation | jsonb | who to notify, in what order |

### 3.3 Medications & adherence

**`medication`** ♻️ (today: free-text checklist tasks + HealthKit import)
| field | type | notes |
|---|---|---|
| id `pk` | uuid | |
| patient_id `fk` | uuid | |
| rxnorm_code | text | coded drug 🆕 (autocomplete from RxNorm) |
| display_name | text | |
| dose / unit | text | |
| route | enum | oral/IV/sub-q/topical |
| schedule | jsonb | times, days, cyclical (chemo cycles!) |
| source | enum | `manual`\|`healthkit`\|`document_extracted`\|`clinician` |
| active | bool | |

**`medication_event`** 🆕 (replaces boolean `isDone` on a checklist task)
| field | type |
|---|
| id `pk` | uuid |
| medication_id `fk` | uuid |
| scheduled_for | timestamptz |
| status | enum (`taken`\|`skipped`\|`missed`\|`taken_late`) |
| logged_at | timestamptz |

**`task`** ♻️ (general non-med tasks — keep existing ChecklistTask concept, move to DB)
| field | type |
|---|
| id `pk` / patient_id `fk` | uuid |
| title | text |
| due_at | timestamptz |
| category | enum (`appointment`\|`measurement`\|`lifestyle`\|`admin`) |
| status | enum |
| source | enum (`manual`\|`ai_proposed`\|`clinician`) |

### 3.4 Health metrics (HealthKit)

**`health_metric_sample`** ♻️ (today: read live from HealthKit, never persisted)
| field | type | notes |
|---|---|---|
| id `pk` / patient_id `fk` | uuid | |
| type | enum | steps/sleep/hr/bp_sys/bp_dia/glucose/calories/weight |
| value / unit | numeric/text | |
| measured_at | timestamptz | |
| source | enum | `healthkit`\|`manual`\|`device` |

> Decision needed (§20): persist HealthKit aggregates server-side (enables clinician view + reports
> without the phone) vs. keep on-device only (stronger privacy). Recommendation: persist **daily
> aggregates** only, not raw samples.

### 3.5 Documents & reports

**`document`** 🆕 (today: attachment handled transiently in chat)
| field | type | notes |
|---|---|---|
| id `pk` / patient_id `fk` | uuid | |
| kind | enum | `discharge_summary`\|`lab_result`\|`imaging`\|`visit_note`\|`other` |
| storage_url | text | encrypted bucket |
| ocr_text | text | extracted |
| ai_plain_summary | text | "decode my document" output |
| extracted_values | jsonb | structured labs (e.g. ANC, hemoglobin) with flags |
| created_at | timestamptz | |

**`report`** ♻️ (today: `HealthReport` in UserDefaults + on-disk PDF)
| field | type | notes |
|---|---|---|
| id `pk` / patient_id `fk` | uuid | |
| kind | enum | `visit_prep`\|`interval_summary`\|`shared_with_clinician` |
| date_range | daterange | |
| structured_payload | jsonb | the data behind the visual report (§7) |
| narrative | text | AI prose (secondary now) |
| pdf_url | text | |
| shared_with `fk` | uuid[] | clinician recipients |
| created_at | timestamptz | |

### 3.6 Clinical trials (existing, keep)

**`trial_match`** 🆕 (persist what's today computed live)
| field | type |
|---|
| id `pk` / patient_id `fk` | uuid |
| nct_id | text |
| match_score | numeric |
| status | enum (`suggested`\|`saved`\|`contacted`\|`dismissed`) |

---

## 4. EPIC: Onboarding & profile (`ONB`)

Builds on existing 7-screen onboarding in `ContentView.swift`.

| ID | Feature | Pri | Description |
|---|---|---|---|
| ONB-01 | Coded condition selection | P0 | Replace free-text `managing` list with coded `condition` picker; drives which PRO-CTCAE panel loads. Keep "Other". |
| ONB-02 | Diagnosis detail capture | P0 | For oncology: diagnosis date, stage, treatment status, current regimen. Branches by condition category. |
| ONB-03 | Date-of-birth (not age) | P0 | Replace `ageString` with DOB; compute age; needed for reference ranges. |
| ONB-04 | Care-team invite | P1 | Promote care partner from auth metadata to `care_relationship`; send invite (email/SMS) with permission scopes. |
| ONB-05 | Treatment calendar setup | P1 | Capture chemo cycle schedule (e.g. every 21 days) so logging prompts align to cycle day. |
| ONB-06 | Consent & disclaimers | P0 | Explicit consent for data use, AI limitations, "not a medical device" language; versioned + stored. |
| ONB-07 | HealthKit permission priming | ♻️P0 | Keep existing flow; add explanation of *why* per metric. |

**Functions/services:** `ConditionCatalog.load()`, `PanelResolver.panel(for:condition)`,
`CareInviteService.invite()`, `ConsentStore.record(version:)`.
**Acceptance:** a new oncology user finishes onboarding with a coded diagnosis, a loaded symptom
panel, and (optionally) a pending caregiver invite.

---

## 5. EPIC: Structured symptom logging (`SYM`) — **highest priority**

This replaces `SymptomLogView` + `SymptomStore`'s free-text model.

| ID | Feature | Pri | Description |
|---|---|---|---|
| SYM-01 | PRO-CTCAE data model | P0 | Implement `symptom_term`, `symptom_panel`, `symptom_report`, `symptom_response` (§3.2). Seed term library. |
| SYM-02 | Quick-log flow (<30s) | P0 | Condition-panel card stack: tap a symptom → frequency/severity/interference chips. Skip = "none". Target median completion < 30s. |
| SYM-03 | Daily check-in prompt | P0 | Scheduled push ("How are you feeling today?") aligned to treatment cycle; one-tap deep link. |
| SYM-04 | Composite grading | P0 | Server fn maps PRO-CTCAE attributes → 0–3 grade (`PRO-01`). |
| SYM-05 | Free-text + voice notes | ♻️P0 | Keep existing `TextField` + `SpeechRecognizer`; attach as `free_text`/`audio_url` to structured report, not instead of it. |
| SYM-06 | Baseline & trend detection | P1 | Rolling 7-day baseline per term; detect worsening (Δgrade). Feeds alerts + report. |
| SYM-07 | Symptom history timeline | ♻️P1 | Upgrade existing list to a per-symptom sparkline + calendar heatmap. |
| SYM-08 | Caregiver proxy logging | P1 | Caregiver can log on patient's behalf (`source = caregiver`). |
| SYM-09 | Offline capture & sync | P0 | Queue logs locally (Core Data/SQLite), sync when online (`OFFLINE-01`). |
| SYM-10 | Widget quick-log upgrade | ♻️P1 | Existing `LogSymptomWidget` deep-links into the new structured quick-log, not the old text box. |
| SYM-11 | Body-map for pain/location | P2 | Tap-a-bodypart for pain location → `body_location`. |

**Screens/components:** `SymptomCheckInView` (card stack), `SeverityChipRow`, `SymptomTimelineView`,
`SymptomHeatmapView`, `QuickLogWidgetEntry`.
**Functions/services:** `SymptomService.submit(report:)`, `ProCtcaeScorer.grade(response:)`,
`BaselineEngine.baseline(term:window:)`, `OfflineQueue.enqueue/flush()`.
**Acceptance:** patient logs 3 symptoms with severities in <30s offline on the subway; data syncs and
appears, graded, in history and (later) in the report and clinician view.

---

## 6. EPIC: Alerting & care-team escalation (`ALRT`)

The mechanism behind the survival benefit — symptoms must *reach a human who acts*.

| ID | Feature | Pri | Description |
|---|---|---|---|
| ALRT-01 | Alert rule engine | P1 | Evaluate `alert_rule`s on each symptom submit; create `symptom_alert`. |
| ALRT-02 | Default oncology rule set | P1 | Seed clinically-sensible thresholds (e.g. severe diarrhea, fever-adjacent, uncontrolled pain/nausea, SI flags). |
| ALRT-03 | Patient-side guidance | P0 | On severe/emergency self-report, immediately surface safety guidance ("call your care team / 911 if…"). **Stays on right side of FDA: guidance, not diagnosis.** |
| ALRT-04 | Caregiver notification | P1 | Push/SMS to caregiver on urgent alerts (per permissions). |
| ALRT-05 | Clinician alert inbox | P2 | Phase-2 dashboard queue with ack/resolve + audit trail. |
| ALRT-06 | Escalation policy | P2 | Configurable per practice (who, order, timeout → escalate). |

**Functions/services:** `AlertEngine.evaluate(report:)`, `EscalationRouter.route(alert:)`,
`SafetyGuidanceProvider.guidance(for:grade:)`.
**Acceptance:** a grade-3 nausea report creates an urgent alert, shows the patient guidance, notifies
the caregiver, and (Phase 2) lands in the clinician inbox with full context.

---

## 7. EPIC: Doctor-ready report, redesigned (`RPT`)

Transforms today's AI-prose PDF into a **scannable, data-driven clinical artifact** that also
*finally includes symptoms*.

| ID | Feature | Pri | Description |
|---|---|---|---|
| RPT-01 | Structured report payload | P0 | Assemble `structured_payload`: symptom heatmap by day, worst 3 episodes, med adherence %, vitals trends, new/worsening flags. |
| RPT-02 | **Include symptom data** | P0 | Fix the core gap — feed real `symptom_response` data into the report (currently punted, ReportStore.swift:352). |
| RPT-03 | Visual one-pager | P0 | New PDF/preview: top = at-a-glance summary; symptom heatmap grid; medication adherence bar; vitals sparklines. Optimized for a 20-second physician glance. |
| RPT-04 | AI narrative (secondary) | ♻️P1 | Keep a short AI executive summary, now grounded in real symptom data + upgraded model. |
| RPT-05 | Visit-prep mode | P1 | "Questions to ask your doctor" + "what changed since last visit" generated for the upcoming appointment. |
| RPT-06 | Share-to-clinician | P1 | Secure link / portal share / email; track `shared_with`. (Phase 2: lands directly in clinician app.) |
| RPT-07 | Background generation | ♻️P0 | Keep existing background `ReportStore` job pattern + completion notification. |
| RPT-08 | PRO-CTCAE attribution | P1 | Label symptom data as PRO-CTCAE-based for clinician credibility/EOM alignment. |

**Components:** `ReportPayloadBuilder`, `VisualReportRenderer` (replaces prose-only
`ReportPDFRenderer`), `SymptomHeatmapPDFSection`, `AdherenceBarSection`, `VisitPrepView`.
**Acceptance:** a generated report shows a real symptom heatmap, medication adherence %, vitals
trends, and flagged changes — and an oncologist can read the key facts in under 30 seconds.

---

## 8. EPIC: Decode-my-documents (`DOC`)

Productize the "understand reports back" half — today only a transient chat attachment.

| ID | Feature | Pri | Description |
|---|---|---|---|
| DOC-01 | Document capture | P1 | Scan (VisionKit) / photo / PDF / share-sheet import → `document`. |
| DOC-02 | OCR + extraction | P1 | Server OCR → `ocr_text`; extract structured labs → `extracted_values`. |
| DOC-03 | Plain-language summary | P1 | AI "what this means for you" at a chosen reading level (reuse `audienceGuidance`). |
| DOC-04 | Abnormal-value flagging | P1 | Flag out-of-range labs (e.g. low ANC during chemo → infection-risk note + guidance). |
| DOC-05 | Doc → tasks/meds | ♻️P1 | Keep existing "checklist skill" that proposes tasks; now also proposes coded `medication` rows. |
| DOC-06 | Doc → questions | P2 | Generate suggested questions to raise with the care team. |

**Components:** `DocumentScannerView`, `DocumentService.ingest()`, `LabExtractor`,
`PlainLanguageSummarizer`, `AbnormalFlagger`.
**Acceptance:** user scans a discharge summary; gets a plain-language summary, flagged abnormal labs
with guidance, and proposed medications/tasks they can accept into their plan.

---

## 9. EPIC: Aura AI companion (`AURA`)

Upgrade the existing chat (`AIChatView`) — model, context, safety.

| ID | Feature | Pri | Description |
|---|---|---|---|
| AURA-01 | Model upgrade | P0 | Move off Qwen3-4B to **Google Gemini** (2.5 Flash chat / 2.5 Pro reasoning) **via server proxy** behind a swappable provider interface. **Pre-Phase-2 swap:** switch to Claude (Sonnet 4.6) via Vertex AI or AWS Bedrock, both BAA-eligible. |
| AURA-02 | Inject symptom context | P0 | Add recent graded symptoms + trends to system prompt (today: only Apple Health + conditions). |
| AURA-03 | Inject meds & adherence | P1 | Add active medication list + adherence so answers are grounded. |
| AURA-04 | Retrieval over user data | P2 | RAG over symptom history, documents, reports for "what did my labs show last month?". |
| AURA-05 | Safety guardrails | ♻️P0 | Keep "health-only + no diagnosis/prescription" rules; add crisis/self-harm escalation path; red-team. |
| AURA-06 | Citations / sources | P2 | When giving clinical info, cite reputable sources. |
| AURA-07 | Audience tone control | ♻️P1 | Keep existing `audienceGuidance` (reading-level adaptation). |

**Functions/services:** `AuraContextBuilder.build(patient:)`, `AIProxyClient.stream()` (replaces
direct `FeatherlessAIClient`), `CrisisDetector`.
**Acceptance:** Aura answers "is my fatigue getting worse?" using the user's actual graded symptom
trend, in plain language, refusing to diagnose, powered by Gemini through the backend.

---

## 10. EPIC: Medications & adherence (`MED`)

Upgrade `ChecklistView`/`ChecklistStore` into a real medication system.

| ID | Feature | Pri | Description |
|---|---|---|---|
| MED-01 | Coded medication model | P1 | RxNorm-backed `medication` (§3.3); autocomplete search. |
| MED-02 | Adherence events | P1 | Replace boolean `isDone` with `medication_event` (taken/skipped/missed/late). |
| MED-03 | Cyclical schedules | P1 | Support chemo-cycle dosing (on/off days), not just daily. |
| MED-04 | HealthKit med import | ♻️P1 | Keep existing import; map to coded meds. |
| MED-05 | Reminders | ♻️P0 | Keep existing local notifications; tie to `medication_event` outcomes. |
| MED-06 | Adherence in report | P1 | Real adherence % flows into `RPT-01`. |
| MED-07 | Interaction/side-effect notes | P2 | Surface common side effects to watch (links to symptom panel). |

**Acceptance:** a chemo patient sees today's correct doses per cycle day, logs taken/skipped, and
that adherence appears in the doctor report.

---

## 11. EPIC: Health metrics & HealthKit (`HK`)

Mostly keep the strong existing `healthstore.swift`; add persistence.

| ID | Feature | Pri | Description |
|---|---|---|---|
| HK-01 | Keep HealthKit reads | ♻️P0 | steps/sleep/hr/bp/glucose/calories/meds + 30-day history (already solid). |
| HK-02 | Persist daily aggregates | P1 | Store daily aggregates server-side for clinician view + phone-independent reports (see §20 decision). |
| HK-03 | Manual vitals entry | P1 | For users without devices (BP cuff readings, weight, temp). |
| HK-04 | Reference ranges | P2 | Flag out-of-range vitals using age/sex context. |
| HK-05 | Device integrations | P3 | Beyond Apple: Dexcom (glucose), BP cuffs, scales. |

---

## 12. EPIC: Clinical trials (`TRIAL`) — keep & deepen

| ID | Feature | Pri | Description |
|---|---|---|---|
| TRIAL-01 | Keep ClinicalTrials.gov search | ♻️P1 | Existing `ClinicalTrialsService` + location filter. |
| TRIAL-02 | Biomarker-aware matching | P2 | Use diagnosis/stage/biomarkers for better match scores; persist `trial_match`. |
| TRIAL-03 | Save / track / contact | P2 | Lifecycle on matches. |
| TRIAL-04 | Pharma sponsorship hooks | P3 | Monetization surface (Outcomes4Me model). |

---

## 13. EPIC: Caregiver experience (`CARE`)

| ID | Feature | Pri | Description |
|---|---|---|---|
| CARE-01 | Caregiver accounts & roles | P1 | `care_relationship` + permission scopes. |
| CARE-02 | Proxy logging & viewing | P1 | Log symptoms/meds, view reports per permission. |
| CARE-03 | Caregiver alert routing | P1 | Receive urgent alerts (`ALRT-04`). |
| CARE-04 | Shared task coordination | P2 | Multiple caregivers coordinate appointments/tasks. |

---

## 14. EPIC: Clinician / provider product (`CLIN`) — Phase 2 revenue

A separate **web** app on the same database (distinct RLS role). This is where money enters.

| ID | Feature | Pri | Description |
|---|---|---|---|
| CLIN-01 | Clinician auth & practice model | P2 | Practices, clinicians, patient panels; invite/claim patients. |
| CLIN-02 | Patient roster & status board | P2 | Triage view: who's worsening, who has open alerts. |
| CLIN-03 | Alert inbox + ack/resolve | P2 | `ALRT-05/06`; audited. |
| CLIN-04 | Patient detail / symptom trends | P2 | Full PRO-CTCAE trends, meds, vitals, documents. |
| CLIN-05 | RTM time tracking & billing export | P2 | Log monitoring time per patient/month → CPT 98975/98980/98981 superbill export. **Core monetization.** |
| CLIN-06 | EOM ePRO compliance reporting | P2 | Demonstrate ePRO collection for CMS Enhancing Oncology Model. |
| CLIN-07 | Secure messaging to patient | P2 | Two-way, audited, within app. |
| CLIN-08 | EHR integration (FHIR) | P3 | Read demographics/problems; write ePRO observations (Epic/athenahealth). |

**Acceptance:** a nurse opens the dashboard, sees three patients flagged worsening, reviews PRO-CTCAE
trends, acts, logs RTM time, and exports a billing-ready superbill at month end.

---

## 15. AI/ML system (`AI`)

> Concrete provider choices, model picks, and the live env-var list live in **`SETUP.md`** (the
> companion doc). This section is about the *system*: proxy, structured output, eval, guardrails.

| ID | Item | Pri | Description |
|---|---|---|---|
| AI-01 | Server-side AI proxy | P0 | All LLM calls go through backend; keys server-side; per-user rate limits, logging, cost caps. |
| AI-02 | Model integration (build) | P0 | **Build:** Google Gemini 2.5 Flash (chat/document decode, low-latency) + 2.5 Pro (reports, extraction, reasoning), free tier. **Pre-Phase-2 swap:** Claude (Sonnet 4.6) via Vertex AI or AWS Bedrock with a signed BAA — config change only behind the swappable provider interface (AI-01). |
| AI-03 | Prompt library + versioning | P1 | Centralize system prompts (Aura, report, doc-summary, visit-prep); version & eval. |
| AI-04 | Structured output | P1 | Tool-use/JSON schema for lab extraction, task proposals, report payloads (not regex on prose). |
| AI-05 | Evaluation harness | P1 | Golden-set tests for medical accuracy, refusal behavior, hallucination, reading level. |
| AI-06 | Guardrails & red-team | P0 | Crisis handling, no-diagnosis enforcement, jailbreak resistance, PII handling. |
| AI-07 | RAG infra | P2 | Embeddings over user docs/history for grounded answers. |
| AI-08 | Cost & latency monitoring | P1 | Token/cost dashboards; fallbacks. |

> Replaces `FeatherlessAIClient` (Qwen3-4B, hardcoded key, on-device). Keep its nice streaming UX
> pattern; move the transport server-side.

---

## 16. Security, privacy & compliance (`SEC`)

| ID | Item | Pri | Description |
|---|---|---|---|
| SEC-01 | Remove hardcoded secrets | **P0 / now** | Featherless key (FeatherlessAIClient.swift:11) and Supabase key (SupabaseClient.swift:13) must leave the binary. Rotate the exposed Featherless key immediately. |
| SEC-02 | Server-side secret mgmt | P0 | All third-party keys in backend env/secret manager. |
| SEC-03 | Row-Level Security | P0 | Postgres RLS so a patient can only read their rows; clinicians scoped to their panel. |
| SEC-04 | Encryption | P0 | TLS in transit; at-rest encryption for DB + document storage. |
| SEC-05 | Auth hardening | P1 | MFA option, session expiry, device management, biometric app lock. |
| SEC-06 | Audit logging | P2 | Every PHI access logged (required for clinician side / HIPAA). |
| SEC-07 | HIPAA posture | P2 | BAAs (Supabase/AWS, AI provider, push, analytics); risk assessment; policies. Required before provider go-live. |
| SEC-08 | Consent & data-use records | P0 | Versioned consent; granular sharing; revocation. |
| SEC-09 | De-identification pipeline | P3 | Safe-harbor de-id boundary for RWD products; tested. |
| SEC-10 | "Not a medical device" guardrails | P0 | Keep app within FDA wellness/CDS enforcement-discretion lines: surface info to clinicians who decide; no autonomous diagnosis/treatment recommendation. Legal review. |
| SEC-11 | App privacy & data-deletion | P1 | App Store privacy labels, full account/data deletion, export. |

---

## 17. Infrastructure & DevOps (`INF`)

| ID | Item | Pri |
|---|---|---|
| INF-01 | Backend service + CI/CD | P0 |
| INF-02 | DB migrations framework | P0 |
| INF-03 | Environments (dev/staging/prod) | P1 |
| INF-04 | Push (APNs) pipeline | P1 |
| INF-05 | TestFlight + release process | ♻️P0 (TestFlight already announced) |
| INF-06 | Error monitoring (Sentry) + crash reporting | P1 |
| INF-07 | Privacy-respecting analytics | P1 |
| INF-08 | Automated tests (unit/UI) + scoring-fn tests | P1 |
| INF-09 | Clinician web app hosting | P2 |
| INF-10 | Backups & disaster recovery | P2 |

---

## 18. Reuse map — keep / refactor / replace

| Existing file | Verdict | Action |
|---|---|---|
| `healthstore.swift` | **Keep** ✅ | Strongest asset; add aggregate persistence (HK-02). |
| `ChecklistView/ChecklistStore` | **Refactor** ♻️ | Evolve into MED epic; coded meds + adherence events; move off UserDefaults. |
| `SymptomLogView/SymptomStore` | **Replace** 🔁 | Rebuild on PRO-CTCAE (SYM epic). Keep voice/widget entry points. |
| `ReportStore/ReportPDFRenderer` | **Refactor** ♻️ | Keep background-job + notification pattern; replace prose-only PDF with visual payload (RPT). Fix symptom inclusion. |
| `FeatherlessAIClient` | **Replace** 🔁 | Server-side AI proxy (AI-01/02). Keep streaming UX. Build with Gemini; swap to Claude-via-Vertex/Bedrock pre-Phase-2. |
| `AIChatView` | **Refactor** ♻️ | New context builder + model + guardrails (AURA). |
| `SummarizeView` | **Refactor** ♻️ | Currently the report-generation screen; split report vs. document-decode (DOC). |
| `ClinicalTrialsService/View` | **Keep** ✅ | Deepen later (TRIAL). |
| `CalendarExportManager` | **Keep** ✅ | Works; tie to tasks/appointments. |
| `SpeechRecognizer` | **Keep** ✅ | Reuse for voice notes. |
| `LocationManager` | **Keep** ✅ | Trials + practice locating. |
| `Localization.swift` | **Keep/extend** ✅ | 6 languages; extend to new strings + PRO-CTCAE plain-language. |
| `AuthStore` | **Refactor** ♻️ | Promote profile/care-partner out of auth metadata into tables (§3.1). |
| `SupabaseClient` | **Refactor** ♻️ | Stop shipping key; route through backend; add RLS. |
| `MedoraWidget` | **Keep/upgrade** ♻️ | Point at structured quick-log. |
| `Theme/MainTabView/ProfileView` | **Keep** ✅ | UI shell; extend with new screens. |

---

## 19. Phased roadmap

### Phase 1 — Own the patient (P0/P1) · 0–6 months
**Goal:** best-in-class patient experience for one chemo cohort; win an oncologist champion.
- SEC-01/02 (secrets out, rotate key) — **do first, this week**
- Target architecture skeleton: backend + AI proxy (AI-01/02), DB schema + RLS (SEC-03)
- SYM epic (PRO-CTCAE logging, offline, daily check-in) — the centerpiece
- RPT epic (visual report that *includes symptoms*) — the wedge artifact
- AURA-01/02/05 (Gemini + symptom context + guardrails)
- DOC-01..04 (decode-my-documents)
- ONB-01/02/03/06 (coded onboarding + consent)
- MED-01/02 (coded meds + adherence), HK-01 (keep)
- ALRT-03 (patient-side safety guidance — no clinician needed yet)
**Exit criteria:** retained weekly loggers in the cohort; ≥1 oncologist says "I want my patients on
this"; report demoed to clinicians.

### Phase 2 — Bill the provider (P2) · 6–18 months
**Goal:** turn the report + alerts into a reimbursable clinician product.
- CLIN epic (dashboard, alert inbox, RTM time tracking & billing export, EOM compliance)
- ALRT-01/02/04/05/06 (full alert engine + escalation)
- CARE epic (caregiver roles, proxy, alert routing)
- SEC-06/07 (audit logging, HIPAA/BAAs) — gate before go-live
- HK-02/03 (server aggregates, manual vitals)
**Exit criteria:** first paying practice; RTM superbills generated; EOM ePRO reporting demonstrated.

### Phase 3 — Sell the insight (P3) · 18 months+
**Goal:** platform/venture-scale upside.
- TRIAL-02/03/04 (biomarker matching, pharma hooks)
- AI-07 (RAG), AURA-04/06
- SEC-09 (de-identification), RWD data products
- CLIN-08 (FHIR/EHR integration)
- HK-05 (device ecosystem)
**Exit criteria:** first pharma trial-recruitment / RWD contract.

---

## 20. Open decisions (need a call before/while building)

1. ~~**Backend stack**~~ **RESOLVED (2026-06-15):** Node/TS on Vercel (serverless functions). Postgres
   still on Supabase (auth + DB + RLS); the Node service holds secrets, runs scoring/alerts,
   proxies AI. Long-running report jobs use a queue (Inngest/QStash), not long-lived functions.
2. **HealthKit persistence:** raw vs. daily-aggregate vs. on-device-only. *Recommendation: daily
   aggregates server-side; no raw samples.*
3. ~~**Beachhead cohort**~~ **RESOLVED (2026-06-15):** any active-chemo patient across the 7 EOM
   cancer types (not a single tumor type).
4. **PRO-CTCAE licensing/attribution:** confirm usage terms for the NCI item library + localized
   plain-language phrasing.
5. **Clinician app framework:** Next.js (recommended) vs. native; build vs. buy alert dashboard.
6. **Report rendering location:** keep client-side PDF (offline) vs. server-side (consistency,
   clinician parity). *Recommendation: server-side for shared reports, client for instant preview.*
7. **Regulatory line:** legal review on where alerting/guidance sits re: FDA CDS/device — keep in
   enforcement-discretion zone.
8. **Identity for caregivers/clinicians:** separate auth tenants vs. single users table with roles.
   *Recommendation: single users table + role + RLS.*
9. ~~**AI provider**~~ **RESOLVED (2026-06-17):** **Build phase = Google Gemini free tier** (2.5 Flash
   / 2.5 Pro) via AI Studio — no BAA, no card. **Pre-Phase-2 swap (mandatory before any real PHI
   flows):** Claude (Sonnet 4.6) via Vertex AI or AWS Bedrock, both BAA-eligible. The provider
   interface is built swappable from day one. See `SETUP.md` for the concrete credential list.

---

## Appendix A — Existing codebase snapshot (as cloned 2026-06-15)

- **Stack:** SwiftUI iOS + Widget; Supabase (auth + `symptoms` table); Featherless AI (Qwen3-4B);
  ClinicalTrials.gov; EventKit; PDFKit; Speech; ~9,446 LOC Swift.
- **Persistence today:** Supabase (auth metadata, symptoms), UserDefaults/AppStorage (checklist,
  reports index, profile name/email), on-disk (PDFs), HealthKit (live reads).
- **Conditions today:** 9 free-text presets + "Other" (no coding, no condition-specific logic).
- **Key gaps confirmed by code read:**
  - Symptoms are free-text only and **never reach the report or Aura** (ReportStore.swift:352
    explicitly punts symptom data).
  - AI is Qwen3-4B with **hardcoded keys** (FeatherlessAIClient.swift:11, SupabaseClient.swift:13).
  - No backend; the app calls AI directly. No RLS schema; profile lives in auth metadata.
  - Clinical-ish data (checklist) in UserDefaults.
- **Strengths to build on:** excellent HealthKit layer, solid background-report + notification
  pattern, working trials search, 6-language localization, voice input, home-screen widget,
  care-partner capture (just needs promotion to a real model).
