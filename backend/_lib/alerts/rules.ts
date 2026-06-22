// ALRT-01: Rule engine. Evaluates graded symptom responses against the
// alert_rule table and returns a list of alerts to persist.
//
// Each rule's `condition` jsonb has this shape:
//   { min_grade?: 1|2|3, concurrent?: boolean, term_ids?: string[] }
//
// - min_grade: fire when composite_grade >= this value (default 2)
// - concurrent: fire when count of matching responses >= this value (default 1)

import { serviceClient } from "../supabase.js";
import type { Grade } from "../pro-ctcae/scorer.js";

interface GradedResponse {
  term_id: string;
  pro_ctcae_code: string;
  composite_grade: Grade;
  body_location?: string | null;
}

interface AlertRule {
  id: string;
  term_id: string | null;
  condition: {
    min_grade?: number;
    concurrent?: number;
    term_ids?: string[];
  };
  severity_level: string;
  escalation: Record<string, unknown>;
}

interface GeneratedAlert {
  rule_id: string;
  severity_level: string;
  patient_id: string;
}

export async function evaluateRules(
  patientId: string,
  reportId: string,
  responses: GradedResponse[],
): Promise<GeneratedAlert[]> {
  const supabase = serviceClient();

  const { data: rules } = await supabase
    .from("alert_rule")
    .select("*");

  if (!rules || rules.length === 0) return [];

  const alerts: GeneratedAlert[] = [];
  const seen = new Set<string>();

  for (const rule of rules as AlertRule[]) {
    const key = `${rule.severity_level}-${rule.id}`;
    if (seen.has(key)) continue;

    const minGrade = rule.condition.min_grade ?? 2;
    const concurrent = rule.condition.concurrent ?? 1;
    const termIds = rule.condition.term_ids ?? [];

    let matching: GradedResponse[];

    if (rule.term_id) {
      matching = responses.filter(
        (r) => r.term_id === rule.term_id && r.composite_grade >= minGrade,
      );
    } else if (termIds.length > 0) {
      matching = responses.filter(
        (r) => termIds.includes(r.term_id) && r.composite_grade >= minGrade,
      );
    } else {
      matching = responses.filter((r) => r.composite_grade >= minGrade);
    }

    if (matching.length >= concurrent) {
      alerts.push({
        rule_id: rule.id,
        severity_level: rule.severity_level,
        patient_id: patientId,
      });
      seen.add(key);
    }
  }

  return alerts;
}
