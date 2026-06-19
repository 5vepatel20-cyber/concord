// GET /api/health — public, no auth. Returns 200 with a status snapshot.
// Useful for Vercel health checks, Sentry wiring verification, and CI.

import { initSentry } from "../_lib/sentry.js";
import { getEnv, mask } from "../_lib/env.js";
import { serviceClient } from "../_lib/supabase.js";

export const config = {
  // Vercel Node runtime. No version suffix — Vercel uses the
  // team-default Node version, currently 24.x on this project.
  runtime: "nodejs",
};

export const GET = async (_req: Request): Promise<Response> => {
  initSentry();
  const env = getEnv();

  // Probe Supabase: a cheap SELECT 1 against an obviously-cheap view
  // (PostgREST ping) tells us the DB is reachable and creds work.
  const supabase = serviceClient();
  const startedAt = Date.now();
  let dbOk = false;
  let dbError: string | null = null;
  try {
    const { error } = await supabase.from("symptom_term").select("id", { count: "exact", head: true });
    if (error) {
      dbError = error.message;
    } else {
      dbOk = true;
    }
  } catch (e) {
    dbError = e instanceof Error ? e.message : String(e);
  }
  const dbLatencyMs = Date.now() - startedAt;

  const body = {
    ok: true,
    env: env.VERCEL_ENV ?? env.NODE_ENV,
    services: {
      supabase: { ok: dbOk, latency_ms: dbLatencyMs, error: dbError },
      sentry: { ok: Boolean(env.SENTRY_DSN_BACKEND) },
      ai: { ok: Boolean(env.GEMINI_API_KEY), provider: "gemini", key: mask(env.GEMINI_API_KEY, 6, 4) },
    },
    timestamp: new Date().toISOString(),
  };

  return new Response(JSON.stringify(body, null, 2), {
    status: 200,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
};
