// PRO-CTCAE term library — the most clinically common chemo-toxicity symptoms.
// This is a starter set (~20 of the 78 PRO-CTCAE terms), focused on what
// chemotherapy patients on the 7 EOM cancer types actually report. The full
// ~78-term library seeds separately once the data model is live.
//
// Each entry maps directly to a row in the symptom_term table. The
// "attributes" array is the subset of {frequency, severity, interference,
// presence, amount} that this term scores on per the published PRO-CTCAE
// instrument.

export type Attribute = "frequency" | "severity" | "interference" | "presence" | "amount";
export type BodySystem =
  | "GI"
  | "neuro"
  | "derm"
  | "constitutional"
  | "psych"
  | "pain"
  | "cardiac"
  | "pulmonary"
  | "uro"
  | "sexual"
  | "visual"
  | "hearing"
  | "other";

export interface ProCtcaeTerm {
  pro_ctcae_code: string;
  display_name: string;
  body_system: BodySystem;
  attributes: Attribute[];
  /** Plain-language phrasing shown to patients. */
  plain_language: string;
}

export const STARTER_TERMS: ProCtcaeTerm[] = [
  // GI — the chemo-toxicity core
  {
    pro_ctcae_code: "G1",
    display_name: "Nausea",
    body_system: "GI",
    attributes: ["frequency", "severity"],
    plain_language: "Feeling like you might throw up",
  },
  {
    pro_ctcae_code: "G2",
    display_name: "Vomiting",
    body_system: "GI",
    attributes: ["frequency", "severity"],
    plain_language: "Throwing up",
  },
  {
    pro_ctcae_code: "G3",
    display_name: "Diarrhea",
    body_system: "GI",
    attributes: ["frequency"],
    plain_language: "Loose or watery stools",
  },
  {
    pro_ctcae_code: "G4",
    display_name: "Constipation",
    body_system: "GI",
    attributes: ["severity"],
    plain_language: "Hard time pooping",
  },
  {
    pro_ctcae_code: "G5",
    display_name: "Decreased appetite",
    body_system: "GI",
    attributes: ["severity"],
    plain_language: "Not feeling hungry",
  },
  {
    pro_ctcae_code: "G6",
    display_name: "Mouth/throat sores",
    body_system: "GI",
    attributes: ["severity"],
    plain_language: "Painful spots in mouth or throat",
  },
  {
    pro_ctcae_code: "G7",
    display_name: "Taste changes",
    body_system: "GI",
    attributes: ["severity"],
    plain_language: "Food tastes different or has no taste",
  },
  // Constitutional
  {
    pro_ctcae_code: "C1",
    display_name: "Fatigue",
    body_system: "constitutional",
    attributes: ["severity", "interference"],
    plain_language: "Feeling very tired",
  },
  {
    pro_ctcae_code: "C2",
    display_name: "Fever",
    body_system: "constitutional",
    attributes: ["presence"],
    plain_language: "Temperature of 100.4°F (38°C) or higher",
  },
  {
    pro_ctcae_code: "C3",
    display_name: "Chills",
    body_system: "constitutional",
    attributes: ["severity"],
    plain_language: "Shivering or feeling cold",
  },
  {
    pro_ctcae_code: "C4",
    display_name: "Night sweats",
    body_system: "constitutional",
    attributes: ["frequency", "severity"],
    plain_language: "Heavy sweating at night",
  },
  {
    pro_ctcae_code: "C5",
    display_name: "Weight loss",
    body_system: "constitutional",
    attributes: ["amount"],
    plain_language: "Losing weight without trying",
  },
  // Pain
  {
    pro_ctcae_code: "P1",
    display_name: "General pain",
    body_system: "pain",
    attributes: ["frequency", "severity", "interference"],
    plain_language: "Aches or pain anywhere in the body",
  },
  {
    pro_ctcae_code: "P2",
    display_name: "Headache",
    body_system: "pain",
    attributes: ["frequency", "severity", "interference"],
    plain_language: "Pain in the head",
  },
  {
    pro_ctcae_code: "P3",
    display_name: "Abdominal pain",
    body_system: "pain",
    attributes: ["frequency", "severity", "interference"],
    plain_language: "Pain in the belly",
  },
  // Neuro
  {
    pro_ctcae_code: "N1",
    display_name: "Numbness/tingling in hands/feet",
    body_system: "neuro",
    attributes: ["severity", "interference"],
    plain_language: "Pins-and-needles or numbness in hands or feet",
  },
  // Derm
  {
    pro_ctcae_code: "D1",
    display_name: "Rash",
    body_system: "derm",
    attributes: ["presence"],
    plain_language: "New rash or skin change",
  },
  {
    pro_ctcae_code: "D2",
    display_name: "Skin dryness",
    body_system: "derm",
    attributes: ["severity"],
    plain_language: "Very dry or peeling skin",
  },
  {
    pro_ctcae_code: "D3",
    display_name: "Hair loss",
    body_system: "derm",
    attributes: ["amount"],
    plain_language: "Losing more hair than usual",
  },
  // Psych
  {
    pro_ctcae_code: "PS1",
    display_name: "Anxiety",
    body_system: "psych",
    attributes: ["frequency", "severity", "interference"],
    plain_language: "Feeling worried, on edge, or panicky",
  },
  {
    pro_ctcae_code: "PS2",
    display_name: "Sadness",
    body_system: "psych",
    attributes: ["frequency", "severity", "interference"],
    plain_language: "Feeling down or hopeless",
  },
  {
    pro_ctcae_code: "PS3",
    display_name: "Trouble sleeping",
    body_system: "psych",
    attributes: ["severity", "interference"],
    plain_language: "Hard time falling or staying asleep",
  },
];

/** The default chemo-core panel: every starter term. */
export const CHEMO_CORE_PANEL = {
  name: "Chemo core panel",
  term_codes: STARTER_TERMS.map((t) => t.pro_ctcae_code),
};
