// GET  /api/messages/conversations/[id] — list messages in a conversation.
// POST /api/messages/conversations/[id] — send a message.
// PATCH /api/messages/conversations/[id] — mark conversation as read.
//
// CLIN-07: Secure messaging.

import { z } from "zod";
import { requireUser } from "../../../../_lib/auth.js";
import { serviceClient } from "../../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const SendMessageBody = z.object({
  content: z.string().min(1).max(10000),
});

export const GET = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const convId = ctx.params.id!;

  const supabase = serviceClient();

  // Verify user is a participant.
  const { data: part } = await supabase
    .from("conversation_participant")
    .select("id")
    .eq("conversation_id", convId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!part) {
    return corsedJsonError(req, 403, "forbidden", "Not a participant in this conversation");
  }

  const url = new URL(req.url);
  const limit = parseInt(url.searchParams.get("limit") ?? "100", 10);
  const before = url.searchParams.get("before"); // cursor for pagination

  let query = supabase
    .from("message")
    .select("id, sender_id, content, created_at")
    .eq("conversation_id", convId)
    .order("created_at", { ascending: false })
    .limit(Math.min(limit, 200));

  if (before) {
    query = query.lt("created_at", before);
  }

  const { data, error } = await query;
  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "fetch_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, messages: data ?? [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const POST = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const convId = ctx.params.id!;

  let body: z.infer<typeof SendMessageBody>;
  try {
    body = SendMessageBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  const supabase = serviceClient();

  // Verify user is a participant.
  const { data: part } = await supabase
    .from("conversation_participant")
    .select("id")
    .eq("conversation_id", convId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!part) {
    return corsedJsonError(req, 403, "forbidden", "Not a participant in this conversation");
  }

  const { data, error } = await supabase
    .from("message")
    .insert({
      conversation_id: convId,
      sender_id: user.id,
      content: body.content,
    })
    .select("id, sender_id, content, created_at")
    .single();

  if (error || !data) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "send_failed", error?.message ?? "send failed");
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, message: data }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const PATCH = async (
  req: Request,
  ctx: { params: Record<string, string> },
): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;
  const convId = ctx.params.id!;

  const supabase = serviceClient();

  const { error } = await supabase
    .from("conversation_participant")
    .update({ last_read_at: new Date().toISOString() })
    .eq("conversation_id", convId)
    .eq("user_id", user.id);

  if (error) {
    Sentry.captureException(error);
    return corsedJsonError(req, 500, "update_failed", error.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};
