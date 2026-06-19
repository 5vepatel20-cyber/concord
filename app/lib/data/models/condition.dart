// Clinical vocabulary models — `condition`, `symptom_term`, `symptom_panel`.
// Mirror the rows the backend seeded from PRO-CTCAE / SNOMED CT maps.
//
// Hand-rolled (no freezed) for now to avoid build_runner ceremony. The actual
// Supabase column names are used directly (snake_case) for round-trip safety.
//
// Schema (from list_tables):
//   condition       : id, display_name, icd10_code, category, pro_ctcae_panel_id
//   symptom_term    : id, pro_ctcae_code, display_name, body_system, attributes
//   symptom_panel   : id, name, term_ids (uuid[])

class VocabCondition {
  const VocabCondition({
    required this.id,
    required this.displayName,
    required this.category,
    this.icd10Code,
    this.proCtcaePanelId,
  });

  factory VocabCondition.fromJson(Map<String, dynamic> j) => VocabCondition(
        id: j['id'] as String,
        displayName: j['display_name'] as String? ?? '(unnamed)',
        category: j['category'] as String? ?? 'other',
        icd10Code: j['icd10_code'] as String?,
        proCtcaePanelId: j['pro_ctcae_panel_id'] as String?,
      );

  final String id;
  final String displayName;
  final String category;
  final String? icd10Code;
  final String? proCtcaePanelId;
}

class VocabSymptomTerm {
  const VocabSymptomTerm({
    required this.id,
    required this.displayName,
    required this.bodySystem,
    required this.proCtcaeCode,
    this.attributes = const [],
    this.plainLanguage,
  });

  factory VocabSymptomTerm.fromJson(Map<String, dynamic> j) => VocabSymptomTerm(
        id: j['id'] as String,
        displayName: j['display_name'] as String? ?? '(unnamed)',
        bodySystem: j['body_system'] as String? ?? 'general',
        proCtcaeCode: j['pro_ctcae_code'] as String? ?? '',
        attributes: (j['attributes'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            const [],
        plainLanguage: j['plain_language'] as String?,
      );

  final String id;
  final String displayName;
  final String bodySystem;
  final String proCtcaeCode;
  final List<String> attributes;
  final String? plainLanguage;
}

class VocabSymptomPanel {
  const VocabSymptomPanel({
    required this.id,
    required this.name,
    required this.termIds,
  });

  factory VocabSymptomPanel.fromJson(Map<String, dynamic> j) => VocabSymptomPanel(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Symptoms',
        termIds: ((j['term_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      );

  final String id;
  final String name;
  final List<String> termIds;
}

/// Convenience: a condition paired with its panel and the panel's terms,
/// ready for the quick-log screen.
class ConditionWithTerms {
  const ConditionWithTerms({
    required this.condition,
    required this.terms,
  });

  final VocabCondition condition;
  final List<VocabSymptomTerm> terms;
}