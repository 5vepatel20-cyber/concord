"use client";

import { useState } from "react";

interface AlertReport {
  reported_at: string;
  responses: { grade: number; term_name: string }[];
}

interface AlertItem {
  id: string;
  patient_id: string;
  patient_name: string;
  severity_level: string;
  status: string;
  created_at: string;
  report_id: string | null;
  report: AlertReport | null;
}

export function AlertList({
  alerts,
  acknowledgeAction,
  resolveAction,
}: {
  alerts: AlertItem[];
  acknowledgeAction: (id: string) => Promise<void>;
  resolveAction: (id: string) => Promise<void>;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);

  const severityStyles: Record<string, { bg: string; color: string }> = {
    emergency: { bg: "#FDEAEA", color: "var(--severe)" },
    urgent: { bg: "#FBE6DD", color: "var(--warn)" },
    info: { bg: "var(--concord-blue-tint)", color: "var(--concord-blue)" },
  };

  const gradeColors: Record<number, string> = {
    0: "var(--stable)",
    1: "var(--caution)",
    2: "var(--warn)",
    3: "var(--severe)",
  };

  return (
    <div style={{
      background: "var(--surface)",
      borderRadius: 14,
      border: "1px solid var(--hairline)",
      overflow: "hidden",
    }}>
      {alerts.length === 0 ? (
        <p style={{ padding: 24, textAlign: "center", color: "var(--hint)", fontSize: 15 }}>
          No open alerts.
        </p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
              {["Severity", "Patient", "Date", "Status", "", ""].map((h) => (
                <th key={h} style={{
                  padding: "12px 16px",
                  fontSize: 13,
                  fontWeight: 600,
                  color: "var(--slate)",
                  textTransform: "uppercase",
                }}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {alerts.map((a) => {
              const s = severityStyles[a.severity_level] ?? severityStyles.info;
              const isExpanded = expanded === a.id;
              return (
                <>
                  <tr key={a.id} style={{ borderBottom: "1px solid var(--hairline)" }}>
                    <td style={{ padding: "12px 16px" }}>
                      <span style={{
                        display: "inline-block",
                        padding: "2px 10px",
                        borderRadius: 6,
                        fontSize: 12,
                        fontWeight: 500,
                        background: s.bg,
                        color: s.color,
                        textTransform: "uppercase",
                      }}>
                        {a.severity_level}
                      </span>
                    </td>
                    <td style={{ padding: "12px 16px", fontWeight: 600, color: "var(--ink)" }}>
                      <a href={`/patients/${a.patient_id}`} style={{ color: "inherit", textDecoration: "none" }}>
                        {a.patient_name}
                      </a>
                    </td>
                    <td style={{ padding: "12px 16px", fontSize: 14, color: "var(--body)" }}>
                      {new Date(a.created_at).toLocaleString()}
                    </td>
                    <td style={{ padding: "12px 16px" }}>
                      <span style={{
                        display: "inline-block",
                        padding: "2px 10px",
                        borderRadius: 6,
                        fontSize: 12,
                        fontWeight: 500,
                        color: a.status === "open" ? "var(--warn)" : "var(--stable)",
                        textTransform: "capitalize",
                      }}>
                        {a.status}
                      </span>
                    </td>
                    <td style={{ padding: "12px 16px", display: "flex", gap: 6 }}>
                      {a.report && (
                        <button
                          onClick={() => setExpanded(isExpanded ? null : a.id)}
                          style={{
                            padding: "4px 10px",
                            fontSize: 12,
                            fontWeight: 500,
                            background: "none",
                            color: "var(--concord-blue)",
                            border: "none",
                            cursor: "pointer",
                          }}
                        >
                          {isExpanded ? "Hide" : "View"}
                        </button>
                      )}
                      <a href={`/alerts/${a.id}`} style={{
                        padding: "4px 10px",
                        fontSize: 12,
                        fontWeight: 500,
                        color: "var(--slate)",
                        textDecoration: "none",
                        whiteSpace: "nowrap",
                      }}>
                        Details &rarr;
                      </a>
                    </td>
                    <td style={{ padding: "12px 16px" }}>
                      {a.status === "open" && (
                        <form action={acknowledgeAction.bind(null, a.id)}>
                          <button
                            type="submit"
                            style={{
                              padding: "6px 14px",
                              fontSize: 13,
                              fontWeight: 500,
                              background: "var(--surface)",
                              color: "var(--concord-blue)",
                              border: "1px solid var(--hairline)",
                              borderRadius: 8,
                              cursor: "pointer",
                            }}
                          >
                            Acknowledge
                          </button>
                        </form>
                      )}
                      {(a.status === "open" || a.status === "acknowledged") && (
                        <form action={resolveAction.bind(null, a.id)}>
                          <button
                            type="submit"
                            style={{
                              padding: "6px 14px",
                              fontSize: 13,
                              fontWeight: 500,
                              background: "var(--stable)",
                              color: "var(--surface)",
                              border: "none",
                              borderRadius: 8,
                              cursor: "pointer",
                              marginLeft: a.status === "open" ? 6 : 0,
                            }}
                          >
                            Resolve
                          </button>
                        </form>
                      )}
                    </td>
                  </tr>
                  {isExpanded && a.report && (
                    <tr key={`${a.id}-detail`}>
                      <td colSpan={6} style={{ padding: "0 16px 12px 16px" }}>
                        <div style={{
                          background: "var(--mist)",
                          borderRadius: 10,
                          padding: 12,
                        }}>
                          <div style={{ fontSize: 13, fontWeight: 600, color: "var(--slate)", marginBottom: 8 }}>
                            Symptom Report &middot; {new Date(a.report.reported_at).toLocaleString()}
                          </div>
                          {a.report.responses.length === 0 ? (
                            <p style={{ fontSize: 13, color: "var(--hint)", margin: 0 }}>No symptom data.</p>
                          ) : (
                            <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                              {a.report.responses.map((r, i) => (
                                <div key={i} style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14 }}>
                                  <span style={{
                                    display: "inline-block",
                                    width: 8,
                                    height: 8,
                                    borderRadius: 4,
                                    background: gradeColors[r.grade] ?? "var(--hint)",
                                    flexShrink: 0,
                                  }} />
                                  <span style={{ color: "var(--body)" }}>{r.term_name}</span>
                                  <span style={{
                                    fontSize: 12,
                                    fontWeight: 600,
                                    color: gradeColors[r.grade] ?? "var(--hint)",
                                  }}>
                                    {["None", "Mild", "Moderate", "Severe"][r.grade] ?? "Unknown"}
                                  </span>
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}
