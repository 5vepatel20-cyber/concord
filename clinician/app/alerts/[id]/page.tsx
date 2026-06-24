import { notFound, redirect } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { Nav } from "../../../components/Nav";

async function fetchAlert(id: string) {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") {
    return null;
  }

  const { data: alert } = await supabase
    .from("symptom_alert")
    .select(`
      id,
      patient_id,
      severity_level,
      status,
      created_at,
      acknowledged_by,
      acknowledged_at,
      resolved_at,
      report_id,
      user:user!symptom_alert_patient_id_fkey(full_name)
    `)
    .eq("id", id)
    .single();

  if (!alert) return null;

  let report = null;
  if (alert.report_id) {
    const { data: symptomReport } = await supabase
      .from("symptom_report")
      .select("id, reported_at, symptom_response(composite_grade, symptom_term(display_name, body_system))")
      .eq("id", alert.report_id)
      .single();

    if (symptomReport) {
      report = {
        id: symptomReport.id,
        reported_at: symptomReport.reported_at,
        responses: ((symptomReport as any).symptom_response ?? []).map((sr: any) => ({
          grade: sr.composite_grade ?? 0,
          term_name: sr.symptom_term?.display_name ?? "Unknown",
          body_system: sr.symptom_term?.body_system ?? null,
        })),
      };
    }
  }

  return {
    id: alert.id,
    patient_id: alert.patient_id,
    patient_name: (alert as any).user?.full_name ?? "Unknown",
    severity_level: alert.severity_level,
    status: alert.status,
    created_at: alert.created_at,
    acknowledged_by: alert.acknowledged_by,
    acknowledged_at: alert.acknowledged_at,
    resolved_at: alert.resolved_at,
    report_id: alert.report_id,
    report,
  };
}

async function acknowledgeAlert(alertId: string) {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase
    .from("symptom_alert")
    .update({ status: "acknowledged", acknowledged_by: user.id, acknowledged_at: new Date().toISOString() })
    .eq("id", alertId);
}

async function resolveAlert(alertId: string) {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase
    .from("symptom_alert")
    .update({ status: "resolved", acknowledged_by: user.id, resolved_at: new Date().toISOString() })
    .eq("id", alertId);
}

export default async function AlertDetailPage({ params }: { params: { id: string } }) {
  const alert = await fetchAlert(params.id);

  if (!alert) notFound();

  const severityStyles: Record<string, { bg: string; color: string }> = {
    emergency: { bg: "#FDEAEA", color: "var(--severe)" },
    urgent: { bg: "#FBE6DD", color: "var(--warn)" },
    info: { bg: "var(--concord-blue-tint)", color: "var(--concord-blue)" },
  };

  const gradeColors: Record<string, string> = {
    "0": "var(--stable)",
    "1": "var(--caution)",
    "2": "var(--warn)",
    "3": "var(--severe)",
  };

  const s = severityStyles[alert.severity_level] ?? severityStyles.info;
  const maxGrade = alert.report ? Math.max(...alert.report.responses.map((r: { grade: number }) => r.grade), 0) : 0;

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px", maxWidth: 800 }}>
        <a href="/alerts" style={{
          fontSize: 14,
          color: "var(--concord-blue)",
          textDecoration: "none",
          marginBottom: 16,
          display: "inline-block",
        }}>
          &larr; Back to Alert Inbox
        </a>

        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 24 }}>
          <div>
            <h1 style={{ fontSize: 24, fontWeight: 600, margin: 0, marginBottom: 8 }}>
              Alert Detail
            </h1>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
              <span style={{
                display: "inline-block",
                padding: "4px 12px",
                borderRadius: 6,
                fontSize: 13,
                fontWeight: 600,
                background: s.bg,
                color: s.color,
                textTransform: "uppercase",
              }}>
                {alert.severity_level}
              </span>
              <span style={{
                display: "inline-block",
                padding: "4px 12px",
                borderRadius: 6,
                fontSize: 13,
                fontWeight: 500,
                color: alert.status === "open" ? "var(--warn)" : alert.status === "acknowledged" ? "var(--caution)" : "var(--stable)",
                textTransform: "capitalize",
              }}>
                {alert.status}
              </span>
              <span style={{ fontSize: 14, color: "var(--hint)" }}>
                {new Date(alert.created_at).toLocaleString()}
              </span>
            </div>
          </div>

          <div style={{ display: "flex", gap: 8 }}>
            {alert.status === "open" && (
              <form action={acknowledgeAlert.bind(null, alert.id)}>
                <button type="submit" style={{
                  padding: "8px 18px",
                  fontSize: 14,
                  fontWeight: 500,
                  background: "var(--surface)",
                  color: "var(--concord-blue)",
                  border: "1px solid var(--hairline)",
                  borderRadius: 8,
                  cursor: "pointer",
                }}>
                  Acknowledge
                </button>
              </form>
            )}
            {alert.status !== "resolved" && (
              <form action={resolveAlert.bind(null, alert.id)}>
                <button type="submit" style={{
                  padding: "8px 18px",
                  fontSize: 14,
                  fontWeight: 500,
                  background: "var(--stable)",
                  color: "var(--surface)",
                  border: "none",
                  borderRadius: 8,
                  cursor: "pointer",
                }}>
                  Resolve
                </button>
              </form>
            )}
          </div>
        </div>

        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          padding: 20,
          marginBottom: 24,
        }}>
          <h2 style={{ fontSize: 17, fontWeight: 600, margin: 0, marginBottom: 16 }}>Patient</h2>
          <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
            <div style={{
              width: 48,
              height: 48,
              borderRadius: 24,
              background: "var(--concord-blue-tint)",
              color: "var(--concord-blue)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 18,
              fontWeight: 700,
            }}>
              {alert.patient_name.charAt(0)}
            </div>
            <div>
              <a href={`/patients/${alert.patient_id}`} style={{
                fontSize: 18,
                fontWeight: 600,
                color: "var(--ink)",
                textDecoration: "none",
              }}>
                {alert.patient_name}
              </a>
              <div style={{ fontSize: 14, color: "var(--hint)", marginTop: 2 }}>
                Patient ID: {alert.patient_id.slice(0, 8)}...
              </div>
            </div>
          </div>
        </div>

        {alert.report && (
          <div style={{
            background: "var(--surface)",
            borderRadius: 14,
            border: "1px solid var(--hairline)",
            padding: 20,
            marginBottom: 24,
          }}>
            <h2 style={{ fontSize: 17, fontWeight: 600, margin: 0, marginBottom: 4 }}>Linked Symptom Report</h2>
            <p style={{ fontSize: 14, color: "var(--hint)", margin: "0 0 16px 0" }}>
              {new Date(alert.report.reported_at).toLocaleString()} &middot; {alert.report.responses.length} symptom{alert.report.responses.length !== 1 ? "s" : ""}
            </p>

            <div style={{
              display: "inline-block",
              padding: "4px 12px",
              borderRadius: 6,
              fontSize: 13,
              fontWeight: 600,
              background: `${gradeColors[String(maxGrade)] ?? "var(--hint)"}20`,
              color: gradeColors[String(maxGrade)] ?? "var(--hint)",
              marginBottom: 16,
            }}>
              Overall severity: {["None", "Mild", "Moderate", "Severe"][maxGrade] ?? "Unknown"} (grade {maxGrade})
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {alert.report.responses.map((r: { grade: number; term_name: string; body_system: string | null }, i: number) => {
                const sorted = [...alert.report!.responses].sort((a: { grade: number }, b: { grade: number }) => b.grade - a.grade);
                return (
                  <div key={i} style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 12,
                    padding: "10px 12px",
                    background: "var(--mist)",
                    borderRadius: 10,
                  }}>
                    <span style={{
                      display: "inline-block",
                      width: 10,
                      height: 10,
                      borderRadius: 5,
                      background: gradeColors[String(r.grade)] ?? "var(--hint)",
                      flexShrink: 0,
                    }} />
                    <div style={{ flex: 1 }}>
                      <span style={{ fontSize: 15, fontWeight: 500, color: "var(--ink)" }}>
                        {r.term_name}
                      </span>
                      {r.body_system && (
                        <span style={{ fontSize: 12, color: "var(--hint)", marginLeft: 8 }}>
                          {r.body_system}
                        </span>
                      )}
                    </div>
                    <span style={{
                      fontSize: 13,
                      fontWeight: 600,
                      padding: "2px 10px",
                      borderRadius: 6,
                      background: `${gradeColors[String(r.grade)] ?? "var(--hint)"}20`,
                      color: gradeColors[String(r.grade)] ?? "var(--hint)",
                    }}>
                      {["None", "Mild", "Moderate", "Severe"][r.grade] ?? "Unknown"}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {alert.status === "acknowledged" && alert.acknowledged_at && (
          <div style={{
            background: "var(--surface)",
            borderRadius: 14,
            border: "1px solid var(--hairline)",
            padding: 16,
            marginBottom: 24,
          }}>
            <div style={{ fontSize: 14, color: "var(--hint)" }}>
              Acknowledged at {new Date(alert.acknowledged_at).toLocaleString()}
            </div>
          </div>
        )}

        {alert.status === "resolved" && alert.resolved_at && (
          <div style={{
            background: "var(--surface)",
            borderRadius: 14,
            border: "1px solid var(--hairline)",
            padding: 16,
          }}>
            <div style={{ fontSize: 14, color: "var(--hint)" }}>
              Resolved at {new Date(alert.resolved_at).toLocaleString()}
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
