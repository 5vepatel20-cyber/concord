import { describe, it, expect, vi, beforeEach } from "vitest";
import { detectWorsening } from "./worsening.js";
import type { TermBaseline } from "./worsening.js";

// ── Mock Supabase ──────────────────────────────────────────────────
// detectWorsening makes two sequential queries (prior window, current window).
// We control query results via module-level variables set before each test.

type SupabaseRow = {
  composite_grade: number;
  term: { pro_ctcae_code: string; display_name: string } | null;
  report: { reported_at: string; patient_id: string };
};

let mockPriorData: SupabaseRow[] = [];
let mockCurrentData: SupabaseRow[] = [];
let callCount = 0;

vi.mock("../supabase.js", () => ({
  serviceClient: () => {
    // Build a chainable mock that returns the right data on each call.
    const chain = {
      eq: () => chain,
      gte: () => chain,
      lt: () => chain,
      then: (
        resolve: (v: { data: SupabaseRow[]; error: null }) => void,
      ) => {
        const data = callCount === 0 ? mockPriorData : mockCurrentData;
        callCount++;
        resolve({ data, error: null });
      },
    };
    return { from: () => ({ select: () => chain }) };
  },
}));

describe("detectWorsening", () => {
  beforeEach(() => {
    mockPriorData = [];
    mockCurrentData = [];
    callCount = 0;
  });

  // ── Helpers ─────────────────────────────────────────────────────
  function row(
    code: string,
    name: string,
    grade: number,
    daysAgo: number,
  ): SupabaseRow {
    const d = new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000);
    return {
      composite_grade: grade,
      term: { pro_ctcae_code: code, display_name: name },
      report: { reported_at: d.toISOString(), patient_id: "p1" },
    };
  }

  // ── Tests ───────────────────────────────────────────────────────
  it("returns empty array when no data exists in either window", async () => {
    const result = await detectWorsening("p1");
    expect(result).toEqual([]);
  });

  it("marks symptoms in current window only as 'new'", async () => {
    mockCurrentData = [row("P1", "Pain", 2, 1)];
    const result = await detectWorsening("p1");
    expect(result).toHaveLength(1);
    expect(result[0]!.direction).toBe("new");
    expect(result[0]!.term_code).toBe("P1");
    expect(result[0]!.current_avg_grade).toBe(2);
    expect(result[0]!.baseline_avg_grade).toBe(0);
    expect(result[0]!.delta).toBe(2);
  });

  it("marks worsened when delta >= 1", async () => {
    mockPriorData = [row("P1", "Pain", 1, 10)];
    mockCurrentData = [row("P1", "Pain", 3, 1)];
    const result = await detectWorsening("p1");
    expect(result).toHaveLength(1);
    expect(result[0]!.direction).toBe("worsened");
    expect(result[0]!.delta).toBe(2);
  });

  it("marks improved when delta <= -1", async () => {
    mockPriorData = [row("P1", "Pain", 3, 10)];
    mockCurrentData = [row("P1", "Pain", 1, 1)];
    const result = await detectWorsening("p1");
    expect(result).toHaveLength(1);
    expect(result[0]!.direction).toBe("improved");
    expect(result[0]!.delta).toBe(-2);
  });

  it("marks stable when delta is between -1 and 1", async () => {
    mockPriorData = [row("P1", "Pain", 2, 10)];
    mockCurrentData = [row("P1", "Pain", 2, 1)];
    const result = await detectWorsening("p1");
    expect(result).toHaveLength(1);
    expect(result[0]!.direction).toBe("stable");
    expect(result[0]!.delta).toBe(0);
  });

  it("handles multiple terms sorting by delta descending", async () => {
    mockPriorData = [
      row("P1", "Pain", 1, 10),
      row("F1", "Fatigue", 2, 10),
    ];
    mockCurrentData = [
      row("P1", "Pain", 3, 1),
      row("F1", "Fatigue", 1, 1),
    ];
    const result = await detectWorsening("p1");
    expect(result).toHaveLength(2);
    // Sorted by delta descending: Pain delta=2, Fatigue delta=-1
    expect(result[0]!.term_code).toBe("P1");
    expect(result[0]!.direction).toBe("worsened");
    expect(result[1]!.term_code).toBe("F1");
    expect(result[1]!.direction).toBe("improved");
  });

  it("handles missing term reference gracefully", async () => {
    const d = new Date(Date.now() - 1 * 24 * 60 * 60 * 1000);
    mockCurrentData = [
      {
        composite_grade: 2,
        term: null,
        report: { reported_at: d.toISOString(), patient_id: "p1" },
      },
    ];
    const result = await detectWorsening("p1");
    expect(result).toEqual([]);
  });

  it("averages multiple responses per term", async () => {
    mockPriorData = [
      row("P1", "Pain", 2, 10),
      row("P1", "Pain", 3, 9),
    ];
    mockCurrentData = [
      row("P1", "Pain", 1, 1),
      row("P1", "Pain", 1, 2),
    ];
    const result = await detectWorsening("p1");
    expect(result).toHaveLength(1);
    // prior avg = (2+3)/2 = 2.5, current avg = (1+1)/2 = 1
    expect(result[0]!.baseline_avg_grade).toBe(2.5);
    expect(result[0]!.current_avg_grade).toBe(1);
    expect(result[0]!.delta).toBe(-1.5);
    expect(result[0]!.direction).toBe("improved");
  });

  it("computes sample_count as sum of both windows", async () => {
    mockPriorData = [row("P1", "Pain", 2, 10), row("P1", "Pain", 3, 9)];
    mockCurrentData = [row("P1", "Pain", 2, 1)];
    const result = await detectWorsening("p1");
    expect(result[0]!.sample_count).toBe(3);
  });
});
