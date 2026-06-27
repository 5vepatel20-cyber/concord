// POST /api/waitlist/subscribe — public, no auth.
// Called from the landing page EmailCapture component.
// Validates email, inserts into the waitlist table (deduped by lower(email)),
// and returns a success response.
//
// Idempotent: duplicate emails return 200 (already on list) rather than 409.

import { z } from "zod";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };

export const OPTIONS = (req: Request): Response => preflight(req);

const BodySchema = z.object({
  email: z.string().email().max(320),
  source: z.string().max(100).optional(),
  referred_from: z.string().max(500).optional(),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  let body: z.infer<typeof BodySchema>;
  try {
    body = BodySchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  // Upsert on lower(email) — if the row already exists this is a no-op.
  const { error } = await supabase.from("waitlist").upsert(
    {
      email: body.email.toLowerCase(),
      source: body.source ?? "landing",
      referred_from: body.referred_from ?? null,
    },
    {
      onConflict: "email",
      ignoreDuplicates: true,
    },
  );

  if (error) {
    return corsedJsonError(req, 500, "waitlist_save_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true }, null, 2), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
