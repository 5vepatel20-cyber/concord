// POST /api/conditions/select — auth-required. Sets the patient's primary
// diagnosis (condition) in patient_profile. Used post-onboarding when the
// user changes their condition from the profile screen.
//
// ONB-01: Coded condition selection.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const BodySchema = z.object({
  condition_id: z.string().uuid(),
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

  // Verify the condition exists.
  const { data: condition, error: condErr } = await supabase
    .from("condition")
    .select("id")
    .eq("id", body.condition_id)
    .maybeSingle();

  if (condErr) {
    Sentry.captureException(condErr);
    return corsedJsonError(req, 500, "lookup_failed", condErr.message);
  }
  if (!condition) {
    return corsedJsonError(req, 404, "condition_not_found", "No such condition.");
  }

  const { error: upsertErr } = await supabase
    .from("patient_profile")
    .upsert({
      user_id: user.id,
      primary_diagnosis_id: body.condition_id,
    }, { onConflict: "user_id" });

  if (upsertErr) {
    Sentry.captureException(upsertErr);
    return corsedJsonError(req, 500, "profile_update_failed", upsertErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
