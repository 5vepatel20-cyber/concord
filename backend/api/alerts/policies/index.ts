// GET  /api/alerts/policies — list escalation policies for current patient.
// POST /api/alerts/policies — create an escalation policy.
//
// ALRT-06: Escalation policy & after-hours routing.

import { z } from "zod";
import { requireUser } from "../../../_lib/auth.js";
import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const SeverityThreshold = z.enum(["info", "urgent", "emergency"]);
const TimeRestriction = z.enum(["always", "business_hours", "after_hours"]);
const TargetRole = z.enum(["caregiver", "clinician", "both"]);
const NotificationChannel = z.enum(["email", "push", "sms"]);

const CreatePolicyBody = z.object({
  name: z.string().min(1).max(200).default("Default"),
  severity_threshold: SeverityThreshold.default("urgent"),
  time_restriction: TimeRestriction.default("always"),
  target_role: TargetRole.default("caregiver"),
  delay_minutes: z.number().int().min(0).default(0),
  notification_channel: NotificationChannel.default("email"),
  priority: z.number().int().min(0).default(0),
  active: z.boolean().default(true),
});

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const supabase = serviceClient();
  const { data, error } = await supabase
    .from("escalation_policy")
    .select("*")
    .eq("patient_id", user.id)
    .order("priority", { ascending: true });

  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "fetch_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, policies: data ?? [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof CreatePolicyBody>;
  try {
    body = CreatePolicyBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const supabase = serviceClient();
  const { data, error } = await supabase
    .from("escalation_policy")
    .insert({
      patient_id: user.id,
      name: body.name,
      severity_threshold: body.severity_threshold,
      time_restriction: body.time_restriction,
      target_role: body.target_role,
      delay_minutes: body.delay_minutes,
      notification_channel: body.notification_channel,
      priority: body.priority,
      active: body.active,
    })
    .select("*")
    .single();

  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "insert_failed", error?.message ?? "insert failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, policy: data }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
