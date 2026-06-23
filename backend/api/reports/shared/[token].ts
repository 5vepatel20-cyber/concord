// GET /api/reports/shared/[token] — public, no auth required. Returns the
// full structured report for a valid share token. Used by clinicians / family
// who open a secure link from the patient.
//
// RPT-06: Share-to-clinician (secure link viewing).

import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";

export const config = { runtime: "nodejs" };

export const GET = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const token = ctx.params.token;
  if (!token) {
    return new Response(
      JSON.stringify({ error: { code: "missing_token", message: "Share token is required" } }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }

  // Validate UUID format.
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(token)) {
    return new Response(
      JSON.stringify({ error: { code: "invalid_token", message: "Invalid share token format" } }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }

  const supabase = serviceClient();

  // Look up the share link.
  const { data: link, error: linkErr } = await supabase
    .from("report_share_link")
    .select("id, report_id, expires_at, access_count")
    .eq("token", token)
    .maybeSingle();

  if (linkErr) {
    Sentry.captureException(linkErr);
    return new Response(
      JSON.stringify({ error: { code: "lookup_failed", message: "Failed to look up share link" } }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  }

  if (!link) {
    return new Response(
      JSON.stringify({ error: { code: "not_found", message: "Share link not found" } }),
      { status: 404, headers: { "content-type": "application/json" } },
    );
  }

  // Check expiry.
  if (new Date(link.expires_at) < new Date()) {
    return new Response(
      JSON.stringify({ error: { code: "expired", message: "This share link has expired" } }),
      { status: 410, headers: { "content-type": "application/json" } },
    );
  }

  // Fetch the report.
  const { data: report, error: reportErr } = await supabase
    .from("report")
    .select("structured_payload, narrative, created_at")
    .eq("id", link.report_id)
    .single();

  if (reportErr || !report) {
    Sentry.captureException(reportErr);
    return new Response(
      JSON.stringify({ error: { code: "report_not_found", message: "The linked report no longer exists" } }),
      { status: 404, headers: { "content-type": "application/json" } },
    );
  }

  // Update access tracking (best-effort).
  await supabase
    .from("report_share_link")
    .update({
      last_accessed_at: new Date().toISOString(),
      access_count: (link.access_count ?? 0) + 1,
    })
    .eq("id", link.id);

  return new Response(
    JSON.stringify({
      ok: true,
      report: report.structured_payload,
      narrative: report.narrative,
      generated_at: report.created_at,
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
};
