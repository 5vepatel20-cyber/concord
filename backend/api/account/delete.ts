// POST /api/account/delete — auth-required. Permanently deletes the user's
// account and all associated data. This action is irreversible.
//
// SEC-11: Full account deletion. The patient must confirm by sending
// { "confirmation": "DELETE" }. All user data is cascaded via FK on delete
// from auth.users → public.user → all child tables.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const DeleteSchema = z.object({
  confirmation: z.literal("DELETE"),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof DeleteSchema>;
  try {
    body = DeleteSchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(
      req,
      400,
      "bad_request",
      'Send {"confirmation":"DELETE"} to confirm.',
    );
  }

  const supabase = serviceClient();

  // Delete from auth.users — cascades to public.user and all child tables.
  const { error } = await supabase.auth.admin.deleteUser(user.id);
  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "delete_failed", error.message);
  }

  return corsed(
    req,
    new Response(
      JSON.stringify({ ok: true, message: "Account permanently deleted." }),
      {
        status: 200,
        headers: { "content-type": "application/json" },
      },
    ),
  );
};
