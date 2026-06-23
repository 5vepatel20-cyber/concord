// POST /api/caregiver/invite — auth-required. Patient invites a caregiver
// by email. Creates a care_relationship with status='active' if the caregiver
// user exists, and sends a notification email.
//
// CARE-01: Caregiver accounts + permission scopes.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";
import { sendEmail, caregiverInviteEmail } from "../../_lib/notifications/email.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const RELATIONSHIP_KINDS = ["spouse", "child", "parent", "friend", "clinician", "care_navigator"] as const;

const Body = z.object({
  email: z.string().email(),
  relationship: z.enum(RELATIONSHIP_KINDS),
  permissions: z
    .object({
      can_log: z.boolean().optional(),
      can_view_reports: z.boolean().optional(),
      receives_alerts: z.boolean().optional(),
    })
    .optional(),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  if (user.role !== "patient") {
    return corsedJsonError(req, 403, "not_patient", "Only patients can invite caregivers");
  }

  let body: z.infer<typeof Body>;
  try {
    body = Body.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  // Look up caregiver user by email.
  const { data: caregiverUser, error: lookupErr } = await supabase
    .from("user")
    .select("id, full_name, email")
    .eq("email", body.email)
    .maybeSingle();

  if (lookupErr) {
    Sentry.captureException(lookupErr);
    return corsedJsonError(req, 500, "lookup_failed", lookupErr.message);
  }

  if (!caregiverUser) {
    return corsedJsonError(
      req,
      404,
      "user_not_found",
      "No user found with that email. Ask them to sign up for Concord first.",
    );
  }

  if (caregiverUser.id === user.id) {
    return corsedJsonError(req, 400, "self_invite", "You cannot invite yourself as a caregiver");
  }

  // Check for existing relationship.
  const { data: existing } = await supabase
    .from("care_relationship")
    .select("id, status")
    .eq("patient_id", user.id)
    .eq("member_user_id", caregiverUser.id)
    .maybeSingle();

  if (existing) {
    if (existing.status === "active") {
      return corsedJsonError(req, 409, "already_active", "This caregiver is already part of your care team");
    }
    // Revoked or pending — reactivate.
    const { error: updateErr } = await supabase
      .from("care_relationship")
      .update({ status: "active", permissions: body.permissions ?? {} })
      .eq("id", existing.id);

    if (updateErr) {
      Sentry.captureException(updateErr);
      return corsedJsonError(req, 500, "update_failed", updateErr.message);
    }

    // Send notification email (best-effort).
    const patientName = user.email ?? "A patient";
    await sendEmail({
      to: body.email,
      subject: `${patientName} added you to their care team on Concord`,
      html: caregiverInviteEmail({
        inviterName: patientName,
        inviteUrl: "https://concord.health/sign-in",
      }),
    });

    return corsed(
      req,
      new Response(
        JSON.stringify({
          ok: true,
          relationship_id: existing.id,
          status: "active",
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  }

  // Create new relationship.
  const { data: rel, error: insertErr } = await supabase
    .from("care_relationship")
    .insert({
      patient_id: user.id,
      member_user_id: caregiverUser.id,
      relationship: body.relationship,
      permissions: body.permissions ?? { can_view_reports: true, receives_alerts: true },
      status: "active",
    })
    .select("id")
    .single();

  if (insertErr) {
    Sentry.captureException(insertErr);
    return corsedJsonError(req, 500, "insert_failed", insertErr.message);
  }

  // Send notification email (best-effort).
  const patientName = user.email ?? "A patient";
  await sendEmail({
    to: body.email,
    subject: `${patientName} added you to their care team on Concord`,
    html: caregiverInviteEmail({
      inviterName: patientName,
      inviteUrl: "https://concord.health/sign-in",
    }),
  });

  return corsed(
    req,
    new Response(
      JSON.stringify({
        ok: true,
        relationship_id: rel.id,
        status: "active",
      }),
      { status: 201, headers: { "content-type": "application/json" } },
    ),
  );
};
