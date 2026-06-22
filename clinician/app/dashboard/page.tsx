import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";
import type { PatientSummary } from "../../lib/types";

async function fetchPatients(): Promise<PatientSummary[]> {
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

  const { data: patients } = await supabase
    .from("patient_profile")
    .select(`
      user_id,
      treatment_status,
      diagnosis_date,
      user:user!inner(full_name, date_of_birth),
      condition!patient_profile_primary_diagnosis_id_fkey(display_name)
    `);

  if (!patients) return [];

  return patients.map((p: any) => ({
    id: p.user_id,
    full_name: p.user?.full_name ?? "Unknown",
    date_of_birth: p.user?.date_of_birth ?? "",
    primary_diagnosis: p.condition?.display_name ?? "Unknown",
    treatment_status: p.treatment_status ?? "unknown",
    open_alerts: 0,
    last_report_at: null,
    latest_grade: null,
  }));
}

export default async function DashboardPage() {
  const patients = await fetchPatients();

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px" }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 24 }}>
          Patient Roster
        </h1>

        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
        }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                {["Patient", "Diagnosis", "Status", "Alerts"].map((h) => (
                  <th key={h} style={{
                    padding: "12px 16px",
                    fontSize: 13,
                    fontWeight: 600,
                    color: "var(--slate)",
                    textTransform: "uppercase",
                    letterSpacing: 0.4,
                  }}>
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {patients.length === 0 ? (
                <tr>
                  <td colSpan={4} style={{ padding: 24, textAlign: "center", color: "var(--hint)", fontSize: 15 }}>
                    No patients in your panel yet.
                  </td>
                </tr>
              ) : patients.map((p) => (
                <tr
                  key={p.id}
                  style={{ borderBottom: "1px solid var(--hairline)", cursor: "pointer" }}
                  onClick={() => window.location.href = `/patients/${p.id}`}
                >
                  <td style={{ padding: "12px 16px" }}>
                    <div style={{ fontWeight: 600, color: "var(--ink)" }}>{p.full_name}</div>
                    <div style={{ fontSize: 13, color: "var(--slate)" }}>{p.date_of_birth}</div>
                  </td>
                  <td style={{ padding: "12px 16px", fontSize: 15, color: "var(--body)" }}>
                    {p.primary_diagnosis}
                  </td>
                  <td style={{ padding: "12px 16px" }}>
                    <span style={{
                      display: "inline-block",
                      padding: "2px 10px",
                      borderRadius: 6,
                      fontSize: 12,
                      fontWeight: 500,
                      background: p.treatment_status === "active_treatment"
                        ? "var(--concord-blue-tint)"
                        : "var(--mist)",
                      color: p.treatment_status === "active_treatment"
                        ? "var(--concord-blue)"
                        : "var(--slate)",
                    }}>
                      {p.treatment_status.replace(/_/g, " ")}
                    </span>
                  </td>
                  <td style={{ padding: "12px 16px" }}>
                    {p.open_alerts > 0 ? (
                      <span style={{
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
                      }}>
                        {p.open_alerts}
                      </span>
                    ) : (
                      <span style={{ color: "var(--hint)", fontSize: 14 }}>—</span>
                    )}
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
