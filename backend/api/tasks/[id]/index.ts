// PATCH /api/tasks/:id — update a task (status, assigned_to, title, due_at).
// CARE-04: Caregivers can update tasks assigned to them.

import { z } from "zod";
import { requireUser } from "../../../_lib/auth.js";
import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const UpdateSchema = z.object({
  title: z.string().min(1).max(500).optional(),
  status: z.enum(["open", "done"]).optional(),
  category: z.enum(["appointment", "measurement", "lifestyle", "admin"]).optional(),
  due_at: z.string().datetime().nullable().optional(),
  assigned_to: z.string().uuid().nullable().optional(),
});

export const PATCH = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  // Extract task ID from URL.
  const url = new URL(req.url);
  const id = url.pathname.split("/").filter(Boolean).pop();
  if (!id) {
    return corsedJsonError(req, 400, "missing_id", "Task ID is required");
  }

  let body: z.infer<typeof UpdateSchema>;
  try {
    body = UpdateSchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid body");
  }

  const supabase = serviceClient();

  // Fetch the task to check authorization.
  const { data: existing, error: fetchErr } = await supabase
    .from("task")
    .select("patient_id, assigned_to")
    .eq("id", id)
    .single();

  if (fetchErr || !existing) {
    return corsedJsonError(req, 404, "not_found", "Task not found");
  }

  // Authorize: patient owns it, or caregiver is assigned, or caregiver of the patient.
  const isOwner = existing.patient_id === user.id;
  const isAssignee = existing.assigned_to === user.id;
  const { data: rel } = await supabase
    .rpc("is_active_caregiver_for", { p_patient: existing.patient_id });

  if (!isOwner && !isAssignee && !rel) {
    return corsedJsonError(req, 403, "forbidden", "Not authorized to update this task");
  }

  const updates: Record<string, unknown> = {};
  if (body.title !== undefined) updates.title = body.title;
  if (body.status !== undefined) updates.status = body.status;
  if (body.category !== undefined) updates.category = body.category;
  if (body.due_at !== undefined) updates.due_at = body.due_at ? new Date(body.due_at).toISOString() : null;
  if (body.assigned_to !== undefined) updates.assigned_to = body.assigned_to;

  const { data: updated, error: updateErr } = await supabase
    .from("task")
    .update(updates)
    .eq("id", id)
    .select()
    .single();

  if (updateErr) {
    Sentry.captureException(updateErr);
    return corsedJsonError(req, 500, "update_failed", updateErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, task: updated }), {
      headers: { "content-type": "application/json" },
    }),
  );
};
