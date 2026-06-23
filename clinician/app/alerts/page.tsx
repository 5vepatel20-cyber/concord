import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";
import type { SymptomAlert } from "../../lib/types";

async function fetchAlerts(): Promise<SymptomAlert[]> {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") {
    return [];
  }

  const { data: alerts } = await supabase
    .from("symptom_alert")
    .select(`
      id,
      patient_id,
      severity_level,
      status,
      created_at,
      user:user!symptom_alert_patient_id_fkey(full_name)
    `)
    .order("created_at", { ascending: false })
    .limit(50);

  if (!alerts) return [];

  return alerts.map((a: any) => ({
    id: a.id,
    patient_id: a.patient_id,
    patient_name: a.user?.full_name ?? "Unknown",
    severity_level: a.severity_level,
    status: a.status,
    term_name: "",
    composite_grade: a.severity_level === "emergency" ? 3 : a.severity_level === "urgent" ? 2 : 1,
    created_at: a.created_at,
  }));
}

async function acknowledgeAlert(alertId: string) {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase
    .from("symptom_alert")
    .update({ status: "acknowledged", acknowledged_by: user.id })
    .eq("id", alertId);
}

async function resolveAlert(alertId: string) {
  "use server";

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;

  await supabase
    .from("symptom_alert")
    .update({
      status: "resolved",
      acknowledged_by: user.id,
      resolved_at: new Date().toISOString(),
    })
    .eq("id", alertId);
}

export default async function AlertsPage() {
  const alerts = await fetchAlerts();

  const severityStyles: Record<string, { bg: string; color: string }> = {
    emergency: { bg: "#FDEAEA", color: "var(--severe)" },
    urgent: { bg: "#FBE6DD", color: "var(--warn)" },
    info: { bg: "var(--concord-blue-tint)", color: "var(--concord-blue)" },
  };

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px" }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 24 }}>
          Alert Inbox
        </h1>

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
                  {["Severity", "Patient", "Date", "Status", ""].map((h) => (
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
                  return (
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
                      <td style={{ padding: "12px 16px" }}>
                        {a.status === "open" && (
                          <form action={acknowledgeAlert.bind(null, a.id)}>
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
                          <form action={resolveAlert.bind(null, a.id)}>
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
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </main>
    </div>
  );
}
