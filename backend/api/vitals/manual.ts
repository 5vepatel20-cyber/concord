// POST /api/vitals/manual — auth-required. Accepts a single manual vitals
// reading (weight, BP, heart rate, glucose) and persists to
// health_metric_sample with source="manual".
//
// HK-03: Manual vitals entry for patients without HealthKit / Health Connect.
// Unlike POST /api/health/sync (which takes a batch for HK-02), this
// endpoint takes one form submission at a time and returns the saved rows.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const BodySchema = z.object({
  measured_at: z.string().datetime().optional(),
  weight_kg: z.number().min(10).max(500).optional(),
  bp_sys: z.number().int().min(50).max(300).optional(),
  bp_dia: z.number().int().min(30).max(200).optional(),
  heart_rate: z.number().int().min(20).max(350).optional(),
  glucose_mgdl: z.number().int().min(10).max(1000).optional(),
  notes: z.string().max(500).optional(),
}).refine(
  (d) => d.weight_kg != null || d.bp_sys != null || d.bp_dia != null || d.heart_rate != null || d.glucose_mgdl != null,
  { message: "At least one vitals field must be provided." },
);

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
  const now = body.measured_at ?? new Date().toISOString();
  const datePrefix = now.slice(0, 10);
  const saved: { type: string; value: number; unit: string }[] = [];
  let errorCount = 0;

  const upsert = async (type: string, value: number, unit: string) => {
    // Delete existing for this patient/type/date, then insert.
    const { error: delErr } = await supabase
      .from("health_metric_sample")
      .delete()
      .eq("patient_id", user.id)
      .eq("type", type)
      .gte("measured_at", `${datePrefix}T00:00:00Z`)
      .lt("measured_at", `${datePrefix}T23:59:59Z`);

    if (delErr) {
      Sentry.captureException(delErr);
      errorCount++;
      return;
    }

    const { error: insErr } = await supabase
      .from("health_metric_sample")
      .insert({
        patient_id: user.id,
        type,
        value,
        unit,
        measured_at: now,
        source: "manual",
      });

    if (insErr) {
      Sentry.captureException(insErr);
      errorCount++;
      return;
    }
    saved.push({ type, value, unit });
  };

  const promises: Promise<void>[] = [];

  if (body.weight_kg != null) promises.push(upsert("weight", body.weight_kg, "kg"));
  if (body.bp_sys != null) promises.push(upsert("bp_sys", body.bp_sys, "mmHg"));
  if (body.bp_dia != null) promises.push(upsert("bp_dia", body.bp_dia, "mmHg"));
  if (body.heart_rate != null) promises.push(upsert("hr", body.heart_rate, "bpm"));
  if (body.glucose_mgdl != null) promises.push(upsert("glucose", body.glucose_mgdl, "mg/dL"));

  await Promise.allSettled(promises);

  // Save notes separately (not part of health_metric_sample).
  if (body.notes != null && body.notes.trim().length > 0 && saved.length > 0) {
    await supabase
      .from("health_metric_sample")
      .update({ notes: body.notes.trim() })
      .eq("patient_id", user.id)
      .eq("type", saved[0]!.type)
      .gte("measured_at", `${datePrefix}T00:00:00Z`)
      .lt("measured_at", `${datePrefix}T23:59:59Z`);
  }

  return corsed(
    req,
    new Response(JSON.stringify({
      ok: true,
      saved,
      errors: errorCount,
      measured_at: now,
    }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
