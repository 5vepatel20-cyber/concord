// PATCH /api/medications/:id — update a medication (deactivate, edit).
//
// Currently supports deactivation (active: false). Extend with other
// fields as needed.
//
// Auth: Bearer JWT required. Patient can only update their own meds.
// Caregivers can read but not write.

import { z } from "zod";
import { requireUser } from "../../../_lib/auth.js";
import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = { runtime: "nodejs" };

export const OPTIONS = (req: Request): Response => preflight(req);

const UpdateBody = z.object({
  active: z.boolean().optional(),
  display_name: z.string().min(1).max(200).optional(),
  dose: z.string().max(50).optional(),
  unit: z.string().max(20).optional(),
  route: z
    .enum(["oral", "iv", "sub_q", "topical", "inhaled", "other"])
    .optional(),
});

export const PATCH = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const supabase = serviceClient();

  const medicationId = req.url.split("/").at(-1) ?? "";
  if (!medicationId) {
    return corsedJsonError(req, 400, "bad_request", "Missing medication id");
  }

  let body: z.infer<typeof UpdateBody>;
  try {
    body = UpdateBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(
      req, 400, "bad_request",
      e instanceof Error ? e.message : "Invalid JSON body",
    );
  }

  // Verify the medication belongs to this patient.
  const { data: existing, error: fetchErr } = await supabase
    .from("medication")
    .select("id, patient_id")
    .eq("id", medicationId)
    .single();

  if (fetchErr || !existing) {
    return corsedJsonError(req, 404, "not_found", "Medication not found");
  }
  if (existing.patient_id !== user.id) {
    return corsedJsonError(req, 403, "forbidden", "Not your medication");
  }

  const { data, error } = await supabase
    .from("medication")
    .update(body)
    .eq("id", medicationId)
    .select("id, patient_id, rxnorm_code, display_name, dose, unit, route, schedule, source, active, created_at")
    .single();

  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "update_failed", error?.message ?? "Update failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, medication: data }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
