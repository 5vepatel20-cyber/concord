"use client";

import { useState, useMemo } from "react";
import type { PatientSummary } from "../lib/types";

const STATUSES = ["all", "active_treatment", "surveillance", "completed", "unknown"] as const;
const STATUS_LABELS: Record<string, string> = {
  all: "All",
  active_treatment: "Active Treatment",
  surveillance: "Surveillance",
  completed: "Completed",
  unknown: "Unknown",
};

type SortKey = "name" | "last_report" | "alerts";

export function PatientRosterTable({
  patients,
}: {
  patients: PatientSummary[];
}) {
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [sortKey, setSortKey] = useState<SortKey>("name");
  const [sortAsc, setSortAsc] = useState(true);

  const statusCounts = useMemo(() => {
    const counts: Record<string, number> = { all: patients.length };
    for (const s of STATUSES) {
      if (s !== "all") counts[s] = patients.filter((p) => p.treatment_status === s).length;
    }
    return counts;
  }, [patients]);

  const filtered = useMemo(() => {
    let result = patients;

    if (query.trim()) {
      const q = query.toLowerCase();
      result = result.filter(
        (p) =>
          p.full_name.toLowerCase().includes(q) ||
          p.primary_diagnosis.toLowerCase().includes(q),
      );
    }

    if (statusFilter !== "all") {
      result = result.filter((p) => p.treatment_status === statusFilter);
    }

    result = [...result].sort((a, b) => {
      let cmp = 0;
      if (sortKey === "name") {
        cmp = a.full_name.localeCompare(b.full_name);
      } else if (sortKey === "last_report") {
        const aDate = a.last_report_at ?? "";
        const bDate = b.last_report_at ?? "";
        cmp = aDate.localeCompare(bDate);
      } else if (sortKey === "alerts") {
        cmp = a.open_alerts - b.open_alerts;
      }
      return sortAsc ? cmp : -cmp;
    });

    return result;
  }, [patients, query, statusFilter, sortKey, sortAsc]);

  const chipStyle = (active: boolean): React.CSSProperties => ({
    padding: "4px 12px",
    fontSize: 12,
    fontWeight: 500,
    border: "none",
    borderRadius: 6,
    cursor: "pointer",
    background: active ? "var(--concord-blue)" : "var(--mist)",
    color: active ? "var(--surface)" : "var(--slate)",
    whiteSpace: "nowrap",
  });

  const sortableHead = (label: string, key: SortKey) => (
    <th
      onClick={() => {
        if (sortKey === key) setSortAsc(!sortAsc);
        else { setSortKey(key); setSortAsc(true); }
      }}
      style={{
        padding: "12px 16px",
        fontSize: 13,
        fontWeight: 600,
        color: "var(--slate)",
        textTransform: "uppercase",
        letterSpacing: 0.4,
        cursor: "pointer",
        userSelect: "none",
        whiteSpace: "nowrap",
      }}
    >
      {label} {sortKey === key ? (sortAsc ? "\u25B2" : "\u25BC") : ""}
    </th>
  );

  const gradeColors: Record<number, string> = {
    0: "var(--stable)",
    1: "var(--caution)",
    2: "var(--warn)",
    3: "var(--severe)",
  };

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
          display: "flex",
          flexDirection: "column",
          gap: 10,
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
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {STATUSES.map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              style={chipStyle(statusFilter === s)}
            >
              {STATUS_LABELS[s]} ({statusCounts[s] ?? 0})
            </button>
          ))}
        </div>
      </div>

      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr
            style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}
          >
            {sortableHead("Patient", "name")}
            <th style={{
              padding: "12px 16px",
              fontSize: 13,
              fontWeight: 600,
              color: "var(--slate)",
              textTransform: "uppercase",
              letterSpacing: 0.4,
            }}>
              Diagnosis
            </th>
            <th style={{
              padding: "12px 16px",
              fontSize: 13,
              fontWeight: 600,
              color: "var(--slate)",
              textTransform: "uppercase",
              letterSpacing: 0.4,
            }}>
              Status
            </th>
            {sortableHead("Last Report", "last_report")}
            {sortableHead("Alerts", "alerts")}
          </tr>
        </thead>
        <tbody>
          {filtered.length === 0 ? (
            <tr>
              <td
                colSpan={5}
                style={{
                  padding: 24,
                  textAlign: "center",
                  color: "var(--hint)",
                  fontSize: 15,
                }}
              >
                {query
                  ? "No patients match your search."
                  : statusFilter !== "all"
                  ? "No patients with this status."
                  : "No patients in your panel yet."}
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
                <td style={{ padding: "12px 16px", fontSize: 14 }}>
                  {p.last_report_at ? (
                    <span style={{ color: "var(--body)" }}>
                      {new Date(p.last_report_at).toLocaleDateString()}
                      {p.latest_grade != null && (
                        <span style={{
                          marginLeft: 6,
                          padding: "0 6px",
                          borderRadius: 4,
                          fontSize: 11,
                          fontWeight: 600,
                          background: `${gradeColors[p.latest_grade] ?? "var(--hint)"}20`,
                          color: gradeColors[p.latest_grade] ?? "var(--hint)",
                        }}>
                          g{p.latest_grade}
                        </span>
                      )}
                    </span>
                  ) : (
                    <span style={{ color: "var(--hint)" }}>&mdash;</span>
                  )}
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
