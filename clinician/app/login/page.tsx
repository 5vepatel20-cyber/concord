"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "../../lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const router = useRouter();
  const supabase = createClient();

  async function handleSignIn(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);

    const { error: signInErr } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (signInErr) {
      setError(signInErr.message);
      setBusy(false);
      return;
    }

    router.refresh();
  }

  return (
    <div style={{
      display: "flex",
      minHeight: "100vh",
      alignItems: "center",
      justifyContent: "center",
      padding: 24,
    }}>
      <div style={{
        width: "100%",
        maxWidth: 400,
        background: "var(--surface)",
        borderRadius: 14,
        border: "1px solid var(--hairline)",
        padding: 32,
      }}>
        <h1 style={{
          fontSize: 24,
          fontWeight: 600,
          marginBottom: 4,
          color: "var(--ink)",
        }}>
          Concord
        </h1>
        <p style={{
          fontSize: 15,
          color: "var(--slate)",
          marginBottom: 24,
        }}>
          Clinician sign-in
        </p>

        <form onSubmit={handleSignIn} style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div>
            <label style={{ fontSize: 13, color: "var(--slate)", marginBottom: 4, display: "block" }}>
              Email
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              style={{
                width: "100%",
                padding: "10px 16px",
                borderRadius: 10,
                border: "1px solid var(--hairline)",
                fontSize: 15,
                boxSizing: "border-box",
              }}
            />
          </div>

          <div>
            <label style={{ fontSize: 13, color: "var(--slate)", marginBottom: 4, display: "block" }}>
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              style={{
                width: "100%",
                padding: "10px 16px",
                borderRadius: 10,
                border: "1px solid var(--hairline)",
                fontSize: 15,
                boxSizing: "border-box",
              }}
            />
          </div>

          {error && (
            <p style={{ fontSize: 13, color: "var(--severe)" }}>{error}</p>
          )}

          <button
            type="submit"
            disabled={busy}
            style={{
              width: "100%",
              padding: "12px 24px",
              background: busy ? "var(--hint)" : "var(--concord-blue)",
              color: "var(--surface)",
              border: "none",
              borderRadius: 10,
              fontSize: 15,
              fontWeight: 600,
              cursor: busy ? "not-allowed" : "pointer",
            }}
          >
            {busy ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </div>
    </div>
  );
}
