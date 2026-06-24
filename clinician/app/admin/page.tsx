import { createClient } from "../../lib/supabase/server";
import { Nav } from "../../components/Nav";

async function fetchAdminData() {
  const supabase = await createClient();

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("user")
    .select("full_name, role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "clinician" && profile?.role !== "admin") return null;

  const { count: patientCount } = await supabase
    .from("patient_profile")
    .select("id", { count: "exact", head: true });

  const { data: clinicians } = await supabase
    .from("user")
    .select("id, full_name, email, role")
    .in("role", ["clinician", "admin"])
    .order("full_name");

  const { count: alertCount } = await supabase
    .from("symptom_alert")
    .select("id", { count: "exact", head: true })
    .eq("status", "open");

  return {
    myName: (profile as any)?.full_name ?? "Unknown",
    myRole: profile.role,
    patientCount: patientCount ?? 0,
    clinicianCount: (clinicians ?? []).filter((c: any) => c.role === "clinician").length,
    adminCount: (clinicians ?? []).filter((c: any) => c.role === "admin").length,
    clinicians: (clinicians ?? []).map((c: any) => ({
      id: c.id,
      name: c.full_name ?? "Unknown",
      email: c.email ?? "",
      role: c.role,
    })),
    openAlertCount: alertCount ?? 0,
  };
}

export default async function AdminPage() {
  const data = await fetchAdminData();
  if (!data) return null;

  return (
    <div style={{ display: "flex", minHeight: "100vh" }}>
      <Nav />
      <main style={{ flex: 1, padding: "24px 32px", maxWidth: 720 }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, marginBottom: 4 }}>
          Settings
        </h1>
        <p style={{ fontSize: 15, color: "var(--slate)", marginBottom: 32 }}>
          {data.myName} &middot; {data.myRole}
        </p>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 12, marginBottom: 32 }}>
          {[
            { label: "Patients", value: data.patientCount, color: "var(--concord-blue)" },
            { label: "Clinicians", value: data.clinicianCount, color: "var(--stable)" },
            { label: "Open Alerts", value: data.openAlertCount, color: "var(--severe)" },
          ].map((s) => (
            <div key={s.label} style={{
              background: "var(--surface)",
              borderRadius: 14,
              border: "1px solid var(--hairline)",
              padding: 16,
            }}>
              <div style={{ fontSize: 13, color: "var(--slate)", fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.3, marginBottom: 4 }}>
                {s.label}
              </div>
              <div style={{ fontSize: 32, fontWeight: 700, color: s.color }}>
                {s.value}
              </div>
            </div>
          ))}
        </div>

        <h2 style={{ fontSize: 17, fontWeight: 600, marginBottom: 12 }}>
          Care Team
        </h2>
        <div style={{
          background: "var(--surface)",
          borderRadius: 14,
          border: "1px solid var(--hairline)",
          overflow: "hidden",
        }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid var(--hairline)", textAlign: "left" }}>
                {["Name", "Email", "Role"].map((h) => (
                  <th key={h} style={{ padding: "10px 16px", fontSize: 13, fontWeight: 600, color: "var(--slate)", textTransform: "uppercase" }}>
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {data.clinicians.map((c: any) => (
                <tr key={c.id} style={{ borderBottom: "1px solid var(--hairline)" }}>
                  <td style={{ padding: "10px 16px", fontWeight: 600, color: "var(--ink)", fontSize: 14 }}>
                    {c.name}
                  </td>
                  <td style={{ padding: "10px 16px", color: "var(--body)", fontSize: 14 }}>
                    {c.email}
                  </td>
                  <td style={{ padding: "10px 16px" }}>
                    <span style={{
                      display: "inline-block",
                      padding: "2px 8px",
                      borderRadius: 4,
                      fontSize: 12,
                      fontWeight: 500,
                      background: c.role === "admin" ? "var(--concord-blue-tint)" : "var(--mist)",
                      color: c.role === "admin" ? "var(--concord-blue)" : "var(--slate)",
                      textTransform: "capitalize",
                    }}>
                      {c.role}
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
