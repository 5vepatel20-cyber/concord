import { notFound } from "next/navigation";
import { createClient } from "../../../lib/supabase/server";
import { Nav } from "../../../components/Nav";
import type { PatientDetail } from "../../../lib/types";

async function fetchPatient(id: string): Promise<PatientDetail | null> {
  const supabase = await createClient();

  const { data: profile } = await supabase
    .from("patient_profile")
    .select(`
      user_id,
      treatment_status,
      diagnosis_date,
      cancer_stage,
      user:user!inner(full_name, date_of_birth, sex_at_birth),
      condition:condition!patient_profile_primary_diagnosis_id_fkey(display_name)
    `)
    .eq("user_id", id)
    .single();

  if (!profile) return null;

  const { data: reports } = await supabase
    .from("symptom_report")
    .select("id, reported_at, symptom_response(composite_grade, symptom_term(display_name))")
    .eq("patient_id", id)
    .order("reported_at", { ascending: false })
    .limit(20);

  const { data: meds } = await supabase
    .from("medication")
    .select("id, display_name, dose, route")
    .eq("patient_id", id)
    .eq("active", true);

  const { data: openAlerts } = await supabase
    .from("symptom_alert")
    .select("id, severity_level, created_at, status")
    .eq("patient_id", id)
    .eq("status", "open")
    .order("created_at", { ascending: false });

  return {
    id: profile.user_id,
    full_name: (profile as any).user?.full_name ?? "Unknown",
    date_of_birth: (profile as any).user?.date_of_birth ?? "",
    primary_diagnosis: (profile as any).condition?.display_name ?? "Unknown",
    treatment_status: profile.treatment_status ?? "unknown",
    diagnosis_date: profile.diagnosis_date,
    cancer_stage: profile.cancer_stage,
    sex_at_birth: (profile as any).user?.sex_at_birth,
    open_alerts: openAlerts?.length ?? 0,
    last_report_at: reports?.[0]?.reported_at ?? null,
    latest_grade: null,
    recent_reports: (reports ?? []).flatMap((r: any) =>
      (r.symptom_response ?? []).map((sr: any) => ({
        id: r.id,
        reported_at: r.reported_at,
        grade: sr.composite_grade,
        term_name: sr.symptom_term?.display_name ?? "Unknown",
      })),
    ),
    medications: (meds ?? []).map((m: any) => ({
      id: m.id,
      display_name: m.display_name,
      dose: m.dose ?? "",
      route: m.route ?? "oral",
      adherence_pct: 0,
    })),
  };
}

export default async function PatientDetailPage({ params }: { params: { id: string } }) {
  const patient = await fetchPatient(params.id);
  if (!patient) notFound();

  const gradeColors: Record<string, string> = {
    "0": "var(--stable)",
    "1": "var(--caution)",
    "2": "var(--warn)",
    "3": "var(--severe)",
  };

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px", maxWidth: 960 }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 4 }}>
          {patient.full_name}
        </h1>
        <p style={{ fontSize: 15, color: "var(--slate)", marginBottom: 32 }}>
          {patient.primary_diagnosis}
          {patient.cancer_stage ? ` · Stage ${patient.cancer_stage}` : ""}
          {patient.diagnosis_date ? ` · Diagnosed ${patient.diagnosis_date}` : ""}
        </p>

        <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12 }}>
          Recent Symptoms
        </h2>
        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
          marginBottom: 32,
        }}>
          {patient.recent_reports.length === 0 ? (
            <p style={{ padding: 24, color: "var(--hint)", fontSize: 15 }}>
              No symptoms logged yet.
            </p>
          ) : (
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                  {["Date", "Symptom", "Grade"].map((h) => (
                    <th key={h} style={{
                      padding: "10px 16px",
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
                {patient.recent_reports.slice(0, 30).map((r, i) => (
                  <tr key={`${r.id}-${i}`} style={{ borderBottom: "1px solid var(--hairline)" }}>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {new Date(r.reported_at).toLocaleDateString()}
                    </td>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {r.term_name}
                    </td>
                    <td style={{ padding: "10px 16px" }}>
                      <span style={{
                        display: "inline-block",
                        padding: "2px 10px",
                        borderRadius: 6,
                        fontSize: 12,
                        fontWeight: 500,
                        background: `${gradeColors[String(r.grade)] ?? "var(--hint)"}20`,
                        color: gradeColors[String(r.grade)] ?? "var(--hint)",
                      }}>
                        {["None", "Mild", "Moderate", "Severe"][r.grade] ?? "Unknown"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12 }}>
          Medications
        </h2>
        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
        }}>
          {patient.medications.length === 0 ? (
            <p style={{ padding: 24, color: "var(--hint)", fontSize: 15 }}>
              No medications recorded.
            </p>
          ) : (
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                  {["Medication", "Dose", "Route"].map((h) => (
                    <th key={h} style={{
                      padding: "10px 16px",
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
                {patient.medications.map((m) => (
                  <tr key={m.id} style={{ borderBottom: "1px solid var(--hairline)" }}>
                    <td style={{ padding: "10px 16px", fontSize: 14, fontWeight: 600, color: "var(--ink)" }}>
                      {m.display_name}
                    </td>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {m.dose || "—"}
                    </td>
                    <td style={{ padding: "10px 16px", fontSize: 14, color: "var(--body)" }}>
                      {m.route}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </main>
    </div>
  );
}
