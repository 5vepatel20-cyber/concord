// POST /api/documents/decode — auth-required. Accepts medical text (OCR'd
// or pasted), sends it to Gemini for structured extraction, and persists
// a `document` row. Returns the plain-language summary + extracted values.
//
// DOC-01/02/03/04: capture → OCR → plain-language summary → abnormal flags.
// DOC-05: extracted values may include proposed coded medication names.
//
// This endpoint does the AI processing server-side; on-device OCR (iOS
// Vision, ML Kit) is handled client-side before calling here with raw text.
// For PDF/image uploads without client-side OCR, the caller sends the file
// URL and we use AWS Textract (Phase 2 — DOC-02 deferred).

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { getAIProvider } from "../../_lib/ai/provider.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };

export const OPTIONS = (req: Request): Response => preflight(req);

const BodySchema = z.object({
  kind: z.enum(["discharge_summary", "lab_result", "imaging", "visit_note", "other"]).default("other"),
  ocr_text: z.string().min(10).max(50000),
  storage_url: z.string().url().optional(),
  reading_level: z.enum(["kid", "simple", "normal"]).default("normal"),
});

interface LabExtraction {
  name: string;
  value: string;
  unit: string;
  reference_range: string;
  flag: "normal" | "high" | "low" | "critical_high" | "critical_low";
}

interface DecodeResult {
  summary: string;
  extracted_labs: LabExtraction[];
  medications: string[];
  diagnoses: string[];
  suggested_questions: string[];
  critical_flags: string[];
  doc_type: string;
}

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof BodySchema>;
  try {
    body = BodySchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const ai = getAIProvider();

  const readingLevelInstruction =
    body.reading_level === "kid" ? "Use very simple words, as if explaining to a 10-year-old." :
    body.reading_level === "simple" ? "Use clear, straightforward language. Avoid medical jargon without explanation." :
    "Use plain but precise language suitable for a patient with high health literacy.";

  const systemPrompt = [
    "You are a clinical document assistant inside Concord, a health app for cancer patients.",
    "A patient has uploaded the following medical text.",
    readingLevelInstruction,
    "Respond ONLY with valid JSON matching the specified schema.",
  ].join(" ");

  let extraction: DecodeResult;
  try {
    extraction = await ai.chatJSON<DecodeResult>({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: body.ocr_text },
      ],
      model: "pro",
      temperature: 0.3,
      schema: {
        type: "object",
        properties: {
          summary: { type: "string", description: "Plain-language summary of the document (4-6 sentences)" },
          extracted_labs: { type: "string", description: "JSON array of extracted lab values with name, value, unit, reference_range, flag" },
          medications: { type: "string", description: "JSON array of medication names mentioned" },
          diagnoses: { type: "string", description: "JSON array of diagnoses or conditions mentioned" },
          suggested_questions: { type: "string", description: "JSON array of 2-3 questions for the care team" },
          critical_flags: { type: "string", description: "JSON array of critically abnormal findings requiring urgent attention" },
          doc_type: { type: "string", description: "The likely document type" },
        },
        required: ["summary", "extracted_labs", "medications", "diagnoses", "suggested_questions", "critical_flags", "doc_type"],
        additionalProperties: false,
      },
    });
  } catch (e) {
    Sentry.captureException(e);
    return corsedJsonError(req, 500, "ai_extraction_failed", e instanceof Error ? e.message : "AI processing error");
  }

  const supabase = serviceClient();
  const { data: saved, error: saveErr } = await supabase
    .from("document")
    .insert({
      patient_id: user.id,
      kind: body.kind,
      storage_url: body.storage_url ?? `manual://${user.id}/${Date.now()}`,
      ocr_text: body.ocr_text,
      ai_plain_summary: extraction.summary,
      extracted_values: extraction as unknown as Record<string, unknown>,
    })
    .select("id, ai_plain_summary, extracted_values")
    .single();

  if (saveErr || !saved) {
    Sentry.captureException(saveErr);
    return corsedJsonError(req, 500, "document_save_failed", saveErr?.message ?? "save failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, document_id: saved.id, summary: saved.ai_plain_summary, extraction: saved.extracted_values }, null, 2), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
