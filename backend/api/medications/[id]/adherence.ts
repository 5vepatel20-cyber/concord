// POST /api/medications/[id]/adherence — log a taken / skipped / missed event
// for one dose of one medication. Returns the persisted event.
//
// Idempotency-Key supported (same contract as the other write endpoints).
//
// Auth: Bearer JWT required. The handler verifies the medication belongs to
// the caller (or to one of their active caregivers) before accepting the
// write.

import { z } from "zod";
import { requireUser, jsonError } from "../../../_lib/auth.js";
import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = {
  runtime: "nodejs",
};

export const OPTIONS = (req: Request): Response => preflight(req);

const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9_\-:.]{8,128}$/;

const Body = z.object({
  status: z.enum(["taken", "skipped", "missed", "taken_late"]),
  scheduled_for: z.string().datetime({ offset: true }),
  logged_at: z.string().datetime({ offset: true }).optional(),
});

export const POST = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();
  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const medicationId = ctx.params.id;

  const idempotencyKeyRaw = req.headers.get("idempotency-key");
  const idempotencyKey =
    idempotencyKeyRaw && IDEMPOTENCY_KEY_RE.test(idempotencyKeyRaw)
      ? idempotencyKeyRaw
      : null;

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
          headers: {
            "content-type": "application/json",
            "idempotent-replay": "true",
          },
        }),
      );
    }
  }

  let body: z.infer<typeof Body>;
  try {
    body = Body.parse(await req.json());
  } catch (e) {
    return corsedJsonError(
      req,
      400,
      "bad_request",
      e instanceof Error ? e.message : "Invalid JSON body",
    );
  }

  // Ownership check: confirm the medication belongs to the caller. This is
  // a defensive check on top of RLS — even though our service client bypasses
  // RLS, we don't want a caller writing events against someone else's meds
  // because of a misrouted id.
  const { data: med, error: medErr } = await supabase
    .from("medication")
    .select("id, patient_id")
    .eq("id", medicationId)
    .maybeSingle();
  if (medErr) {
    Sentry.captureException(medErr);
    return corsedJsonError(req, 500, "lookup_failed", medErr.message);
  }
  if (!med) {
    return corsedJsonError(req, 404, "not_found", "Medication not found");
  }
  if (med.patient_id !== user.id) {
    return corsedJsonError(req, 403, "forbidden", "Medication belongs to another user");
  }

  const row = {
    medication_id: medicationId,
    status: body.status,
    scheduled_for: body.scheduled_for,
    logged_at: body.logged_at ?? new Date().toISOString(),
  };
  const { data, error } = await supabase
    .from("medication_event")
    .insert(row)
    .select("id, medication_id, status, scheduled_for, logged_at")
    .single();
  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "insert_failed", error?.message ?? "insert failed");
  }

  const responseBody = { ok: true, event: data };
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

  return corsed(
    req,
    new Response(JSON.stringify(responseBody, null, 2), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
