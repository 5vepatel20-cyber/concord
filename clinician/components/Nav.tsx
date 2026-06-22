"use client";

import { useRouter } from "next/navigation";
import { createClient } from "../lib/supabase/client";

export function Nav() {
  const router = useRouter();
  const supabase = createClient();

  async function handleSignOut() {
    await supabase.auth.signOut();
    router.refresh();
  }

  const linkStyle: React.CSSProperties = {
    display: "block",
    padding: "10px 24px",
    fontSize: 15,
    fontWeight: 500,
    color: "var(--body)",
    textDecoration: "none",
    borderRadius: 8,
  };

  return (
    <nav style={{
      width: 240,
      background: "var(--surface)",
      borderRight: "1px solid var(--hairline)",
      padding: "24px 16px",
      display: "flex",
      flexDirection: "column",
      gap: 4,
    }}>
      <div style={{ fontSize: 20, fontWeight: 600, color: "var(--ink)", padding: "0 8px", marginBottom: 24 }}>
        Concord
      </div>

      <a href="/dashboard" style={linkStyle}>
        Patient Roster
      </a>
      <a href="/alerts" style={linkStyle}>
        Alert Inbox
      </a>

      <div style={{ flex: 1 }} />

      <button
        onClick={handleSignOut}
        style={{
          ...linkStyle,
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
