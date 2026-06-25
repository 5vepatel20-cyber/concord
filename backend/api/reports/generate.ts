// POST /api/reports/generate — auth-required. Assembles a doctor-ready
// structured report (RPT-01/02/07) for the caller's last N days.
//
// The response includes:
//   - symptom_heatmap: daily grade per term across the window
//   - worst_episodes: up to 3 highest-grade symptoms
//   - new_or_worsening: symptoms that are new or >=1 grade worse vs prior
//   - medication_adherence: adherence % per med (broken down by status)
//   - vitals: daily aggregates (steps, hr, sleep, weight, bp)
//   - narrative (optional): Atlas-generated plain-language summary (RPT-04)
//
// The report is persisted to the `report` table for history + sharing.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";
import { getAIProvider } from "../../_lib/ai/provider.js";

export const config = { runtime: "nodejs" };

export const OPTIONS = (req: Request): Response => preflight(req);

const QuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(90).default(14),
  include_narrative: z.coerce.boolean().default(false),
});

interface SymptomEntry {
  date: string;
  term_code: string;
  term_name: string;
  body_system: string;
  grade: number;
}

interface WorstEpisode {
  term_code: string;
  term_name: string;
  grade: number;
  count: number;
}

interface NewOrWorsening {
  term_code: string;
  term_name: string;
  prior_avg_grade: number;
  current_avg_grade: number;
  direction: "new" | "worsened";
}

interface AdherenceStats {
  medication_id: string;
  display_name: string;
  total: number;
  taken: number;
  skipped: number;
  missed: number;
  taken_late: number;
  adherence_pct: number;
}

interface VitalsSummary {
  date: string;
  steps: number | null;
  avg_hr_bpm: number | null;
  sleep_hours: number | null;
  weight_kg: number | null;
  bp_sys_avg: number | null;
  bp_dia_avg: number | null;
}

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const url = new URL(req.url);
  const query = QuerySchema.parse(Object.fromEntries(url.searchParams));
  const windowStart = new Date(Date.now() - query.days * 24 * 60 * 60 * 1000).toISOString();
  const priorWindowStart = new Date(Date.now() - query.days * 2 * 24 * 60 * 60 * 1000).toISOString();

  const supabase = serviceClient();

  // ── 1. Symptom heatmap (current window) ──────────────────────────
  const { data: symptoms, error: symErr } = await supabase
    .from("symptom_response")
    .select(`
      composite_grade,
      created_at,
      term:symptom_term(pro_ctcae_code, display_name, body_system),
      report:symptom_report!inner(reported_at, patient_id)
    `)
    .eq("report.patient_id", user.id)
    .gte("report.reported_at", windowStart)
    .order("report(reported_at)", { ascending: true });

  if (symErr) {
    Sentry.captureException(symErr);
    return corsedJsonError(req, 500, "symptom_query_failed", symErr.message);
  }

  // ── 2. Prior window symptoms (for new/worsening detection) ──────
  const { data: priorSymptoms } = await supabase
    .from("symptom_response")
    .select(`
      composite_grade,
      created_at,
      term:symptom_term(pro_ctcae_code),
      report:symptom_report!inner(reported_at, patient_id)
    `)
    .eq("report.patient_id", user.id)
    .gte("report.reported_at", priorWindowStart)
    .lt("report.reported_at", windowStart)
    .order("report(reported_at)", { ascending: true });

  // ── 3. Medication adherence (current window) ────────────────────
  const { data: meds } = await supabase
    .from("medication")
    .select("id, display_name, patient_id")
    .eq("patient_id", user.id)
    .eq("active", true);

  const medIds = (meds ?? []).map((m) => m.id);
  const adherenceStats: AdherenceStats[] = [];
  if (medIds.length > 0) {
    const { data: events } = await supabase
      .from("medication_event")
      .select("medication_id, status")
      .in("medication_id", medIds)
      .gte("scheduled_for", windowStart);

    const eventsByMed = new Map<string, { total: number; taken: number; skipped: number; missed: number; taken_late: number }>();
    for (const e of events ?? []) {
      const acc = eventsByMed.get(e.medication_id) ?? { total: 0, taken: 0, skipped: 0, missed: 0, taken_late: 0 };
      acc.total++;
      if (e.status === "taken") acc.taken++;
      else if (e.status === "skipped") acc.skipped++;
      else if (e.status === "missed") acc.missed++;
      else if (e.status === "taken_late") acc.taken_late++;
      eventsByMed.set(e.medication_id, acc);
    }

    for (const med of meds ?? []) {
      const acc = eventsByMed.get(med.id);
      if (!acc || acc.total === 0) {
        adherenceStats.push({ medication_id: med.id, display_name: med.display_name, total: 0, taken: 0, skipped: 0, missed: 0, taken_late: 0, adherence_pct: 0 });
        continue;
      }
      adherenceStats.push({
        medication_id: med.id,
        display_name: med.display_name,
        ...acc,
        adherence_pct: Math.round((acc.taken / acc.total) * 100),
      });
    }
  }

  // ── 4. Vitals (current window) ──────────────────────────────────
  const { data: vitalsRaw } = await supabase
    .from("health_metric_sample")
    .select("type, value, unit, measured_at")
    .eq("patient_id", user.id)
    .gte("measured_at", windowStart)
    .order("measured_at", { ascending: true });

  const vitalsByDate = new Map<string, VitalsSummary>();
  for (const v of vitalsRaw ?? []) {
    const dateKey = v.measured_at.slice(0, 10);
    let entry = vitalsByDate.get(dateKey);
    if (!entry) {
      entry = { date: dateKey, steps: null, avg_hr_bpm: null, sleep_hours: null, weight_kg: null, bp_sys_avg: null, bp_dia_avg: null };
      vitalsByDate.set(dateKey, entry);
    }
    if (v.type === "steps") entry.steps = Math.round(v.value ?? 0);
    if (v.type === "hr") entry.avg_hr_bpm = Math.round(v.value ?? 0);
    if (v.type === "sleep") entry.sleep_hours = Math.round(((v.value ?? 0) / 3600) * 10) / 10;
    if (v.type === "weight") entry.weight_kg = Math.round((v.value ?? 0) * 10) / 10;
    if (v.type === "bp_sys") entry.bp_sys_avg = Math.round(v.value ?? 0);
    if (v.type === "bp_dia") entry.bp_dia_avg = Math.round(v.value ?? 0);
  }

  // ── 5. Assemble heatmap ─────────────────────────────────────────
  const heatmap: SymptomEntry[] = [];
  const termGradeCounts = new Map<string, { sum: number; count: number }>();
  for (const sr of symptoms ?? []) {
    const term = Array.isArray(sr.term) ? sr.term[0] : sr.term;
    const report = Array.isArray(sr.report) ? sr.report[0] : sr.report;
    if (!term || !report) continue;
    const date = report.reported_at.slice(0, 10);
    const code = term.pro_ctcae_code;
    heatmap.push({ date, term_code: code, term_name: term.display_name, body_system: term.body_system, grade: sr.composite_grade ?? 0 });
    const acc = termGradeCounts.get(code) ?? { sum: 0, count: 0 };
    acc.sum += sr.composite_grade ?? 0;
    acc.count++;
    termGradeCounts.set(code, acc);
  }

  // ── 6. Worst episodes ───────────────────────────────────────────
  const worstEpisodes: WorstEpisode[] = [...termGradeCounts.entries()]
    .map(([code, acc]) => ({
      term_code: code,
      term_name: heatmap.find((h) => h.term_code === code)?.term_name ?? code,
      grade: Math.round((acc.sum / acc.count) * 10) / 10,
      count: acc.count,
    }))
    .sort((a, b) => b.grade - a.grade)
    .slice(0, 3);

  // ── 7. New/worsening detection ──────────────────────────────────
  const priorAvg = new Map<string, { sum: number; count: number }>();
  for (const sr of priorSymptoms ?? []) {
    const term = Array.isArray(sr.term) ? sr.term[0] : sr.term;
    if (!term) continue;
    const acc = priorAvg.get(term.pro_ctcae_code) ?? { sum: 0, count: 0 };
    acc.sum += sr.composite_grade ?? 0;
    acc.count++;
    priorAvg.set(term.pro_ctcae_code, acc);
  }

  const newOrWorsening: NewOrWorsening[] = [];
  for (const [code, current] of termGradeCounts) {
    const currentAvg = current.sum / current.count;
    const prior = priorAvg.get(code);
    if (!prior) {
      newOrWorsening.push({ term_code: code, term_name: heatmap.find((h) => h.term_code === code)?.term_name ?? code, prior_avg_grade: 0, current_avg_grade: Math.round(currentAvg * 10) / 10, direction: "new" });
    } else {
      const priorAvgVal = prior.sum / prior.count;
      if (currentAvg >= priorAvgVal + 1) {
        newOrWorsening.push({ term_code: code, term_name: heatmap.find((h) => h.term_code === code)?.term_name ?? code, prior_avg_grade: Math.round(priorAvgVal * 10) / 10, current_avg_grade: Math.round(currentAvg * 10) / 10, direction: "worsened" });
      }
    }
  }

  const overallAdherencePct = adherenceStats.length > 0 ? Math.round(adherenceStats.reduce((s, a) => s + a.adherence_pct, 0) / adherenceStats.length) : null;

  const payload: Record<string, unknown> = {
    generated_at: new Date().toISOString(),
    period_days: query.days,
    patient_id: user.id,
    symptom_heatmap: heatmap,
    worst_episodes: worstEpisodes,
    new_or_worsening: newOrWorsening,
    medication_adherence: { by_medication: adherenceStats, overall_pct: overallAdherencePct },
    vitals: [...vitalsByDate.values()].sort((a, b) => a.date.localeCompare(b.date)),
  };

  // ── 8. Atlas narrative (RPT-04) ────────────────────────────────
  if (query.include_narrative) {
    try {
      const provider = getAIProvider();
      const worstLine = worstEpisodes.length > 0
        ? `Worst symptoms: ${worstEpisodes.map((e) => `${e.term_name} (avg grade ${e.grade})`).join(", ")}.`
        : "No significant symptom episodes.";
      const newLine = newOrWorsening.length > 0
        ? `Changes detected: ${newOrWorsening.map((e) => `${e.term_name} is ${e.direction} (${e.prior_avg_grade} → ${e.current_avg_grade})`).join(", ")}.`
        : "No new or worsening symptoms.";
      const medLine = overallAdherencePct != null
        ? `Medication adherence: ${overallAdherencePct}%.`
        : "No medication data.";

      const vitalsArr = [...vitalsByDate.values()];
      const vitalsLine = (() => {
        const parts: string[] = [];
        const stepsVals = vitalsArr.filter((v) => v.steps != null).map((v) => v.steps!);
        if (stepsVals.length > 0) {
          const avg = Math.round(stepsVals.reduce((a, b) => a + b, 0) / stepsVals.length);
          parts.push(`avg ${avg} steps/day`);
        }
        const hrVals = vitalsArr.filter((v) => v.avg_hr_bpm != null).map((v) => v.avg_hr_bpm!);
        if (hrVals.length > 0) {
          const avg = Math.round(hrVals.reduce((a, b) => a + b, 0) / hrVals.length);
          parts.push(`avg HR ${avg} bpm`);
        }
        const sleepVals = vitalsArr.filter((v) => v.sleep_hours != null).map((v) => v.sleep_hours!);
        if (sleepVals.length > 0) {
          const avg = Math.round((sleepVals.reduce((a, b) => a + b, 0) / sleepVals.length) * 10) / 10;
          parts.push(`avg sleep ${avg}h`);
        }
        const bpSysVals = vitalsArr.filter((v) => v.bp_sys_avg != null).map((v) => v.bp_sys_avg!);
        const bpDiaVals = vitalsArr.filter((v) => v.bp_dia_avg != null).map((v) => v.bp_dia_avg!);
        if (bpSysVals.length > 0 && bpDiaVals.length > 0) {
          const sysAvg = Math.round(bpSysVals.reduce((a, b) => a + b, 0) / bpSysVals.length);
          const diaAvg = Math.round(bpDiaVals.reduce((a, b) => a + b, 0) / bpDiaVals.length);
          parts.push(`avg BP ${sysAvg}/${diaAvg}`);
        }
        const weightVals = vitalsArr.filter((v) => v.weight_kg != null).map((v) => v.weight_kg!);
        if (weightVals.length > 0) {
          const avg = Math.round((weightVals.reduce((a, b) => a + b, 0) / weightVals.length) * 10) / 10;
          parts.push(`avg weight ${avg}kg`);
        }
        return parts.length > 0
          ? `Vitals trends (${vitalsArr.length} days): ${parts.join(", ")}.`
          : "No vitals data.";
      })();

      let narrative = "";
      for await (const chunk of provider.chat({
        messages: [
          {
            role: "system",
            content: [
              "You are Atlas, a clinical-grade AI companion for people in active cancer treatment.",
              "Write a brief (3-5 sentence) plain-language narrative summary of the patient's symptom report.",
              "Focus on what matters most: what changed, what's severe, and medication patterns.",
              "Use warm, clear language. Grade 6 reading level. Never diagnose or prescribe.",
            ].join(" "),
          },
          {
            role: "user",
            content: [
              `This patient's report covers the last ${query.days} days.`,
              worstLine,
              newLine,
              medLine,
              vitalsLine,
              `Total symptoms tracked: ${heatmap.length} entries across ${termGradeCounts.size} different symptom types.`,
              "Write a brief narrative summary a patient could share with their doctor:",
            ].join("\n"),
          },
        ],
        model: "flash",
        temperature: 0.5,
        maxOutputTokens: 512,
      })) {
        narrative += chunk.text;
      }
      payload.narrative = narrative.trim();
    } catch (e) {
      Sentry.captureException(e);
      payload.narrative = null;
    }
  }

  // ── 9. Save to report table ─────────────────────────────────────
  const { data: saved, error: saveErr } = await supabase
    .from("report")
    .insert({
      patient_id: user.id,
      kind: "interval_summary",
      date_range: `[${windowStart.slice(0, 10)},${new Date().toISOString().slice(0, 10)})`,
      structured_payload: payload,
    })
    .select("id")
    .single();

  if (saveErr) {
    Sentry.captureException(saveErr);
    return corsedJsonError(req, 500, "report_save_failed", saveErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, report_id: saved.id, report: payload }, null, 2), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
