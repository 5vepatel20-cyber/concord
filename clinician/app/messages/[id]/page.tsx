import { notFound, redirect } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { Nav } from "../../../components/Nav";
import { MarkAsRead } from "../../../components/MarkAsRead";

async function markAsRead(conversationId: string) {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase
    .from("conversation_participant")
    .update({ last_read_at: new Date().toISOString() })
    .eq("conversation_id", conversationId)
    .eq("user_id", user.id);
}

async function sendMessage(conversationId: string, _formData: FormData) {
  "use server";

  const content = _formData.get("content") as string;
  if (!content || !content.trim()) return;

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase.from("message").insert({
    conversation_id: conversationId,
    sender_id: user.id,
    content: content.trim(),
  });
}

async function fetchThread(conversationId: string) {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: part } = await supabase
    .from("conversation_participant")
    .select("id")
    .eq("conversation_id", conversationId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!part) return null;

  const { data: messages } = await supabase
    .from("message")
    .select("id, sender_id, content, created_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true });

  const { data: otherParticipants } = await supabase
    .from("conversation_participant")
    .select("user:user!inner(id, full_name)")
    .eq("conversation_id", conversationId)
    .neq("user_id", user.id);

  const otherParticipant = otherParticipants?.[0] as any;
  const patientName = otherParticipant?.user?.full_name ?? "Unknown";

  return {
    messages: (messages ?? []).map((m: any) => ({
      id: m.id,
      sender_id: m.sender_id,
      content: m.content,
      created_at: m.created_at,
      is_me: m.sender_id === user.id,
    })),
    patient_name: patientName,
    current_user_id: user.id,
  };
}

export default async function MessageThreadPage({
  params,
}: {
  params: { id: string };
}) {
  const thread = await fetchThread(params.id);
  if (!thread) notFound();

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{
        flex: 1,
        display: "flex",
        flexDirection: "column",
        maxWidth: 720,
      }}>
        <div style={{
          padding: "16px 24px",
          borderBottom: "1px solid var(--hairline)",
          display: "flex",
          alignItems: "center",
          gap: 12,
        }}>
          <a href="/messages" style={{
            color: "var(--hint)",
            textDecoration: "none",
            fontSize: 14,
          }}>
            &larr; Back
          </a>
          <div style={{
            width: 36,
            height: 36,
            borderRadius: 18,
            background: "var(--concord-blue-tint)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 14,
            fontWeight: 600,
            color: "var(--concord-blue)",
          }}>
            {thread.patient_name.charAt(0).toUpperCase()}
          </div>
          <h1 style={{ fontSize: 18, fontWeight: 600, margin: 0 }}>
            {thread.patient_name}
          </h1>
        </div>

        <div style={{
          flex: 1,
          overflowY: "auto",
          padding: "16px 24px",
          display: "flex",
          flexDirection: "column",
          gap: 8,
        }}>
          {thread.messages.length === 0 ? (
            <p style={{ color: "var(--hint)", fontSize: 15, textAlign: "center", marginTop: 48 }}>
              No messages yet. Send a message to start the conversation.
            </p>
          ) : (
            thread.messages.map((m: any) => (
              <div
                key={m.id}
                style={{
                  alignSelf: m.is_me ? "flex-end" : "flex-start",
                  maxWidth: "75%",
                  padding: "10px 14px",
                  borderRadius: 14,
                  background: m.is_me ? "var(--concord-blue)" : "var(--mist)",
                  color: m.is_me ? "var(--surface)" : "var(--ink)",
                  fontSize: 14,
                  lineHeight: 1.5,
                }}
              >
                <div>{m.content}</div>
                <div style={{
                  fontSize: 11,
                  marginTop: 4,
                  opacity: 0.6,
                  textAlign: "right",
                }}>
                  {new Date(m.created_at).toLocaleString(undefined, {
                    month: "short",
                    day: "numeric",
                    hour: "numeric",
                    minute: "2-digit",
                  })}
                </div>
              </div>
            ))
          )}
        </div>

        <form
          action={sendMessage.bind(null, params.id)}
          style={{
            display: "flex",
            gap: 8,
            padding: "16px 24px",
            borderTop: "1px solid var(--hairline)",
            background: "var(--surface)",
          }}
        >
          <input
            name="content"
            type="text"
            placeholder="Type a message\u2026"
            autoFocus
            style={{
              flex: 1,
              padding: "10px 14px",
              fontSize: 14,
              border: "1px solid var(--hairline)",
              borderRadius: 10,
              background: "var(--mist)",
              color: "var(--ink)",
              outline: "none",
            }}
          />
          <button
            type="submit"
            style={{
              padding: "10px 20px",
              fontSize: 14,
              fontWeight: 600,
              background: "var(--concord-blue)",
              color: "var(--surface)",
              border: "none",
              borderRadius: 10,
              cursor: "pointer",
            }}
          >
            Send
          </button>
        </form>
        <MarkAsRead conversationId={params.id} markAsReadAction={markAsRead} />
      </main>
    </div>
  );
}
