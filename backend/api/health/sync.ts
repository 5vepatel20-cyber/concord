// POST /api/health/sync — auth-required. Accepts a batch of daily health
// metric samples and persists them to health_metric_sample.
//
// HK-02: Persist daily aggregates server-side so clinician dashboards and
// reports can reference vitals trends without an on-device fetch.
//
// The client sends one or more samples with type, value, unit, and date.
// The server upserts by (patient_id, type, measured_at::date) — only the
// latest value per metric per day is kept.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const MetricType = z.enum([
  "steps", "sleep", "hr", "bp_sys", "bp_dia", "glucose", "calories", "weight",
]);

const SampleSchema = z.object({
  type: MetricType,
  value: z.number(),
  unit: z.string().min(1).max(20),
  measured_at: z.string().datetime(),
});

const BodySchema = z.object({
  samples: z.array(SampleSchema).min(1).max(30),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof BodySchema>;
  try {
    body = BodySchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  let upserted = 0;
  for (const sample of body.samples) {
    const measuredDate = sample.measured_at.slice(0, 10);

    // Upsert: delete existing row for this patient/type/date, then insert.
    // This avoids unique-constraint gymnastics and keeps code simple.
    const { error: delErr } = await supabase
      .from("health_metric_sample")
      .delete()
      .eq("patient_id", user.id)
      .eq("type", sample.type)
      .gte("measured_at", `${measuredDate}T00:00:00Z`)
      .lt("measured_at", `${measuredDate}T23:59:59Z`);

    if (delErr) {
      Sentry.captureException(delErr);
      continue;
    }

    const { error: insErr } = await supabase
      .from("health_metric_sample")
      .insert({
        patient_id: user.id,
        type: sample.type,
        value: sample.value,
        unit: sample.unit,
        measured_at: sample.measured_at,
        source: "healthkit",
      });

    if (insErr) {
      Sentry.captureException(insErr);
      continue;
    }
    upserted++;
  }

  return corsed(
    req,
    new Response(JSON.stringify({
      ok: true,
      samples_received: body.samples.length,
      samples_upserted: upserted,
    }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
