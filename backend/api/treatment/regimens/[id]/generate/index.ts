// POST /api/treatment/regimens/[id]/generate — generate treatment events for a regimen.
// Body: { start_date: "2026-07-01" }
//
// Creates one infusion event per cycle on the cycle start date.
// MED-03: Cyclical chemo schedules.

import { z } from "zod";
import { requireUser } from "../../../../../_lib/auth.js";
import { serviceClient } from "../../../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const GenerateBody = z.object({
  start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

export const POST = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof GenerateBody>;
  try {
    body = GenerateBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const supabase = serviceClient();
  const regimenId = ctx.params.id!;

  const { data: regimen, error: regErr } = await supabase
    .from("treatment_regimen")
    .select("*")
    .eq("id", regimenId)
    .single();

  if (regErr || !regimen) {
    return corsedJsonError(req, 404, "not_found", "Regimen not found");
  }
  if (regimen.patient_id !== user.id) {
    return corsedJsonError(req, 403, "forbidden", "Regimen belongs to another user");
  }

  const startDate = new Date(body.start_date + "T00:00:00Z");
  const events: Array<Record<string, unknown>> = [];
  const cycleLen = regimen.cycle_length_days;
  const restDays = regimen.rest_days;
  const totalDaysPerCycle = cycleLen + restDays;

  for (let cycle = 1; cycle <= regimen.total_cycles; cycle++) {
    const cycleStart = new Date(startDate);
    cycleStart.setUTCDate(cycleStart.getUTCDate() + (cycle - 1) * totalDaysPerCycle);

    const dateStr = cycleStart.toISOString().slice(0, 10);

    const { data: meds } = await supabase
      .from("treatment_regimen_medication")
      .select("*")
      .eq("regimen_id", regimen.id)
      .eq("day_within_cycle", 1);

    const notes = meds && meds.length > 0
      ? `Cycle ${cycle} medications: ${meds.map((m: { medication_name: string }) => m.medication_name).join(", ")}`
      : `Cycle ${cycle} of ${regimen.name}`;

    events.push({
      patient_id: user.id,
      regimen_id: regimen.id,
      cycle_number: cycle,
      event_type: "infusion",
      title: `${regimen.name} — Cycle ${cycle}`,
      description: regimen.description,
      event_date: dateStr,
      status: "scheduled",
      notes,
    });
  }

  const { data: inserted, error: insertErr } = await supabase
    .from("treatment_event")
    .insert(events)
    .select("*");

  if (insertErr) {
    Sentry.captureException(insertErr);
    return corsedJsonError(req, 500, "generate_failed", insertErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, events: inserted ?? [] }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
