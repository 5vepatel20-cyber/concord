import { notFound } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { Nav } from "../../../components/Nav";
import { SymptomTrendChart } from "../../../components/SymptomTrendChart";
import type { PatientDetail } from "../../../lib/types";

const METRIC_LABELS: Record<string, { label: string; unit: string; color: string }> = {
  weight: { label: "Weight", unit: "kg", color: "#1ABC9C" },
  hr: { label: "Heart Rate", unit: "bpm", color: "#E74C3C" },
  bp_sys: { label: "Systolic BP", unit: "mmHg", color: "#E67E22" },
  bp_dia: { label: "Diastolic BP", unit: "mmHg", color: "#F39C12" },
  glucose: { label: "Glucose", unit: "mg/dL", color: "#2ECC71" },
};

interface VitalsGroup {
  type: string;
  label: string;
  unit: string;
  color: string;
  samples: { value: number; measured_at: string }[];
  latest: number | null;
  min: number | null;
  max: number | null;
  avg: number | null;
}

async function fetchVitals(patientId: string): Promise<VitalsGroup[]> {
  const supabase = await createClient();

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 90);

  const { data } = await supabase
    .from("health_metric_sample")
    .select("type, value, measured_at")
    .eq("patient_id", patientId)
    .gte("measured_at", cutoff.toISOString())
    .in("type", ["weight", "hr", "bp_sys", "bp_dia", "glucose"])
    .order("measured_at", { ascending: true });

  if (!data || data.length === 0) return [];

  const grouped = new Map<string, { value: number; measured_at: string }[]>();
  for (const row of data as any[]) {
    if (row.value == null) continue;
    const list = grouped.get(row.type) ?? [];
    list.push({ value: row.value, measured_at: row.measured_at });
    grouped.set(row.type, list);
  }

  const result: VitalsGroup[] = [];
  for (const [type, samples] of grouped) {
    const meta = METRIC_LABELS[type];
    if (!meta) continue;
    const values = samples.map((s) => s.value);
    result.push({
      type,
      label: meta.label,
      unit: meta.unit,
      color: meta.color,
      samples,
      latest: values[values.length - 1],
      min: Math.min(...values),
      max: Math.max(...values),
      avg: Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10,
    });
  }

  return result.sort((a, b) => a.label.localeCompare(b.label));
}

async function fetchPatient(id: string): Promise<PatientDetail | null> {
  const supabase = await createClient();

  const { data: profile } = await supabase
    .from("patient_profile")
    .select(`
      user_id,
      treatment_status,
      diagnosis_date,
      cancer_stage,
      user:user!inner(full_name, date_of_birth, sex_at_birth),
      condition:condition!patient_profile_primary_diagnosis_id_fkey(display_name)
    `)
    .eq("user_id", id)
    .single();

  if (!profile) return null;

  const { data: reports } = await supabase
    .from("symptom_report")
    .select("id, reported_at, symptom_response(composite_grade, symptom_term(display_name))")
    .eq("patient_id", id)
    .order("reported_at", { ascending: false })
    .limit(20);

  const { data: meds } = await supabase
    .from("medication")
    .select("id, display_name, dose, route")
    .eq("patient_id", id)
    .eq("active", true);

  const { data: openAlerts } = await supabase
    .from("symptom_alert")
    .select("id, severity_level, created_at, status")
    .eq("patient_id", id)
    .eq("status", "open")
    .order("created_at", { ascending: false });

  return {
    id: profile.user_id,
    full_name: (profile as any).user?.full_name ?? "Unknown",
    date_of_birth: (profile as any).user?.date_of_birth ?? "",
    primary_diagnosis: (profile as any).condition?.display_name ?? "Unknown",
    treatment_status: profile.treatment_status ?? "unknown",
    diagnosis_date: profile.diagnosis_date,
    cancer_stage: profile.cancer_stage,
    sex_at_birth: (profile as any).user?.sex_at_birth,
    open_alerts: openAlerts?.length ?? 0,
    last_report_at: reports?.[0]?.reported_at ?? null,
    latest_grade: null,
    recent_reports: (reports ?? []).flatMap((r: any) =>
      (r.symptom_response ?? []).map((sr: any) => ({
        id: r.id,
        reported_at: r.reported_at,
        grade: sr.composite_grade,
        term_name: sr.symptom_term?.display_name ?? "Unknown",
      })),
    ),
    medications: (meds ?? []).map((m: any) => ({
      id: m.id,
      display_name: m.display_name,
      dose: m.dose ?? "",
      route: m.route ?? "oral",
      adherence_pct: 0,
    })),
  };
}

interface OpenAlertSummary {
  id: string;
  severity_level: string;
  created_at: string;
}

async function fetchOpenAlerts(patientId: string): Promise<OpenAlertSummary[]> {
  const supabase = await createClient();

  const { data } = await supabase
    .from("symptom_alert")
    .select("id, severity_level, created_at")
    .eq("patient_id", patientId)
    .eq("status", "open")
    .order("created_at", { ascending: false })
    .limit(10);

  return (data ?? []) as OpenAlertSummary[];
}

interface MedAdherence {
  id: string;
  display_name: string;
  dose: string;
  route: string;
  adherence_pct: number;
  total_doses: number;
  taken: number;
  skipped: number;
  missed: number;
}

async function fetchMedicationAdherence(patientId: string): Promise<MedAdherence[]> {
  const supabase = await createClient();

  const { data: meds } = await supabase
    .from("medication")
    .select("id, display_name, dose, route")
    .eq("patient_id", patientId)
    .eq("active", true);

  if (!meds || meds.length === 0) return [];

  const medIds = meds.map((m: any) => m.id);

  const { data: events } = await supabase
    .from("medication_event")
    .select("medication_id, status")
    .in("medication_id", medIds);

  const eventMap = new Map<string, { taken: number; skipped: number; missed: number; taken_late: number }>();
  for (const e of (events as any[]) ?? []) {
    const acc = eventMap.get(e.medication_id) ?? { taken: 0, skipped: 0, missed: 0, taken_late: 0 };
    if (e.status === "taken") acc.taken++;
    else if (e.status === "skipped") acc.skipped++;
    else if (e.status === "missed") acc.missed++;
    else if (e.status === "taken_late") acc.taken_late++;
    eventMap.set(e.medication_id, acc);
  }

  return (meds as any[]).map((m) => {
    const e = eventMap.get(m.id) ?? { taken: 0, skipped: 0, missed: 0, taken_late: 0 };
    const total = e.taken + e.skipped + e.missed + e.taken_late;
    const adherence_pct = total > 0 ? Math.round((e.taken / total) * 100) : 0;
    return {
      id: m.id,
      display_name: m.display_name,
      dose: m.dose ?? "",
      route: m.route ?? "oral",
      adherence_pct,
      total_doses: total,
      taken: e.taken,
      skipped: e.skipped,
      missed: e.missed,
    };
  });
}

interface ReportSummary {
  id: string;
  created_at: string;
  kind: string;
  date_range: string;
  narrative: string | null;
  worst_episodes: { term_name: string; grade: number; count: number }[];
  overall_adherence: number | null;
  new_or_worsening: { term_name: string; direction: string }[];
  vitals: { date: string; weight_kg: number | null; bp_sys_avg: number | null; bp_dia_avg: number | null }[];
}

async function fetchReports(patientId: string): Promise<ReportSummary[]> {
  const supabase = await createClient();

  const { data } = await supabase
    .from("report")
    .select("id, created_at, kind, date_range, narrative, structured_payload")
    .eq("patient_id", patientId)
    .order("created_at", { ascending: false })
    .limit(10);

  if (!data) return [];

  return (data as any[]).map((r) => {
    const p = r.structured_payload ?? {};
    return {
      id: r.id,
      created_at: r.created_at,
      kind: r.kind,
      date_range: r.date_range ?? "",
      narrative: r.narrative ?? p.narrative ?? null,
      worst_episodes: (p.worst_episodes ?? []).map((w: any) => ({
        term_name: w.term_name,
        grade: w.grade,
        count: w.count,
      })),
      overall_adherence: p.medication_adherence?.overall_pct ?? null,
      new_or_worsening: (p.new_or_worsening ?? []).map((n: any) => ({
        term_name: n.term_name,
        direction: n.direction,
      })),
      vitals: (p.vitals ?? []).slice(0, 7).map((v: any) => ({
        date: v.date,
        weight_kg: v.weight_kg ?? null,
        bp_sys_avg: v.bp_sys_avg ?? null,
        bp_dia_avg: v.bp_dia_avg ?? null,
      })),
    };
  });
}

interface DayCompliance {
  date: string;
  completed: boolean;
  grade: number | null;
}

async function fetchCompliance(patientId: string): Promise<DayCompliance[]> {
  const supabase = await createClient();

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 30);

  const { data } = await supabase
    .from("symptom_report")
    .select("reported_at, symptom_response(composite_grade)")
    .eq("patient_id", patientId)
    .gte("reported_at", cutoff.toISOString())
    .order("reported_at", { ascending: true });

  const dayMap = new Map<string, number[]>();
  for (const row of (data as any[]) ?? []) {
    const day = row.reported_at.slice(0, 10);
    const grades = (row.symptom_response ?? []).map((sr: any) => sr.composite_grade ?? 0);
    const existing = dayMap.get(day) ?? [];
    dayMap.set(day, [...existing, ...grades]);
  }

  const result: DayCompliance[] = [];
  const now = new Date();
  for (let i = 29; i >= 0; i--) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    const grades = dayMap.get(key);
    result.push({
      date: key,
      completed: grades != null && grades.length > 0,
      grade: grades != null && grades.length > 0 ? Math.max(...grades) : null,
    });
  }

  return result;
}

interface TimelineEvent {
  id: string;
  type: "symptom" | "report" | "medication" | "vitals";
  date: string;
  label: string;
  detail: string;
  grade?: number;
}

async function fetchTimeline(patientId: string): Promise<TimelineEvent[]> {
  const supabase = await createClient();
  const events: TimelineEvent[] = [];

  const { data: symptomReports } = await supabase
    .from("symptom_report")
    .select("id, reported_at, symptom_response(composite_grade, symptom_term(display_name))")
    .eq("patient_id", patientId)
    .gte("reported_at", new Date(Date.now() - 90 * 86400000).toISOString())
    .order("reported_at", { ascending: false })
    .limit(20);

  for (const r of (symptomReports as any[]) ?? []) {
    const responses = (r.symptom_response ?? []) as any[];
    const maxGrade = responses.length > 0 ? Math.max(...responses.map((sr: any) => sr.composite_grade ?? 0)) : 0;
    const terms = responses.map((sr: any) => sr.symptom_term?.display_name).filter(Boolean);
    events.push({
      id: `sym-${r.id}`,
      type: "symptom",
      date: r.reported_at,
      label: "Symptoms Logged",
      detail: terms.length > 0 ? terms.slice(0, 3).join(", ") + (terms.length > 3 ? ` +${terms.length - 3}` : "") : "Check-in completed",
      grade: maxGrade,
    });
  }

  const { data: reports } = await supabase
    .from("report")
    .select("id, created_at, kind, narrative")
    .eq("patient_id", patientId)
    .gte("created_at", new Date(Date.now() - 90 * 86400000).toISOString())
    .order("created_at", { ascending: false })
    .limit(10);

  for (const r of (reports as any[]) ?? []) {
    events.push({
      id: `rpt-${r.id}`,
      type: "report",
      date: r.created_at,
      label: r.kind === "visit_prep" ? "Visit Prep Report" : r.kind === "interval_summary" ? "Interval Summary" : "Report Generated",
      detail: r.narrative ? r.narrative.slice(0, 80) + (r.narrative.length > 80 ? "..." : "") : "One-pager generated",
    });
  }

  const { data: medEvents } = await supabase
    .from("medication_event")
    .select("id, scheduled_for, status, medication:medication_id(display_name)")
    .in("medication_id", (await supabase.from("medication").select("id").eq("patient_id", patientId).eq("active", true)).data?.map((m: any) => m.id) ?? [])
    .gte("scheduled_for", new Date(Date.now() - 30 * 86400000).toISOString())
    .order("scheduled_for", { ascending: false })
    .limit(20);

  for (const e of (medEvents as any[]) ?? []) {
    events.push({
      id: `med-${e.id}`,
      type: "medication",
      date: e.scheduled_for,
      label: `Medication ${e.status.replace("_", " ")}`,
      detail: e.medication?.display_name ?? "Unknown",
    });
  }

  const { data: vitals } = await supabase
    .from("health_metric_sample")
    .select("id, type, value, measured_at")
    .eq("patient_id", patientId)
    .in("type", ["weight", "hr", "bp_sys", "glucose"])
    .gte("measured_at", new Date(Date.now() - 30 * 86400000).toISOString())
    .order("measured_at", { ascending: false })
    .limit(20);

  const typeLabels: Record<string, string> = { weight: "Weight", hr: "Heart Rate", bp_sys: "Blood Pressure", glucose: "Glucose" };
  for (const v of (vitals as any[]) ?? []) {
    events.push({
      id: `vit-${v.id}`,
      type: "vitals",
      date: v.measured_at,
      label: "Vitals Recorded",
      detail: `${typeLabels[v.type] ?? v.type}: ${v.value}`,
    });
  }

  events.sort((a, b) => b.date.localeCompare(a.date));
  return events.slice(0, 50);
}

async function ensureConversation(patientId: string) {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: myConvs } = await supabase
    .from("conversation_participant")
    .select("conversation_id")
    .eq("user_id", user.id);

  if (myConvs && myConvs.length > 0) {
    const myConvIds = myConvs.map((c: any) => c.conversation_id);
    const { data: existing } = await supabase
      .from("conversation_participant")
      .select("conversation_id")
      .in("conversation_id", myConvIds)
      .eq("user_id", patientId)
      .maybeSingle();

    if (existing) return existing.conversation_id;
  }

  const { data: conv } = await supabase
    .from("conversation")
    .insert({})
    .select("id")
    .single();

  if (!conv) return null;

  await supabase.from("conversation_participant").insert([
    { conversation_id: conv.id, user_id: user.id },
    { conversation_id: conv.id, user_id: patientId },
  ]);

  return conv.id;
}

interface WorseningItem {
  term_name: string;
  direction: string;
  baseline_avg_grade: number;
  current_avg_grade: number;
  delta: number;
}

async function fetchWorsening(patientId: string): Promise<WorseningItem[]> {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") return [];

  const DAYS_MS = 7 * 24 * 60 * 60 * 1000;
  const now = Date.now();
  const currentStart = new Date(now - DAYS_MS).toISOString();
  const priorStart = new Date(now - 2 * DAYS_MS).toISOString();

  const { data: priorSymptoms } = await supabase
    .from("symptom_response")
    .select("composite_grade, term:symptom_term(pro_ctcae_code, display_name), report:symptom_report!inner(reported_at, patient_id)")
    .eq("report.patient_id", patientId)
    .gte("report.reported_at", priorStart)
    .lt("report.reported_at", currentStart);

  const { data: currentSymptoms } = await supabase
    .from("symptom_response")
    .select("composite_grade, term:symptom_term(pro_ctcae_code, display_name), report:symptom_report!inner(reported_at, patient_id)")
    .eq("report.patient_id", patientId)
    .gte("report.reported_at", currentStart);

  const priorMap = new Map<string, { sum: number; count: number; name: string }>();
  for (const sr of (priorSymptoms as any[]) ?? []) {
    const term = Array.isArray(sr.term) ? sr.term[0] : sr.term;
    if (!term) continue;
    const acc = priorMap.get(term.pro_ctcae_code) ?? { sum: 0, count: 0, name: term.display_name };
    acc.sum += sr.composite_grade ?? 0;
    acc.count++;
    priorMap.set(term.pro_ctcae_code, acc);
  }

  const currentMap = new Map<string, { sum: number; count: number; name: string }>();
  for (const sr of (currentSymptoms as any[]) ?? []) {
    const term = Array.isArray(sr.term) ? sr.term[0] : sr.term;
    if (!term) continue;
    const acc = currentMap.get(term.pro_ctcae_code) ?? { sum: 0, count: 0, name: term.display_name };
    acc.sum += sr.composite_grade ?? 0;
    acc.count++;
    currentMap.set(term.pro_ctcae_code, acc);
  }

  const allCodes = new Set([...priorMap.keys(), ...currentMap.keys()]);
  const results: WorseningItem[] = [];

  for (const code of allCodes) {
    const prior = priorMap.get(code);
    const current = currentMap.get(code);
    const currentAvg = current ? current.sum / current.count : 0;
    const priorAvg = prior ? prior.sum / prior.count : 0;
    const delta = currentAvg - priorAvg;

    const direction = !prior ? "new" : delta >= 1 ? "worsened" : delta <= -1 ? "improved" : "stable";

    results.push({
      term_name: current?.name ?? prior?.name ?? code,
      direction,
      baseline_avg_grade: Math.round(priorAvg * 10) / 10,
      current_avg_grade: Math.round(currentAvg * 10) / 10,
      delta: Math.round(delta * 10) / 10,
    });
  }

  return results.filter((r) => r.direction === "worsened" || r.direction === "new").sort((a, b) => b.delta - a.delta);
}

async function generateReport(patientId: string) {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") return;

  const windowStart = new Date(Date.now() - 14 * 86400000).toISOString();

  const { data: symptoms } = await supabase
    .from("symptom_response")
    .select("composite_grade, created_at, term:symptom_term(pro_ctcae_code, display_name, body_system), report:symptom_report!inner(reported_at, patient_id)")
    .eq("report.patient_id", patientId)
    .gte("report.reported_at", windowStart)
    .order("report(reported_at)", { ascending: true });

  const { data: priorSymptoms } = await supabase
    .from("symptom_response")
    .select("composite_grade, term:symptom_term(pro_ctcae_code), report:symptom_report!inner(reported_at, patient_id)")
    .eq("report.patient_id", patientId)
    .gte("report.reported_at", new Date(Date.now() - 28 * 86400000).toISOString())
    .lt("report.reported_at", windowStart)
    .order("report(reported_at)", { ascending: true });

  const { data: meds } = await supabase
    .from("medication")
    .select("id, display_name")
    .eq("patient_id", patientId)
    .eq("active", true);

  const medIds = (meds ?? []).map((m: any) => m.id);
  const adherenceStats: Array<{ medication_id: string; display_name: string; total: number; taken: number; adherence_pct: number }> = [];
  if (medIds.length > 0) {
    const { data: events } = await supabase
      .from("medication_event")
      .select("medication_id, status")
      .in("medication_id", medIds)
      .gte("scheduled_for", windowStart);

    const eventsByMed = new Map<string, { total: number; taken: number }>();
    for (const e of (events as any[]) ?? []) {
      const acc = eventsByMed.get(e.medication_id) ?? { total: 0, taken: 0 };
      acc.total++;
      if (e.status === "taken") acc.taken++;
      eventsByMed.set(e.medication_id, acc);
    }
    for (const med of (meds as any[]) ?? []) {
      const acc = eventsByMed.get(med.id);
      if (!acc || acc.total === 0) {
        adherenceStats.push({ medication_id: med.id, display_name: med.display_name, total: 0, taken: 0, adherence_pct: 0 });
      } else {
        adherenceStats.push({ medication_id: med.id, display_name: med.display_name, total: acc.total, taken: acc.taken, adherence_pct: Math.round((acc.taken / acc.total) * 100) });
      }
    }
  }

  const { data: vitalsRaw } = await supabase
    .from("health_metric_sample")
    .select("type, value, measured_at")
    .eq("patient_id", patientId)
    .gte("measured_at", windowStart)
    .order("measured_at", { ascending: true });

  const vitalsByDate = new Map<string, Record<string, any>>();
  for (const v of (vitalsRaw as any[]) ?? []) {
    const dateKey = v.measured_at.slice(0, 10);
    let entry = vitalsByDate.get(dateKey);
    if (!entry) { entry = { date: dateKey }; vitalsByDate.set(dateKey, entry); }
    if (v.type === "weight") entry.weight_kg = Math.round((v.value ?? 0) * 10) / 10;
    if (v.type === "hr") entry.avg_hr_bpm = Math.round(v.value ?? 0);
    if (v.type === "bp_sys") entry.bp_sys_avg = Math.round(v.value ?? 0);
    if (v.type === "bp_dia") entry.bp_dia_avg = Math.round(v.value ?? 0);
  }

  const heatmap: Array<{ date: string; term_code: string; term_name: string; body_system: string; grade: number }> = [];
  const termGradeCounts = new Map<string, { sum: number; count: number }>();
  for (const sr of (symptoms as any[]) ?? []) {
    const term = Array.isArray(sr.term) ? sr.term[0] : sr.term;
    const report = Array.isArray(sr.report) ? sr.report[0] : sr.report;
    if (!term || !report) continue;
    const date = report.reported_at.slice(0, 10);
    heatmap.push({ date, term_code: term.pro_ctcae_code, term_name: term.display_name, body_system: term.body_system, grade: sr.composite_grade ?? 0 });
    const acc = termGradeCounts.get(term.pro_ctcae_code) ?? { sum: 0, count: 0 };
    acc.sum += sr.composite_grade ?? 0;
    acc.count++;
    termGradeCounts.set(term.pro_ctcae_code, acc);
  }

  const worstEpisodes = [...termGradeCounts.entries()]
    .map(([code, acc]) => ({ term_code: code, term_name: heatmap.find((h) => h.term_code === code)?.term_name ?? code, grade: Math.round((acc.sum / acc.count) * 10) / 10, count: acc.count }))
    .sort((a, b) => b.grade - a.grade)
    .slice(0, 3);

  const priorAvg = new Map<string, { sum: number; count: number }>();
  for (const sr of (priorSymptoms as any[]) ?? []) {
    const term = Array.isArray(sr.term) ? sr.term[0] : sr.term;
    if (!term) continue;
    const acc = priorAvg.get(term.pro_ctcae_code) ?? { sum: 0, count: 0 };
    acc.sum += sr.composite_grade ?? 0;
    acc.count++;
    priorAvg.set(term.pro_ctcae_code, acc);
  }

  const newOrWorsening: Array<{ term_code: string; term_name: string; prior_avg_grade: number; current_avg_grade: number; direction: string }> = [];
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

  const payload = {
    generated_at: new Date().toISOString(),
    period_days: 14,
    patient_id: patientId,
    symptom_heatmap: heatmap,
    worst_episodes: worstEpisodes,
    new_or_worsening: newOrWorsening,
    medication_adherence: { by_medication: adherenceStats, overall_pct: overallAdherencePct },
    vitals: [...vitalsByDate.values()].sort((a: any, b: any) => a.date.localeCompare(b.date)),
  };

  await supabase.from("report").insert({
    patient_id: patientId,
    kind: "interval_summary",
    date_range: `[${windowStart.slice(0, 10)},${new Date().toISOString().slice(0, 10)})`,
    structured_payload: payload,
  });
}

export default async function PatientDetailPage({ params }: { params: { id: string } }) {
  const patient = await fetchPatient(params.id);
  if (!patient) notFound();

  const vitals = await fetchVitals(params.id);
  const openAlerts = await fetchOpenAlerts(params.id);
  const reports = await fetchReports(params.id);
  const compliance = await fetchCompliance(params.id);
  const medsWithAdherence = await fetchMedicationAdherence(params.id);
  const timeline = await fetchTimeline(params.id);
  const worsening = await fetchWorsening(params.id);

  const gradeColors: Record<string, string> = {
    "0": "var(--stable)",
    "1": "var(--caution)",
    "2": "var(--warn)",
    "3": "var(--severe)",
  };

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px", maxWidth: 960 }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 4 }}>
          {patient.full_name}
        </h1>
        <p style={{ fontSize: 15, color: "var(--slate)", marginBottom: 16 }}>
          {patient.primary_diagnosis}
          {patient.cancer_stage ? ` · Stage ${patient.cancer_stage}` : ""}
          {patient.diagnosis_date ? ` · Diagnosed ${patient.diagnosis_date}` : ""}
        </p>

        {openAlerts.length > 0 && (
          <div style={{
            background: "#FDEAEA",
            border: "1px solid #E5484D",
            borderRadius: 10,
            padding: "12px 16px",
            marginBottom: 24,
            display: "flex",
            alignItems: "center",
            gap: 12,
          }}>
            <span style={{ fontSize: 18, color: "#E5484D" }}>!</span>
            <div style={{ flex: 1, fontSize: 14, color: "#CD2B31" }}>
              <strong>{openAlerts.length} open {openAlerts.length === 1 ? "alert" : "alerts"}</strong>
              {openAlerts.length > 0 && (
                <span> &mdash; {openAlerts.filter((a: any) => a.severity_level === "emergency").length > 0
                  ? `${openAlerts.filter((a: any) => a.severity_level === "emergency").length} emergency`
                  : ""}{openAlerts.filter((a: any) => a.severity_level === "urgent").length > 0
                    ? `${openAlerts.filter((a: any) => a.severity_level === "emergency").length > 0 ? ", " : ""}${openAlerts.filter((a: any) => a.severity_level === "urgent").length} urgent` : ""}</span>
              )}
            </div>
            <a href="/alerts" style={{
              padding: "6px 14px",
              fontSize: 13,
              fontWeight: 500,
              background: "var(--surface)",
              color: "var(--concord-blue)",
              border: "1px solid var(--hairline)",
              borderRadius: 8,
              textDecoration: "none",
            }}>
              View All
            </a>
          </div>
        )}

        <div style={{ display: "flex", gap: 8, marginBottom: 24 }}>
          <form action={ensureConversation.bind(null, params.id)}>
            <button
              type="submit"
              style={{
                padding: "8px 16px",
                fontSize: 13,
                fontWeight: 500,
                background: "var(--concord-blue)",
                color: "var(--surface)",
                border: "none",
                borderRadius: 8,
                cursor: "pointer",
              }}
            >
              Message Patient
            </button>
          </form>
        </div>

        {worsening.length > 0 && (
          <div style={{
            background: "#FBE6DD",
            border: "1px solid #F2683C",
            borderRadius: 14,
            padding: "14px 16px",
            marginBottom: 24,
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
              <span style={{ fontSize: 16, color: "#F2683C", fontWeight: 700 }}>&#9650;</span>
              <span style={{ fontSize: 14, fontWeight: 600, color: "#CD2B31" }}>
                {worsening.length} worsening {worsening.length === 1 ? "symptom" : "symptoms"} detected (7-day baseline)
              </span>
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              {worsening.map((w, i) => (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", fontSize: 13 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{
                      display: "inline-block",
                      width: 8,
                      height: 8,
                      borderRadius: 4,
                      background: w.direction === "new" ? "var(--warn)" : "var(--severe)",
                    }} />
                    <span style={{ color: "var(--ink)", fontWeight: 500 }}>{w.term_name}</span>
                    <span style={{
                      padding: "1px 6px",
                      borderRadius: 4,
                      fontSize: 11,
                      fontWeight: 600,
                      background: w.direction === "new" ? "var(--warn-tint)" : "#FDEAEA",
                      color: w.direction === "new" ? "var(--warn)" : "var(--severe)",
                      textTransform: "uppercase",
                    }}>
                      {w.direction}
                    </span>
                  </div>
                  <span style={{ color: "var(--slate)" }}>
                    {w.direction === "new" ? (
                      <>new &middot; avg grade {w.current_avg_grade}</>
                    ) : (
                      <>{w.baseline_avg_grade} &rarr; {w.current_avg_grade} (&Delta;+{w.delta})</>
                    )}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          padding: "14px 16px",
          marginBottom: 24,
        }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: "var(--slate)", textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 10 }}>
            Check-in Compliance &middot; Last 30 Days
          </div>
          <div style={{
            display: "grid",
            gridTemplateColumns: "repeat(7, 1fr)",
            gap: 3,
          }}>
            {["S", "M", "T", "W", "T", "F", "S"].map((d) => (
              <div key={d} style={{ fontSize: 10, fontWeight: 600, color: "var(--hint)", textAlign: "center", marginBottom: 4 }}>
                {d}
              </div>
            ))}
            {(() => {
              const firstDay = new Date(compliance[0]?.date ?? new Date());
              const startPad = firstDay.getDay();
              const cells: React.ReactNode[] = [];
              for (let i = 0; i < startPad; i++) {
                cells.push(<div key={`pad-${i}`} />);
              }
              for (const day of compliance) {
                const d = new Date(day.date);
                const isToday = d.toDateString() === new Date().toDateString();
                let bg = "var(--mist)";
                let fg = "var(--hint)";
                if (day.completed) {
                  bg = "var(--stable)";
                  fg = "var(--surface)";
                } else if (d < new Date(new Date().toDateString())) {
                  bg = "#FDEAEA";
                  fg = "var(--severe)";
                }
                if (isToday) {
                  bg = day.completed ? "var(--stable)" : "var(--concord-blue-tint)";
                  fg = day.completed ? "var(--surface)" : "var(--concord-blue)";
                }
                cells.push(
                  <div
                    key={day.date}
                    title={`${day.date}${day.completed ? ` (grade ${day.grade})` : " — no check-in"}`}
                    style={{
                      aspectRatio: "1",
                      borderRadius: 6,
                      background: bg,
                      color: fg,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      fontSize: 11,
                      fontWeight: d.getDay() === 0 || d.getDay() === 6 ? d > new Date(new Date().toDateString()) ? 400 : 700 : 500,
                    }}
                  >
                    {d.getDate()}
                  </div>
                );
              }
              return cells;
            })()}
          </div>
          <div style={{ display: "flex", gap: 16, marginTop: 8, fontSize: 12, color: "var(--hint)" }}>
            <span>&bull; Completed ({compliance.filter((d) => d.completed).length})</span>
            <span style={{ color: "var(--severe)" }}>&bull; Missed ({compliance.filter((d) => !d.completed && new Date(d.date) < new Date(new Date().toDateString())).length})</span>
            <span>&bull; {Math.round((compliance.filter((d) => d.completed).length / Math.max(compliance.filter((d) => new Date(d.date) <= new Date(new Date().toDateString())).length, 1)) * 100)}% rate</span>
          </div>
        </div>

        <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12 }}>
          Symptom Trend
        </h2>
        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
          marginBottom: 24,
        }}>
          <SymptomTrendChart reports={patient.recent_reports} />
        </div>

        <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12 }}>
          Recent Symptoms
        </h2>
        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
          marginBottom: 32,
        }}>
          {patient.recent_reports.length === 0 ? (
            <p style={{ padding: 24, color: "var(--hint)", fontSize: 15 }}>
              No symptoms logged yet.
            </p>
          ) : (
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                  {["Date", "Symptom", "Grade"].map((h) => (
                    <th key={h} style={{
                      padding: "10px 16px",
                      fontSize: 13,
                      fontWeight: 600,
                      color: "var(--slate)",
                      textTransform: "uppercase",
                    }}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {patient.recent_reports.slice(0, 30).map((r, i) => (
                  <tr key={`${r.id}-${i}`} style={{ borderBottom: "1px solid var(--hairline)" }}>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {new Date(r.reported_at).toLocaleDateString()}
                    </td>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {r.term_name}
                    </td>
                    <td style={{ padding: "10px 16px" }}>
                      <span style={{
                        display: "inline-block",
                        padding: "2px 10px",
                        borderRadius: 6,
                        fontSize: 12,
                        fontWeight: 500,
                        background: `${gradeColors[String(r.grade)] ?? "var(--hint)"}20`,
                        color: gradeColors[String(r.grade)] ?? "var(--hint)",
                      }}>
                        {["None", "Mild", "Moderate", "Severe"][r.grade] ?? "Unknown"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12 }}>
          Medications
        </h2>
        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
        }}>
          {(medsWithAdherence.length > 0 ? medsWithAdherence : patient.medications).length === 0 ? (
            <p style={{ padding: 24, color: "var(--hint)", fontSize: 15 }}>
              No medications recorded.
            </p>
          ) : (
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                  {["Medication", "Dose", "Route", "Adherence"].map((h) => (
                    <th key={h} style={{
                      padding: "10px 16px",
                      fontSize: 13,
                      fontWeight: 600,
                      color: "var(--slate)",
                      textTransform: "uppercase",
                    }}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {(medsWithAdherence.length > 0 ? medsWithAdherence : patient.medications).map((m: any) => (
                  <tr key={m.id} style={{ borderBottom: "1px solid var(--hairline)" }}>
                    <td style={{ padding: "10px 16px", fontSize: 14, fontWeight: 600, color: "var(--ink)" }}>
                      {m.display_name}
                    </td>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {m.dose || "—"}
                    </td>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {m.route}
                    </td>
                    <td style={{ padding: "10px 16px" }}>
                      {m.adherence_pct != null ? (
                        <span style={{
                          display: "inline-block",
                          padding: "2px 8px",
                          borderRadius: 4,
                          fontSize: 12,
                          fontWeight: 600,
                          background: m.adherence_pct >= 80 ? "var(--stable-tint)" : m.adherence_pct >= 50 ? "#FBE6DD" : "#FDEAEA",
                          color: m.adherence_pct >= 80 ? "var(--stable)" : m.adherence_pct >= 50 ? "var(--warn)" : "var(--severe)",
                        }}>
                          {m.adherence_pct}%
                        </span>
                      ) : (
                        <span style={{ fontSize: 13, color: "var(--hint)" }}>—</span>
                      )}
                      {m.total_doses > 0 && (
                        <span style={{ fontSize: 11, color: "var(--hint)", marginLeft: 4 }}>
                          ({m.taken}/{m.total_doses})
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {vitals.length > 0 && (
          <>
            <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12, marginTop: 32 }}>
              Vitals
            </h2>
            <div style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))",
              gap: 12,
            }}>
              {vitals.map((v) => (
                <div key={v.type} style={{
                  background: "var(--surface)",
                  borderRadius: 14,
                  border: "1px solid var(--hairline)",
                  padding: 16,
                }}>
                  <div style={{
                    fontSize: 13,
                    fontWeight: 600,
                    color: "var(--slate)",
                    textTransform: "uppercase",
                    letterSpacing: 0.3,
                    marginBottom: 8,
                  }}>
                    {v.label}
                  </div>
                  <div style={{
                    fontSize: 28,
                    fontWeight: 700,
                    color: "var(--ink)",
                    marginBottom: 4,
                  }}>
                    {v.latest != null ? `${v.latest} ` : "— "}
                    <span style={{ fontSize: 14, fontWeight: 400, color: "var(--hint)" }}>
                      {v.unit}
                    </span>
                  </div>
                  <div style={{ fontSize: 13, color: "var(--hint)", marginBottom: 12 }}>
                    min {v.min} &middot; max {v.max} &middot; avg {v.avg}
                  </div>
                  <svg width="100%" height={48} viewBox="0 0 200 48" preserveAspectRatio="none">
                    <defs>
                      <linearGradient id={`grad-${v.type}`} x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={v.color} stopOpacity={0.2} />
                        <stop offset="100%" stopColor={v.color} stopOpacity={0.02} />
                      </linearGradient>
                    </defs>
                    {(() => {
                      const vals = v.samples.map((s) => s.value);
                      const mn = Math.min(...vals);
                      const mx = Math.max(...vals);
                      const range = mx - mn || 1;
                      const w = 200;
                      const h = 48;
                      const pts = vals.map((val, i) => {
                        const x = (i / (vals.length - 1 || 1)) * w;
                        const y = h - ((val - mn) / range) * (h - 4) - 2;
                        return `${x},${y}`;
                      });
                      const area = `M0,48 L${pts.join(" L")} L${w},48 Z`;
                      return (
                        <>
                          <path d={area} fill={`url(#grad-${v.type})`} />
                          <polyline
                            points={pts.join(" ")}
                            fill="none"
                            stroke={v.color}
                            strokeWidth={2}
                            strokeLinejoin="round"
                            strokeLinecap="round"
                          />
                        </>
                      );
                    })()}
                  </svg>
                </div>
              ))}
            </div>
          </>
        )}

        <>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 32, marginBottom: 12 }}>
            <h2 style={{ fontSize: 17, fontWeight: 600, margin: 0 }}>
              Patient Reports
            </h2>
            <form action={generateReport.bind(null, params.id)}>
              <button type="submit" style={{
                padding: "8px 16px",
                fontSize: 13,
                fontWeight: 500,
                background: "var(--concord-blue)",
                color: "var(--surface)",
                border: "none",
                borderRadius: 8,
                cursor: "pointer",
              }}>
                Generate Report (14d)
              </button>
            </form>
          </div>
          {reports.length > 0 ? (
            <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
              {reports.map((r) => (
                <div key={r.id} style={{
                  background: "var(--surface)",
                  borderRadius: 14,
                  border: "1px solid var(--hairline)",
                  padding: 16,
                }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                    <div>
                      <div style={{ fontSize: 15, fontWeight: 600, color: "var(--ink)" }}>
                        {r.kind === "visit_prep" ? "Visit Prep" : r.kind === "interval_summary" ? "Interval Summary" : "Shared Report"}
                      </div>
                      <div style={{ fontSize: 13, color: "var(--hint)", marginTop: 2 }}>
                        {new Date(r.created_at).toLocaleDateString()} &middot; {r.date_range}
                      </div>
                    </div>
                    {r.overall_adherence != null && (
                      <div style={{
                        padding: "4px 12px",
                        borderRadius: 6,
                        fontSize: 13,
                        fontWeight: 600,
                        background: r.overall_adherence >= 80 ? "var(--stable-tint)" : r.overall_adherence >= 50 ? "#FBE6DD" : "#FDEAEA",
                        color: r.overall_adherence >= 80 ? "var(--stable)" : r.overall_adherence >= 50 ? "var(--warn)" : "var(--severe)",
                      }}>
                        {r.overall_adherence}% adherence
                      </div>
                    )}
                  </div>

                  {r.narrative && (
                    <p style={{ fontSize: 14, color: "var(--body)", lineHeight: 1.6, marginBottom: 12 }}>
                      {r.narrative}
                    </p>
                  )}

                  <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
                    {r.worst_episodes.length > 0 && (
                      <div style={{ minWidth: 160 }}>
                        <div style={{ fontSize: 12, fontWeight: 600, color: "var(--slate)", textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 6 }}>
                          Worst Episodes
                        </div>
                        {r.worst_episodes.slice(0, 3).map((w) => (
                          <div key={w.term_name} style={{ fontSize: 13, color: "var(--body)", marginBottom: 2 }}>
                            {w.term_name} &mdash; avg grade {w.grade.toFixed(1)} ({w.count}x)
                          </div>
                        ))}
                      </div>
                    )}

                    {r.new_or_worsening.length > 0 && (
                      <div style={{ minWidth: 160 }}>
                        <div style={{ fontSize: 12, fontWeight: 600, color: "var(--slate)", textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 6 }}>
                          New / Worsening
                        </div>
                        {r.new_or_worsening.slice(0, 3).map((n) => (
                          <div key={n.term_name} style={{
                            fontSize: 13,
                            color: n.direction === "new" ? "var(--warn)" : "var(--severe)",
                            marginBottom: 2,
                          }}>
                            {n.term_name} ({n.direction})
                          </div>
                        ))}
                      </div>
                    )}

                    {r.vitals.length > 0 && (
                      <div style={{ minWidth: 160 }}>
                        <div style={{ fontSize: 12, fontWeight: 600, color: "var(--slate)", textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 6 }}>
                          Latest Vitals
                        </div>
                        {r.vitals.slice(0, 3).map((v) => (
                          <div key={v.date} style={{ fontSize: 13, color: "var(--body)", marginBottom: 2 }}>
                            {v.date.slice(5)} &middot; {v.weight_kg ? `${v.weight_kg}kg` : ""}{v.weight_kg && v.bp_sys_avg ? " " : ""}{v.bp_sys_avg ? `${v.bp_sys_avg}/${v.bp_dia_avg ?? "—"}` : ""}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div style={{
              background: "var(--surface)",
              borderRadius: 14,
              border: "1px solid var(--hairline)",
              padding: 24,
              textAlign: "center",
              color: "var(--hint)",
              fontSize: 15,
            }}>
              No reports yet. Click "Generate Report" to create a 14-day interval summary.
            </div>
          )}
        </>

        {timeline.length > 0 && (
          <>
            <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12, marginTop: 32 }}>
              Activity Timeline
            </h2>
            <div style={{
              background: "var(--surface)",
              borderRadius: 14,
              border: "1px solid var(--hairline)",
              overflow: "hidden",
              padding: 16,
            }}>
              {timeline.map((event, i) => {
                const typeColors: Record<string, string> = {
                  symptom: "var(--warn)",
                  report: "var(--concord-blue)",
                  medication: "var(--stable)",
                  vitals: "var(--slate)",
                };
                const typeIcons: Record<string, string> = {
                  symptom: "S",
                  report: "R",
                  medication: "M",
                  vitals: "V",
                };
                const color = typeColors[event.type] ?? "var(--hint)";
                return (
                  <div key={event.id} style={{
                    display: "flex",
                    gap: 12,
                    padding: "8px 0",
                    borderBottom: i < timeline.length - 1 ? "1px solid var(--hairline)" : "none",
                  }}>
                    <div style={{
                      width: 28,
                      height: 28,
                      borderRadius: 14,
                      background: `${color}20`,
                      color,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      fontSize: 12,
                      fontWeight: 700,
                      flexShrink: 0,
                      marginTop: 2,
                    }}>
                      {typeIcons[event.type] ?? "?"}
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
                        <span style={{ fontSize: 14, fontWeight: 600, color: "var(--ink)" }}>
                          {event.label}
                        </span>
                        <span style={{ fontSize: 12, color: "var(--hint)", whiteSpace: "nowrap", marginLeft: 12 }}>
                          {new Date(event.date).toLocaleDateString()}
                        </span>
                      </div>
                      <div style={{ fontSize: 13, color: "var(--body)", marginTop: 2, lineHeight: 1.4 }}>
                        {event.detail}
                        {event.grade != null && (
                          <span style={{
                            display: "inline-block",
                            marginLeft: 6,
                            padding: "0 6px",
                            borderRadius: 4,
                            fontSize: 11,
                            fontWeight: 600,
                            background: `${gradeColors[String(event.grade)] ?? "var(--hint)"}20`,
                            color: gradeColors[String(event.grade)] ?? "var(--hint)",
                          }}>
                            grade {event.grade}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </>
        )}
      </main>
    </div>
  );
}
