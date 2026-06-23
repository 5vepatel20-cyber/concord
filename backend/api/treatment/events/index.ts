// GET  /api/treatment/events — list treatment events (filtered by month/status).
// POST /api/treatment/events — create a new treatment event.
//
// ONB-05: Treatment calendar.

import { z } from "zod";
import { requireUser } from "../../../_lib/auth.js";
import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

// ── Shared types ──────────────────────────────────────────────────────────────

const EventType = z.enum(["infusion", "appointment", "lab", "scan", "surgery", "other"]);
const EventStatus = z.enum(["scheduled", "completed", "cancelled", "rescheduled"]);

// ── POST body ─────────────────────────────────────────────────────────────────

const CreateBody = z.object({
  event_type: EventType,
  title: z.string().min(1).max(300),
  description: z.string().max(2000).nullable().optional(),
  location: z.string().max(500).nullable().optional(),
  event_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  event_time: z.string().regex(/^\d{2}:\d{2}$/).nullable().optional(),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  status: EventStatus.default("scheduled"),
  notes: z.string().max(4000).nullable().optional(),
});

// ── Helpers ───────────────────────────────────────────────────────────────────

async function resolvePatientId(req: Request, user: { id: string; role?: string }): Promise<string | Response> {
  const supabase = serviceClient();
  const url = new URL(req.url);

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role === "patient") return user.id;

  const targetPatient = url.searchParams.get("patient_id");
  if (!targetPatient) {
    return corsedJsonError(req, 400, "missing_patient", "Caregivers must specify patient_id");
  }
  const { data: rel } = await supabase
    .from("care_relationship")
    .select("id")
    .eq("patient_id", targetPatient)
    .eq("member_user_id", user.id)
    .eq("status", "active")
    .maybeSingle();
  if (!rel) {
    return corsedJsonError(req, 403, "not_caregiver", "Not an active caregiver for this patient");
  }
  return targetPatient;
}

// ── GET ───────────────────────────────────────────────────────────────────────

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const patientOrResp = await resolvePatientId(req, user);
  if (patientOrResp instanceof Response) return patientOrResp;
  const patientId = patientOrResp;

  const url = new URL(req.url);
  const year = parseInt(url.searchParams.get("year") ?? "", 10);
  const month = parseInt(url.searchParams.get("month") ?? "", 10);
  const status = url.searchParams.get("status");

  const supabase = serviceClient();

  let query = supabase
    .from("treatment_event")
    .select("*")
    .eq("patient_id", patientId)
    .order("event_date", { ascending: true })
    .order("event_time", { ascending: true });

  if (!isNaN(year) && !isNaN(month)) {
    const start = `${year}-${String(month).padStart(2, "0")}-01`;
    const endDate = new Date(year, month, 0);
    const end = `${year}-${String(month).padStart(2, "0")}-${String(endDate.getDate()).padStart(2, "0")}`;
    query = query.gte("event_date", start).lte("event_date", end);
  }

  if (status) {
    query = query.eq("status", status);
  }

  const { data, error } = await query;
  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "fetch_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, events: data ?? [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

// ── POST ──────────────────────────────────────────────────────────────────────

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof CreateBody>;
  try {
    body = CreateBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON body");
  }

  const supabase = serviceClient();

  const row = {
    patient_id: user.id,
    event_type: body.event_type,
    title: body.title,
    description: body.description ?? null,
    location: body.location ?? null,
    event_date: body.event_date,
    event_time: body.event_time ?? null,
    end_date: body.end_date ?? null,
    status: body.status,
    notes: body.notes ?? null,
  };

  const { data, error } = await supabase
    .from("treatment_event")
    .insert(row)
    .select("*")
    .single();

  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "insert_failed", error?.message ?? "insert failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, event: data }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
