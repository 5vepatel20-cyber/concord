import { describe, it, expect, vi, beforeEach } from "vitest";
import type { AIProvider } from "../../../_lib/ai/types.js";

// ── Hoisted mock fns (must use vi.hoisted so they're available in vi.mock factory) ──

const { mockChatJSON, mockOcrFromImage } = vi.hoisted(() => ({
  mockChatJSON: vi.fn(),
  mockOcrFromImage: vi.fn(),
}));

vi.mock("../../../_lib/ai/provider.js", () => ({
  getAIProvider: (): AIProvider => ({
    name: "mock",
    chat: vi.fn(),
    chatJSON: mockChatJSON,
  }),
}));

vi.mock("../../../_lib/ai/ocr.js", () => ({
  ocrFromImage: mockOcrFromImage,
}));

vi.mock("../../../_lib/sentry.js", () => ({
  initSentry: vi.fn(),
  Sentry: { captureException: vi.fn() },
}));

// ── Module under test ─────────────────────────────────────────────────

import { POST, OPTIONS } from "../decode-public.js";

// ── Fixtures ──────────────────────────────────────────────────────────

const fakeBase64 = "aW1hZ2UuLi4uLi4uLi4uLi4uLi4u"; // 30 chars — exceeds schema min(20)

const validExtraction = {
  summary: "Patient has normal lab results with no critical findings.",
  extracted_labs: [
    { name: "WBC", value: "6.5", unit: "K/uL", reference_range: "4.0-11.0", flag: "normal" },
    { name: "Hemoglobin", value: "14.2", unit: "g/dL", reference_range: "13.5-17.5", flag: "normal" },
  ],
  medications: ["Lisinopril 10mg"],
  diagnoses: ["Hypertension"],
  suggested_questions: ["Should I continue my current dosage?", "Is my blood pressure under control?"],
  critical_flags: [],
  doc_type: "Lab Result",
};

function jsonResponse(res: Response): Promise<unknown> {
  return res.json() as Promise<unknown>;
}

function postReq(body: unknown): Request {
  return new Request("http://localhost/api/documents/decode-public", {
    method: "POST",
    headers: { "Content-Type": "application/json", origin: "http://localhost:8080" },
    body: JSON.stringify(body),
  });
}

// ── Tests ─────────────────────────────────────────────────────────────

describe("POST /api/documents/decode-public", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockChatJSON.mockResolvedValue(validExtraction);
  });

  it("returns 200 with extraction for valid text-only request", async () => {
    const res = await POST(postReq({ ocr_text: "Patient has normal blood work and is doing well." }));
    expect(res.status).toBe(200);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.summary).toBe(validExtraction.summary);

    const extraction = body.extraction as Record<string, unknown>;
    expect(extraction.doc_type).toBe("Lab Result");
    expect(extraction.extracted_labs).toEqual(validExtraction.extracted_labs);
    expect(extraction.medications).toEqual(validExtraction.medications);
  });

  it("returns 400 for empty body", async () => {
    const res = await POST(postReq({}));
    expect(res.status).toBe(400);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const err = body.error as Record<string, unknown>;
    expect(err.code).toBe("bad_request");
  });

  it("returns 400 for text shorter than 10 characters", async () => {
    const res = await POST(postReq({ ocr_text: "Hi" }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when neither text nor image is provided", async () => {
    const res = await POST(postReq({ ocr_text: "" }));
    expect(res.status).toBe(400);
  });

  it("calls OCR when image_base64 is provided without ocr_text", async () => {
    mockOcrFromImage.mockResolvedValue("Extracted text from image: blood work normal.");
    const res = await POST(postReq({ image_base64: fakeBase64, image_mime: "image/jpeg" }));
    expect(res.status).toBe(200);
    expect(mockOcrFromImage).toHaveBeenCalledOnce();
    expect(mockOcrFromImage).toHaveBeenCalledWith(fakeBase64, "image/jpeg");
    expect(mockChatJSON).toHaveBeenCalledOnce();
  });

  it("uses ocr_text directly when both text and image are provided", async () => {
    mockOcrFromImage.mockResolvedValue("should not be called");
    const res = await POST(postReq({ ocr_text: "Patient hemoglobin is 10.2", image_base64: fakeBase64 }));
    expect(res.status).toBe(200);
    expect(mockOcrFromImage).not.toHaveBeenCalled();
  });

  it("returns 500 when OCR fails", async () => {
    mockOcrFromImage.mockRejectedValue(new Error("OCR timeout"));
    const res = await POST(postReq({ image_base64: fakeBase64 }));
    expect(res.status).toBe(500);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const err = body.error as Record<string, unknown>;
    expect(err.code).toBe("ocr_failed");
  });

  it("returns 500 when AI extraction fails", async () => {
    mockChatJSON.mockRejectedValue(new Error("AI provider unavailable"));
    const res = await POST(postReq({ ocr_text: "Patient has normal blood work." }));
    expect(res.status).toBe(500);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const err = body.error as Record<string, unknown>;
    expect(err.code).toBe("ai_extraction_failed");
  });

  it("includes CORS headers in the response", async () => {
    const res = await POST(postReq({ ocr_text: "Patient has normal blood work." }));
    expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:8080");
    expect(res.headers.get("access-control-allow-headers")).toContain("authorization");
  });

  it("handles OPTIONS preflight request", async () => {
    const req = new Request("http://localhost/api/documents/decode-public", {
      method: "OPTIONS",
      headers: { origin: "http://localhost:8080" },
    });
    const res = await OPTIONS(req);
    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:8080");
  });

  it("passes reading_level to AI provider", async () => {
    await POST(postReq({ ocr_text: "Patient is doing well.", reading_level: "kid" }));

    const callArgs = mockChatJSON.mock.calls[0]?.[0] as { messages: Array<{ content: string }> };
    const systemMsg = callArgs.messages.find((m) => m.role === "system")?.content ?? "";
    expect(systemMsg).toContain("10-year-old");
  });

  it("returns empty arrays when AI returns no labs/medications", async () => {
    mockChatJSON.mockResolvedValue({
      ...validExtraction,
      extracted_labs: [],
      medications: [],
      diagnoses: [],
      suggested_questions: [],
      critical_flags: [],
    });
    const res = await POST(postReq({ ocr_text: "Patient is feeling fine." }));
    expect(res.status).toBe(200);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const extraction = body.extraction as Record<string, unknown>;
    expect(extraction.extracted_labs).toEqual([]);
    expect(extraction.medications).toEqual([]);
  });
});
