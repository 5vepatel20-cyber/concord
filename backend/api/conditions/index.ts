// GET /api/conditions — auth-required. Lists/search coded conditions.
// ONB-01: Coded condition selection.
//
// Query params:
//   q      — search by display_name or icd10_code (optional)
//   limit  — max results (default 50, max 100)

import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);

  const url = new URL(req.url);
  const q = url.searchParams.get("q") ?? "";
  const limit = Math.min(parseInt(url.searchParams.get("limit") ?? "50", 10), 100);

  const supabase = serviceClient();

  let query = supabase
    .from("condition")
    .select("id, display_name, icd10_code, category, pro_ctcae_panel_id")
    .order("display_name", { ascending: true })
    .limit(limit);

  if (q.trim()) {
    const pattern = `%${q.trim()}%`;
    query = query.or(`display_name.ilike.${pattern},icd10_code.ilike.${pattern}`);
  }

  const { data, error } = await query;

  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "fetch_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, conditions: data ?? [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
