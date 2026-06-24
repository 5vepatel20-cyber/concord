"use client";

import { useEffect, useState, useRef } from "react";
import { createClient } from "../lib/supabase/client";

interface Stats {
  openAlerts: number;
  unreadMessages: number;
}

export function LiveStats({
  initialOpenAlerts,
  initialUnreadMessages,
  patientCount,
}: {
  initialOpenAlerts: number;
  initialUnreadMessages: number;
  patientCount: number;
}) {
  const [stats, setStats] = useState<Stats>({
    openAlerts: initialOpenAlerts,
    unreadMessages: initialUnreadMessages,
  });
  const supabase = useRef(createClient());

  useEffect(() => {
    let cancelled = false;

    async function poll() {
      const { data: { user } } = await supabase.current.auth.getUser();
      if (!user || cancelled) return;

      const [{ count: alertCount }, { data: participations }] = await Promise.all([
        supabase.current
          .from("symptom_alert")
          .select("id", { count: "exact", head: true })
          .eq("status", "open"),
        supabase.current
          .from("conversation_participant")
          .select("conversation_id, last_read_at")
          .eq("user_id", user.id),
      ]);

      if (cancelled) return;

      let unread = 0;
      if (participations && participations.length > 0) {
        const convIds = participations.map((p: any) => p.conversation_id);
        const { data: lastMessages } = await supabase.current
          .from("message")
          .select("conversation_id, created_at, sender_id")
          .in("conversation_id", convIds);

        if (lastMessages) {
          const myReadMap = new Map(participations.map((p: any) => [p.conversation_id, p.last_read_at]));
          const lastMsgMap = new Map<string, any>();
          for (const msg of lastMessages) {
            if (!lastMsgMap.has(msg.conversation_id)) {
              lastMsgMap.set(msg.conversation_id, msg);
            }
          }
          for (const [cid, lastMsg] of lastMsgMap) {
            const myReadAt = myReadMap.get(cid);
            if (lastMsg.sender_id !== user.id && (myReadAt == null || new Date(lastMsg.created_at) > new Date(myReadAt))) {
              unread++;
            }
          }
        }
      }

      if (!cancelled) setStats({ openAlerts: alertCount ?? 0, unreadMessages: unread });
    }

    poll();
    const interval = setInterval(poll, 15000);
    return () => { cancelled = true; clearInterval(interval); };
  }, []);

  return (
    <div style={{ display: "flex", gap: 12, marginBottom: 20 }}>
      {[
        { label: "Total Patients", value: patientCount, color: "var(--concord-blue)" },
        { label: "Open Alerts", value: stats.openAlerts, color: stats.openAlerts > 0 ? "var(--severe)" : "var(--stable)" },
        { label: "Unread Messages", value: stats.unreadMessages, color: stats.unreadMessages > 0 ? "var(--warn)" : "var(--hint)" },
      ].map((s) => (
        <div key={s.label} style={{
          flex: 1,
          background: "var(--surface)",
          borderRadius: 12,
          border: "1px solid var(--hairline)",
          padding: "14px 16px",
          transition: "opacity 0.2s",
        }}>
          <div style={{ fontSize: 13, color: "var(--slate)", fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 2 }}>
            {s.label}
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, color: s.color }}>
            {s.value}
          </div>
        </div>
      ))}
    </div>
  );
}
