// POST /api/atlas/chat — auth-required streaming chat with Atlas (the AI).
// Streams server-sent events: each chunk is `data: {"text": "..."}\n\n`,
// terminated by `data: [DONE]\n\n`.
//
// This is the ATLAS-01 endpoint (Gemini via server proxy). ATLAS-02 (inject
// symptom context) is wired in here too — once a patient is identified, we
// fetch their recent graded symptoms and prepend them to the system prompt.

import type { ChatMessage } from "../../_lib/ai/types.js";
import { getAIProvider } from "../../_lib/ai/provider.js";
import { requireUser, jsonError } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { z } from "zod";

export const config = {
  runtime: "nodejs",
};

const BodySchema = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(["system", "user", "assistant"]),
        content: z.string().min(1).max(8000),
      }),
    )
    .min(1)
    .max(50),
  model: z.enum(["flash", "pro"]).optional(),
});

const SYSTEM_PROMPT = [
  "You are Atlas, a clinical-grade companion inside Concord, a health app for people in active cancer treatment.",
  "Your job is to help the patient understand their symptoms, prepare for appointments, and decode medical documents.",
  "You are NOT a doctor. You never diagnose. You never prescribe. You never recommend a specific treatment or dose change.",
  "If the patient describes something that could be a medical emergency (chest pain, trouble breathing, severe bleeding, fever >= 100.4F during chemo, sudden severe pain, thoughts of self-harm), tell them clearly to call their oncology care team or 911 / local emergency number — do not try to interpret further.",
  "When you reference clinical information, be specific and grounded. If you don't know, say so.",
  "Match the patient's reading level. Be warm but not chatty. Be precise.",
].join(" ");

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return userOrError;
  const user = userOrError;

  let body: z.infer<typeof BodySchema>;
  try {
    body = BodySchema.parse(await req.json());
  } catch (e) {
    return jsonError(400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  // ATLAS-02: pull the patient's last 7 days of graded symptom responses
  // and prepend a context block to the system prompt.
  const context = await loadRecentSymptomContext(user.id);
  const systemMessage: ChatMessage = {
    role: "system",
    content: `${SYSTEM_PROMPT}\n\n${context}`,
  };
  const messages: ChatMessage[] = [systemMessage, ...body.messages];

  const provider = getAIProvider();
  const usePro = body.model === "pro";

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      try {
        for await (const chunk of provider.chat({
          messages,
          model: usePro ? "pro" : "flash",
          temperature: 0.7,
        })) {
          if (chunk.text) {
            controller.enqueue(
              encoder.encode(`data: ${JSON.stringify({ text: chunk.text })}\n\n`),
            );
          }
          if (chunk.done) break;
        }
        controller.enqueue(encoder.encode(`data: [DONE]\n\n`));
        controller.close();
      } catch (e) {
        Sentry.captureException(e);
        const msg = e instanceof Error ? e.message : String(e);
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify({ error: msg })}\n\n`),
        );
        controller.close();
      }
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-store",
      "x-accel-buffering": "no", // disable Vercel buffering for true streaming
    },
  });
};

/**
 * Build a short context block describing the patient's last 7 days of
 * graded symptoms. Returns a placeholder if there's no data yet.
 */
async function loadRecentSymptomContext(userId: string): Promise<string> {
  try {
    const supabase = serviceClient();
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { data, error } = await supabase
      .from("symptom_response")
      .select(
        "composite_grade, term:symptom_term(display_name, pro_ctcae_code), report:symptom_report!inner(reported_at, patient_id)",
      )
      .eq("report.patient_id", userId)
      .gte("report.reported_at", sevenDaysAgo)
      .order("report(reported_at)", { ascending: false })
      .limit(30);

    if (error || !data || data.length === 0) {
      return "[Patient has no recent symptom logs in the last 7 days.]";
    }

    const lines = data
      .map((r) => {
        const term = Array.isArray(r.term) ? r.term[0] : r.term;
        const name = term?.display_name ?? "unknown";
        const code = term?.pro_ctcae_code ?? "?";
        const grade = (r.composite_grade as number | null) ?? 0;
        return `- ${name} (${code}): grade ${grade}/3`;
      })
      .join("\n");

    return `[Patient's last 7 days of symptom logs]\n${lines}\n[Use this context to ground your answers.]`;
  } catch {
    return "[Symptom context unavailable.]";
  }
}
