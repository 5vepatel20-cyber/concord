// POST /api/trials/save — auth-required. Save or update a trial match.
// Body: { nct_id: string, status?: "saved" | "dismissed" }
//
// TRIAL-02/03: Persist trial_match rows for save/track lifecycle.
// Default status is "saved". Send status="dismissed" to dismiss.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const SaveSchema = z.object({
  nct_id: z.string().min(1).max(20),
  status: z.enum(["saved", "dismissed"]).default("saved"),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof SaveSchema>;
  try {
    body = SaveSchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const supabase = serviceClient();

  const { error } = await supabase.from("trial_match").upsert(
    {
      patient_id: user.id,
      nct_id: body.nct_id,
      status: body.status,
    },
    { onConflict: "patient_id, nct_id" },
  );

  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "save_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
