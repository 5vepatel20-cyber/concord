import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";
import { AlertList } from "../../components/AlertList";

async function fetchAlerts() {
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
      report_id,
      user:user!symptom_alert_patient_id_fkey(full_name)
    `)
    .order("created_at", { ascending: false })
    .limit(50);

  if (!alerts) return [];

  const reportIds = alerts
    .map((a: any) => a.report_id)
    .filter(Boolean);

  const reportDataMap = new Map<string, { reported_at: string; responses: { grade: number; term_name: string }[] }>();

  if (reportIds.length > 0) {
    const { data: reports } = await supabase
      .from("symptom_report")
      .select("id, reported_at, symptom_response(composite_grade, symptom_term(display_name))")
      .in("id", reportIds);

    for (const r of (reports as any[]) ?? []) {
      reportDataMap.set(r.id, {
        reported_at: r.reported_at,
        responses: (r.symptom_response ?? []).map((sr: any) => ({
          grade: sr.composite_grade ?? 0,
          term_name: sr.symptom_term?.display_name ?? "Unknown",
        })),
      });
    }
  }

  return alerts.map((a: any) => ({
    id: a.id,
    patient_id: a.patient_id,
    patient_name: a.user?.full_name ?? "Unknown",
    severity_level: a.severity_level,
    status: a.status,
    created_at: a.created_at,
    report_id: a.report_id,
    report: a.report_id ? (reportDataMap.get(a.report_id) ?? null) : null,
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

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px" }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 24 }}>
          Alert Inbox
        </h1>

        <AlertList
          alerts={alerts}
          acknowledgeAction={acknowledgeAlert}
          resolveAction={resolveAlert}
        />
      </main>
    </div>
  );
}
