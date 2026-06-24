import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";
import { PatientRosterTable } from "../../components/PatientRosterTable";
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

  const patientIds = patients.map((p: any) => p.user_id);

  // Batch query for open alert counts per patient.
  const { data: alertCounts } = await supabase
    .from("symptom_alert")
    .select("patient_id, severity_level")
    .in("patient_id", patientIds)
    .eq("status", "open");

  const alertCountMap = new Map<string, number>();
  for (const a of alertCounts ?? []) {
    alertCountMap.set(a.patient_id, (alertCountMap.get(a.patient_id) ?? 0) + 1);
  }

  // Batch query for most recent report date + grade per patient.
  const { data: latestReports } = await supabase
    .from("symptom_report")
    .select(`
      patient_id,
      reported_at,
      symptom_response(composite_grade)
    `)
    .in("patient_id", patientIds)
    .order("reported_at", { ascending: false })
    .limit(1);

  const latestReportMap = new Map<string, { reported_at: string; top_grade: number }>();
  for (const r of latestReports ?? []) {
    const grades = (r.symptom_response as any[] | undefined) ?? [];
    const topGrade = grades.length > 0
      ? Math.max(...grades.map((g: any) => g.composite_grade ?? 0))
      : 0;
    latestReportMap.set(r.patient_id, {
      reported_at: r.reported_at,
      top_grade: topGrade,
    });
  }

  return patients.map((p: any) => {
    const alerts = alertCountMap.get(p.user_id) ?? 0;
    const latest = latestReportMap.get(p.user_id);
    return {
      id: p.user_id,
      full_name: p.user?.full_name ?? "Unknown",
      date_of_birth: p.user?.date_of_birth ?? "",
      primary_diagnosis: p.condition?.display_name ?? "Unknown",
      treatment_status: p.treatment_status ?? "unknown",
      open_alerts: alerts,
      last_report_at: latest?.reported_at ?? null,
      latest_grade: latest?.top_grade ?? null,
    };
  });
}

export default async function DashboardPage() {
  const supabase = await createClient();
  const patients = await fetchPatients();

  const { count: totalAlerts } = await supabase
    .from("symptom_alert")
    .select("id", { count: "exact", head: true })
    .eq("status", "open");

  const { data: { user } } = await supabase.auth.getUser();
  let unreadMessages = 0;
  if (user) {
    const { data: participations } = await supabase
      .from("conversation_participant")
      .select("conversation_id, last_read_at")
      .eq("user_id", user.id);

    if (participations && participations.length > 0) {
      const convIds = participations.map((p: any) => p.conversation_id);
      const { data: lastMessages } = await supabase
        .from("message")
        .select("conversation_id, created_at, sender_id")
        .in("conversation_id", convIds);

      if (lastMessages) {
        const myReadMap = new Map(participations.map((p: any) => [p.conversation_id, p.last_read_at]));
        const lastMsgMap = new Map<string, any>();
        for (const msg of lastMessages) {
          if (!lastMsgMap.has(msg.conversation_id)) {
            lastMsgMap.set(msg.conversation_id, msg);
          }
        }
        for (const [cid, lastMsg] of lastMsgMap) {
          const myReadAt = myReadMap.get(cid);
          if (lastMsg.sender_id !== user.id && (myReadAt == null || new Date(lastMsg.created_at) > new Date(myReadAt))) {
            unreadMessages++;
          }
        }
      }
    }
  }

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 20 }}>
          <h1 style={{ fontSize: 24, fontWeight: 600, margin: 0 }}>
            Patient Roster
          </h1>
          <a href="/api/export" style={{
            padding: "8px 16px",
            fontSize: 13,
            fontWeight: 500,
            background: "var(--surface)",
            color: "var(--concord-blue)",
            border: "1px solid var(--hairline)",
            borderRadius: 8,
            textDecoration: "none",
          }}>
            Export CSV
          </a>
        </div>

        <div style={{ display: "flex", gap: 12, marginBottom: 20 }}>
          {[
            { label: "Total Patients", value: patients.length, color: "var(--concord-blue)" },
            { label: "Open Alerts", value: totalAlerts ?? 0, color: totalAlerts && totalAlerts > 0 ? "var(--severe)" : "var(--stable)" },
            { label: "Unread Messages", value: unreadMessages, color: unreadMessages > 0 ? "var(--warn)" : "var(--hint)" },
          ].map((s) => (
            <div key={s.label} style={{
              flex: 1,
              background: "var(--surface)",
              borderRadius: 12,
              border: "1px solid var(--hairline)",
              padding: "14px 16px",
            }}>
              <div style={{ fontSize: 13, color: "var(--slate)", fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 2 }}>
                {s.label}
              </div>
              <div style={{ fontSize: 28, fontWeight: 700, color: s.color }}>
                {s.value}
              </div>
            </div>
          ))}
        </div>

        <PatientRosterTable patients={patients} />
      </main>
    </div>
  );
}
