// GET  /api/treatment/regimens — list patient's chemo regimens.
// POST /api/treatment/regimens — create a new regimen template.
//
// MED-03: Cyclical chemo schedules.

import { z } from "zod";
import { requireUser } from "../../../_lib/auth.js";
import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const CreateRegimenBody = z.object({
  name: z.string().min(1).max(300),
  description: z.string().max(2000).nullable().optional(),
  cycle_length_days: z.number().int().min(1),
  rest_days: z.number().int().min(0).default(0),
  total_cycles: z.number().int().min(1),
  medications: z.array(
    z.object({
      medication_name: z.string().min(1),
      rxnorm_cui: z.string().nullable().optional(),
      dose: z.string().nullable().optional(),
      unit: z.string().nullable().optional(),
      route: z.string().nullable().optional(),
      day_within_cycle: z.number().int().min(1).default(1),
      notes: z.string().nullable().optional(),
    }),
  ).optional().default([]),
});

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const supabase = serviceClient();
  const { data, error } = await supabase
    .from("treatment_regimen")
    .select("*, medications:treatment_regimen_medication(*)")
    .eq("patient_id", user.id)
    .order("created_at", { ascending: false });

  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "fetch_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, regimens: data ?? [] }), {
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

  let body: z.infer<typeof CreateRegimenBody>;
  try {
    body = CreateRegimenBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const supabase = serviceClient();

  const { data: regimen, error: insertErr } = await supabase
    .from("treatment_regimen")
    .insert({
      patient_id: user.id,
      name: body.name,
      description: body.description ?? null,
      cycle_length_days: body.cycle_length_days,
      rest_days: body.rest_days,
      total_cycles: body.total_cycles,
    })
    .select("*")
    .single();

  if (insertErr || !regimen) {
    Sentry.captureException(insertErr);
    return corsedJsonError(req, 500, "insert_failed", insertErr?.message ?? "insert failed");
  }

  if (body.medications.length > 0) {
    const medRows = body.medications.map((m) => ({
      regimen_id: regimen.id,
      medication_name: m.medication_name,
      rxnorm_cui: m.rxnorm_cui ?? null,
      dose: m.dose ?? null,
      unit: m.unit ?? null,
      route: m.route ?? null,
      day_within_cycle: m.day_within_cycle,
      notes: m.notes ?? null,
    }));

    const { error: medErr } = await supabase
      .from("treatment_regimen_medication")
      .insert(medRows);

    if (medErr) {
      Sentry.captureException(medErr);
    }
  }

  const { data: full, error: fetchErr } = await supabase
    .from("treatment_regimen")
    .select("*, medications:treatment_regimen_medication(*)")
    .eq("id", regimen.id)
    .single();

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, regimen: full ?? regimen }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
