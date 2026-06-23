// POST /api/medications/rxnorm/search — auth-required. Proxies the NIH
// RxNorm REST API to provide medication autocomplete for the add-medication
// screen. Returns normalized drug names with RxNorm CUIs.
//
// MED-01: Uses the public RxNav API (no token required). The Vercel backend
// handles CORS so the Flutter client calls us directly.
//
// RxNav docs: https://rxnav.nlm.nih.gov/RxNormAPIs.html

import { z } from "zod";
import { requireUser } from "../../../_lib/auth.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const RXNAV_BASE = "https://rxnav.nlm.nih.gov/REST";

const BodySchema = z.object({
  query: z.string().min(1).max(200),
  maxResults: z.number().int().min(1).max(50).default(20),
});

interface RxNormResult {
  rxcui: string;
  name: string;
  synonym: string | null;
  tty: string | null;
}

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);

  let body: z.infer<typeof BodySchema>;
  try {
    body = BodySchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  try {
    // Step 1: GET /REST/drugs?name=<query> for the initial search.
    const params = new URLSearchParams({ name: body.query });
    const drugResp = await fetch(`${RXNAV_BASE}/drugs?${params.toString()}`, {
      headers: { Accept: "application/json" },
    });
    if (!drugResp.ok) {
      throw new Error(`RxNav returned ${drugResp.status}`);
    }

    const drugJson: { drugGroup?: { conceptGroup?: unknown[] } } = await drugResp.json();
    const results: RxNormResult[] = [];

    // Parse the response structure — it's a nested array of concept groups.
    const conceptGroups = drugJson.drugGroup?.conceptGroup ?? [];
    for (const group of conceptGroups) {
      const g = group as Record<string, unknown>;
      const props = (g["conceptProperties"] as Record<string, unknown>[]) ?? [];
      for (const cp of props) {
        if (results.length >= body.maxResults) break;
        results.push({
          rxcui: String(cp["rxcui"] ?? ""),
          name: String(cp["name"] ?? ""),
          synonym: (cp["synonym"] as string) ?? null,
          tty: (cp["tty"] as string) ?? null,
        });
      }
      if (results.length >= body.maxResults) break;
    }

    // Step 2: If we got few results, also try spelling suggestions via
    // /REST/spellingsuggestions?name=<query>.
    if (results.length < 3) {
      const spellResp = await fetch(
        `${RXNAV_BASE}/spellingsuggestions?${params.toString()}`,
        { headers: { Accept: "application/json" } },
      );
      if (spellResp.ok) {
        const spellJson: {
          suggestionGroup?: { suggestionList?: { suggestion?: string[] } };
        } = await spellResp.json();
        const suggestions =
          spellJson.suggestionGroup?.suggestionList?.suggestion ?? [];
        // Try the first few suggestions as new searches.
        for (const s of suggestions.slice(0, 3)) {
          if (results.length >= body.maxResults) break;
          if (s.toLowerCase() === body.query.toLowerCase()) continue;
          const retry = await fetch(
            `${RXNAV_BASE}/drugs?name=${encodeURIComponent(s)}`,
            { headers: { Accept: "application/json" } },
          );
          if (!retry.ok) continue;
          const retryJson: { drugGroup?: { conceptGroup?: unknown[] } } =
            await retry.json();
          for (const g of retryJson.drugGroup?.conceptGroup ?? []) {
            const grp = g as Record<string, unknown>;
            const props = (grp["conceptProperties"] as Record<string, unknown>[]) ?? [];
            for (const cp of props) {
              if (results.length >= body.maxResults) break;
              // Avoid duplicates by rxcui.
              if (results.some((r) => r.rxcui === String(cp["rxcui"] ?? "")))
                continue;
              results.push({
                rxcui: String(cp["rxcui"] ?? ""),
                name: String(cp["name"] ?? ""),
                synonym: (cp["synonym"] as string) ?? null,
                tty: (cp["tty"] as string) ?? null,
              });
            }
            if (results.length >= body.maxResults) break;
          }
        }
      }
    }

    return corsed(
      req,
      new Response(
        JSON.stringify({ ok: true, results, total: results.length }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  } catch (e) {
    Sentry.captureException(e);
    return corsedJsonError(req, 502, "upstream_failed", e instanceof Error ? e.message : String(e));
  }
};
