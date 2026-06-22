// POST /api/atlas/visit-prep — auth-required. Returns a structured
// visit-preparation summary powered by Atlas (Gemini).
//
// RPT-05: Before an appointment, the patient can pull up a guided prep
// view with: what to mention, questions to ask, medication concerns,
// and key symptom trends.

import { getAIProvider } from "../../_lib/ai/provider.js";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const SCHEMA = {
  type: "object" as const,
  properties: {
    visit_summary: { type: "string", description: "2-3 sentence plain-language summary of how the patient has been since their last visit." },
    mention_to_doctor: {
      type: "array",
      items: { type: "string" },
      description: "3-5 specific things the patient should tell their doctor about symptoms, changes, or concerns.",
    },
    questions_to_ask: {
      type: "array",
      items: { type: "string" },
      description: "3-5 questions the patient could ask their care team.",
    },
    medication_notes: {
      type: "string",
      description: "1-2 sentence note about any medication adherence issues or changes worth discussing.",
    },
    key_trends: {
      type: "array",
      items: { type: "string" },
      description: "2-3 notable symptom trends the doctor should know about.",
    },
  },
  required: ["visit_summary", "mention_to_doctor", "questions_to_ask", "medication_notes", "key_trends"],
  additionalProperties: false,
};

interface VisitPrepResult {
  visit_summary: string;
  mention_to_doctor: string[];
  questions_to_ask: string[];
  medication_notes: string;
  key_trends: string[];
}

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const supabase = serviceClient();
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

  // Fetch recent symptom data.
  const { data: symptoms } = await supabase
    .from("symptom_response")
    .select(`
      composite_grade,
      term:symptom_term(display_name, pro_ctcae_code, body_system),
      report:symptom_report!inner(reported_at)
    `)
    .eq("report.patient_id", user.id)
    .gte("report.reported_at", thirtyDaysAgo)
    .order("report(reported_at)", { ascending: false })
    .limit(40);

  // Fetch medication adherence.
  const { data: meds } = await supabase
    .from("medication")
    .select("id, display_name")
    .eq("patient_id", user.id)
    .eq("active", true);

  let medContext = "[No active medications.]";
  if (meds && meds.length > 0) {
    const medIds = meds.map((m) => m.id);
    const { data: events } = await supabase
      .from("medication_event")
      .select("medication_id, status")
      .in("medication_id", medIds)
      .gte("scheduled_for", thirtyDaysAgo);

    const takenByMed = new Map<string, { taken: number; total: number }>();
    for (const e of events ?? []) {
      const acc = takenByMed.get(e.medication_id) ?? { taken: 0, total: 0 };
      acc.total++;
      if (e.status === "taken") acc.taken++;
      takenByMed.set(e.medication_id, acc);
    }
    const lines = meds.map((m) => {
      const acc = takenByMed.get(m.id);
      const pct = acc && acc.total > 0 ? Math.round((acc.taken / acc.total) * 100) : 0;
      return `${m.display_name}: ${pct}% adherence`;
    });
    medContext = lines.join("\n");
  }

  // Build symptom context.
  const symptomLines = (symptoms ?? []).map((r) => {
    const term = Array.isArray(r.term) ? r.term[0] : r.term;
    const name = term?.display_name ?? "unknown";
    const grade = (r.composite_grade as number | null) ?? 0;
    return `${name}: grade ${grade}/3`;
  }).join("\n");
  const symContext = symptomLines.length > 0
    ? symptomLines
    : "[No symptom logs in the last 30 days.]";

  try {
    const provider = getAIProvider();
    const result = await provider.chatJSON<VisitPrepResult>({
      messages: [
        {
          role: "system",
          content: [
            "You are Atlas, a clinical-grade AI companion for people in active cancer treatment.",
            "Your job is to help a patient prepare for a doctor's visit.",
            "Based on their recent symptom logs and medication data, generate a structured visit-prep summary.",
            "Use warm, clear language at a grade 6 reading level.",
            "Never diagnose or prescribe.",
            "Focus on helping the patient communicate effectively with their care team.",
          ].join(" "),
        },
        {
          role: "user",
          content: [
            "Here is the patient's recent data for visit preparation:",
            "",
            "--- Symptoms (last 30 days) ---",
            symContext,
            "",
            "--- Medication Adherence ---",
            medContext,
          ].join("\n"),
        },
      ],
      model: "flash",
      temperature: 0.4,
      schema: SCHEMA,
    });

    return corsed(
      req,
      new Response(JSON.stringify({ ok: true, ...result }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  } catch (e) {
    Sentry.captureException(e);
    return corsedJsonError(req, 500, "visit_prep_failed", e instanceof Error ? e.message : String(e));
  }
};
