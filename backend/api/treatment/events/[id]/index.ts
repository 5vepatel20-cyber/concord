// PATCH /api/treatment/events/[id] — update a treatment event (status, etc.).
// DELETE /api/treatment/events/[id] — delete a treatment event.
//
// ONB-05: Treatment calendar.

import { z } from "zod";
import { requireUser } from "../../../../_lib/auth.js";
import { serviceClient } from "../../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const EventStatus = z.enum(["scheduled", "completed", "cancelled", "rescheduled"]);

const PatchBody = z.object({
  title: z.string().min(1).max(300).optional(),
  description: z.string().max(2000).nullable().optional(),
  location: z.string().max(500).nullable().optional(),
  event_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  event_time: z.string().regex(/^\d{2}:\d{2}$/).nullable().optional(),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  status: EventStatus.optional(),
  notes: z.string().max(4000).nullable().optional(),
});

export const PATCH = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const eventId = ctx.params.id;

  let body: z.infer<typeof PatchBody>;
  try {
    body = PatchBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  // Ownership check.
  const { data: existing, error: lookupErr } = await supabase
    .from("treatment_event")
    .select("id, patient_id")
    .eq("id", eventId)
    .single();
  if (lookupErr || !existing) {
    return corsedJsonError(req, 404, "not_found", "Event not found");
  }
  if (existing.patient_id !== user.id) {
    return corsedJsonError(req, 403, "forbidden", "Event belongs to another user");
  }

  const updates: Record<string, unknown> = {};
  if (body.title !== undefined) updates.title = body.title;
  if (body.description !== undefined) updates.description = body.description;
  if (body.location !== undefined) updates.location = body.location;
  if (body.event_date !== undefined) updates.event_date = body.event_date;
  if (body.event_time !== undefined) updates.event_time = body.event_time;
  if (body.end_date !== undefined) updates.end_date = body.end_date;
  if (body.status !== undefined) updates.status = body.status;
  if (body.notes !== undefined) updates.notes = body.notes;
  updates.updated_at = new Date().toISOString();

  const { data, error } = await supabase
    .from("treatment_event")
    .update(updates)
    .eq("id", eventId)
    .select("*")
    .single();

  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "update_failed", error?.message ?? "update failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, event: data }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const DELETE = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const eventId = ctx.params.id;

  const supabase = serviceClient();

  const { data: existing, error: lookupErr } = await supabase
    .from("treatment_event")
    .select("id, patient_id")
    .eq("id", eventId)
    .single();
  if (lookupErr || !existing) {
    return corsedJsonError(req, 404, "not_found", "Event not found");
  }
  if (existing.patient_id !== user.id) {
    return corsedJsonError(req, 403, "forbidden", "Event belongs to another user");
  }

  const { error: delErr } = await supabase.from("treatment_event").delete().eq("id", eventId);
  if (delErr) {
    Sentry.captureException(delErr);
    return corsedJsonError(req, 500, "delete_failed", delErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
