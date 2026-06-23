// POST /api/symptoms/caregiver-submit — auth-required. Allows a verified
// caregiver to log symptoms on behalf of a patient (SYM-08).
//
// The caller must have an active care_relationship with the target patient
// that includes the `proxy_logging` permission.
//
// Delegates scoring, alert evaluation, and worsening detection to the
// shared createSymptomReport() helper.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";
import { createSymptomReport, AppError, ResponseSchema } from "../../_lib/symptoms/submit-report.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9_\-:.]{8,128}$/;

const Body = z.object({
  patient_id: z.string().uuid(),
  recall_window: z.enum(["now", "past_7_days"]).default("now"),
  free_text: z.string().max(4000).nullable().optional(),
  responses: z.array(ResponseSchema).min(1).max(20),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const caregiver = userOrError;

  const idempotencyKeyRaw = req.headers.get("idempotency-key");
  const idempotencyKey =
    idempotencyKeyRaw && IDEMPOTENCY_KEY_RE.test(idempotencyKeyRaw)
      ? idempotencyKeyRaw
      : null;

  let body: z.infer<typeof Body>;
  try {
    body = Body.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  // Idempotency replay.
  if (idempotencyKey) {
    const { data: cached, error: cacheErr } = await supabase
      .from("idempotency_keys")
      .select("status_code, response_body")
      .eq("user_id", caregiver.id)
      .eq("key", idempotencyKey)
      .maybeSingle();
    if (cacheErr) {
      Sentry.captureException(cacheErr);
    } else if (cached) {
      return corsed(
        req,
        new Response(JSON.stringify(cached.response_body), {
          status: cached.status_code,
          headers: { "content-type": "application/json", "idempotent-replay": "true" },
        }),
      );
    }
  }

  // Verify caregiver relationship: caller must be an active caregiver for
  // the specified patient with proxy_logging permission.
  const { data: rel, error: relErr } = await supabase
    .from("care_relationship")
    .select("id, permissions")
    .eq("patient_id", body.patient_id)
    .eq("member_user_id", caregiver.id)
    .eq("status", "active")
    .maybeSingle();

  if (relErr) {
    Sentry.captureException(relErr);
    return corsedJsonError(req, 500, "lookup_failed", relErr.message);
  }
  if (!rel) {
    return corsedJsonError(req, 403, "not_caregiver", "You are not an active caregiver for this patient");
  }

  const permissions = (rel.permissions as Record<string, boolean>) ?? {};
  if (!permissions["can_log"]) {
    return corsedJsonError(req, 403, "permission_denied", "Your care relationship does not include symptom logging permission");
  }

  // Proceed with report creation on behalf of the patient.
  let result;
  try {
    result = await createSymptomReport({
      supabase,
      patientId: body.patient_id,
      recallWindow: body.recall_window,
      source: "caregiver",
      freeText: body.free_text ?? null,
      responses: body.responses,
    });
  } catch (e) {
    if (e instanceof AppError) {
      return corsedJsonError(req, 400, e.code, e.message);
    }
    Sentry.captureException(e);
    return corsedJsonError(req, 500, "internal", e instanceof Error ? e.message : String(e));
  }

  const responseBody: Record<string, unknown> = {
    ok: true,
    report_id: result.reportId,
    responses_written: result.responsesWritten,
    severe_responses: result.severeResponses,
    alerts_created: result.alertsCreated,
    worsening: result.worsening,
    emergency_guidance: result.emergencyGuidance,
    logged_by: caregiver.id,
  };

  if (idempotencyKey) {
    const { error: cacheWriteErr } = await supabase
      .from("idempotency_keys")
      .insert({
        user_id: caregiver.id,
        key: idempotencyKey,
        status_code: 201,
        response_body: responseBody,
      });
    if (cacheWriteErr && !String(cacheWriteErr.message).includes("duplicate")) {
      Sentry.captureException(cacheWriteErr);
    }
  }

  return corsed(
    req,
    new Response(JSON.stringify(responseBody, null, 2), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
