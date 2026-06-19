// PRO-CTCAE composite grading.
//
// The PRO-CTCAE instrument scores each symptom item on 0-4 scales for one or
// more attributes (frequency, severity, interference, amount) or as a simple
// presence (yes/no). The clinical convention is:
//
//   - The composite_grade is the WORST attribute value across the item, capped
//     at 3 (PRO-CTCAE's published 0-3 grade is a derived simplification for
//     alert thresholds and the UI severity ramp — the underlying 0-4 attribute
//     values stay in the row for research-grade fidelity).
//   - For presence-only items, true → grade 1, false → grade 0.
//   - If multiple attributes are present and all are 0, grade is 0 (None).
//   - Special case: any attribute value of 4 escalates to grade 3 (Severe) —
//     the published "4" anchors as the worst end of the underlying scale but
//     is folded into Severe for clinical signaling.
//
// This is the function SYM-04 (composite grading) and the input to ALRT-01
// (alert rule engine) and RPT-01 (report assembly).

export type AttributeValue = number; // 0-4, or 0/1 for presence

export interface SymptomResponseInput {
  frequency?: AttributeValue | null;
  severity?: AttributeValue | null;
  interference?: AttributeValue | null;
  presence?: boolean | null;
  amount?: AttributeValue | null;
}

export type Grade = 0 | 1 | 2 | 3;
export const GRADE_LABEL: Record<Grade, "None" | "Mild" | "Moderate" | "Severe"> = {
  0: "None",
  1: "Mild",
  2: "Moderate",
  3: "Severe",
};

/**
 * Compute the 0-3 composite grade for a single symptom response.
 *
 * @throws if any provided attribute is outside its valid range.
 */
export function compositeGrade(input: SymptomResponseInput): Grade {
  // Validate ranges early — fail loud rather than silently clamp.
  for (const [k, v] of Object.entries(input)) {
    if (v == null) continue;
    if (k === "presence") continue;
    if (typeof v !== "number" || !Number.isFinite(v)) {
      throw new Error(`proCtcae: ${k} must be a finite number, got ${v}`);
    }
    if (v < 0 || v > 4 || !Number.isInteger(v)) {
      throw new Error(`proCtcae: ${k} must be an integer in [0,4], got ${v}`);
    }
  }

  // Presence-only path: true → 1, false/null → 0.
  if (input.presence != null) {
    return input.presence ? 1 : 0;
  }

  // Find the worst non-null attribute value.
  const values: number[] = [];
  if (input.frequency != null) values.push(input.frequency);
  if (input.severity != null) values.push(input.severity);
  if (input.interference != null) values.push(input.interference);
  if (input.amount != null) values.push(input.amount);

  if (values.length === 0) {
    // No attributes provided and no presence flag — treat as "not asked".
    return 0;
  }

  const worst = Math.max(...values);

  // Fold 4 → 3 (Severe) per the published PRO-CTCAE grade simplification.
  if (worst >= 4) return 3;
  return worst as Grade;
}

/** Convenience: returns { grade, label } together. */
export function gradeWithLabel(input: SymptomResponseInput): { grade: Grade; label: string } {
  const grade = compositeGrade(input);
  return { grade, label: GRADE_LABEL[grade] };
}
