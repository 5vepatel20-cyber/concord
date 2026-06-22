export interface PatientSummary {
  id: string;
  full_name: string;
  date_of_birth: string;
  primary_diagnosis: string;
  treatment_status: string;
  open_alerts: number;
  last_report_at: string | null;
  latest_grade: number | null;
}

export interface SymptomAlert {
  id: string;
  patient_id: string;
  patient_name: string;
  severity_level: "info" | "urgent" | "emergency";
  status: "open" | "acknowledged" | "resolved";
  term_name: string;
  composite_grade: number;
  created_at: string;
}

export interface PatientDetail extends PatientSummary {
  diagnosis_date: string | null;
  cancer_stage: string | null;
  sex_at_birth: string | null;
  recent_reports: {
    id: string;
    reported_at: string;
    grade: number;
    term_name: string;
  }[];
  medications: {
    id: string;
    display_name: string;
    dose: string;
    route: string;
    adherence_pct: number;
  }[];
}

export interface RtmPatientSummary {
  id: string;
  full_name: string;
  primary_diagnosis: string;
  status: string;
  consent_on_file: boolean;
  cpt_98975_billed: boolean;
}

export interface EomPatientCompliance {
  id: string;
  full_name: string;
  primary_diagnosis: string;
  expected_reports: number;
  actual_reports: number;
  compliance_pct: number;
  last_report_at: string | null;
  days_since_last_report: number | null;
}

export interface EomMonthlySummary {
  month: number;
  year: number;
  monthName: string;
  avg_compliance_pct: number;
  patient_count: number;
}

export interface RtmBillingPeriod {
  id: string;
  patient_id: string;
  year: number;
  month: number;
  total_minutes: number;
  cpt_98980_units: number;
  cpt_98981_units: number;
  billed: boolean;
  billed_at: string | null;
}
