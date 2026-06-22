// POST /api/trials/search — auth-required. Searches ClinicalTrials.gov
// for studies matching the patient's condition and returns a curated list.
//
// TRIAL-01: Proxies the public ClinicalTrials.gov API v2 so the Flutter
// client doesn't need to handle CORS, rate-limiting, or response parsing.

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const CT_GOV_BASE = "https://clinicaltrials.gov/api/v2/studies";

const BodySchema = z.object({
  query: z.string().min(1).max(200),
  maxResults: z.number().int().min(1).max(50).default(10),
  recruitingOnly: z.boolean().default(true),
  phase: z
    .enum(["EARLY1", "PHASE1", "PHASE2", "PHASE3", "PHASE4", "NA"])
    .optional(),
});

interface TrialStudy {
  nctId: string;
  title: string;
  status: string;
  phase: string;
  conditions: string[];
  interventions: string[];
  location: string | null;
  briefSummary: string;
  lastUpdated: string;
  url: string;
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
    // Build ClinicalTrials.gov API query params.
    const params = new URLSearchParams({
      "query.term": body.query,
      "pageSize": String(body.maxResults),
      "format": "json",
      "fields": "NCTId|BriefTitle|OverallStatus|Phase|Condition|InterventionName|OverallOfficialName|City|Country|BriefSummary|LastUpdateSubmitDate",
    });

    if (body.recruitingOnly) {
      params.set("filter.overallStatus", "RECRUITING");
    }
    if (body.phase) {
      params.set("filter.phase", body.phase);
    }

    const response = await fetch(`${CT_GOV_BASE}?${params.toString()}`, {
      headers: { "Accept": "application/json" },
    });

    if (!response.ok) {
      throw new Error(`ClinicalTrials.gov returned ${response.status}`);
    }

    const raw: { studies?: unknown[] } = await response.json();
    const studies: TrialStudy[] = (raw.studies ?? []).map((s: Record<string, unknown>) => {
      const proto = (s["protocolSection"] as Record<string, unknown>) ?? {};
      const id = (proto["identificationModule"] as Record<string, unknown>) ?? {};
      const status = (proto["statusModule"] as Record<string, unknown>) ?? {};
      const design = (proto["designModule"] as Record<string, unknown>) ?? {};
      const conditions = (proto["conditionsModule"] as Record<string, unknown>) ?? {};
      const arms = (proto["armsInterventionsModule"] as Record<string, unknown>) ?? {};
      const contacts = (proto["contactsLocationsModule"] as Record<string, unknown>) ?? {};
      const desc = (proto["descriptionModule"] as Record<string, unknown>) ?? {};

      const locations = (contacts["locations"] as Record<string, unknown>[]) ?? [];

      return {
        nctId: (id["nctId"] as string) ?? "",
        title: (id["briefTitle"] as string) ?? "Untitled study",
        status: (status["overallStatus"] as string) ?? "UNKNOWN",
        phase: (design["phases"] as string[])?.[0] ?? "NA",
        conditions: (conditions["conditions"] as string[]) ?? [],
        interventions: (arms["interventionNames"] as string[]) ?? [],
        location: locations.length > 0
          ? `${(locations[0]["city"] as string) ?? "?"}, ${(locations[0]["country"] as string) ?? "?"}`
          : null,
        briefSummary: ((desc["briefSummary"] as string) ?? "").slice(0, 500),
        lastUpdated: (status["lastUpdateSubmitDate"] as string) ?? "",
        url: `https://clinicaltrials.gov/study/${(id["nctId"] as string) ?? ""}`,
      };
    });

    return corsed(
      req,
      new Response(
        JSON.stringify({ ok: true, studies, total: studies.length }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  } catch (e) {
    Sentry.captureException(e);
    return corsedJsonError(req, 502, "upstream_failed", e instanceof Error ? e.message : String(e));
  }
};
