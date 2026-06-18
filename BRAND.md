# Concord — Brand & Visual System

> **App:** Concord · **AI companion:** Atlas
> **Tagline:** *You and your doctor, on the same page.*
> **Personality:** precise · thorough · trustworthy · a capable instrument, not a calm/wellness app.
> Optimized first for **clinician credibility**.

This document is the full design reference. The essentials are duplicated in `SPEC.md` §4 for
one-stop reading. When the two disagree, this file wins.

---

## 1. Naming

| Surface | Name |
|---|---|
| App (patient + clinician) | **Concord** |
| AI companion | **Atlas** |
| Tagline | *You and your doctor, on the same page.* |
| Bundle id (TBD) | `com.concord.app` |
| Domains (planned) | `concordhealth.app` · `getconcord.app` |
| Trademark class | Nice class 9 (software) and 44 (medical) — search required before launch |

**Why "Concord":** the literal meaning — agreement, harmony — captures the product thesis (patient
and clinician on one shared source of truth). It's short, pronounceable, and works in all six
locales (en/es/fr/de/zh/hi) without translation.

**Why "Atlas":** the AI carries the full picture across time and surfaces (symptoms, meds, vitals,
docs), interprets it, and flags what needs attention. Atlas holds the world; it never judges it.

---

## 2. Direction

**"Clinical Trust"** — light-first, neutral, instrument-grade. References: Apple Health, One Medical,
Epic MyChart (cleaner version), the calm end of Linear/Stripe.

**What this is not:** pastel, wellness-y, breathwork-app, herbivore, hand-drawn, warm-fuzzy. No
meditation bells, no soft gradients, no "we're all friends here" tone. The patient has cancer; the
clinician has 8 minutes. Concord respects both.

---

## 3. Color tokens

### 3.1 Brand
| Token | Hex | Use |
|---|---|---|
| `concordBlue` | `#1668E0` | Primary actions, links, brand mark, focus ring |
| `concordBluePressed` | `#0F4FB0` | Pressed/active state for primary |
| `concordBlueTint` | `#EAF1FD` | Soft blue background, selected-row tint, chart fills |

### 3.2 Neutrals
| Token | Hex | Use |
|---|---|---|
| `ink` | `#0F1B2D` | Primary text, headlines |
| `body` | `#2B3A4F` | Body text |
| `slate` | `#5E6B7E` | Secondary text, captions |
| `hint` | `#9AA6B6` | Placeholder, disabled, tertiary |
| `mist` | `#F4F7FA` | App background, card alt-bg |
| `surface` | `#FFFFFF` | Card / sheet surface |
| `hairline` | `#E2E8F0` | 1px dividers, borders |

### 3.3 Semantic (PRO-CTCAE severity ramp — never color-only)
| Token | Hex | Grade | Label |
|---|---|---|---|
| `stable` | `#16A974` | 0 | None |
| `caution` | `#E8A33D` | 1 | Mild |
| `warn` | `#F2683C` | 2 | Moderate |
| `severe` | `#E5484D` | 3 | Severe |

**Rule:** every severity color must be paired with the grade label ("Severe", not just a red dot).
Color-blind users can read the label; the color is a redundant cue, not the carrier.

---

## 4. Typography

**Family:** **Inter** (open-license, ships with tabular numerals). Use Inter Variable when possible.

**Tabular numerals:** turn on for **all clinical data** (symptom grades, vitals, lab values,
adherence %, dates). Patients and clinicians read these in columns; proportional numbers wobble.

### 4.1 Scale
| Token | Size / line | Weight | Use |
|---|---|---|---|
| `display` | 32 / 40 | 600 | Onboarding hero, report PDF title |
| `h1` | 24 / 32 | 600 | Screen titles |
| `h2` | 20 / 28 | 600 | Section headers, card titles |
| `h3` | 17 / 24 | 600 | Sub-headers |
| `body` | 15 / 22 | 400 | Default body |
| `bodyStrong` | 15 / 22 | 600 | Emphasized body, list-item primary |
| `caption` | 13 / 18 | 400 | Secondary text, helper, timestamps |
| `micro` | 11 / 16 | 500 | All-caps labels, badges (`URGENT`, `EMERGENCY`) |
| `numeric` | varies | 500 (tabular) | All clinical numbers |

### 4.2 Weight rules
- 400 (regular) is the default.
- 600 (semibold) for emphasis — never bold (700) in body. Bold is reserved for the brand mark.
- All-caps reserved for `micro` (severity labels, status chips).

---

## 5. Spacing & layout

**4-pt grid.** All margins, paddings, gaps are multiples of 4.

| Token | Value | Use |
|---|---|---|
| `space1` | 4 | Tight gap (icon-to-label) |
| `space2` | 8 | Default inline gap |
| `space3` | 12 | Stack gap (chips) |
| `space4` | 16 | Card padding, screen edge (compact) |
| `space5` | 20 | Card padding (comfortable) |
| `space6` | 24 | Section gap |
| `space8` | 32 | Hero spacing |
| `space10` | 40 | Top of major screen |

**Radius:**
| Token | Value | Use |
|---|---|---|
| `radiusSm` | 6 | Chips, badges, small buttons |
| `radiusMd` | 10 | Inputs, list rows |
| `radiusLg` | 14 | Cards, sheets |
| `radiusXl` | 20 | Modals, hero surfaces |

**Elevation:** prefer 1px hairlines (`hairline`) over shadows. One soft shadow reserved for the
report PDF preview card.

---

## 6. Components (high-level)

- **Button** — three variants: `primary` (Concord Blue), `secondary` (hairline border), `tertiary`
  (text-only, blue). Pressed states darken to `concordBluePressed` / `slate`.
- **Chip / severity tag** — pill, `micro` type, severity color background at 12% opacity, severity
  color text, optional 1px border at full opacity.
- **Card** — `surface` on `mist`, `radiusLg`, 1px `hairline` border, no shadow.
- **List row** — 56pt min height, `body` primary, `slate` secondary, 16pt left/right padding,
  trailing chevron only when the row is tappable.
- **Severity scale** — horizontal 4-step widget (None → Severe) with labels, current grade filled,
  tap to set. Always paired with the label, never color-only.
- **Heatmap cell** — `radiusSm`, semantic color background, day-of-month label inside in
  `body` weight, hover/long-press shows grade number.

---

## 7. Iconography

- **Style:** line, 1.5pt stroke, rounded caps, monochrome (use `body` color, semantic color in
  context).
- **Library:** Lucide (open license, large clinical/health subset). Replace ad-hoc icons with
  Lucide IDs in code.
- **Severity / status:** use the severity ramp colors, never red alone.

---

## 8. App icon

- **Tile:** Concord Blue (`#1668E0`) rounded square, 22% corner radius (iOS-style).
- **Mark:** white open-"C" arc + small pulse tick to its right (the "data flowing through" cue).
- **Background:** flat, no gradient, no glow.
- **Variants:** 1024 (master), then standard iOS/Android sizes. No badge overlays for test/dev.

---

## 9. Motion

- **Default easing:** `cubic-bezier(0.2, 0.8, 0.2, 1)` (decelerate, "settle").
- **Durations:** micro (chip press) 80ms, UI (sheet open, screen transition) 240ms, hero
  (onboarding) 400ms. No bounces.
- **Severity pulse:** a single, slow (1.2s) outward pulse on the `severe` chip when an
  emergency self-report is logged. Single pulse only — no infinite animation.

---

## 10. Tone of voice (writing)

- **Direct, not warm.** "You've logged 3 days of severe nausea. Call your oncology nurse line
  before your next dose." — not "Oh no, that sounds rough 💙".
- **Plain numbers, no hedging.** Grade 2, not "moderate-to-severe-ish".
- **"Not a medical device"** is in the consent screen and visible from the Atlas panel. Not
  hidden, not euphemistic.
- **No second person in error states.** "Couldn't reach Concord" — not "Oops! Something went
  wrong on our end 😬".

---

## 11. What this doc does **not** cover yet (TBD)

- [ ] Illustration style for empty states, onboarding, Atlas
- [ ] PDF report skin (header, footer, type, color in print)
- [ ] Accessibility audit (contrast pairs, focus order, screen-reader copy for severity)
- [ ] Localization QA — 6 languages, but tone rules need a native-speaker pass
- [ ] Marketing site visual system (logo lockups, social-card template)

When any of these are decided, edit this file — do not edit the spec. The spec mirrors the
*essentials*; this is the source.
