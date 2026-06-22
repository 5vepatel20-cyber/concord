// SYM-06: Rolling 7-day baseline + worsening detection.
//
// For a given patient, computes:
//   - Baseline: average composite grade per symptom term over the prior 7 days
//   - Current: average composite grade per symptom term over the latest 7 days
//   - Worsening: any symptom whose current average grade is ≥1 point higher
//     than its baseline average
//
// This is called from the submit endpoint after logging to flag worsening
// in real-time, and from the report generator for the structured payload.

import { serviceClient } from "../supabase.js";
import type { Grade } from "./scorer.js";

export interface TermBaseline {
  term_code: string;
  term_name: string;
  baseline_avg_grade: number;
  current_avg_grade: number;
  delta: number;
  direction: "stable" | "worsened" | "new" | "improved";
  sample_count: number;
}

const DAYS_MS = 7 * 24 * 60 * 60 * 1000;

export async function detectWorsening(
  patientId: string,
): Promise<TermBaseline[]> {
  const supabase = serviceClient();

  const now = Date.now();
  const currentWindowStart = new Date(now - DAYS_MS).toISOString();
  const priorWindowStart = new Date(now - 2 * DAYS_MS).toISOString();

  const { data: priorSymptoms } = await supabase
    .from("symptom_response")
    .select(`
      composite_grade,
      term:symptom_term(pro_ctcae_code, display_name),
      report:symptom_report!inner(reported_at, patient_id)
    `)
    .eq("report.patient_id", patientId)
    .gte("report.reported_at", priorWindowStart)
    .lt("report.reported_at", currentWindowStart);

  const { data: currentSymptoms } = await supabase
    .from("symptom_response")
    .select(`
      composite_grade,
      term:symptom_term(pro_ctcae_code, display_name),
      report:symptom_report!inner(reported_at, patient_id)
    `)
    .eq("report.patient_id", patientId)
    .gte("report.reported_at", currentWindowStart);

  // Aggregate prior window
  const priorMap = new Map<string, { sum: number; count: number; name: string }>();
  for (const sr of priorSymptoms ?? []) {
    const term = Array.isArray((sr as any).term) ? (sr as any).term[0] : (sr as any).term;
    if (!term) continue;
    const acc = priorMap.get(term.pro_ctcae_code) ?? { sum: 0, count: 0, name: term.display_name };
    acc.sum += (sr as any).composite_grade ?? 0;
    acc.count++;
    priorMap.set(term.pro_ctcae_code, acc);
  }

  // Aggregate current window
  const currentMap = new Map<string, { sum: number; count: number; name: string }>();
  for (const sr of currentSymptoms ?? []) {
    const term = Array.isArray((sr as any).term) ? (sr as any).term[0] : (sr as any).term;
    if (!term) continue;
    const acc = currentMap.get(term.pro_ctcae_code) ?? { sum: 0, count: 0, name: term.display_name };
    acc.sum += (sr as any).composite_grade ?? 0;
    acc.count++;
    currentMap.set(term.pro_ctcae_code, acc);
  }

  // Collect all unique term codes
  const allCodes = new Set([...priorMap.keys(), ...currentMap.keys()]);
  const results: TermBaseline[] = [];

  for (const code of allCodes) {
    const prior = priorMap.get(code);
    const current = currentMap.get(code);

    const currentAvg = current ? current.sum / current.count : 0;
    const priorAvg = prior ? prior.sum / prior.count : 0;
    const delta = currentAvg - priorAvg;

    let direction: TermBaseline["direction"];
    if (!prior) {
      direction = "new";
    } else if (delta >= 1) {
      direction = "worsened";
    } else if (delta <= -1) {
      direction = "improved";
    } else {
      direction = "stable";
    }

    results.push({
      term_code: code,
      term_name: current?.name ?? prior?.name ?? code,
      baseline_avg_grade: Math.round(priorAvg * 10) / 10,
      current_avg_grade: Math.round(currentAvg * 10) / 10,
      delta: Math.round(delta * 10) / 10,
      direction,
      sample_count: (prior?.count ?? 0) + (current?.count ?? 0),
    });
  }

  return results.sort((a, b) => b.delta - a.delta);
}
