// POST /api/alerts/acknowledge — acknowledge a symptom alert.
// Body: { alert_id: string }
//
// ALRT-06: Allows patients and caregivers to mark alerts as acknowledged.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const AcknowledgeBody = z.object({
  alert_id: z.string().uuid(),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof AcknowledgeBody>;
  try {
    body = AcknowledgeBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const supabase = serviceClient();

  const { data: alert, error: fetchErr } = await supabase
    .from("symptom_alert")
    .select("id, patient_id, status")
    .eq("id", body.alert_id)
    .single();

  if (fetchErr || !alert) {
    return corsedJsonError(req, 404, "not_found", "Alert not found");
  }

  // Patient or their active caregivers can acknowledge.
  if (alert.patient_id !== user.id) {
    const { data: rel } = await supabase
      .from("care_relationship")
      .select("id")
      .eq("patient_id", alert.patient_id)
      .eq("member_user_id", user.id)
      .eq("status", "active")
      .maybeSingle();

    if (!rel) {
      return corsedJsonError(req, 403, "forbidden", "Not authorized to acknowledge this alert");
    }
  }

  const { error: updateErr } = await supabase
    .from("symptom_alert")
    .update({
      status: "acknowledged",
      acknowledged_by: user.id,
      acknowledged_at: new Date().toISOString(),
    })
    .eq("id", body.alert_id);

  if (updateErr) {
    Sentry.captureException(updateErr);
    return corsedJsonError(req, 500, "update_failed", updateErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
