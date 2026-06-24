"use client";

import { usePathname } from "next/navigation";
import { useRouter } from "next/navigation";
import { createClient } from "../lib/supabase/client";
import { useEffect, useState } from "react";

const links = [
  { href: "/dashboard", label: "Patient Roster" },
  { href: "/messages", label: "Messages" },
  { href: "/alerts", label: "Alert Inbox" },
  { href: "/billing", label: "RTM Billing" },
  { href: "/compliance", label: "EOM Compliance" },
  { href: "/admin", label: "Settings" },
];

export function Nav() {
  const pathname = usePathname();
  const router = useRouter();
  const supabase = createClient();
  const [unreadCount, setUnreadCount] = useState(0);

  useEffect(() => {
    let cancelled = false;

    async function fetchUnread() {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user || cancelled) return;

      const { data: participations } = await supabase
        .from("conversation_participant")
        .select("conversation_id, last_read_at")
        .eq("user_id", user.id);

      if (!participations || participations.length === 0 || cancelled) return;

      const convIds = participations.map((p: any) => p.conversation_id);
      const { data: lastMessages } = await supabase
        .from("message")
        .select("conversation_id, created_at, sender_id")
        .in("conversation_id", convIds);

      if (!lastMessages || cancelled) return;

      const myReadMap = new Map(participations.map((p: any) => [p.conversation_id, p.last_read_at]));
      const lastMsgMap = new Map<string, any>();
      for (const msg of lastMessages) {
        if (!lastMsgMap.has(msg.conversation_id)) {
          lastMsgMap.set(msg.conversation_id, msg);
        }
      }

      let count = 0;
      for (const [cid, lastMsg] of lastMsgMap) {
        const myReadAt = myReadMap.get(cid);
        if (lastMsg.sender_id !== user.id && (myReadAt == null || new Date(lastMsg.created_at) > new Date(myReadAt))) {
          count++;
        }
      }
      if (!cancelled) setUnreadCount(count);
    }

    fetchUnread();
    const interval = setInterval(fetchUnread, 30000);
    return () => { cancelled = true; clearInterval(interval); };
  }, [supabase]);

  async function handleSignOut() {
    await supabase.auth.signOut();
    router.refresh();
  }

  const baseLinkStyle: React.CSSProperties = {
    display: "block",
    padding: "10px 24px",
    fontSize: 15,
    fontWeight: 500,
    color: "var(--body)",
    textDecoration: "none",
    borderRadius: 8,
    transition: "background 0.15s, color 0.15s",
  };

  return (
    <nav
      style={{
        width: 240,
        background: "var(--surface)",
        borderRight: "1px solid var(--hairline)",
        padding: "24px 16px",
        display: "flex",
        flexDirection: "column",
        gap: 4,
      }}
    >
      <div
        style={{
          fontSize: 20,
          fontWeight: 600,
          color: "var(--ink)",
          padding: "0 8px",
          marginBottom: 24,
        }}
      >
        Concord
      </div>

      {links.map((link) => {
        const isActive = pathname === link.href || pathname.startsWith(link.href + "/");
        const showBadge = link.href === "/messages" && unreadCount > 0;
        return (
          <a
            key={link.href}
            href={link.href}
            style={{
              ...baseLinkStyle,
              background: isActive ? "var(--concord-blue-tint)" : "transparent",
              color: isActive ? "var(--concord-blue)" : "var(--body)",
              fontWeight: isActive ? 600 : 500,
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            {link.label}
            {showBadge && (
              <span style={{
                display: "inline-flex",
                alignItems: "center",
                justifyContent: "center",
                minWidth: 20,
                height: 20,
                borderRadius: 10,
                background: "var(--concord-blue)",
                color: "var(--surface)",
                fontSize: 11,
                fontWeight: 700,
                padding: "0 5px",
              }}>
                {unreadCount}
              </span>
            )}
          </a>
        );
      })}

      <div style={{ flex: 1 }} />

      <button
        onClick={handleSignOut}
        style={{
          ...baseLinkStyle,
          background: "none",
          border: "none",
          textAlign: "left",
          cursor: "pointer",
          color: "var(--hint)",
        }}
      >
        Sign out
      </button>
    </nav>
  );
}
