// Resend transactional email wrapper. Used by caregiver invite and alert
// notification flows. SILENTLY no-ops when RESEND_API_KEY is not configured
// (local dev, preview deploys without secrets).
//
// ALRT-04: Caregiver alert routing uses this to send urgent/emergency
// symptom alerts to caregivers with receives_alerts permission.

import { getEnv } from "../env.js";
import { Sentry } from "../sentry.js";

const RESEND_URL = "https://api.resend.com/emails";

interface SendEmailParams {
  to: string | string[];
  subject: string;
  html: string;
}

export async function sendEmail({ to, subject, html }: SendEmailParams): Promise<boolean> {
  const env = getEnv();
  const apiKey = env.RESEND_API_KEY;
  const fromEmail = env.RESEND_FROM_EMAIL ?? "noreply@concord.health";

  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY not set — skipping email");
    return false;
  }

  try {
    const res = await fetch(RESEND_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromEmail,
        to: Array.isArray(to) ? to : [to],
        subject,
        html,
      }),
    });

    if (!res.ok) {
      const errBody = await res.text().catch(() => "unknown");
      console.error(`[email] Resend error ${res.status}: ${errBody}`);
      Sentry.captureException(new Error(`Resend error: ${res.status} ${errBody}`));
      return false;
    }

    return true;
  } catch (err) {
    console.error("[email] send failed", err);
    Sentry.captureException(err);
    return false;
  }
}

export function caregiverInviteEmail({
  inviterName,
  inviteUrl,
}: {
  inviterName: string;
  inviteUrl: string;
}): string {
  return `
    <div style="font-family: Inter, -apple-system, sans-serif; max-width: 480px; margin: 0 auto;">
      <h2 style="color: #1a1a2e;">You've been invited to Concord</h2>
      <p style="color: #555; font-size: 15px; line-height: 1.5;">
        <strong>${escHtml(inviterName)}</strong> has invited you to join their care team on Concord.
        As a caregiver, you'll be able to view their symptoms, reports, and receive alerts
        if something needs attention.
      </p>
      <a href="${escHtml(inviteUrl)}"
         style="display: inline-block; padding: 12px 24px; margin: 16px 0;
                background-color: #2563eb; color: #fff; text-decoration: none;
                border-radius: 8px; font-weight: 600;">
        Accept invitation
      </a>
      <p style="color: #999; font-size: 13px;">
        If you don't have a Concord account yet, you'll be prompted to create one.
      </p>
    </div>
  `;
}

export function alertNotificationEmail({
  patientName,
  severity,
  symptomNames,
  signInUrl,
}: {
  patientName: string;
  severity: string;
  symptomNames: string[];
  signInUrl: string;
}): string {
  const severityColor = severity === "emergency" ? "#dc2626" : "#f59e0b";
  const severityLabel = severity === "emergency" ? "URGENT" : "Needs attention";

  return `
    <div style="font-family: Inter, -apple-system, sans-serif; max-width: 480px; margin: 0 auto;">
      <div style="background-color: ${severityColor}; color: #fff; padding: 16px 24px;
                  border-radius: 8px 8px 0 0;">
        <h2 style="margin: 0; font-size: 18px;">${severityLabel}</h2>
      </div>
      <div style="border: 1px solid #e5e7eb; border-top: none; padding: 24px;
                  border-radius: 0 0 8px 8px;">
        <p style="color: #555; font-size: 15px; line-height: 1.5;">
          <strong>${escHtml(patientName)}</strong> has reported symptoms that may need attention:
        </p>
        <ul style="color: #333; font-size: 15px;">
          ${symptomNames.map((s) => `<li>${escHtml(s)}</li>`).join("")}
        </ul>
        <a href="${escHtml(signInUrl)}"
           style="display: inline-block; padding: 12px 24px; margin: 16px 0;
                  background-color: #2563eb; color: #fff; text-decoration: none;
                  border-radius: 8px; font-weight: 600;">
          View in Concord
        </a>
      </div>
    </div>
  `;
}

function escHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
