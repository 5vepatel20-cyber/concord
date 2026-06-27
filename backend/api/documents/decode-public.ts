// POST /api/documents/decode-public — no auth required.
// Viral wedge: lets anyone paste medical text and get a plain-language decode
// without signing up. No document is persisted. Results are returned to the
// client only (for Share Card generation or display).
//
// Rate-limited at the CDN level. Production should enforce a per-IP cap.

import { z } from "zod";
import { getAIProvider } from "../../_lib/ai/provider.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };

export const OPTIONS = (req: Request): Response => preflight(req);

const BodySchema = z.object({
  ocr_text: z.string().min(10).max(50000),
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
