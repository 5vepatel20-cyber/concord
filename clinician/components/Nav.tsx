"use client";

import { usePathname } from "next/navigation";
import { useRouter } from "next/navigation";
import { createClient } from "../lib/supabase/client";

const links = [
  { href: "/dashboard", label: "Patient Roster" },
  { href: "/alerts", label: "Alert Inbox" },
  { href: "/billing", label: "RTM Billing" },
  { href: "/compliance", label: "EOM Compliance" },
];

export function Nav() {
  const pathname = usePathname();
  const router = useRouter();
  const supabase = createClient();

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
        return (
          <a
            key={link.href}
            href={link.href}
            style={{
              ...baseLinkStyle,
              background: isActive ? "var(--concord-blue-tint)" : "transparent",
              color: isActive ? "var(--concord-blue)" : "var(--body)",
              fontWeight: isActive ? 600 : 500,
            }}
          >
            {link.label}
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
