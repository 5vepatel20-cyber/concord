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

import { z } from "zod";
import { requireUser, jsonError } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { compositeGrade, type Grade } from "../../_lib/pro-ctcae/scorer.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";

export const config = {
  runtime: "nodejs",
};

// 0-4 integer attributes; 0/1 for presence; null = "not asked".
const Attr = z.number().int().min(0).max(4).nullable();
const Body = z.object({
  recall_window: z.enum(["now", "past_7_days"]).default("now"),
  source: z.enum(["self", "caregiver", "voice"]).default("self"),
  free_text: z.string().max(4000).nullable().optional(),
  responses: z
    .array(
      z.object({
        pro_ctcae_code: z.string().min(1).max(20),
        frequency: Attr.optional(),
        severity: Attr.optional(),
        interference: Attr.optional(),
        presence: z.boolean().nullable().optional(),
        amount: Attr.optional(),
        body_location: z.string().max(200).nullable().optional(),
      }),
    )
    .min(1)
    .max(20),
});

const IDEMPOTENCY_KEY_RE = /^[A-Za-z0-9_\-:.]{8,128}$/;

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return userOrError;
  const user = userOrError;

  // Idempotency-Key: optional but recommended. Format is permissive enough
  // for UUIDs and most client-generated tokens; reject anything that smells
  // like an injection attempt (whitespace, quotes, length).
  const idempotencyKeyRaw = req.headers.get("idempotency-key");
  const idempotencyKey =
    idempotencyKeyRaw && IDEMPOTENCY_KEY_RE.test(idempotencyKeyRaw)
      ? idempotencyKeyRaw
      : null;

  let body: z.infer<typeof Body>;
  try {
    body = Body.parse(await req.json());
  } catch (e) {
    return jsonError(400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  // Replay cached response if the client retried with the same key.
  if (idempotencyKey) {
    const { data: cached, error: cacheErr } = await supabase
      .from("idempotency_keys")
      .select("status_code, response_body")
      .eq("user_id", user.id)
      .eq("key", idempotencyKey)
      .maybeSingle();
    if (cacheErr) {
      // Don't fail the request on a cache lookup error — fall through and
      // do the write. Worst case we get a duplicate, which is recoverable.
      Sentry.captureException(cacheErr);
    } else if (cached) {
      return new Response(JSON.stringify(cached.response_body), {
        status: cached.status_code,
        headers: {
          "content-type": "application/json",
          "idempotent-replay": "true",
        },
      });
    }
  }

  // Resolve term codes → term ids. One round-trip.
  const codes = body.responses.map((r) => r.pro_ctcae_code);
  const { data: terms, error: termsErr } = await supabase
    .from("symptom_term")
    .select("id, pro_ctcae_code")
    .in("pro_ctcae_code", codes);
  if (termsErr) {
    Sentry.captureException(termsErr);
    return jsonError(500, "term_lookup_failed", termsErr.message);
  }
  const codeToId = new Map(terms?.map((t) => [t.pro_ctcae_code, t.id] as const) ?? []);
  for (const code of codes) {
    if (!codeToId.has(code)) {
      return jsonError(400, "unknown_term", `Unknown PRO-CTCAE code: ${code}`);
    }
  }

  // Compute grades server-side — never trust the client.
  const graded = body.responses.map((r) => {
    const grade: Grade = compositeGrade({
      frequency: r.frequency ?? null,
      severity: r.severity ?? null,
      interference: r.interference ?? null,
      presence: r.presence ?? null,
      amount: r.amount ?? null,
    });
    return { ...r, composite_grade: grade, term_id: codeToId.get(r.pro_ctcae_code)! };
  });

  // Insert the report, then the responses.
  const { data: report, error: reportErr } = await supabase
    .from("symptom_report")
    .insert({
      patient_id: user.id,
      recall_window: body.recall_window,
      source: body.source,
      free_text: body.free_text ?? null,
      reported_at: new Date().toISOString(),
    })
    .select("id")
    .single();
  if (reportErr || !report) {
    Sentry.captureException(reportErr);
    return jsonError(500, "report_insert_failed", reportErr?.message ?? "insert failed");
  }

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
    return jsonError(500, "response_insert_failed", respErr.message);
  }

  // ALRT-03 (patient-side safety guidance): if any response graded Severe (3),
  // surface a guidance block. The patient sees this in the app; clinicians see
  // it in the alert inbox (Phase 2).
  const severe = graded
    .filter((g) => g.composite_grade === 3)
    .map((g) => ({ term_code: g.pro_ctcae_code, body_location: g.body_location }));

  const responseBody = {
    ok: true,
    report_id: report.id,
    responses_written: responseRows.length,
    severe_responses: severe,
    guidance: severe.length > 0 ? EMERGENCY_GUIDANCE : null,
  };

  // Cache the response so a retry replays it instead of double-writing.
  // We swallow any cache-write error — duplicates are recoverable, but
  // never block the original write.
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

  return new Response(JSON.stringify(responseBody, null, 2), {
    status: 201,
    headers: { "content-type": "application/json" },
  });
};

const EMERGENCY_GUIDANCE = {
  title: "This sounds like it may need urgent attention",
  body: "Based on what you logged, please contact your oncology care team now. If you can't reach them and you're feeling very unwell, call 911 or your local emergency number.",
  callout: "Concord is not a medical device. This guidance is informational, not a diagnosis.",
};
