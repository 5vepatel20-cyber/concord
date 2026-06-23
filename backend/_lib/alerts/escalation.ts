// ALRT-06: Escalation policy evaluator. Called after symptom_alert rows are
// created. Checks the patient's escalation policies and sends targeted
// notifications based on severity, time of day, and target role.
//
// Business hours: Mon-Fri 08:00-18:00 (configurable per policy in the future).

import { serviceClient } from "../supabase.js";
import { sendEmail, alertNotificationEmail } from "../notifications/email.js";
import { Sentry } from "../sentry.js";

interface AlertInfo {
  id: string;
  severity_level: string;
}

interface PolicyRow {
  id: string;
  patient_id: string;
  name: string;
  severity_threshold: string;
  time_restriction: string;
  target_role: string;
  delay_minutes: number;
  notification_channel: string;
  priority: number;
  active: boolean;
}

function isBusinessHours(): boolean {
  const now = new Date();
  const day = now.getUTCDay();
  const hour = now.getUTCHours();
  // Mon-Fri 08:00-18:00 UTC. Adjust if needed per timezone.
  if (day === 0 || day === 6) return false;
  return hour >= 8 && hour < 18;
}

function matchesTimeRestriction(restriction: string): boolean {
  switch (restriction) {
    case "always":
      return true;
    case "business_hours":
      return isBusinessHours();
    case "after_hours":
      return !isBusinessHours();
    default:
      return true;
  }
}

function severityRank(level: string): number {
  switch (level) {
    case "emergency": return 3;
    case "urgent": return 2;
    case "info": return 1;
    default: return 0;
  }
}

export async function evaluateEscalation(
  patientId: string,
  alerts: AlertInfo[],
  symptomCodes: string[],
): Promise<void> {
  if (alerts.length === 0) return;

  const supabase = serviceClient();

  // Fetch active policies for this patient, ordered by priority.
  const { data: policies } = await supabase
    .from("escalation_policy")
    .select("*")
    .eq("patient_id", patientId)
    .eq("active", true)
    .order("priority", { ascending: true });

  if (!policies || policies.length === 0) {
    // No custom policies; fall back to default caregiver notify for urgent+.
    await defaultEscalation(patientId, alerts, symptomCodes);
    return;
  }

  const maxAlertRank = Math.max(...alerts.map((a) => severityRank(a.severity_level)));

  for (const policy of policies as PolicyRow[]) {
    const policyRank = severityRank(policy.severity_threshold);
    if (maxAlertRank < policyRank) continue;
    if (!matchesTimeRestriction(policy.time_restriction)) continue;

    const matchingAlerts = alerts.filter(
      (a) => severityRank(a.severity_level) >= policyRank,
    );
    if (matchingAlerts.length === 0) continue;

    const topSeverity = matchingAlerts.some((a) => a.severity_level === "emergency")
      ? "emergency"
      : "urgent";

    let targetUserIds: string[] = [];

    if (policy.target_role === "caregiver" || policy.target_role === "both") {
      const { data: caregivers } = await supabase
        .from("care_relationship")
        .select("member_user_id")
        .eq("patient_id", patientId)
        .eq("status", "active")
        .contains("permissions", { receives_alerts: true });

      if (caregivers) {
        targetUserIds.push(...caregivers.map((c) => c.member_user_id));
      }
    }

    if (policy.target_role === "clinician" || policy.target_role === "both") {
      const { data: relationships } = await supabase
        .from("care_relationship")
        .select("member_user_id")
        .eq("patient_id", patientId)
        .eq("status", "active")
        .eq("role", "clinician");

      if (relationships) {
        targetUserIds.push(...relationships.map((r) => r.member_user_id));
      }
    }

    if (targetUserIds.length === 0) continue;

    const { data: users } = await supabase
      .from("user")
      .select("email, full_name")
      .in("id", targetUserIds);

    if (!users || users.length === 0) continue;

    for (const user of users) {
      if (!user.email) continue;

      if (policy.notification_channel === "email") {
        try {
          await sendEmail({
            to: user.email,
            subject: topSeverity === "emergency"
              ? "[URGENT] Symptom alert requires attention"
              : "[Alert] Symptom update for your patient",
            html: alertNotificationEmail({
              patientName: "Your patient",
              severity: topSeverity,
              symptomNames: [...new Set(symptomCodes)],
              signInUrl: "https://concord.health/sign-in",
            }),
          });
        } catch (e) {
          Sentry.captureException(e);
        }
      }
    }

    // Only apply the highest-priority matching policy.
    return;
  }

  // No policy matched; fall back to default.
  await defaultEscalation(patientId, alerts, symptomCodes);
}

async function defaultEscalation(
  patientId: string,
  alerts: AlertInfo[],
  symptomCodes: string[],
): Promise<void> {
  const urgentAlerts = alerts.filter(
    (a) => a.severity_level === "urgent" || a.severity_level === "emergency",
  );
  if (urgentAlerts.length === 0) return;

  const supabase = serviceClient();
  const topSeverity = urgentAlerts.some((a) => a.severity_level === "emergency")
    ? "emergency"
    : "urgent";

  const { data: caregivers } = await supabase
    .from("care_relationship")
    .select("member_user_id")
    .eq("patient_id", patientId)
    .eq("status", "active")
    .contains("permissions", { receives_alerts: true });

  if (!caregivers || caregivers.length === 0) return;

  const caregiverIds = caregivers.map((c) => c.member_user_id);
  const { data: users } = await supabase
    .from("user")
    .select("email, full_name")
    .in("id", caregiverIds);

  if (!users) return;

  for (const user of users) {
    if (!user.email) continue;
    try {
      await sendEmail({
        to: user.email,
        subject: topSeverity === "emergency"
          ? "[URGENT] Your loved one needs attention"
          : "[Alert] Your loved one reported symptoms",
        html: alertNotificationEmail({
          patientName: "Your loved one",
          severity: topSeverity,
          symptomNames: [...new Set(symptomCodes)],
          signInUrl: "https://concord.health/sign-in",
        }),
      });
    } catch (e) {
      Sentry.captureException(e);
    }
  }
}
