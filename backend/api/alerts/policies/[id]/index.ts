// PATCH /api/alerts/policies/[id] — update an escalation policy.
// DELETE /api/alerts/policies/[id] — delete an escalation policy.
//
// ALRT-06: Escalation policy & after-hours routing.

import { z } from "zod";
import { requireUser } from "../../../../_lib/auth.js";
import { serviceClient } from "../../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const SeverityThreshold = z.enum(["info", "urgent", "emergency"]);
const TimeRestriction = z.enum(["always", "business_hours", "after_hours"]);
const TargetRole = z.enum(["caregiver", "clinician", "both"]);
const NotificationChannel = z.enum(["email", "push", "sms"]);

const PatchBody = z.object({
  name: z.string().min(1).max(200).optional(),
  severity_threshold: SeverityThreshold.optional(),
  time_restriction: TimeRestriction.optional(),
  target_role: TargetRole.optional(),
  delay_minutes: z.number().int().min(0).optional(),
  notification_channel: NotificationChannel.optional(),
  priority: z.number().int().min(0).optional(),
  active: z.boolean().optional(),
});

export const PATCH = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const policyId = ctx.params.id!;

  const supabase = serviceClient();

  const { data: existing } = await supabase
    .from("escalation_policy")
    .select("id, patient_id")
    .eq("id", policyId)
    .single();

  if (!existing || existing.patient_id !== user.id) {
    return corsedJsonError(req, 404, "not_found", "Policy not found");
  }

  let body: z.infer<typeof PatchBody>;
  try {
    body = PatchBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const updates: Record<string, unknown> = {};
  if (body.name !== undefined) updates.name = body.name;
  if (body.severity_threshold !== undefined) updates.severity_threshold = body.severity_threshold;
  if (body.time_restriction !== undefined) updates.time_restriction = body.time_restriction;
  if (body.target_role !== undefined) updates.target_role = body.target_role;
  if (body.delay_minutes !== undefined) updates.delay_minutes = body.delay_minutes;
  if (body.notification_channel !== undefined) updates.notification_channel = body.notification_channel;
  if (body.priority !== undefined) updates.priority = body.priority;
  if (body.active !== undefined) updates.active = body.active;
  updates.updated_at = new Date().toISOString();

  const { data, error } = await supabase
    .from("escalation_policy")
    .update(updates)
    .eq("id", policyId)
    .select("*")
    .single();

  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "update_failed", error?.message ?? "update failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, policy: data }), {
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
  const policyId = ctx.params.id!;

  const supabase = serviceClient();

  const { data: existing } = await supabase
    .from("escalation_policy")
    .select("id, patient_id")
    .eq("id", policyId)
    .single();

  if (!existing || existing.patient_id !== user.id) {
    return corsedJsonError(req, 404, "not_found", "Policy not found");
  }

  const { error: delErr } = await supabase
    .from("escalation_policy")
    .delete()
    .eq("id", policyId);

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
