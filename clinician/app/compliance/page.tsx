import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";
import type { EomPatientCompliance, EomMonthlySummary } from "../../lib/types";

const EOM_MONTHLY_RATE = 110;
const EXPECTED_REPORTS_PER_WEEK = 1;
const WEEKS_PER_MONTH = 4.33;
const COMPLIANCE_THRESHOLD = 0.7;

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

async function fetchComplianceData(year: number, month: number) {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { patients: [], monthlyTrend: [] };

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") {
    return { patients: [], monthlyTrend: [] };
  }

  const { data: patients } = await supabase
    .from("patient_profile")
    .select(`
      user_id,
      user:user!inner(full_name),
      condition!patient_profile_primary_diagnosis_id_fkey(display_name)
    `);

  if (!patients) return { patients: [], monthlyTrend: [] };

  const startOfMonth = new Date(year, month - 1, 1).toISOString();
  const endOfMonth = new Date(year, month, 0, 23, 59, 59).toISOString();
  const expectedPerPatient = Math.round(WEEKS_PER_MONTH * EXPECTED_REPORTS_PER_WEEK);

  const { data: reports } = await supabase
    .from("symptom_report")
    .select("patient_id, reported_at")
    .gte("reported_at", startOfMonth)
    .lte("reported_at", endOfMonth);

  const reportCounts = new Map<string, number>();
  const lastReports = new Map<string, string>();
  for (const r of reports ?? []) {
    const enc = r as any;
    reportCounts.set(enc.patient_id, (reportCounts.get(enc.patient_id) ?? 0) + 1);
    const existing = lastReports.get(enc.patient_id);
    if (!existing || enc.reported_at > existing) {
      lastReports.set(enc.patient_id, enc.reported_at);
    }
  }

  const patientCompliance: EomPatientCompliance[] = patients.map((p: any) => {
    const actual = reportCounts.get(p.user_id) ?? 0;
    const lastReport = lastReports.get(p.user_id) ?? null;
    const daysSince = lastReport
      ? Math.floor((Date.now() - new Date(lastReport).getTime()) / 86400000)
      : null;

    return {
      id: p.user_id,
      full_name: p.user?.full_name ?? "Unknown",
      primary_diagnosis: p.condition?.display_name ?? "Unknown",
      expected_reports: expectedPerPatient,
      actual_reports: actual,
      compliance_pct: Math.round((actual / expectedPerPatient) * 100),
      last_report_at: lastReport,
      days_since_last_report: daysSince,
    };
  });

  // 6-month trend
  const monthlyTrend: EomMonthlySummary[] = [];
  for (let i = 5; i >= 0; i--) {
    const m = month - i;
    const y = year + (m <= 0 ? -1 : 0);
    const adjM = ((m - 1) % 12 + 12) % 12 + 1;

    const s = new Date(y, adjM - 1, 1).toISOString();
    const e = new Date(y, adjM, 0, 23, 59, 59).toISOString();
    const exp = Math.round(WEEKS_PER_MONTH * EXPECTED_REPORTS_PER_WEEK) * patients.length;

    const { data: moReports } = await supabase
      .from("symptom_report")
      .select("id", { count: "exact", head: true })
      .gte("reported_at", s)
      .lte("reported_at", e);

    monthlyTrend.push({
      month: adjM,
      year: y,
      monthName: MONTH_NAMES[adjM - 1],
      avg_compliance_pct: exp > 0 ? Math.round(((moReports?.length ?? 0) / exp) * 100) : 0,
      patient_count: patients.length,
    });
  }

  return { patients: patientCompliance, monthlyTrend };
}

export default async function CompliancePage({
  searchParams,
}: {
  searchParams: { year?: string; month?: string };
}) {
  const now = new Date();
  const year = parseInt(searchParams.year ?? String(now.getFullYear()), 10);
  const month = parseInt(searchParams.month ?? String(now.getMonth() + 1), 10);
  const { patients, monthlyTrend } = await fetchComplianceData(year, month);

  if (!patients.length) redirect("/login");

  const patientCount = patients.length;
  const compliant = patients.filter((p) => p.compliance_pct >= COMPLIANCE_THRESHOLD * 100);
  const nonCompliant = patients.filter((p) => p.compliance_pct < COMPLIANCE_THRESHOLD * 100);
  const avgCompliance = Math.round(patients.reduce((s, p) => s + p.compliance_pct, 0) / patientCount);
  const revenueAtRisk = Math.round(
    nonCompliant.reduce((s, p) => s + (1 - p.compliance_pct / 100), 0) * EOM_MONTHLY_RATE,
  );

  const prevMonth = month === 1 ? 12 : month - 1;
  const prevYear = month === 1 ? year - 1 : year;
  const isCurrentPeriod = year === now.getFullYear() && month === now.getMonth() + 1;

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 24 }}>
          <div>
            <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 4 }}>EOM ePRO Compliance</h1>
            <p style={{ fontSize: 15, color: "var(--slate)" }}>
              <a
                href={`/compliance?year=${prevYear}&month=${prevMonth}`}
                style={{ color: "var(--concord-blue)", textDecoration: "none", marginRight: 12 }}
              >
                &larr; Prev
              </a>
              {MONTH_NAMES[month - 1]} {year}
              {isCurrentPeriod && (
                <span style={{ marginLeft: 8, fontSize: 12, color: "var(--hint)" }}>(current)</span>
              )}
              {!isCurrentPeriod && (
                <a href="/compliance" style={{ color: "var(--concord-blue)", textDecoration: "none", marginLeft: 12 }}>
                  Back to current &rarr;
                </a>
              )}
            </p>
          </div>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16, marginBottom: 24 }}>
          {[
            { label: "Patients in Panel", value: patientCount, color: "var(--concord-blue)" },
            { label: "Avg Compliance", value: `${avgCompliance}%`, color: avgCompliance >= 70 ? "var(--stable)" : "var(--warn)" },
            { label: "Non-Compliant", value: nonCompliant.length, color: nonCompliant.length > 0 ? "var(--severe)" : "var(--stable)" },
            { label: "EOM Revenue at Risk", value: `$${revenueAtRisk}/mo`, color: revenueAtRisk > 0 ? "var(--warn)" : "var(--stable)" },
          ].map((card) => (
            <div
              key={card.label}
              style={{
                background: "var(--surface)",
                borderRadius: 14,
                border: "1px solid var(--hairline)",
                padding: "20px 24px",
              }}
            >
              <div style={{ fontSize: 13, fontWeight: 500, color: "var(--slate)", textTransform: "uppercase", marginBottom: 8 }}>
                {card.label}
              </div>
              <div style={{ fontSize: 32, fontWeight: 600, color: card.color }}>
                {card.value}
              </div>
            </div>
          ))}
        </div>

        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
          marginBottom: 24,
        }}>
          <div style={{ padding: "16px 24px", borderBottom: "1px solid var(--hairline)" }}>
            <h2 style={{ fontSize: 17, fontWeight: 600 }}>6-Month Compliance Trend</h2>
          </div>
          <div style={{ padding: "24px", display: "flex", gap: 12, alignItems: "flex-end" }}>
            {monthlyTrend.map((t) => {
              const barH = Math.max(t.avg_compliance_pct, 4);
              return (
                <div key={`${t.year}-${t.month}`} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
                  <span style={{ fontSize: 13, fontWeight: 600, color: "var(--body)" }}>
                    {t.avg_compliance_pct}%
                  </span>
                  <div
                    style={{
                      width: "100%",
                      maxWidth: 48,
                      height: 140,
                      background: "var(--mist)",
                      borderRadius: 8,
                      position: "relative",
                      overflow: "hidden",
                    }}
                  >
                    <div
                      style={{
                        position: "absolute",
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: `${barH}%`,
                        borderRadius: 8,
                        background: t.avg_compliance_pct >= 70
                          ? "var(--stable)"
                          : t.avg_compliance_pct >= 50
                          ? "var(--caution)"
                          : "var(--severe)",
                        transition: "height 0.3s",
                      }}
                    />
                  </div>
                  <span style={{ fontSize: 11, color: "var(--hint)", textTransform: "uppercase" }}>
                    {t.monthName.slice(0, 3)}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
        }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                {["Patient", "Diagnosis", "Expected", "Actual", "Compliance", "Last Report", "Status"].map((h) => (
                  <th key={h} style={{
                    padding: "12px 16px",
                    fontSize: 13,
                    fontWeight: 600,
                    color: "var(--slate)",
                    textTransform: "uppercase",
                    letterSpacing: 0.4,
                    whiteSpace: "nowrap",
                  }}>
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {patients.length === 0 ? (
                <tr>
                  <td colSpan={7} style={{ padding: 24, textAlign: "center", color: "var(--hint)", fontSize: 15 }}>
                    No patients in your panel.
                  </td>
                </tr>
              ) : patients.map((p) => (
                <tr key={p.id} style={{ borderBottom: "1px solid var(--hairline)" }}>
                  <td style={{ padding: "12px 16px", fontWeight: 600, color: "var(--ink)" }}>
                    <a href={`/patients/${p.id}`} style={{ color: "inherit", textDecoration: "none" }}>
                      {p.full_name}
                    </a>
                  </td>
                  <td style={{ padding: "12px 16px", fontSize: 14, color: "var(--body)" }}>
                    {p.primary_diagnosis}
                  </td>
                  <td style={{ padding: "12px 16px", fontSize: 14, color: "var(--body)" }}>
                    {p.expected_reports}
                  </td>
                  <td style={{ padding: "12px 16px", fontSize: 14, fontWeight: 600, color: "var(--body)" }}>
                    {p.actual_reports}
                  </td>
                  <td style={{ padding: "12px 16px" }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <div style={{
                        width: 80,
                        height: 8,
                        background: "var(--mist)",
                        borderRadius: 4,
                        overflow: "hidden",
                      }}>
                        <div style={{
                          width: `${Math.min(p.compliance_pct, 100)}%`,
                          height: "100%",
                          borderRadius: 4,
                          background: p.compliance_pct >= 70
                            ? "var(--stable)"
                            : p.compliance_pct >= 50
                            ? "var(--caution)"
                            : "var(--severe)",
                        }} />
                      </div>
                      <span style={{
                        fontSize: 13,
                        fontWeight: 600,
                        color: p.compliance_pct >= 70 ? "var(--stable)" : "var(--warn)",
                      }}>
                        {p.compliance_pct}%
                      </span>
                    </div>
                  </td>
                  <td style={{ padding: "12px 16px", fontSize: 13, color: "var(--slate)" }}>
                    {p.last_report_at ? (
                      <>
                        {new Date(p.last_report_at).toLocaleDateString()}
                        {p.days_since_last_report != null && p.days_since_last_report > 7 && (
                          <span style={{ color: "var(--warn)", marginLeft: 4 }}>
                            ({p.days_since_last_report}d ago)
                          </span>
                        )}
                      </>
                    ) : (
                      <span style={{ color: "var(--hint)" }}>Never</span>
                    )}
                  </td>
                  <td style={{ padding: "12px 16px" }}>
                    <span style={{
                      display: "inline-block",
                      padding: "2px 10px",
                      borderRadius: 6,
                      fontSize: 12,
                      fontWeight: 500,
                      background: p.compliance_pct >= 70
                        ? "var(--concord-blue-tint)"
                        : "var(--mist)",
                      color: p.compliance_pct >= 70 ? "var(--stable)" : "var(--warn)",
                      textTransform: "capitalize",
                    }}>
                      {p.compliance_pct >= 70 ? "Compliant" : p.compliance_pct >= 50 ? "At Risk" : "Non-Compliant"}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
