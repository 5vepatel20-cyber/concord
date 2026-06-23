// POST /api/caregiver/revoke — auth-required. Patient revokes a caregiver
// relationship. Sets status to 'revoked'.
//
// CARE-01: Caregiver accounts + permission scopes.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const Body = z.object({
  relationship_id: z.string().uuid(),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof Body>;
  try {
    body = Body.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  // Verify the relationship exists and belongs to this patient.
  const { data: rel, error: fetchErr } = await supabase
    .from("care_relationship")
    .select("id, status")
    .eq("id", body.relationship_id)
    .eq("patient_id", user.id)
    .maybeSingle();

  if (fetchErr) {
    Sentry.captureException(fetchErr);
    return corsedJsonError(req, 500, "fetch_failed", fetchErr.message);
  }

  if (!rel) {
    return corsedJsonError(req, 404, "not_found", "Relationship not found");
  }

  if (rel.status === "revoked") {
    return corsedJsonError(req, 409, "already_revoked", "This relationship is already revoked");
  }

  const { error: updateErr } = await supabase
    .from("care_relationship")
    .update({ status: "revoked" })
    .eq("id", body.relationship_id);

  if (updateErr) {
    Sentry.captureException(updateErr);
    return corsedJsonError(req, 500, "revoke_failed", updateErr.message);
  }

  return corsed(
    req,
    new Response(
      JSON.stringify({ ok: true, relationship_id: body.relationship_id, status: "revoked" }),
      { status: 200, headers: { "content-type": "application/json" } },
    ),
  );
};
