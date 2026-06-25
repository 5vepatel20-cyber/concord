// POST /api/symptoms/submit — auth-required. Accepts a symptom report with
// one or more structured responses, grades them via the PRO-CTCAE scorer,
// and persists to Postgres. This is the SYM-04 + SYM-09 wired endpoint.
//
// Idempotency:
//   Clients SHOULD send an `Idempotency-Key` header (UUID). When present,
//   the server caches the response for 24h keyed by (user_id, key) and
//   replays it on retry instead of creating a second report. This makes
//   the offline-queue retry path safe: a network blip right after the
//   server writes but before the client receives 201 will not double-log.
//
// SYM-08: Caregiver proxy logging uses POST /api/symptoms/caregiver-submit
// which also delegates to the same shared helper.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { logAudit } from "../../_lib/audit.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";
import { createSymptomReport, AppError, ResponseSchema } from "../../_lib/symptoms/submit-report.js";

export const config = {
  runtime: "nodejs",
};

export const OPTIONS = (req: Request): Response => preflight(req);

const Body = z.object({
  recall_window: z.enum(["now", "past_7_days"]).default("now"),
  source: z.enum(["self", "caregiver", "voice"]).default("self"),
  free_text: z.string().max(4000).nullable().optional(),
  responses: z.array(ResponseSchema).min(1).max(20),
});

const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9_\-:.]{8,128}$/;

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

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
      .eq("user_id", user.id)
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

  let result;
  try {
    result = await createSymptomReport({
      supabase,
      patientId: user.id,
      recallWindow: body.recall_window,
      source: body.source,
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
  };

  // Cache idempotency key.
  if (idempotencyKey) {
    const { error: cacheWriteErr } = await supabase
      .from("idempotency_keys")
      .insert({
        user_id: user.id,
        key: idempotencyKey,
        status_code: 201,
        response_body: responseBody,
      });
    if (cacheWriteErr && !String(cacheWriteErr.message).includes("duplicate")) {
      Sentry.captureException(cacheWriteErr);
    }
  }

  // SEC-06: Audit log the symptom report submission.
  await logAudit(supabase, {
    patientId: user.id,
    actorId: user.id,
    action: "symptom_report.submit",
    entityType: "symptom_report",
    entityId: result.reportId,
    details: {
      responses_written: result.responsesWritten,
      alerts_created: result.alertsCreated,
      worsening: result.worsening,
    },
  });

  return corsed(
    req,
    new Response(JSON.stringify(responseBody, null, 2), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
