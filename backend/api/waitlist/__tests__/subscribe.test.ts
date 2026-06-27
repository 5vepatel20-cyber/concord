import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockSupabaseFrom } = vi.hoisted(() => ({
  mockSupabaseFrom: vi.fn(),
}));

vi.mock("../../../_lib/supabase.js", () => ({
  serviceClient: () => ({
    from: mockSupabaseFrom,
  }),
}));

vi.mock("../../../_lib/sentry.js", () => ({
  initSentry: vi.fn(),
}));

import { POST, OPTIONS } from "../subscribe.js";

function jsonResponse(res: Response): Promise<unknown> {
  return res.json() as Promise<unknown>;
}

function postReq(body: unknown): Request {
  return new Request("http://localhost/api/waitlist/subscribe", {
    method: "POST",
    headers: { "Content-Type": "application/json", origin: "http://localhost:8080" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/waitlist/subscribe", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 200 and inserts email on valid request", async () => {
    const mockUpsert = vi.fn().mockResolvedValue({ error: null });
    mockSupabaseFrom.mockReturnValue({ upsert: mockUpsert });

    const res = await POST(postReq({ email: "test@example.com" }));
    expect(res.status).toBe(200);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    expect(body.ok).toBe(true);

    expect(mockSupabaseFrom).toHaveBeenCalledWith("waitlist");
    expect(mockUpsert).toHaveBeenCalledWith(
      { email: "test@example.com", source: "landing", referred_from: null },
      { onConflict: "email", ignoreDuplicates: true },
    );
  });

  it("returns 200 with custom source and referred_from", async () => {
    const mockUpsert = vi.fn().mockResolvedValue({ error: null });
    mockSupabaseFrom.mockReturnValue({ upsert: mockUpsert });

    const res = await POST(postReq({ email: "test@example.com", source: "decode-result", referred_from: "https://concord.so" }));
    expect(res.status).toBe(200);
    expect(mockUpsert).toHaveBeenCalledWith(
      { email: "test@example.com", source: "decode-result", referred_from: "https://concord.so" },
      { onConflict: "email", ignoreDuplicates: true },
    );
  });

  it("returns 400 for invalid email", async () => {
    const res = await POST(postReq({ email: "not-an-email" }));
    expect(res.status).toBe(400);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const err = body.error as Record<string, unknown>;
    expect(err.code).toBe("bad_request");
  });

  it("returns 400 for empty body", async () => {
    const res = await POST(postReq({}));
    expect(res.status).toBe(400);
  });

  it("returns 500 when Supabase insert fails", async () => {
    const mockUpsert = vi.fn().mockResolvedValue({ error: new Error("DB connection failed") });
    mockSupabaseFrom.mockReturnValue({ upsert: mockUpsert });

    const res = await POST(postReq({ email: "test@example.com" }));
    expect(res.status).toBe(500);

    const body = (await jsonResponse(res)) as Record<string, unknown>;
    const err = body.error as Record<string, unknown>;
    expect(err.code).toBe("waitlist_save_failed");
  });

  it("includes CORS headers in the response", async () => {
    const mockUpsert = vi.fn().mockResolvedValue({ error: null });
    mockSupabaseFrom.mockReturnValue({ upsert: mockUpsert });

    const res = await POST(postReq({ email: "test@example.com" }));
    expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:8080");
  });

  it("handles OPTIONS preflight request", async () => {
    const req = new Request("http://localhost/api/waitlist/subscribe", {
      method: "OPTIONS",
      headers: { origin: "http://localhost:8080" },
    });
    const res = await OPTIONS(req);
    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:8080");
  });

  it("normalizes email to lowercase", async () => {
    const mockUpsert = vi.fn().mockResolvedValue({ error: null });
    mockSupabaseFrom.mockReturnValue({ upsert: mockUpsert });

    await POST(postReq({ email: "Test.User@Example.COM" }));
    expect(mockUpsert).toHaveBeenCalledWith(
      { email: "test.user@example.com", source: "landing", referred_from: null },
      { onConflict: "email", ignoreDuplicates: true },
    );
  });

  it("is idempotent — duplicate email returns 200", async () => {
    const mockUpsert = vi.fn().mockResolvedValue({ error: null });
    mockSupabaseFrom.mockReturnValue({ upsert: mockUpsert });

    const res1 = await POST(postReq({ email: "test@example.com" }));
    const res2 = await POST(postReq({ email: "test@example.com" }));
    expect(res1.status).toBe(200);
    expect(res2.status).toBe(200);
    expect(mockUpsert).toHaveBeenCalledTimes(2);
  });
});
