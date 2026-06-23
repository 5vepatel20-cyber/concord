// GET   /api/treatment/regimens/[id] — get a single regimen + meds.
// PATCH /api/treatment/regimens/[id] — update regimen fields.
// DELETE /api/treatment/regimens/[id] — delete a regimen.
//
// MED-03: Cyclical chemo schedules.

import { z } from "zod";
import { requireUser } from "../../../../_lib/auth.js";
import { serviceClient } from "../../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const PatchBody = z.object({
  name: z.string().min(1).max(300).optional(),
  description: z.string().max(2000).nullable().optional(),
  cycle_length_days: z.number().int().min(1).optional(),
  rest_days: z.number().int().min(0).optional(),
  total_cycles: z.number().int().min(1).optional(),
});

async function getRegimen(supabase: ReturnType<typeof serviceClient>, id: string, userId: string) {
  const { data, error } = await supabase
    .from("treatment_regimen")
    .select("*, medications:treatment_regimen_medication(*)")
    .eq("id", id)
    .single();

  if (error || !data) return null;
  if (data.patient_id !== userId) return null;
  return data;
}

export const GET = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const regimenId = ctx.params.id!;

  const supabase = serviceClient();
  const regimen = await getRegimen(supabase, regimenId, user.id);
  if (!regimen) {
    return corsedJsonError(req, 404, "not_found", "Regimen not found");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, regimen }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const PATCH = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const regimenId = ctx.params.id!;

  const supabase = serviceClient();
  const existing = await getRegimen(supabase, regimenId, user.id);
  if (!existing) {
    return corsedJsonError(req, 404, "not_found", "Regimen not found");
  }

  let body: z.infer<typeof PatchBody>;
  try {
    body = PatchBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const updates: Record<string, unknown> = {};
  if (body.name !== undefined) updates.name = body.name;
  if (body.description !== undefined) updates.description = body.description;
  if (body.cycle_length_days !== undefined) updates.cycle_length_days = body.cycle_length_days;
  if (body.rest_days !== undefined) updates.rest_days = body.rest_days;
  if (body.total_cycles !== undefined) updates.total_cycles = body.total_cycles;
  updates.updated_at = new Date().toISOString();

  const { data, error } = await supabase
    .from("treatment_regimen")
    .update(updates)
    .eq("id", ctx.params.id)
    .select("*, medications:treatment_regimen_medication(*)")
    .single();

  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "update_failed", error?.message ?? "update failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, regimen: data }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const DELETE = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const regimenId = ctx.params.id!;

  const supabase = serviceClient();
  const existing = await getRegimen(supabase, regimenId, user.id);
  if (!existing) {
    return corsedJsonError(req, 404, "not_found", "Regimen not found");
  }

  const { error: delErr } = await supabase
    .from("treatment_regimen")
    .delete()
    .eq("id", regimenId);

  if (delErr) {
    Sentry.captureException(delErr);
    return corsedJsonError(req, 500, "delete_failed", delErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
