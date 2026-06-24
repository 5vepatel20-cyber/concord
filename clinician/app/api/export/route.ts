import { NextRequest, NextResponse } from "next/server";
import { createClient } from "../../../lib/supabase/server";

export async function GET(req: NextRequest) {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return new NextResponse("Unauthorized", { status: 401 });
  }

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") {
    return new NextResponse("Forbidden", { status: 403 });
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

  const patientIds = (patients ?? []).map((p: any) => p.user_id);

  const { data: alertCounts } = await supabase
    .from("symptom_alert")
    .select("patient_id")
    .in("patient_id", patientIds)
    .eq("status", "open");

  const alertMap = new Map<string, number>();
  for (const a of alertCounts ?? []) {
    alertMap.set(a.patient_id, (alertMap.get(a.patient_id) ?? 0) + 1);
  }

  const { data: latestReports } = await supabase
    .from("symptom_report")
    .select("patient_id, reported_at")
    .in("patient_id", patientIds)
    .order("reported_at", { ascending: false })
    .limit(1);

  const reportMap = new Map<string, string>();
  for (const r of latestReports ?? []) {
    if (!reportMap.has(r.patient_id)) {
      reportMap.set(r.patient_id, r.reported_at);
    }
  }

  const rows = (patients ?? []).map((p: any) => ({
    name: p.user?.full_name ?? "Unknown",
    dob: p.user?.date_of_birth ?? "",
    diagnosis: p.condition?.display_name ?? "Unknown",
    status: p.treatment_status ?? "unknown",
    alerts: alertMap.get(p.user_id) ?? 0,
    lastReport: reportMap.get(p.user_id) ?? "",
  }));

  const header = "Patient Name,Date of Birth,Diagnosis,Treatment Status,Open Alerts,Last Report";
  const csv = rows.map((r) =>
    `"${r.name}","${r.dob}","${r.diagnosis}","${r.status}",${r.alerts},"${r.lastReport}"`,
  ).join("\n");

  return new NextResponse(`${header}\n${csv}`, {
    headers: {
      "content-type": "text/csv",
      "content-disposition": `attachment; filename="patient-roster-${new Date().toISOString().slice(0, 10)}.csv"`,
    },
  });
}
