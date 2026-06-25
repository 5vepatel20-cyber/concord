// POST /api/account/export — auth-required. Returns a JSON blob with all
// of the user's data for download. SEC-11: data export.
//
// Collects data from all patient tables keyed by patient_id and returns
// a JSON response with content-disposition attachment so the browser or
// Flutter WebView triggers a download.

import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const TABLES = [
  "patient_profile",
  "symptom_report",
  "symptom_response",
  "medication",
  "medication_event",
  "health_metric_sample",
  "document",
  "report",
  "report_share_link",
  "trial_match",
  "user_consent",
  "treatment_event",
  "treatment_regimen",
  "treatment_regimen_medication",
  "conversation_participant",
  "message",
] as const;

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const supabase = serviceClient();
  const exportData: Record<string, unknown[]> = {};

  for (const table of TABLES) {
    let query = supabase.from(table).select("*");

    // Determine the patient/user column for this table.
    // Tables with "patient_id" column.
    if (
      ["patient_profile", "symptom_report", "medication", "health_metric_sample",
       "document", "report", "trial_match", "user_consent", "treatment_event",
       "treatment_regimen"].includes(table)
    ) {
      query = query.eq("patient_id", user.id);
    } else if (table === "treatment_regimen_medication") {
      // Subquery through regimen.
      const { data: regimenIds } = await supabase
        .from("treatment_regimen")
        .select("id")
        .eq("patient_id", user.id);
      const ids = (regimenIds ?? []).map((r: { id: string }) => r.id);
      if (ids.length > 0) {
        query = query.in("regimen_id", ids);
      } else {
        exportData[table] = [];
        continue;
      }
    } else if (table === "conversation_participant") {
      query = query.eq("user_id", user.id);
    } else if (table === "message") {
      // Messages where user is sender or in a conversation they're part of.
      const { data: convs } = await supabase
        .from("conversation_participant")
        .select("conversation_id")
        .eq("user_id", user.id);
      const convIds = (convs ?? []).map((c: { conversation_id: string }) => c.conversation_id);
      if (convIds.length > 0) {
        query = query.in("conversation_id", convIds);
      } else {
        exportData[table] = [];
        continue;
      }
    } else if (table === "medication_event") {
      // Subquery through medication.
      const { data: medIds } = await supabase
        .from("medication")
        .select("id")
        .eq("patient_id", user.id);
      const ids = (medIds ?? []).map((m: { id: string }) => m.id);
      if (ids.length > 0) {
        query = query.in("medication_id", ids);
      } else {
        exportData[table] = [];
        continue;
      }
    } else if (table === "report_share_link") {
      // Subquery through report.
      const { data: reportIds } = await supabase
        .from("report")
        .select("id")
        .eq("patient_id", user.id);
      const ids = (reportIds ?? []).map((r: { id: string }) => r.id);
      if (ids.length > 0) {
        query = query.in("report_id", ids);
      } else {
        exportData[table] = [];
        continue;
      }
    }

    const { data, error } = await query;
    if (!error && data) exportData[table] = data;
  }

  const payload = {
    ok: true,
    exported_at: new Date().toISOString(),
    data: exportData,
  };

  return corsed(
    req,
    new Response(JSON.stringify(payload, null, 2), {
      status: 200,
      headers: {
        "content-type": "application/json",
        "content-disposition": `attachment; filename="concord-export-${user.id.slice(0, 8)}.json"`,
      },
    }),
  );
};
