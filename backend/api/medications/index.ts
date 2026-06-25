// GET  /api/medications        — list the caller's active (or all) medications.
// POST /api/medications        — create a new medication for the caller.
//
// Idempotency-Key is supported on POST (same contract as /api/symptoms/submit).
//
// Auth: Bearer JWT required. RLS lets active caregivers read the patient's
// meds; writes are patient-only. We use the service client and pass
// patient_id from the verified JWT, so the policy check happens implicitly
// when callers fall through to a userClient path later.

import { z } from "zod";
import { requireUser, jsonError } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = {
  runtime: "nodejs",
};

export const OPTIONS = (req: Request): Response => preflight(req);

const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9_\-:.]{8,128}$/;

// Schedule is intentionally flexible (jsonb). For the scaffold we accept:
//   { "frequency": "daily", "times": ["08:00", "20:00"] }
//   { "frequency": "weekly", "days": ["mon","wed"], "times": ["09:00"] }
//   { "frequency": "as_needed" }
// Validated with zod so garbage doesn't sneak in.
const Schedule = z
  .object({
    frequency: z.enum(["daily", "weekly", "as_needed"]),
    times: z.array(z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/)).optional(),
    days: z
      .array(z.enum(["mon", "tue", "wed", "thu", "fri", "sat", "sun"]))
      .optional(),
    notes: z.string().max(500).optional(),
  })
  .strict();

const CreateBody = z.object({
  display_name: z.string().min(1).max(200),
  dose: z.string().max(50).optional(),
  unit: z.string().max(20).optional(),
  route: z
    .enum(["oral", "iv", "sub_q", "topical", "inhaled", "other"])
    .default("oral"),
  schedule: Schedule.default({ frequency: "daily" }),
  rxnorm_code: z.string().max(40).optional(),
  source: z
    .enum(["manual", "healthkit", "document_extracted", "clinician"])
    .default("manual"),
  // MED-07: side-effects-to-watch notes.
  side_effects_watch: z.string().max(1000).optional(),
});

export const GET = async (req: Request): Promise<Response> => {
  initSentry();
  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const supabase = serviceClient();

  const url = new URL(req.url);
  const onlyActive = url.searchParams.get("active") !== "false";

  let query = supabase
    .from("medication")
    .select(
      "id, patient_id, rxnorm_code, display_name, dose, unit, route, schedule, source, active, created_at",
    )
    .eq("patient_id", user.id)
    .order("active", { ascending: false })
    .order("created_at", { ascending: false });
  if (onlyActive) query = query.eq("active", true);

  const { data, error } = await query;
  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "list_failed", error.message);
  }
  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, medications: data ?? [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const POST = async (req: Request): Promise<Response> => {
  initSentry();
  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const supabase = serviceClient();

  // Idempotency replay (same shape as /api/symptoms/submit).
  const idempotencyKeyRaw = req.headers.get("idempotency-key");
  const idempotencyKey =
    idempotencyKeyRaw && IDEMPOTENCY_KEY_RE.test(idempotencyKeyRaw)
      ? idempotencyKeyRaw
      : null;

  let body: z.infer<typeof CreateBody>;
  try {
    body = CreateBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(
      req,
      400,
      "bad_request",
      e instanceof Error ? e.message : "Invalid JSON body",
    );
  }

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

  const row = {
    patient_id: user.id,
    rxnorm_code: body.rxnorm_code ?? null,
    display_name: body.display_name,
    dose: body.dose ?? null,
    unit: body.unit ?? null,
    route: body.route,
    schedule: body.schedule,
    source: body.source,
    active: true,
    side_effects_watch: body.side_effects_watch ?? null,
  };
  const { data, error } = await supabase
    .from("medication")
    .insert(row)
    .select(
      "id, patient_id, rxnorm_code, display_name, dose, unit, route, schedule, source, active, created_at",
    )
    .single();
  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "insert_failed", error?.message ?? "insert failed");
  }

  const responseBody = { ok: true, medication: data };
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
