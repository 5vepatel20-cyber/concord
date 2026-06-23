// POST /api/reports/share — auth-required. Creates a secure expiring link
// for a generated report. The link can be shared with a clinician or family
// member who does not have a Concord account.
//
// RPT-06: Share-to-clinician (secure link tracking).

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const Body = z.object({
  report_id: z.string().uuid(),
  expires_in_days: z.number().int().min(1).max(30).default(7),
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

  // Verify the report exists and belongs to this patient.
  const { data: report, error: reportErr } = await supabase
    .from("report")
    .select("id")
    .eq("id", body.report_id)
    .eq("patient_id", user.id)
    .maybeSingle();

  if (reportErr) {
    Sentry.captureException(reportErr);
    return corsedJsonError(req, 500, "report_lookup_failed", reportErr.message);
  }

  if (!report) {
    return corsedJsonError(req, 404, "not_found", "Report not found or does not belong to you");
  }

  // Create share link (expires N days from now).
  const expiresAt = new Date(Date.now() + body.expires_in_days * 24 * 60 * 60 * 1000).toISOString();

  const { data: link, error: insertErr } = await supabase
    .from("report_share_link")
    .insert({
      report_id: body.report_id,
      expires_at: expiresAt,
    })
    .select("token, expires_at")
    .single();

  if (insertErr) {
    Sentry.captureException(insertErr);
    return corsedJsonError(req, 500, "share_failed", insertErr.message);
  }

  const shareUrl = `${req.headers.get("origin") ?? "https://concord.health"}/api/reports/shared/${link.token}`;

  return corsed(
    req,
    new Response(
      JSON.stringify({
        ok: true,
        token: link.token,
        share_url: shareUrl,
        expires_at: link.expires_at,
      }),
      { status: 201, headers: { "content-type": "application/json" } },
    ),
  );
};
