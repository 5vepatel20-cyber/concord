"use client";

import { useState } from "react";
import type { PatientSummary } from "../lib/types";

export function PatientRosterTable({
  patients,
}: {
  patients: PatientSummary[];
}) {
  const [query, setQuery] = useState("");

  const filtered = query.trim()
    ? patients.filter(
        (p) =>
          p.full_name.toLowerCase().includes(query.toLowerCase()) ||
          p.primary_diagnosis.toLowerCase().includes(query.toLowerCase()),
      )
    : patients;

  return (
    <div
      style={{
        background: "var(--surface)",
        borderRadius: 14,
        border: "1px solid var(--hairline)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          padding: "12px 16px",
          borderBottom: "1px solid var(--hairline)",
        }}
      >
        <input
          type="text"
          placeholder="Search by name or diagnosis\u2026"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          style={{
            width: "100%",
            padding: "8px 12px",
            fontSize: 14,
            border: "1px solid var(--hairline)",
            borderRadius: 8,
            background: "var(--mist)",
            color: "var(--ink)",
            outline: "none",
            boxSizing: "border-box",
          }}
        />
      </div>

      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr
            style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}
          >
            {["Patient", "Diagnosis", "Status", "Alerts"].map((h) => (
              <th
                key={h}
                style={{
                  padding: "12px 16px",
                  fontSize: 13,
                  fontWeight: 600,
                  color: "var(--slate)",
                  textTransform: "uppercase",
                  letterSpacing: 0.4,
                }}
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {filtered.length === 0 ? (
            <tr>
              <td
                colSpan={4}
                style={{
                  padding: 24,
                  textAlign: "center",
                  color: "var(--hint)",
                  fontSize: 15,
                }}
              >
                {query ? "No patients match your search." : "No patients in your panel yet."}
              </td>
            </tr>
          ) : (
            filtered.map((p) => (
              <tr
                key={p.id}
                style={{
                  borderBottom: "1px solid var(--hairline)",
                  cursor: "pointer",
                }}
                onClick={() => (window.location.href = `/patients/${p.id}`)}
              >
                <td style={{ padding: "12px 16px" }}>
                  <div style={{ fontWeight: 600, color: "var(--ink)" }}>
                    {p.full_name}
                  </div>
                  <div style={{ fontSize: 13, color: "var(--slate)" }}>
                    {p.date_of_birth}
                  </div>
                </td>
                <td
                  style={{
                    padding: "12px 16px",
                    fontSize: 15,
                    color: "var(--body)",
                  }}
                >
                  {p.primary_diagnosis}
                </td>
                <td style={{ padding: "12px 16px" }}>
                  <span
                    style={{
                      display: "inline-block",
                      padding: "2px 10px",
                      borderRadius: 6,
                      fontSize: 12,
                      fontWeight: 500,
                      background:
                        p.treatment_status === "active_treatment"
                          ? "var(--concord-blue-tint)"
                          : "var(--mist)",
                      color:
                        p.treatment_status === "active_treatment"
                          ? "var(--concord-blue)"
                          : "var(--slate)",
                    }}
                  >
                    {p.treatment_status.replace(/_/g, " ")}
                  </span>
                </td>
                <td style={{ padding: "12px 16px" }}>
                  {p.open_alerts > 0 ? (
                    <span
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        justifyContent: "center",
                        width: 24,
                        height: 24,
                        borderRadius: 12,
                        background: "var(--severe)",
                        color: "var(--surface)",
                        fontSize: 12,
                        fontWeight: 600,
                      }}
                    >
                      {p.open_alerts}
                    </span>
                  ) : (
                    <span style={{ color: "var(--hint)", fontSize: 14 }}>
                      &mdash;
                    </span>
                  )}
                </td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}
