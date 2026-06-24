import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };

export const OPTIONS = (req: Request): Response => preflight(req);

const BodySchema = z.object({
  full_name: z.string().min(1).max(200),
  date_of_birth: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  sex_at_birth: z.enum(["female", "male", "intersex", "prefer_not_to_say"]),
  primary_diagnosis_id: z.string().uuid(),
  diagnosis_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  cancer_stage: z.string().max(20).optional(),
  treatment_status: z.enum(["active_treatment", "surveillance", "remission", "palliative"]),
  regimen_name: z.string().max(200).optional(),
  consent_version: z.string().min(1),
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

  const { error: userErr } = await supabase
    .from("user")
    .update({
      full_name: body.full_name,
      date_of_birth: body.date_of_birth,
      sex_at_birth: body.sex_at_birth,
    })
    .eq("id", user.id);

  if (userErr) {
    return corsedJsonError(req, 500, "user_update_failed", userErr.message);
  }

  const { error: profileErr } = await supabase
    .from("patient_profile")
    .upsert({
      user_id: user.id,
      primary_diagnosis_id: body.primary_diagnosis_id,
      diagnosis_date: body.diagnosis_date ?? null,
      cancer_stage: body.cancer_stage ?? null,
      treatment_status: body.treatment_status,
      regimen_name: body.regimen_name ?? null,
    }, { onConflict: "user_id" });

  if (profileErr) {
    return corsedJsonError(req, 500, "profile_upsert_failed", profileErr.message);
  }

  const { error: consentErr } = await supabase
    .from("user_consent")
    .insert({
      user_id: user.id,
      consent_version: body.consent_version,
    });

  if (consentErr) {
    return corsedJsonError(req, 500, "consent_save_failed", consentErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, user_id: user.id }, null, 2), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
