import { describe, it, expect } from "vitest";
import { compositeGrade, gradeWithLabel } from "./scorer.js";

describe("compositeGrade", () => {
  // ── Presence-only items ────────────────────────────────────────────
  it("returns 1 for presence: true", () => {
    expect(compositeGrade({ presence: true })).toBe(1);
  });

  it("returns 0 for presence: false", () => {
    expect(compositeGrade({ presence: false })).toBe(0);
  });

  // ── Single attribute ───────────────────────────────────────────────
  it("returns the attribute value for a single attribute", () => {
    expect(compositeGrade({ severity: 0 })).toBe(0);
    expect(compositeGrade({ severity: 1 })).toBe(1);
    expect(compositeGrade({ severity: 2 })).toBe(2);
    expect(compositeGrade({ severity: 3 })).toBe(3);
    expect(compositeGrade({ frequency: 1 })).toBe(1);
    expect(compositeGrade({ interference: 2 })).toBe(2);
    expect(compositeGrade({ amount: 3 })).toBe(3);
  });

  // ── Multi-attribute: worst wins ────────────────────────────────────
  it("uses the worst attribute value when multiple are present", () => {
    expect(compositeGrade({ severity: 1, frequency: 2 })).toBe(2);
    expect(compositeGrade({ severity: 3, interference: 1, amount: 0 })).toBe(3);
    expect(compositeGrade({ severity: 2, frequency: 1, interference: 0 })).toBe(2);
  });

  // ── 4 → 3 folding ─────────────────────────────────────────────────
  it("folds attribute value 4 to composite grade 3", () => {
    expect(compositeGrade({ severity: 4 })).toBe(3);
    expect(compositeGrade({ frequency: 4 })).toBe(3);
    expect(compositeGrade({ interference: 4 })).toBe(3);
    expect(compositeGrade({ amount: 4 })).toBe(3);
  });

  it("folds any attribute of 4 to 3 when others are lower", () => {
    expect(compositeGrade({ severity: 4, frequency: 0 })).toBe(3);
    expect(compositeGrade({ frequency: 4, interference: 2 })).toBe(3);
  });

  it("folds any attribute of 4 to 3 when others are also 4", () => {
    expect(compositeGrade({ severity: 4, frequency: 4 })).toBe(3);
  });

  // ── All zeroes ─────────────────────────────────────────────────────
  it("returns 0 when all attributes are 0", () => {
    expect(compositeGrade({ severity: 0, frequency: 0, interference: 0 })).toBe(0);
  });

  // ── Empty / absent attributes ──────────────────────────────────────
  it("returns 0 when no attributes or presence are provided", () => {
    expect(compositeGrade({})).toBe(0);
  });

  it("ignores null attributes and finds the worst among non-null", () => {
    expect(compositeGrade({ severity: null, frequency: 2, interference: null })).toBe(2);
  });

  it("returns 0 when all attributes are null", () => {
    expect(compositeGrade({ severity: null, frequency: null })).toBe(0);
  });

  // ── Validation: throws on invalid input ────────────────────────────
  it("throws for a non-integer attribute value", () => {
    expect(() => compositeGrade({ severity: 1.5 })).toThrow("proCtcae");
    expect(() => compositeGrade({ severity: 0.5 })).toThrow("proCtcae");
  });

  it("throws for an out-of-range attribute value", () => {
    expect(() => compositeGrade({ severity: -1 })).toThrow("proCtcae");
    expect(() => compositeGrade({ severity: 5 })).toThrow("proCtcae");
  });

  it("throws for a non-finite attribute value", () => {
    expect(() => compositeGrade({ severity: NaN })).toThrow("proCtcae");
    expect(() => compositeGrade({ severity: Infinity })).toThrow("proCtcae");
    expect(() => compositeGrade({ severity: -Infinity })).toThrow("proCtcae");
  });

  it("throws for a string attribute value", () => {
    expect(() => compositeGrade({ severity: "bad" as any })).toThrow("proCtcae");
  });

  it("does not throw for null or undefined attributes", () => {
    expect(() => compositeGrade({ severity: undefined })).not.toThrow();
    expect(() => compositeGrade({ severity: null })).not.toThrow();
  });
});

describe("gradeWithLabel", () => {
  it("returns correct label for each grade", () => {
    expect(gradeWithLabel({ severity: 0 })).toEqual({ grade: 0, label: "None" });
    expect(gradeWithLabel({ severity: 1 })).toEqual({ grade: 1, label: "Mild" });
    expect(gradeWithLabel({ severity: 2 })).toEqual({ grade: 2, label: "Moderate" });
    expect(gradeWithLabel({ severity: 3 })).toEqual({ grade: 3, label: "Severe" });
    expect(gradeWithLabel({ severity: 4 })).toEqual({ grade: 3, label: "Severe" });
  });

  it("delegates to compositeGrade for edge cases", () => {
    expect(gradeWithLabel({ presence: true })).toEqual({ grade: 1, label: "Mild" });
    expect(gradeWithLabel({})).toEqual({ grade: 0, label: "None" });
  });
});
