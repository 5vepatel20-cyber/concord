import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";

async function fetchConversations() {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") {
    return [];
  }

  const { data: participations } = await supabase
    .from("conversation_participant")
    .select("conversation_id, last_read_at")
    .eq("user_id", user.id)
    .order("last_read_at", { ascending: false });

  if (!participations || participations.length === 0) return [];

  const convIds = participations.map((p: any) => p.conversation_id);

  const { data: otherParticipants } = await supabase
    .from("conversation_participant")
    .select("conversation_id, user:user!inner(id, full_name)")
    .in("conversation_id", convIds)
    .neq("user_id", user.id);

  const { data: lastMessages } = await supabase
    .from("message")
    .select("conversation_id, content, created_at, sender_id")
    .in("conversation_id", convIds)
    .order("created_at", { ascending: false });

  const lastMsgMap = new Map<string, any>();
  for (const msg of lastMessages ?? []) {
    if (!lastMsgMap.has(msg.conversation_id)) {
      lastMsgMap.set(msg.conversation_id, msg);
    }
  }

  const myReadMap = new Map(
    participations.map((p: any) => [p.conversation_id, p.last_read_at]),
  );

  const conversations = convIds.map((cid: string) => {
    const other = (otherParticipants ?? []).find(
      (o: any) => o.conversation_id === cid,
    );
    const lastMsg = lastMsgMap.get(cid);
    const myReadAt = myReadMap.get(cid);
    const hasUnread =
      lastMsg != null &&
      (myReadAt == null || new Date(lastMsg.created_at) > new Date(myReadAt)) &&
      lastMsg.sender_id !== user.id;

    return {
      id: cid,
      patient_name: (other as any)?.user?.full_name ?? "Unknown",
      last_content: lastMsg?.content ?? null,
      last_at: lastMsg?.created_at ?? null,
      has_unread: hasUnread,
    };
  });

  conversations.sort((a: any, b: any) => {
    const aTime = a.last_at ?? "";
    const bTime = b.last_at ?? "";
    return bTime.localeCompare(aTime);
  });

  return conversations;
}

export default async function MessagesPage() {
  const conversations = await fetchConversations();

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px", maxWidth: 720 }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 24 }}>
          Messages
        </h1>

        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
        }}>
          {conversations.length === 0 ? (
            <p style={{ padding: 24, textAlign: "center", color: "var(--hint)", fontSize: 15 }}>
              No conversations yet. Messages from patients will appear here.
            </p>
          ) : (
            conversations.map((c: any) => (
              <a
                key={c.id}
                href={`/messages/${c.id}`}
                style={{
                  display: "flex",
                  alignItems: "center",
                  padding: "14px 16px",
                  borderBottom: "1px solid var(--hairline)",
                  textDecoration: "none",
                  transition: "background 0.1s",
                }}
                onMouseEnter={(e) => e.currentTarget.style.background = "var(--mist)"}
                onMouseLeave={(e) => e.currentTarget.style.background = "transparent"}
              >
                <div style={{
                  width: 40,
                  height: 40,
                  borderRadius: 20,
                  background: "var(--concord-blue-tint)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 16,
                  fontWeight: 600,
                  color: "var(--concord-blue)",
                  marginRight: 14,
                  flexShrink: 0,
                }}>
                  {c.patient_name.charAt(0).toUpperCase()}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontWeight: 600,
                    fontSize: 15,
                    color: "var(--ink)",
                    marginBottom: 2,
                  }}>
                    {c.patient_name}
                    {c.has_unread && (
                      <span style={{
                        display: "inline-block",
                        width: 8,
                        height: 8,
                        borderRadius: 4,
                        background: "var(--concord-blue)",
                        marginLeft: 8,
                      }} />
                    )}
                  </div>
                  <div style={{
                    fontSize: 14,
                    color: c.has_unread ? "var(--body)" : "var(--hint)",
                    whiteSpace: "nowrap",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    fontWeight: c.has_unread ? 500 : 400,
                  }}>
                    {c.last_content ?? "No messages yet"}
                  </div>
                </div>
                {c.last_at && (
                  <div style={{
                    fontSize: 12,
                    color: "var(--hint)",
                    marginLeft: 12,
                    flexShrink: 0,
                  }}>
                    {new Date(c.last_at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}
                  </div>
                )}
              </a>
            ))
          )}
        </div>
      </main>
    </div>
  );
}
