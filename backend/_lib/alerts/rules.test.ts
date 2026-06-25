import { describe, it, expect, vi, beforeEach } from "vitest";
import { evaluateRules } from "./rules.js";

// ── Mock Supabase ──────────────────────────────────────────────
// evaluateRules queries alert_rule table. We control return data
// via module-level variable.

type MockRule = {
  id: string;
  term_id: string | null;
  condition: {
    min_grade?: number;
    concurrent?: number;
    term_ids?: string[];
  };
  severity_level: string;
  escalation: Record<string, unknown>;
};

let mockRules: MockRule[] = [];

vi.mock("../supabase.js", () => ({
  serviceClient: () => ({
    from: () => ({
      select: () => ({
        then: (resolve: (v: { data: MockRule[]; error: null }) => void) => {
          resolve({ data: mockRules, error: null });
        },
      }),
    }),
  }),
}));

describe("evaluateRules", () => {
  beforeEach(() => {
    mockRules = [];
  });

  const resp = (termId: string, grade: number) => ({
    term_id: termId,
    pro_ctcae_code: "T1",
    composite_grade: grade as 0 | 1 | 2 | 3,
  });

  it("returns empty when no rules exist", async () => {
    const result = await evaluateRules("p1", "r1", [resp("t1", 3)]);
    expect(result).toEqual([]);
  });

  it("fires rule when term_id matches and grade >= min_grade", async () => {
    mockRules = [
      {
        id: "r1",
        term_id: "t1",
        condition: { min_grade: 2 },
        severity_level: "urgent",
        escalation: {},
      },
    ];
    const result = await evaluateRules("p1", "r1", [resp("t1", 3)]);
    expect(result).toHaveLength(1);
    expect(result[0]!.rule_id).toBe("r1");
    expect(result[0]!.severity_level).toBe("urgent");
    expect(result[0]!.patient_id).toBe("p1");
  });

  it("does not fire when composite_grade < min_grade", async () => {
    mockRules = [
      {
        id: "r1",
        term_id: "t1",
        condition: { min_grade: 2 },
        severity_level: "urgent",
        escalation: {},
      },
    ];
    const result = await evaluateRules("p1", "r1", [resp("t1", 1)]);
    expect(result).toEqual([]);
  });

  it("uses default min_grade=2 when not specified", async () => {
    mockRules = [
      {
        id: "r1",
        term_id: "t1",
        condition: {},
        severity_level: "info",
        escalation: {},
      },
    ];
    expect(await evaluateRules("p1", "r1", [resp("t1", 1)])).toEqual([]);
    expect(await evaluateRules("p1", "r1", [resp("t1", 2)])).toHaveLength(1);
  });

  it("fires rule with term_ids list match", async () => {
    mockRules = [
      {
        id: "r1",
        term_id: null,
        condition: { term_ids: ["t1", "t2"], min_grade: 1 },
        severity_level: "info",
        escalation: {},
      },
    ];
    const result = await evaluateRules("p1", "r1", [resp("t3", 3)]);
    expect(result).toEqual([]);

    const result2 = await evaluateRules("p1", "r1", [resp("t2", 1)]);
    expect(result2).toHaveLength(1);
  });

  it("fires catch-all rule (no term_id, no term_ids) for any matching grade", async () => {
    mockRules = [
      {
        id: "r1",
        term_id: null,
        condition: { min_grade: 3 },
        severity_level: "emergency",
        escalation: {},
      },
    ];
    const result = await evaluateRules("p1", "r1", [resp("t1", 3), resp("t2", 1)]);
    expect(result).toHaveLength(1);
  });

  it("respects concurrent threshold", async () => {
    mockRules = [
      {
        id: "r1",
        term_id: null,
        condition: { min_grade: 2, concurrent: 2 },
        severity_level: "urgent",
        escalation: {},
      },
    ];
    // Only 1 response meets min_grade.
    const result = await evaluateRules("p1", "r1", [
      resp("t1", 3),
      resp("t2", 1),
    ]);
    expect(result).toEqual([]);

    // 2 responses meet min_grade.
    const result2 = await evaluateRules("p1", "r1", [
      resp("t1", 3),
      resp("t2", 2),
    ]);
    expect(result2).toHaveLength(1);
  });

  it("deduplicates by severity_level + rule_id", async () => {
    mockRules = [
      {
        id: "r1",
        term_id: "t1",
        condition: { min_grade: 1 },
        severity_level: "urgent",
        escalation: {},
      },
      {
        id: "r1",
        term_id: "t2",
        condition: { min_grade: 1 },
        severity_level: "urgent",
        escalation: {},
      },
    ];
    const result = await evaluateRules("p1", "r1", [
      resp("t1", 2),
      resp("t2", 3),
    ]);
    expect(result).toHaveLength(1);
  });
});
