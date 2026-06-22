import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";
import type { RtmPatientSummary, RtmBillingPeriod } from "../../lib/types";

const CPT_RATES: Record<string, number> = {
  "98975": 20,
  "98980": 50,
  "98981": 40,
};

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

function currentPeriod() {
  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() + 1, monthName: MONTH_NAMES[now.getMonth()] };
}

async function fetchBillingData(year: number, month: number) {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { patients: [], periods: [], profile: null };

  const { data: profile } = await supabase
    .from("user")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") {
    return { patients: [], periods: [], profile: null };
  }

  const { data: enrollments } = await supabase
    .from("rtm_enrollment")
    .select(`
      id,
      patient_id,
      status,
      consent_on_file,
      cpt_98975_billed,
      user:user!rtm_enrollment_patient_id_fkey(full_name),
      patient_profile!inner(primary_diagnosis_id, condition!patient_profile_primary_diagnosis_id_fkey(display_name))
    `)
    .order("enrolled_at", { ascending: false });

  const { data: periods } = await supabase
    .from("rtm_billing_period")
    .select("*")
    .eq("year", year)
    .eq("month", month);

  const patients: RtmPatientSummary[] = (enrollments ?? []).map((e: any) => ({
    id: e.patient_id,
    full_name: e.user?.full_name ?? "Unknown",
    primary_diagnosis: e.patient_profile?.condition?.display_name ?? "Unknown",
    status: e.status,
    consent_on_file: e.consent_on_file,
    cpt_98975_billed: e.cpt_98975_billed,
  }));

  return { patients, periods: (periods ?? []) as RtmBillingPeriod[], profile };
}

async function logTimeEntry(
  _prev: any,
  formData: FormData,
) {
  "use server";

  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not authenticated" };

  const patientId = formData.get("patient_id") as string;
  const cptCode = formData.get("cpt_code") as string;
  const minutes = parseInt(formData.get("minutes") as string, 10);
  const description = formData.get("description") as string;

  if (!patientId || !cptCode || !minutes || minutes < 1 || minutes > 120) {
    return { error: "Invalid input" };
  }

  const { error } = await supabase.from("rtm_time_entry").insert({
    patient_id: patientId,
    clinician_id: user.id,
    cpt_code: cptCode,
    minutes,
    description: description || null,
  });

  if (error) return { error: error.message };
  return { success: true };
}

async function toggleBilled(periodId: string, billed: boolean) {
  "use server";

  const supabase = await createClient();
  await supabase
    .from("rtm_billing_period")
    .update({ billed, billed_at: billed ? new Date().toISOString() : null })
    .eq("id", periodId);
}

async function toggleEnrollment(patientId: string, status: string) {
  "use server";

  const supabase = await createClient();
  await supabase
    .from("rtm_enrollment")
    .update({ status })
    .eq("patient_id", patientId);
}

export default async function BillingPage({
  searchParams,
}: {
  searchParams: { year?: string; month?: string };
}) {
  const now = new Date();
  const year = parseInt(searchParams.year ?? String(now.getFullYear()), 10);
  const month = parseInt(searchParams.month ?? String(now.getMonth() + 1), 10);
  const { patients, periods, profile } = await fetchBillingData(year, month);

  if (!profile) redirect("/login");

  const periodMap = new Map(periods.map((p) => [p.patient_id, p]));
  const cp = currentPeriod();
  const isCurrentPeriod = year === cp.year && month === cp.month;

  const activePatients = patients.filter((p) => p.status === "active");
  const totalMonthlyRevenue = periods
    .filter((p) => !p.billed)
    .reduce((sum, p) => {
      return sum + p.cpt_98980_units * CPT_RATES["98980"] + p.cpt_98981_units * CPT_RATES["98981"];
    }, 0);

  const prevMonth = month === 1 ? 12 : month - 1;
  const prevYear = month === 1 ? year - 1 : year;

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 24 }}>
          <div>
            <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 4 }}>RTM Billing Dashboard</h1>
            <p style={{ fontSize: 15, color: "var(--slate)" }}>
              <a
                href={`/billing?year=${prevYear}&month=${prevMonth}`}
                style={{ color: "var(--concord-blue)", textDecoration: "none", marginRight: 12 }}
              >
                &larr; Prev
              </a>
              {MONTH_NAMES[month - 1]} {year}
              {isCurrentPeriod ? (
                <span style={{ marginLeft: 8, fontSize: 12, color: "var(--hint)" }}>(current)</span>
              ) : (
                <a
                  href="/billing"
                  style={{ color: "var(--concord-blue)", textDecoration: "none", marginLeft: 12 }}
                >
                  Back to current &rarr;
                </a>
              )}
            </p>
          </div>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16, marginBottom: 24 }}>
          {[
            { label: "RTM-Enrolled Patients", value: activePatients.length, color: "var(--concord-blue)" },
            { label: "Billable This Period", value: periods.filter((p) => p.total_minutes > 0 && !p.billed).length, color: "var(--stable)" },
            { label: "Unbilled Revenue", value: `$${totalMonthlyRevenue}`, color: "var(--warn)" },
            { label: "Setup (98975) Remaining", value: activePatients.filter((p) => !p.cpt_98975_billed).length, color: "var(--caution)" },
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
        }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                {["Patient", "Diagnosis", "Enrollment", "Consent", "98975 Setup", "Time This Period", "98980 Units", "98981 Units", "Revenue", "Billed", ""].map((h) => (
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
                  <td colSpan={11} style={{ padding: 24, textAlign: "center", color: "var(--hint)", fontSize: 15 }}>
                    No patients enrolled in RTM yet.
                  </td>
                </tr>
              ) : patients.map((p) => {
                const period = periodMap.get(p.id);
                const minutes = period?.total_minutes ?? 0;
                const units80 = period?.cpt_98980_units ?? 0;
                const units81 = period?.cpt_98981_units ?? 0;
                const revenue = units80 * CPT_RATES["98980"] + units81 * CPT_RATES["98981"];
                const billed = period?.billed ?? false;

                return (
                  <tr key={p.id} style={{ borderBottom: "1px solid var(--hairline)" }}>
                    <td style={{ padding: "12px 16px", fontWeight: 600, color: "var(--ink)" }}>
                      <a href={`/patients/${p.id}`} style={{ color: "inherit", textDecoration: "none" }}>
                        {p.full_name}
                      </a>
                    </td>
                    <td style={{ padding: "12px 16px", fontSize: 14, color: "var(--body)" }}>
                      {p.primary_diagnosis}
                    </td>
                    <td style={{ padding: "12px 16px" }}>
                      <form action={toggleEnrollment.bind(null, p.id, p.status === "active" ? "paused" : "active")}>
                        <span style={{
                          display: "inline-block",
                          padding: "2px 10px",
                          borderRadius: 6,
                          fontSize: 12,
                          fontWeight: 500,
                          background: p.status === "active" ? "var(--concord-blue-tint)" : "var(--mist)",
                          color: p.status === "active" ? "var(--concord-blue)" : "var(--slate)",
                          textTransform: "capitalize",
                        }}>
                          {p.status}
                        </span>
                      </form>
                    </td>
                    <td style={{ padding: "12px 16px" }}>
                      <span style={{ fontSize: 14, color: p.consent_on_file ? "var(--stable)" : "var(--warn)" }}>
                        {p.consent_on_file ? "Yes" : "No"}
                      </span>
                    </td>
                    <td style={{ padding: "12px 16px" }}>
                      <span style={{
                        display: "inline-block",
                        padding: "2px 10px",
                        borderRadius: 6,
                        fontSize: 12,
                        fontWeight: 500,
                        background: p.cpt_98975_billed ? "var(--concord-blue-tint)" : "var(--mist)",
                        color: p.cpt_98975_billed ? "var(--stable)" : "var(--hint)",
                      }}>
                        {p.cpt_98975_billed ? "Billed" : "Pending"}
                      </span>
                    </td>
                    <td style={{ padding: "12px 16px", fontSize: 14, fontWeight: 600, color: "var(--body)" }}>
                      {minutes} min
                    </td>
                    <td style={{ padding: "12px 16px", fontSize: 14, color: "var(--body)" }}>
                      {units80}
                    </td>
                    <td style={{ padding: "12px 16px", fontSize: 14, color: "var(--body)" }}>
                      {units81}
                    </td>
                    <td style={{ padding: "12px 16px", fontSize: 14, fontWeight: 600, color: "var(--stable)" }}>
                      ${revenue}
                    </td>
                    <td style={{ padding: "12px 16px" }}>
                      <form action={toggleBilled.bind(null, period?.id ?? "", !billed)}>
                        <button
                          type="submit"
                          style={{
                            padding: "4px 12px",
                            fontSize: 12,
                            fontWeight: 500,
                            border: "1px solid var(--hairline)",
                            borderRadius: 6,
                            background: billed ? "var(--concord-blue-tint)" : "var(--surface)",
                            color: billed ? "var(--stable)" : "var(--hint)",
                            cursor: "pointer",
                          }}
                        >
                          {billed ? "Billed" : "Mark billed"}
                        </button>
                      </form>
                    </td>
                    <td style={{ padding: "12px 16px" }}>
                      {isCurrentPeriod && p.status === "active" && (
                        <form action={logTimeEntry}>
                          <input type="hidden" name="patient_id" value={p.id} />
                          <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
                            <select
                              name="cpt_code"
                              style={{
                                padding: "4px 8px",
                                fontSize: 12,
                                border: "1px solid var(--hairline)",
                                borderRadius: 6,
                                background: "var(--surface)",
                                color: "var(--ink)",
                              }}
                            >
                              <option value="98980">98980</option>
                              <option value="98981">98981</option>
                            </select>
                            <input
                              type="number"
                              name="minutes"
                              min={1}
                              max={120}
                              placeholder="min"
                              style={{
                                width: 52,
                                padding: "4px 6px",
                                fontSize: 12,
                                border: "1px solid var(--hairline)",
                                borderRadius: 6,
                                background: "var(--surface)",
                                color: "var(--ink)",
                              }}
                            />
                            <button
                              type="submit"
                              style={{
                                padding: "4px 10px",
                                fontSize: 12,
                                fontWeight: 500,
                                background: "var(--concord-blue)",
                                color: "var(--surface)",
                                border: "none",
                                borderRadius: 6,
                                cursor: "pointer",
                              }}
                            >
                              Log
                            </button>
                          </div>
                        </form>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <div style={{ marginTop: 24, display: "flex", gap: 12 }}>
          <a
            href={`/billing/export?year=${year}&month=${month}`}
            style={{
              display: "inline-block",
              padding: "10px 20px",
              fontSize: 14,
              fontWeight: 500,
              background: "var(--concord-blue)",
              color: "var(--surface)",
              border: "none",
              borderRadius: 10,
              cursor: "pointer",
              textDecoration: "none",
            }}
          >
            Export Superbill CSV
          </a>
          <a
            href={`/billing?year=${year}&month=${month}&setup=1`}
            style={{
              display: "inline-block",
              padding: "10px 20px",
              fontSize: 14,
              fontWeight: 500,
              background: "var(--surface)",
              color: "var(--concord-blue)",
              border: "1px solid var(--hairline)",
              borderRadius: 10,
              cursor: "pointer",
              textDecoration: "none",
            }}
          >
            Show Setup-eligible Patients
          </a>
        </div>
      </main>
    </div>
  );
}
