// GET /api/caregiver/relationships — auth-required. Lists care relationships
// for the current user. Patients see their caregivers; caregivers see their
// linked patients.
//
// CARE-01: Caregiver accounts + permission scopes.

import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const supabase = serviceClient();

  // Relationships where user is patient.
  const { data: asPatient, error: patientErr } = await supabase
    .from("care_relationship")
    .select(`
      id,
      relationship,
      permissions,
      status,
      created_at,
      member:member_user_id(id, email, full_name)
    `)
    .eq("patient_id", user.id)
    .order("created_at", { ascending: false });

  if (patientErr) {
    Sentry.captureException(patientErr);
    return corsedJsonError(req, 500, "fetch_failed", patientErr.message);
  }

  // Relationships where user is caregiver.
  const { data: asCaregiver, error: caregiverErr } = await supabase
    .from("care_relationship")
    .select(`
      id,
      relationship,
      permissions,
      status,
      created_at,
      patient:patient_id(id, email, full_name)
    `)
    .eq("member_user_id", user.id)
    .eq("status", "active")
    .order("created_at", { ascending: false });

  if (caregiverErr) {
    Sentry.captureException(caregiverErr);
    return corsedJsonError(req, 500, "fetch_failed", caregiverErr.message);
  }

  return corsed(
    req,
    new Response(
      JSON.stringify({
        ok: true,
        as_patient: asPatient ?? [],
        as_caregiver: asCaregiver ?? [],
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    ),
  );
};
