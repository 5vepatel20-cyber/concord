// GET /api/symptoms/history — symptom grade history (last 90 days).
// Returns per-term daily composite grades for sparklines + heatmap.
//
// SYM-07: Symptom history.

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
  const days = parseInt(url.searchParams.get("days") ?? "90", 10);
  const limit = Math.min(Math.max(days, 7), 365);
  const since = new Date();
  since.setUTCDate(since.getUTCDate() - limit);

  const supabase = serviceClient();

  const { data: reports, error: reportErr } = await supabase
    .from("symptom_report")
    .select("id, reported_at")
    .eq("patient_id", user.id)
    .gte("reported_at", since.toISOString())
    .order("reported_at", { ascending: false });

  if (reportErr) {
    Sentry.captureException(reportErr);
    return corsedJsonError(req, 500, "fetch_failed", reportErr.message);
  }

  if (!reports || reports.length === 0) {
    return corsed(
      req,
      new Response(JSON.stringify({ ok: true, terms: [], data: [] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }

  const reportIds = reports.map((r: { id: string }) => r.id);

  const { data: responses, error: respErr } = await supabase
    .from("symptom_response")
    .select("term_id, composite_grade, report_id")
    .in("report_id", reportIds);

  if (respErr) {
    Sentry.captureException(respErr);
    return corsedJsonError(req, 500, "fetch_failed", respErr.message);
  }

  // Get unique term IDs.
  const termIds = [...new Set((responses ?? []).map((r: { term_id: string }) => r.term_id))];

  const { data: terms, error: termErr } = await supabase
    .from("symptom_term")
    .select("id, pro_ctcae_code, name")
    .in("id", termIds);

  if (termErr) {
    Sentry.captureException(termErr);
    return corsedJsonError(req, 500, "fetch_failed", termErr.message);
  }

  // Build report_id -> date map.
  const reportDateMap = new Map(
    reports.map((r: { id: string; reported_at: string }) => [
      r.id,
      r.reported_at.slice(0, 10),
    ]),
  );

  // Group by term, then by date.
  const termData = new Map<string, Array<{ date: string; grade: number; reportId: string }>>();

  for (const resp of responses ?? []) {
    const date = reportDateMap.get(resp.report_id);
    if (!date) continue;
    if (!termData.has(resp.term_id)) termData.set(resp.term_id, []);
    termData.get(resp.term_id)!.push({
      date,
      grade: resp.composite_grade,
      reportId: resp.report_id,
    });
  }

  // Build output.
  const termList = (terms ?? []).map((t: { id: string; pro_ctcae_code: string; name: string }) => {
    const entries = (termData.get(t.id) ?? []).sort(
      (a: { date: string }, b: { date: string }) => a.date.localeCompare(b.date),
    );
    return {
      term_id: t.id,
      pro_ctcae_code: t.pro_ctcae_code,
      name: t.name,
      entries,
      max_grade: entries.length > 0 ? Math.max(...entries.map((e: { grade: number }) => e.grade)) : 0,
    };
  });

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, terms: termList }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
