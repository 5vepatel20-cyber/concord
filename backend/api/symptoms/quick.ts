// POST /api/symptoms/quick — auth-required. One-tap symptom log.
// SYM-10: Accepts a single symptom + composite grade and creates a minimal
// report. The grade (0-3) is expanded into PRO-CTCAE severity/frequency
// attributes automatically so the patient doesn't need to fill out the full
// form for a quick check-in.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";
import { evaluateRules } from "../../_lib/alerts/rules.js";
import { detectWorsening } from "../../_lib/pro-ctcae/worsening.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const QuickSchema = z.object({
  responses: z
    .array(
      z.object({
        pro_ctcae_code: z.string().min(1).max(20),
        grade: z.number().int().min(0).max(3),
      }),
    )
    .min(1)
    .max(5),
  recall_window: z.enum(["now", "past_7_days"]).default("now"),
  free_text: z.string().max(1000).nullable().optional(),
});

/**
 * Expand a composite grade (0-3) into PRO-CTCAE attribute values.
 */
function gradeToAttributes(grade: number) {
  if (grade <= 0) return { presence: false, frequency: null, severity: null, interference: null, amount: null };
  return {
    presence: true,
    frequency: grade,
    severity: grade,
    interference: grade >= 2 ? grade - 1 : 0,
    amount: null,
  };
}

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof QuickSchema>;
  try {
    body = QuickSchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();
  const now = new Date().toISOString();

  // Resolve term codes to IDs.
  const codes = body.responses.map((r) => r.pro_ctcae_code);
  const { data: terms, error: termErr } = await supabase
    .from("symptom_term")
    .select("id, pro_ctcae_code")
    .in("pro_ctcae_code", codes);

  if (termErr) {
    Sentry.captureException(termErr);
    return corsedJsonError(req, 500, "term_lookup_failed", termErr.message);
  }

  const termIdByCode = new Map((terms ?? []).map((t) => [t.pro_ctcae_code, t.id]));

  // Create the symptom report.
  const { data: report, error: repErr } = await supabase
    .from("symptom_report")
    .insert({
      patient_id: user.id,
      reported_at: now,
      recall_window: body.recall_window,
      source: "self",
      free_text: body.free_text ?? null,
    })
    .select("id")
    .single();

  if (repErr) {
    Sentry.captureException(repErr);
    return corsedJsonError(req, 500, "report_insert_failed", repErr.message);
  }

  // Create symptom responses.
  const responses = body.responses.map((r) => {
    const attrs = gradeToAttributes(r.grade);
    const termId = termIdByCode.get(r.pro_ctcae_code);
    return {
      report_id: report.id,
      term_id: termId ?? r.pro_ctcae_code,
      composite_grade: r.grade,
      frequency: attrs.frequency,
      severity: attrs.severity,
      interference: attrs.interference,
      presence: attrs.presence,
      amount: attrs.amount,
      body_location: null,
    };
  });

  const { error: resErr } = await supabase
    .from("symptom_response")
    .insert(responses);

  if (resErr) {
    Sentry.captureException(resErr);
    return corsedJsonError(req, 500, "response_insert_failed", resErr.message);
  }

  // Evaluate alert rules (best-effort).
  let emergencyGuidance: string | null = null;
  try {
    const result = await evaluateRules({ patientId: user.id, responses });
    if (result.emergency) {
      emergencyGuidance = `${result.emergency.title}\n\n${result.emergency.body}`;
      if (result.emergency.callout) emergencyGuidance += `\n\n${result.emergency.callout}`;
    }
  } catch {
    // Best-effort.
  }

  // Detect worsening (best-effort).
  let worsening: unknown[] = [];
  try {
    worsening = await detectWorsening({ patientId: user.id, responses });
  } catch {
    // Best-effort.
  }

  return corsed(
    req,
    new Response(
      JSON.stringify({
        ok: true,
        report_id: report.id,
        emergency_guidance: emergencyGuidance ? { title: "Quick alert", body: emergencyGuidance, callout: null } : null,
        worsening,
      }),
      { status: 201, headers: { "content-type": "application/json" } },
    ),
  );
};
