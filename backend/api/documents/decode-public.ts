// POST /api/documents/decode-public — no auth required.
// Viral wedge: lets anyone paste medical text (or snap a photo) and get a
// plain-language decode without signing up. No document is persisted.
// Results are returned to the client only (for Share Card generation or display).
//
// Supports two modes:
//   1. Text-only: pass `ocr_text` with the medical text.
//   2. Image OCR: pass `image_base64` + `image_mime`; the server runs OCR
//      using Gemini's vision capabilities, then decodes the extracted text.
//
// Rate-limited at the CDN level. Production should enforce a per-IP cap.

import { z } from "zod";
import { getAIProvider } from "../../_lib/ai/provider.js";
import { ocrFromImage } from "../../_lib/ai/ocr.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };

export const OPTIONS = (req: Request): Response => preflight(req);

const BodySchema = z.object({
  ocr_text: z.string().min(10).max(50000).optional(),
  image_base64: z.string().min(20).optional(),
  image_mime: z.string().default("image/jpeg"),
  reading_level: z.enum(["kid", "simple", "normal"]).default("normal"),
});

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  let body: z.infer<typeof BodySchema>;
  try {
    body = BodySchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  // If an image was provided but no text, run OCR first.
  let text = body.ocr_text;
  if (!text && body.image_base64) {
    try {
      text = await ocrFromImage(body.image_base64, body.image_mime);
    } catch (e) {
      return corsedJsonError(req, 500, "ocr_failed", e instanceof Error ? e.message : "OCR processing error");
    }
  }

  if (!text || text.length < 10) {
    return corsedJsonError(req, 400, "bad_request", "Provide at least 10 characters of text or a legible image.");
  }

  const ai = getAIProvider();

  const readingLevelInstruction =
    body.reading_level === "kid" ? "Use very simple words, as if explaining to a 10-year-old." :
    body.reading_level === "simple" ? "Use clear, straightforward language. Avoid medical jargon without explanation." :
    "Use plain but precise language suitable for a patient with high health literacy.";

  const systemPrompt = [
    "You are a clinical document assistant inside Concord, a health app.",
    "A user has pasted the following medical text.",
    readingLevelInstruction,
    "Respond ONLY with valid JSON matching the specified schema.",
  ].join(" ");

  let extraction: {
    summary: string;
    extracted_labs: unknown[];
    medications: string[];
    diagnoses: string[];
    suggested_questions: string[];
    critical_flags: string[];
    doc_type: string;
  };
  try {
    extraction = await ai.chatJSON({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: text },
      ],
      model: "pro",
      temperature: 0.3,
      schema: {
        type: "object",
        properties: {
          summary: { type: "string", description: "Plain-language summary of the document (4-6 sentences)" },
          extracted_labs: {
            type: "array",
            description: "Extracted lab values with name, value, unit, reference_range, flag",
            items: {
              type: "object",
              properties: {
                name: { type: "string", description: "Lab test name" },
                value: { type: "string", description: "Measured value" },
                unit: { type: "string", description: "Unit of measurement" },
                reference_range: { type: "string", description: "Normal reference range" },
                flag: { type: "string", enum: ["normal", "high", "low", "critical_high", "critical_low"], description: "Flag indicating if result is abnormal" },
              },
              required: ["name", "value", "unit", "reference_range", "flag"],
            },
          },
          medications: { type: "array", items: { type: "string" }, description: "Medication names mentioned" },
          diagnoses: { type: "array", items: { type: "string" }, description: "Diagnoses or conditions mentioned" },
          suggested_questions: { type: "array", items: { type: "string" }, description: "2-3 questions for the care team" },
          critical_flags: { type: "array", items: { type: "string" }, description: "Critically abnormal findings requiring urgent attention" },
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

  return corsed(
    req,
    new Response(JSON.stringify({
      ok: true,
      summary: extraction.summary,
      extraction: {
        doc_type: extraction.doc_type,
        summary: extraction.summary,
        extracted_labs: extraction.extracted_labs,
        medications: extraction.medications,
        diagnoses: extraction.diagnoses,
        suggested_questions: extraction.suggested_questions,
        critical_flags: extraction.critical_flags,
      },
    }, null, 2), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
