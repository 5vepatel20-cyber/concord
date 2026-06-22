import { NextResponse } from "next/server";
import { createClient } from "../../../lib/supabase/server";

const CPT_RATES: Record<string, number> = {
  "98975": 20,
  "98980": 50,
  "98981": 40,
};

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export async function GET(request: Request) {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") {
    return NextResponse.redirect(new URL("/dashboard", request.url));
  }

  const { searchParams } = new URL(request.url);
  const now = new Date();
  const year = parseInt(searchParams.get("year") ?? String(now.getFullYear()), 10);
  const month = parseInt(searchParams.get("month") ?? String(now.getMonth() + 1), 10);

  const { data: enrollments } = await supabase
    .from("rtm_enrollment")
    .select(`
      patient_id,
      status,
      cpt_98975_billed,
      consent_on_file,
      user:user!rtm_enrollment_patient_id_fkey(full_name),
      patient_profile!inner(
        diagnosis_date,
        condition!patient_profile_primary_diagnosis_id_fkey(display_name, icd10_code)
      )
    `)
    .eq("status", "active");

  const { data: periods } = await supabase
    .from("rtm_billing_period")
    .select("*")
    .eq("year", year)
    .eq("month", month);

  const periodMap = new Map((periods ?? []).map((p: any) => [p.patient_id, p]));

  const rows: string[] = [
    ["Patient Name", "ICD-10 Code", "DOB", "CPT Code", "Units", "Rate", "Charge", "Billed"].join(","),
  ];

  for (const e of enrollments ?? []) {
    const enc = e as any;
    const period = periodMap.get(enc.patient_id) as any;
    const patientName = enc.user?.full_name ?? "Unknown";

    const icd10 = enc.patient_profile?.condition?.icd10_code ?? "";
    const units98980 = period?.cpt_98980_units ?? 0;
    const units98981 = period?.cpt_98981_units ?? 0;

    if (units98980 > 0) {
      rows.push([
        `"${patientName}"`,
        icd10,
        "",
        "98980",
        units98980,
        CPT_RATES["98980"],
        units98980 * CPT_RATES["98980"],
        period?.billed ? "Yes" : "No",
      ].join(","));
    }

    if (units98981 > 0) {
      rows.push([
        `"${patientName}"`,
        icd10,
        "",
        "98981",
        units98981,
        CPT_RATES["98981"],
        units98981 * CPT_RATES["98981"],
        period?.billed ? "Yes" : "No",
      ].join(","));
    }

    if (!enc.cpt_98975_billed) {
      rows.push([
        `"${patientName}"`,
        icd10,
        "",
        "98975",
        1,
        CPT_RATES["98975"],
        CPT_RATES["98975"],
        "No",
      ].join(","));
    }
  }

  const csv = rows.join("\n");
  const filename = `superbill-${year}-${String(month).padStart(2, "0")}.csv`;

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}
