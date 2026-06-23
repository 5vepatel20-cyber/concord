// Shared symptom report creation logic used by:
//   - POST /api/symptoms/submit        (patient self-report)
//   - POST /api/symptoms/caregiver-submit (caregiver proxy report)
//
// Extracted to avoid duplicating the scoring, alert, and worsening pipeline.

import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import { compositeGrade, type Grade } from "../pro-ctcae/scorer.js";
import { evaluateRules } from "../alerts/rules.js";
import { evaluateEscalation } from "../alerts/escalation.js";
import { detectWorsening } from "../pro-ctcae/worsening.js";
import { Sentry } from "../sentry.js";

const Attr = z.number().int().min(0).max(4).nullable();

export const ResponseSchema = z.object({
  pro_ctcae_code: z.string().min(1).max(20),
  frequency: Attr.optional(),
  severity: Attr.optional(),
  interference: Attr.optional(),
  presence: z.boolean().nullable().optional(),
  amount: Attr.optional(),
  body_location: z.string().max(200).nullable().optional(),
});

export type ResponseInput = z.infer<typeof ResponseSchema>;

export interface CreateReportOpts {
  supabase: SupabaseClient;
  patientId: string;
  recallWindow: "now" | "past_7_days";
  source: "self" | "caregiver" | "voice";
  freeText: string | null;
  responses: ResponseInput[];
}

export interface CreateReportResult {
  reportId: string;
  responsesWritten: number;
  severeResponses: { term_code: string; body_location: string | null | undefined }[];
  alertsCreated: number;
  worsening: Array<{ term_code: string; term_name: string; direction: string; current_avg_grade: number; baseline_avg_grade: number }>;
  emergencyGuidance: { title: string; body: string; callout: string } | null;
}

const EMERGENCY_GUIDANCE = {
  title: "This sounds like it may need urgent attention",
  body: "Based on what you logged, please contact your oncology care team now. If you can't reach them and you're feeling very unwell, call 911 or your local emergency number.",
  callout: "Concord is not a medical device. This guidance is informational, not a diagnosis.",
};

export async function createSymptomReport(opts: CreateReportOpts): Promise<CreateReportResult> {
  const { supabase, patientId, recallWindow, source, freeText, responses } = opts;

  // Resolve term codes → term ids.
  const codes = responses.map((r) => r.pro_ctcae_code);
  const { data: terms, error: termsErr } = await supabase
    .from("symptom_term")
    .select("id, pro_ctcae_code")
    .in("pro_ctcae_code", codes);
  if (termsErr) {
    Sentry.captureException(termsErr);
    throw new AppError("term_lookup_failed", termsErr.message);
  }
  const codeToId = new Map(terms?.map((t) => [t.pro_ctcae_code, t.id] as const) ?? []);
  for (const code of codes) {
    if (!codeToId.has(code)) {
      throw new AppError("unknown_term", `Unknown PRO-CTCAE code: ${code}`);
    }
  }

  // Compute grades server-side.
  const graded = responses.map((r) => {
    const grade: Grade = compositeGrade({
      frequency: r.frequency ?? null,
      severity: r.severity ?? null,
      interference: r.interference ?? null,
      presence: r.presence ?? null,
      amount: r.amount ?? null,
    });
    return { ...r, composite_grade: grade, term_id: codeToId.get(r.pro_ctcae_code)! };
  });

  // Insert the report.
  const { data: report, error: reportErr } = await supabase
    .from("symptom_report")
    .insert({
      patient_id: patientId,
      recall_window: recallWindow,
      source,
      free_text: freeText ?? null,
      reported_at: new Date().toISOString(),
    })
    .select("id")
    .single();
  if (reportErr || !report) {
    Sentry.captureException(reportErr);
    throw new AppError("report_insert_failed", reportErr?.message ?? "insert failed");
  }

  // Insert responses.
  const responseRows = graded.map((g) => ({
    report_id: report.id,
    term_id: g.term_id,
    frequency: g.frequency ?? null,
    severity: g.severity ?? null,
    interference: g.interference ?? null,
    presence: g.presence ?? null,
    amount: g.amount ?? null,
    body_location: g.body_location ?? null,
    composite_grade: g.composite_grade,
  }));
  const { error: respErr } = await supabase.from("symptom_response").insert(responseRows);
  if (respErr) {
    Sentry.captureException(respErr);
    throw new AppError("response_insert_failed", respErr.message);
  }

  // Evaluate alert rules.
  const generatedAlerts = await evaluateRules(
    patientId,
    report.id,
    graded.map((g) => ({
      term_id: g.term_id,
      pro_ctcae_code: g.pro_ctcae_code,
      composite_grade: g.composite_grade,
      body_location: g.body_location,
    })),
  );

  let alertsCreated = 0;
  if (generatedAlerts.length > 0) {
    const alertRows = generatedAlerts.map((a) => ({
      patient_id: a.patient_id,
      report_id: report.id,
      rule_id: a.rule_id,
      severity_level: a.severity_level,
    }));
    const { error: alertErr } = await supabase.from("symptom_alert").insert(alertRows);
    if (alertErr) {
      Sentry.captureException(alertErr);
    } else {
      alertsCreated = alertRows.length;
    }
  }

  // Evaluate escalation policies (ALRT-06) — routes notifications based on
  // severity, time of day, and target role. Falls back to default caregiver
  // notify if no custom policies are configured.
  if (alertsCreated > 0) {
    try {
      const alertInfos = generatedAlerts.map((a) => ({
        id: a.rule_id,
        severity_level: a.severity_level,
      }));
      const symptomCodes = responses.map((r) => r.pro_ctcae_code);
      await evaluateEscalation(patientId, alertInfos, symptomCodes);
    } catch (notifErr) {
      Sentry.captureException(notifErr);
    }
  }

  // Detect worsening vs 7-day rolling baseline.
  let worsening: Awaited<ReturnType<typeof detectWorsening>> = [];
  try {
    worsening = await detectWorsening(patientId);
  } catch (e) {
    Sentry.captureException(e);
  }

  // Severe symptom guidance.
  const severeTerms = graded.filter((g) => g.composite_grade === 3);
  const severe = severeTerms.map((g) => ({
    term_code: g.pro_ctcae_code,
    body_location: g.body_location,
  }));

  const emergencyGuidance =
    severeTerms.length > 0
      ? {
          title: EMERGENCY_GUIDANCE.title,
          body: `You reported severe ${severeTerms.map((g) => g.pro_ctcae_code).join(", ")}. ${EMERGENCY_GUIDANCE.body}`,
          callout: EMERGENCY_GUIDANCE.callout,
        }
      : null;

  return {
    reportId: report.id,
    responsesWritten: responseRows.length,
    severeResponses: severe,
    alertsCreated,
    worsening: worsening.filter((w) => w.direction === "worsened" || w.direction === "new"),
    emergencyGuidance,
  };
}

export class AppError extends Error {
  constructor(
    public code: string,
    message: string,
  ) {
    super(message);
    this.name = "AppError";
  }
}
