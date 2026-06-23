// GET /api/alerts — list symptom alerts for the current patient.
// Supports ?status=open|acknowledged|resolved and ?limit=N.
//
// ALRT-06: Alert list view.

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

  const url = new URL(req.url);
  const status = url.searchParams.get("status");
  const limit = parseInt(url.searchParams.get("limit") ?? "50", 10);

  const supabase = serviceClient();

  let query = supabase
    .from("symptom_alert")
    .select("*, rule:alert_rule(term_id)")
    .eq("patient_id", user.id)
    .order("created_at", { ascending: false })
    .limit(Math.min(limit, 200));

  if (status) {
    query = query.eq("status", status);
  }

  const { data, error } = await query;
  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "fetch_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, alerts: data ?? [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
