// GET /api/health/metrics — auth-required. Returns health metric history
// for the current patient, optionally filtered by type and date range.
//
// HK-04: Health metrics history view with trends.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const MetricType = z.enum([
  "steps", "sleep", "hr", "bp_sys", "bp_dia", "glucose", "calories", "weight",
]);

const METRIC_META: Record<string, { label: string; unit: string; color: string }> = {
  steps:   { label: "Steps",       unit: "steps",  color: "#4A90D9" },
  sleep:   { label: "Sleep",       unit: "hours",  color: "#7B61FF" },
  hr:      { label: "Heart Rate",  unit: "bpm",    color: "#E74C3C" },
  bp_sys:  { label: "Systolic BP", unit: "mmHg",   color: "#E67E22" },
  bp_dia:  { label: "Diastolic BP",unit: "mmHg",   color: "#F39C12" },
  glucose: { label: "Glucose",     unit: "mg/dL",  color: "#2ECC71" },
  calories:{ label: "Calories",    unit: "kcal",   color: "#E91E63" },
  weight:  { label: "Weight",      unit: "kg",     color: "#1ABC9C" },
};

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const url = new URL(req.url);
  const typeParam = url.searchParams.get("type");        // optional: filter by type
  const daysParam = url.searchParams.get("days") ?? "30"; // default: last 30 days

  let typeFilter: string | undefined;
  if (typeParam) {
    const parsed = MetricType.safeParse(typeParam);
    if (!parsed.success) {
      return corsedJsonError(req, 400, "invalid_type", `Unknown metric type: ${typeParam}`);
    }
    typeFilter = parsed.data;
  }

  const days = parseInt(daysParam, 10);
  if (isNaN(days) || days < 1 || days > 365) {
    return corsedJsonError(req, 400, "invalid_days", "days must be between 1 and 365");
  }

  const since = new Date();
  since.setDate(since.getDate() - days);

  const supabase = serviceClient();

  let query = supabase
    .from("health_metric_sample")
    .select("id, type, value, unit, measured_at, source")
    .eq("patient_id", user.id)
    .gte("measured_at", since.toISOString())
    .order("measured_at", { ascending: false });

  if (typeFilter) {
    query = query.eq("type", typeFilter);
  }

  const { data, error } = await query;
  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "fetch_failed", error.message);
  }

  // Group by type for the response.
  const byType = new Map<string, unknown[]>();
  for (const row of data ?? []) {
    const t = row.type as string;
    if (!byType.has(t)) byType.set(t, []);
    byType.get(t)!.push({
      id: row.id,
      value: row.value,
      unit: row.unit,
      measured_at: row.measured_at,
      source: row.source,
    });
  }

  const types = Array.from(byType.entries()).map(([type, samples]) => {
    const meta = METRIC_META[type] ?? { label: type, unit: "", color: "#888" };
    const values = (samples as Array<{ value: number }>).map((s) => s.value);
    const latest = values[0] ?? null;
    const min = values.length > 0 ? Math.min(...values) : null;
    const max = values.length > 0 ? Math.max(...values) : null;
    const avg = values.length > 0
      ? values.reduce((a, b) => a + b, 0) / values.length
      : null;

    // Sort ascending for charts.
    const sorted = [...(samples as Array<Record<string, unknown>>)].reverse();

    return {
      type,
      label: meta.label,
      unit: meta.unit,
      color: meta.color,
      count: samples.length,
      latest,
      min,
      max,
      avg: avg !== null ? Math.round(avg * 10) / 10 : null,
      samples: sorted,
    };
  });

  // Sort by count descending so most-frequently-logged types appear first.
  types.sort((a, b) => b.count - a.count);

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, days, types }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
