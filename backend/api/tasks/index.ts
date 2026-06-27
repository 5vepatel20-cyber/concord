// CARE-04: Task CRUD endpoints.
//
// GET  /api/tasks          — list tasks for current user (patient sees own;
//                            caregiver sees unassigned for their patients + assigned).
// POST /api/tasks          — create a new task (patient or caregiver).

import { z } from "zod";
import { requireUser } from "../../_lib/auth.js";
import { serviceClient } from "../../_lib/supabase.js";
import { initSentry, Sentry } from "../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const TASK_CATEGORIES = ["appointment", "measurement", "lifestyle", "admin"] as const;
const TASK_SOURCES = ["manual", "ai_proposed", "clinician"] as const;

const CreateSchema = z.object({
  title: z.string().min(1).max(500),
  category: z.enum(TASK_CATEGORIES).default("admin"),
  due_at: z.string().datetime().nullable().optional(),
  assigned_to: z.string().uuid().nullable().optional(),
});

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const supabase = serviceClient();
  const url = new URL(req.url);
  const status = url.searchParams.get("status"); // optional filter: open | done

  let query = supabase
    .from("task")
    .select("*")
    .or(`patient_id.eq.${user.id},assigned_to.eq.${user.id}`)
    .order("due_at", { ascending: true, nullsFirst: false });

  if (status) {
    query = query.eq("status", status);
  }

  const { data: tasks, error } = await query;
  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "list_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, tasks }), {
      headers: { "content-type": "application/json" },
    }),
  );
};

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof CreateSchema>;
  try {
    body = CreateSchema.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid body");
  }

  const supabase = serviceClient();

  // Determine patient_id: if caregiver, require it in the body; if patient, use own.
  const patientId = user.role === "patient" ? user.id : body.assigned_to ?? user.id;

  const { data: task, error } = await supabase
    .from("task")
    .insert({
      patient_id: patientId,
      title: body.title,
      category: body.category,
      due_at: body.due_at ? new Date(body.due_at).toISOString() : null,
      assigned_to: body.assigned_to ?? null,
      source: "manual",
    })
    .select()
    .single();

  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "create_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, task }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
