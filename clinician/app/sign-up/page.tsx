"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "../../lib/supabase/client";

export default function SignUpPage() {
  const router = useRouter();
  const supabase = createClient();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirmSent, setConfirmSent] = useState(false);

  async function handleSignUp(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);

    const { error: signUpErr } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
          role: "clinician",
        },
      },
    });

    if (signUpErr) {
      setError(signUpErr.message);
      setBusy(false);
      return;
    }

    setConfirmSent(true);
    setBusy(false);
  }

  if (confirmSent) {
    return (
      <div
        style={{
          display: "flex",
          minHeight: "100vh",
          alignItems: "center",
          justifyContent: "center",
          background: "var(--mist)",
        }}
      >
        <div
          style={{
            width: 400,
            background: "var(--surface)",
            borderRadius: 16,
            border: "1px solid var(--hairline)",
            padding: 40,
            textAlign: "center",
          }}
        >
          <div
            style={{
              fontSize: 40,
              marginBottom: 16,
            }}
          >
            ✉️
          </div>
          <h1 style={{ fontSize: 20, fontWeight: 600, color: "var(--ink)", marginBottom: 8 }}>
            Check your email
          </h1>
          <p style={{ fontSize: 15, color: "var(--slate)", marginBottom: 24 }}>
            We sent a confirmation link to <strong>{email}</strong>.
            Click the link to activate your account.
          </p>
          <a
            href="/login"
            style={{
              display: "inline-block",
              padding: "10px 24px",
              fontSize: 14,
              fontWeight: 500,
              color: "var(--concord-blue)",
              textDecoration: "none",
              border: "1px solid var(--hairline)",
              borderRadius: 10,
            }}
          >
            Back to sign-in
          </a>
        </div>
      </div>
    );
  }

  return (
    <div
      style={{
        display: "flex",
        minHeight: "100vh",
        alignItems: "center",
        justifyContent: "center",
        background: "var(--mist)",
      }}
    >
      <div
        style={{
          width: 400,
          background: "var(--surface)",
          borderRadius: 16,
          border: "1px solid var(--hairline)",
          padding: 40,
        }}
      >
        <div style={{ fontSize: 24, fontWeight: 600, color: "var(--ink)", marginBottom: 4 }}>
          Concord
        </div>
        <div style={{ fontSize: 15, color: "var(--slate)", marginBottom: 32 }}>
          Clinician registration
        </div>

        <form onSubmit={handleSignUp}>
          <label style={{ display: "block", fontSize: 13, fontWeight: 600, color: "var(--body)", marginBottom: 6 }}>
            Full name
          </label>
          <input
            type="text"
            required
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            style={{
              width: "100%",
              padding: "10px 14px",
              fontSize: 15,
              border: "1px solid var(--hairline)",
              borderRadius: 10,
              background: "var(--surface)",
              color: "var(--ink)",
              outline: "none",
              marginBottom: 16,
              boxSizing: "border-box",
            }}
          />

          <label style={{ display: "block", fontSize: 13, fontWeight: 600, color: "var(--body)", marginBottom: 6 }}>
            Email
          </label>
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            style={{
              width: "100%",
              padding: "10px 14px",
              fontSize: 15,
              border: "1px solid var(--hairline)",
              borderRadius: 10,
              background: "var(--surface)",
              color: "var(--ink)",
              outline: "none",
              marginBottom: 16,
              boxSizing: "border-box",
            }}
          />

          <label style={{ display: "block", fontSize: 13, fontWeight: 600, color: "var(--body)", marginBottom: 6 }}>
            Password
          </label>
          <input
            type="password"
            required
            minLength={6}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            style={{
              width: "100%",
              padding: "10px 14px",
              fontSize: 15,
              border: "1px solid var(--hairline)",
              borderRadius: 10,
              background: "var(--surface)",
              color: "var(--ink)",
              outline: "none",
              marginBottom: 24,
              boxSizing: "border-box",
            }}
          />

          {error && (
            <p style={{ fontSize: 13, color: "var(--severe)", marginBottom: 16 }}>
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={busy}
            style={{
              width: "100%",
              padding: "12px 0",
              fontSize: 15,
              fontWeight: 600,
              background: busy ? "var(--hint)" : "var(--concord-blue)",
              color: "var(--surface)",
              border: "none",
              borderRadius: 10,
              cursor: busy ? "not-allowed" : "pointer",
            }}
          >
            {busy ? "Creating account\u2026" : "Create account"}
          </button>
        </form>

        <div style={{ marginTop: 24, textAlign: "center", fontSize: 14, color: "var(--slate)" }}>
          Already have an account?{" "}
          <a
            href="/login"
            style={{
              color: "var(--concord-blue)",
              textDecoration: "none",
              fontWeight: 500,
            }}
          >
            Sign in
          </a>
        </div>
      </div>
    </div>
  );
}
