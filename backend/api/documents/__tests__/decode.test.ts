import { describe, it, expect, vi, beforeEach } from "vitest";
import type { AIProvider } from "../../../_lib/ai/types.js";
import type { AuthedUser } from "../../../_lib/auth.js";

// ── Hoisted mock fns (must use vi.hoisted so they're available in vi.mock factory) ──

// ── Build a Supabase chain mock that's self-contained ──────────────────

function buildSupabaseChain(result: { data: unknown; error: null | { message: string } }) {
  const single = vi.fn<() => Promise<typeof result>>().mockResolvedValue(result);
  const select = vi.fn<() => { single: typeof single }>(() => ({ single }));
  const insert = vi.fn<(...args: unknown[]) => { select: typeof select }>(() => ({ select }));
  const from = vi.fn<() => { insert: typeof insert }>(() => ({ insert }));
  return { from, insert, select, single };
}

// ── Hoisted mock fns ──────────────────────────────────────────────────

const { mockChatJSON, mockOcrFromImage, mockRequireUser, supabaseChain } = vi.hoisted(() => {
  const chain = buildSupabaseChain({ data: null, error: null });
  return {
    mockChatJSON: vi.fn(),
    mockOcrFromImage: vi.fn(),
    mockRequireUser: vi.fn<() => Promise<AuthedUser | Response>>(),
    supabaseChain: chain,
  };
});

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

vi.mock("../../../_lib/auth.js", () => ({
  requireUser: (...args: Parameters<typeof mockRequireUser>) => mockRequireUser(...args),
}));

vi.mock("../../../_lib/supabase.js", () => ({
  serviceClient: () => ({
    from: supabaseChain.from,
  }),
}));

// ── Module under test ─────────────────────────────────────────────────

import { POST, OPTIONS } from "../decode.js";

// ── Fixtures ──────────────────────────────────────────────────────────

const mockUser: AuthedUser = { id: "user-123", email: "test@example.com", role: "patient" };

const fakeBase64 = "aW1hZ2UuLi4uLi4uLi4uLi4uLi4u"; // 30 chars

const validExtraction = {
  summary: "Patient has normal lab results with no critical findings.",
  extracted_labs: [
    { name: "WBC", value: "6.5", unit: "K/uL", reference_range: "4.0-11.0", flag: "normal" },
  ],
  medications: ["Lisinopril 10mg"],
  diagnoses: ["Hypertension"],
  suggested_questions: ["Should I continue my current dosage?"],
  critical_flags: [],
  doc_type: "Lab Result",
};

function jsonResponse(res: Response): Promise<unknown> {
  return res.json() as Promise<unknown>;
}

function postReq(body: unknown): Request {
  return new Request("http://localhost/api/documents/decode", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      authorization: "Bearer valid.jwt.token",
      origin: "http://localhost:8080",
    },
    body: JSON.stringify(body),
  });
}

/** Rebuild the Supabase chain to return a specific DB result. */
function mockDbResult(result: { id: string; ai_plain_summary: string; extracted_values: unknown }) {
  supabaseChain.single.mockReset();
  supabaseChain.single.mockResolvedValue({ data: result, error: null });
}

/** Rebuild the Supabase chain to simulate a DB error. */
function mockDbError(message: string) {
  supabaseChain.single.mockReset();
  supabaseChain.single.mockResolvedValue({ data: null, error: { message } });
}

// ── Tests ─────────────────────────────────────────────────────────────

describe("POST /api/documents/decode (auth-required)", () => {
  beforeEach(() => {
    mockChatJSON.mockReset();
    mockOcrFromImage.mockReset();
    mockRequireUser.mockReset();
    vi.clearAllMocks();

    mockChatJSON.mockResolvedValue(validExtraction);
    mockRequireUser.mockResolvedValue(mockUser);

    // Reset the Supabase chain to a default success result.
    supabaseChain.single.mockReset();
    supabaseChain.insert.mockReset();
    supabaseChain.select.mockReset();
    supabaseChain.from.mockReset().mockReturnValue({ insert: supabaseChain.insert });
    supabaseChain.insert.mockReturnValue({ select: supabaseChain.select });
    supabaseChain.select.mockReturnValue({ single: supabaseChain.single });
    supabaseChain.single.mockResolvedValue({
      data: { id: "doc-default", ai_plain_summary: validExtraction.summary, extracted_values: validExtraction },
      error: null,
    });
  });

  it("returns 201 with extraction for valid request", async () => {
    mockDbResult({ id: "doc-123", ai_plain_summary: validExtraction.summary, extracted_values: validExtraction });

    const res = await POST(postReq({ ocr_text: "Patient has normal blood work and is doing well.", kind: "lab_result" }));
    expect(res.status).toBe(201);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.document_id).toBe("doc-123");
    expect(body.summary).toBe(validExtraction.summary);

    const extraction = body.extraction as Record<string, unknown>;
    expect(extraction.extracted_labs).toEqual(validExtraction.extracted_labs);
  });

  it("returns 401 when auth token is missing", async () => {
    mockRequireUser.mockResolvedValue(
      new Response(JSON.stringify({ error: { code: "missing_bearer" } }), { status: 401 }),
    );

    const req = new Request("http://localhost/api/documents/decode", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ocr_text: "Patient is doing well." }),
    });
    const res = await POST(req);
    expect(res.status).toBe(401);
  });

  it("returns 400 for invalid body", async () => {
    const res = await POST(postReq({}));
    expect(res.status).toBe(400);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const err = body.error as Record<string, unknown>;
    expect(err.code).toBe("bad_request");
  });

  it("returns 400 when text is shorter than 10 characters", async () => {
    const res = await POST(postReq({ ocr_text: "Hi" }));
    expect(res.status).toBe(400);
  });

  it("calls OCR when image_base64 is provided without ocr_text", async () => {
    mockOcrFromImage.mockResolvedValue("Extracted text from image: blood work normal.");

    const res = await POST(postReq({ image_base64: fakeBase64, image_mime: "image/png" }));
    expect(res.status).toBe(201);
    expect(mockOcrFromImage).toHaveBeenCalledOnce();
    expect(mockOcrFromImage).toHaveBeenCalledWith(fakeBase64, "image/png");
  });

  it("uses ocr_text directly when both text and image are provided", async () => {
    mockOcrFromImage.mockResolvedValue("should not be called");

    const res = await POST(postReq({ ocr_text: "Hemoglobin is low.", image_base64: fakeBase64 }));
    expect(res.status).toBe(201);
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

  it("returns 500 when database save fails", async () => {
    mockDbError("DB connection failed");

    const res = await POST(postReq({ ocr_text: "Patient has normal blood work." }));
    expect(res.status).toBe(500);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const err = body.error as Record<string, unknown>;
    expect(err.code).toBe("document_save_failed");
  });

  it("includes CORS headers in the response", async () => {
    const res = await POST(postReq({ ocr_text: "Patient has normal blood work." }));
    expect(res.status).toBe(201);
    expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:8080");
  });

  it("handles OPTIONS preflight request", async () => {
    const req = new Request("http://localhost/api/documents/decode", {
      method: "OPTIONS",
      headers: { origin: "http://localhost:8080" },
    });
    const res = await OPTIONS(req);
    expect(res.status).toBe(204);
  });

  it("passes reading_level kid instruction to AI", async () => {
    await POST(postReq({ ocr_text: "Patient is doing well.", reading_level: "kid" }));

    const callArgs = mockChatJSON.mock.calls[0]?.[0] as { messages: Array<{ role: string; content: string }> };
    const systemMsg = callArgs.messages.find((m) => m.role === "system")?.content ?? "";
    expect(systemMsg).toContain("10-year-old");
  });

  it("saves document to Supabase with correct patient_id and kind", async () => {
    supabaseChain.insert.mockReset();
    supabaseChain.insert.mockReturnValue({ select: supabaseChain.select });

    await POST(postReq({ ocr_text: "Patient has normal blood work.", kind: "lab_result" }));

    expect(supabaseChain.from).toHaveBeenCalledWith("document");
    expect(supabaseChain.insert).toHaveBeenCalledOnce();

    const insertArgs = (supabaseChain.insert.mock.calls[0]?.[0] ?? {}) as Record<string, unknown>;
    expect(insertArgs.patient_id).toBe("user-123");
    expect(insertArgs.kind).toBe("lab_result");
    expect(insertArgs.ai_plain_summary).toBe(validExtraction.summary);
  });
});
