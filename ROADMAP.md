# Concord — Launch Roadmap

**Strategy:** Lead with "Decode My Doctor's Report" as a free, no-login viral tool.
Symptom tracking is the retention layer underneath.

---

## ADMIN (Sansar — prerequisites before public launch)

### Must-have before any real users

- [ ] **Privacy Policy + Terms of Service + "Not Medical Advice" disclaimer**
  App Store requirement for any health app. Templates exist; lawyer review is cheap insurance.

- [ ] **Sign BAA with an LLM provider**
  Current Gemini free tier cannot handle real PHI. Must switch to a provider with a signed Business Associate Agreement before launch (e.g. Gemini via Google Cloud Vertex AI, or another BAA-covered provider).

- [ ] **App Store Connect listing**
  Write listing copy + commission screenshots oriented around "understand your lab results / decode medical reports" (not "cancer symptom tracker"). ASO-optimized.

- [ ] **Domain + landing page content**
  Veer builds the page; you write the words. Landing page: decode promise, demo GIF, email capture for waitlist.

### Should happen before revenue/fundraising

- [ ] **Incorporate as Delaware Public Benefit Corporation**
  For-profit, mission baked in. Get the entity before any money, raise, or equity split with Veer.

- [ ] **Business bank account + cap table**
  Once incorporated.

### Marketing / growth (your main job once it ships)

- [ ] **Stand up social accounts** — TikTok + Instagram first (health UGC lives there)
- [ ] **Produce first 5 UGC videos** (see VIRAL_LAUNCH_PLAN §5)
- [ ] **Identify + reach out to 5-10 patient/caregiver micro-influencers**
- [ ] **Seed communities** — r/cancer, r/breastcancer, caregiver Facebook groups, #cancertok
- [ ] **iPhone testing** — confirm builds via Codemagic → TestFlight; Veer proves on Android/web

---

## CODING (Veer — sequential, Sprint 0 → 3)

### Sprint 0 — Lock scope + tear down auth wall

- [ ] **Make Decode the no-login front door**
  - Add `/documents/decode` to `_publicRoutes` in `app.dart`
  - Change `initialLocation` from `/sign-in` to `/documents/decode`
  - The `redirect` logic: unauthenticated users can reach decode; only prompt for account on save/symptom-track actions
  - File: `app/lib/app.dart`

- [ ] **Build a new landing/home screen for unauthenticated users**
  - First launch → decode screen with value props, no sign-up wall
  - Clean, minimal layout: paste/upload area, "How it works" section
  - File: `app/lib/features/landing/landing_screen.dart` (new)

- [ ] **Move onboarding to progressive/optional**
  - Don't force `/onboarding` redirect after auth
  - Only ask diagnosis questions if/when user taps into symptom tracking
  - One question at a time, never as a wall
  - Files: `app/lib/app.dart` (remove onboarding guard), `features/onboarding/*` (refactor)

- [ ] **Hide Phase-2 features from navigation** (keep code, remove from nav)
  - Route entries to keep but NOT link from Profile/Home nav:
    - Caregiver: `/caregiver/manage`, `/caregiver/dashboard`, `/caregiver/log/:patientId`
    - Alerts: `/alerts`, `/alerts/policies`
    - Messages: `/messages`, `/messages/:conversationId`
    - Trials: `/trials/search`
    - Treatment: `/treatment/calendar`, `/treatment/regimens`
    - Adherence: `/medications/adherence`
  - File: `app/lib/features/profile/profile_screen.dart` — remove nav entries for these
  - File: `app/lib/features/home/home_screen.dart` — remove links to these
  - Routes stay registered in `app.dart` so deep links still work, just hidden from UI

### Sprint 1 — Share Card + Analytics + Landing page

- [ ] **Build Share Card generator**
  - After a decode (or symptom report), a "Share" button produces a branded image card
  - Plain-English explanation rendered as a clean card for Instagram/TikTok/texts
  - PHI-safe: user controls what's shared
  - Watermark with app name + handle → every share is an ad
  - New file: `app/lib/widgets/share_card.dart`
  - Modify: `app/lib/features/documents/document_decode_screen.dart`

- [ ] **Wire PostHog analytics on the viral funnel**
  - Events to track: `install`, `first_decode`, `decode_result`, `share_created`, `account_created`, `symptom_log`, `day_7_retention`
  - PostHog infra already exists (`core/monitoring/posthog_init.dart`) — just add event calls
  - Files: `app/lib/features/documents/document_decode_screen.dart`, `app/lib/core/monitoring/posthog_init.dart`

- [ ] **Build landing page** (Next.js)
  - One page: the decode promise, a demo GIF, an email capture
  - Already have `/clinician` Next.js app in the repo — could reuse or create a standalone page
  - File: new in `/clinician` or `/landing`

- [ ] **Simplify the quick symptom log**
  - Polish the bottom sheet for speed and delight
  - Remove friction: pre-select most common condition, faster grade selection
  - File: `app/lib/features/symptoms/quick_log_screen.dart`

### Sprint 2 — BAA provider swap + polish

- [ ] **Swap LLM to BAA-covered provider**
  - Move from Gemini free tier to Google Cloud Vertex AI (BAA available)
  - Or Anthropic via GCP Vertex AI / AWS Bedrock
  - Update `backend/_lib/ai/provider.ts` and `backend/_lib/ai/gemini.ts` (or new vertex.ts)
  - Already have `claude.ts` fallback provider — may need Vertex wrapping
  - File: `backend/_lib/ai/provider.ts`

- [ ] **Branded PDF report polish**
  - Ensure the one-pager PDF has branding, is shareable, is clearly useful
  - File: `app/lib/features/report/one_pager_screen.dart` (check if exist)

- [ ] **Re-engagement notifications**
  - Gentle nudges: "Your symptoms from last week are ready to review"
  - Notification infra already exists (`flutter_local_notifications`, deep-link routing)
  - File: `app/lib/core/notifications/notification_service.dart`

- [ ] **Progressively enhance decode with image OCR**
  - Already have camera/gallery picker (`image_picker`) wired in decode screen
  - Polish the OCR path: snap photo → decode (client-side OCR or server-side via Gemini vision)

### Sprint 3 — Bug fixes + funnel iteration

- [ ] **Polish based on real-user funnel data**
  - Iterate on the share loop
  - Fix any issues from TestFlight feedback
  - Optimize conversion points (decode → account, account → symptom log)

- [ ] **Final compliance pass**
  - Confirm BAA is active before any real PHI flows
  - Confirm privacy policy + terms are linked in-app
  - Confirm "Not Medical Advice" is displayed prominently in decode screens

---

## APPENDIX: Current feature inventory

### 🔵 VIRAL MVP (keep + sharpen)
| Feature | Files | Status |
|---|---|---|
| Document Decode | `features/documents/document_decode_screen.dart` | Exists, needs auth-wall teardown |
| Quick symptom log | `features/symptoms/quick_log_screen.dart` | Exists, needs polish |
| One-pager PDF report | `features/report/one_pager_screen.dart` | Exists |
| Atlas chat | `features/atlas/chat_screen.dart` | Keep, secondary |
| Vitals (light) | `features/vitals/health_metrics_screen.dart` | Keep simple |
| Medications list | `features/medications/medications_screen.dart` | Keep simple |

### 🔴 PHASE 2 (hide from nav, keep in repo)
| Feature | Files |
|---|---|
| Caregiver suite | `features/caregiver/*` |
| Alerts + escalation | `features/alerts/*` |
| Secure messaging | `features/messages/*` |
| Clinical trials | `features/trials/*` |
| Treatment calendar | `features/treatment/*` |
| Chemo regimen | `features/treatment/*` |
| Adherence dashboard | `features/medications/adherence_dashboard_screen.dart` |
| Clinician portal | `/clinician` (separate Next.js app) |

### 🆕 NEW to build
| Feature | Priority |
|---|---|
| No-login Decode landing | Sprint 0 |
| Share Card generator | Sprint 1 |
| PostHog funnel events | Sprint 1 |
| Landing page (Next.js) | Sprint 1 |
| BAA provider swap | Sprint 2 |
| Re-engagement notifications | Sprint 2 |
| OCR decode polish | Sprint 2 |
