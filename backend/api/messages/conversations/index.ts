// GET  /api/messages/conversations — list user's conversations.
// POST /api/messages/conversations — get or create 1:1 conversation.
//
// CLIN-07: Secure messaging.

import { z } from "zod";
import { requireUser } from "../../../_lib/auth.js";
import { serviceClient } from "../../../_lib/supabase.js";
import { initSentry, Sentry } from "../../../_lib/sentry.js";
import { corsed, preflight, corsedJsonError } from "../../../_lib/cors.js";

export const config = { runtime: "nodejs" };
export const OPTIONS = (req: Request): Response => preflight(req);

const StartConversationBody = z.object({
  participant_id: z.string().uuid(),
});

export const GET = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  const supabase = serviceClient();

  // Get conversations where user is a participant, with last message and other participant.
  const { data: participations, error: partErr } = await supabase
    .from("conversation_participant")
    .select("conversation_id, last_read_at")
    .eq("user_id", user.id)
    .order("last_read_at", { ascending: false });

  if (partErr) {
    Sentry.captureException(partErr);
    return corsedJsonError(req, 500, "fetch_failed", partErr.message);
  }

  if (!participations || participations.length === 0) {
    return corsed(
      req,
      new Response(JSON.stringify({ ok: true, conversations: [] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }

  const convIds = participations.map((p: { conversation_id: string }) => p.conversation_id);

  // Get all participants in these conversations (excluding self).
  const { data: otherParticipants, error: otherErr } = await supabase
    .from("conversation_participant")
    .select("conversation_id, user_id, user:user_id(id, full_name)")
    .in("conversation_id", convIds)
    .neq("user_id", user.id);

  if (otherErr) {
    Sentry.captureException(otherErr);
    return corsedJsonError(req, 500, "fetch_failed", otherErr.message);
  }

  // Get last message per conversation.
  const { data: lastMessages, error: msgErr } = await supabase
    .from("message")
    .select("conversation_id, content, created_at, sender_id")
    .in("conversation_id", convIds)
    .order("created_at", { ascending: false });

  if (msgErr) {
    Sentry.captureException(msgErr);
    return corsedJsonError(req, 500, "fetch_failed", msgErr.message);
  }

  // Build conversation objects.
  const lastMsgMap = new Map<string, (typeof lastMessages)[number]>();
  for (const msg of lastMessages ?? []) {
    if (!lastMsgMap.has(msg.conversation_id)) {
      lastMsgMap.set(msg.conversation_id, msg);
    }
  }

  const myReadMap = new Map(
    participations.map((p: { conversation_id: string; last_read_at: string | null }) => [
      p.conversation_id,
      p.last_read_at,
    ]),
  );

  const conversations = convIds.map((cid: string) => {
    const other = (otherParticipants ?? []).find(
      (o: { conversation_id: string }) => o.conversation_id === cid,
    );
    const lastMsg = lastMsgMap.get(cid);
    const myReadAt = myReadMap.get(cid);
    const hasUnread =
      lastMsg != null &&
      (myReadAt == null || new Date(lastMsg.created_at) > new Date(myReadAt)) &&
      lastMsg.sender_id !== user.id;

    return {
      id: cid,
      other_user: other?.user ?? null,
      last_message: lastMsg
        ? {
            content: lastMsg.content,
            created_at: lastMsg.created_at,
            sender_id: lastMsg.sender_id,
          }
        : null,
      has_unread: hasUnread,
    };
  });

  // Sort by most recent message.
  conversations.sort((a: { last_message: { created_at: string } | null }, b: { last_message: { created_at: string } | null }) => {
    const aTime = a.last_message?.created_at ?? "";
    const bTime = b.last_message?.created_at ?? "";
    return bTime.localeCompare(aTime);
  });

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, conversations }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
};

export const POST = async (req: Request): Promise<Response> => {
  initSentry();

  const userOrError = await requireUser(req);
  if (userOrError instanceof Response) return corsed(req, userOrError);
  const user = userOrError;

  let body: z.infer<typeof StartConversationBody>;
  try {
    body = StartConversationBody.parse(await req.json());
  } catch (e) {
    return corsedJsonError(req, 400, "bad_request", e instanceof Error ? e.message : "Invalid JSON");
  }

  if (body.participant_id === user.id) {
    return corsedJsonError(req, 400, "self_chat", "Cannot start a conversation with yourself");
  }

  const supabase = serviceClient();

  // Check if conversation already exists.
  const { data: myConvs } = await supabase
    .from("conversation_participant")
    .select("conversation_id")
    .eq("user_id", user.id);

  if (myConvs && myConvs.length > 0) {
    const myConvIds = myConvs.map((c: { conversation_id: string }) => c.conversation_id);
    const { data: existing } = await supabase
      .from("conversation_participant")
      .select("conversation_id")
      .in("conversation_id", myConvIds)
      .eq("user_id", body.participant_id)
      .maybeSingle();

    if (existing) {
      return corsed(
        req,
        new Response(JSON.stringify({ ok: true, conversation_id: existing.conversation_id, existing: true }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    }
  }

  // Create new conversation.
  const { data: conv, error: convErr } = await supabase
    .from("conversation")
    .insert({})
    .select("id")
    .single();

  if (convErr || !conv) {
    Sentry.captureException(convErr);
    return corsedJsonError(req, 500, "create_failed", convErr?.message ?? "create failed");
  }

  const { error: partErr } = await supabase.from("conversation_participant").insert([
    { conversation_id: conv.id, user_id: user.id },
    { conversation_id: conv.id, user_id: body.participant_id },
  ]);

  if (partErr) {
    Sentry.captureException(partErr);
    // Clean up conversation on participant insert failure.
    await supabase.from("conversation").delete().eq("id", conv.id);
    return corsedJsonError(req, 500, "participant_failed", partErr.message);
  }

  return corsed(
    req,
    new Response(JSON.stringify({ ok: true, conversation_id: conv.id, existing: false }), {
      status: 201,
      headers: { "content-type": "application/json" },
    }),
  );
};
