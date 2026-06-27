// OCR utility — extracts text from a base64-encoded image using Gemini's
// native vision capabilities. Returns the plain text extracted from the image.
//
// Called from the decode-public endpoint when a user snaps a photo instead
// of pasting text. Uses Gemini directly since other providers may not support
// image inputs through the common AIProvider interface.

import { GoogleGenerativeAI } from "@google/generative-ai";
import { getEnv } from "../env.js";

/**
 * Extract text from a base64-encoded image using Gemini.
 * @param imageBase64 - Base64-encoded image data (without data URI prefix).
 * @param mimeType - MIME type of the image (e.g. "image/jpeg", "image/png").
 * @returns Extracted text from the image.
 */
export async function ocrFromImage(
  imageBase64: string,
  mimeType: string,
): Promise<string> {
  const env = getEnv();
  const apiKey = env.GEMINI_API_KEY || env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error("No API key available for OCR — set GEMINI_API_KEY or ANTHROPIC_API_KEY");
  }

  const client = new GoogleGenerativeAI(apiKey);
  const model = client.getGenerativeModel({
    model: "gemini-2.5-flash",
    generationConfig: {
      temperature: 0.1,
      maxOutputTokens: 4096,
    },
  });

  const imagePart = {
    inlineData: {
      mimeType,
      data: imageBase64,
    },
  };

  const result = await model.generateContent([
    "Extract ALL text from this medical document image as accurately as possible. " +
    "Preserve numbers, lab values, dates, and medication names exactly as written. " +
    "Return only the extracted text, no commentary.",
    imagePart,
  ]);

  return result.response.text();
}
