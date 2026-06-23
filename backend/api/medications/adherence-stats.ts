// GET /api/medications/adherence-stats — auth-required. Returns per-medication
// adherence percentages for 7-day and 30-day windows.
//
// MED-06: Adherence % flows into the report.
// Response shape:
//   { ok: true, stats: [{ medication_id, display_name, dose, unit,
//                          days_7: { taken, total, pct },
//                          days_30: { taken, total, pct } }] }

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

  const supabase = serviceClient();

  const { data: meds, error: medsErr } = await supabase
    .from("medication")
    .select("id, display_name, dose, unit")
    .eq("patient_id", user.id)
    .eq("active", true);

  if (medsErr) {
    Sentry.captureException(medsErr);
    return corsedJsonError(req, 500, "fetch_failed", medsErr.message);
  }

  if (!meds || meds.length === 0) {
    return corsed(
      req,
      new Response(JSON.stringify({ ok: true, stats: [] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }

  const medIds = meds.map((m: { id: string }) => m.id);
  const now = Date.now();
  const days7ago = new Date(now - 7 * 24 * 60 * 60 * 1000).toISOString();
  const days30ago = new Date(now - 30 * 24 * 60 * 60 * 1000).toISOString();

  const { data: events, error: eventsErr } = await supabase
    .from("medication_event")
    .select("medication_id, status, scheduled_for")
    .in("medication_id", medIds)
    .gte("scheduled_for", days30ago);

  if (eventsErr) {
    Sentry.captureException(eventsErr);
    return corsedJsonError(req, 500, "fetch_failed", eventsErr.message);
  }

  const now8601 = new Date(now).toISOString();
  const stats = meds.map((m: { id: string; display_name: string; dose: string | null; unit: string | null }) => {
    const medEvents = (events ?? []).filter(
      (e: { medication_id: string }) => e.medication_id === m.id,
    );

    const count = (events: Array<{ status: string; scheduled_for: string }>, since: string) => {
      const window = events.filter((e) => e.scheduled_for >= since && e.scheduled_for <= now8601);
      const taken = window.filter(
        (e) => e.status === "taken" || e.status === "taken_late",
      ).length;
      return {
        taken,
        total: window.length,
        pct: window.length > 0 ? Math.round((taken / window.length) * 100) : 0,
      };
    };

    return {
      medication_id: m.id,
      display_name: m.display_name,
      dose: m.dose,
      unit: m.unit,
      days_7: count(medEvents, days7ago),
      days_30: count(medEvents, days30ago),
    };
  });

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, stats }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
