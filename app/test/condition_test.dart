// Tests for the clinical vocabulary models — JSON round-trip with
// Supabase snake_case field names.

import 'package:concord/data/models/condition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VocabCondition.fromJson', () {
    test('reads full row with optional fields', () {
      final json = {
        'id': 'c1',
        'display_name': 'Breast cancer',
        'icd10_code': 'C50',
        'category': 'oncology',
        'pro_ctcae_panel_id': 'p1',
      };
      final c = VocabCondition.fromJson(json);
      expect(c.id, 'c1');
      expect(c.displayName, 'Breast cancer');
      expect(c.icd10Code, 'C50');
      expect(c.category, 'oncology');
      expect(c.proCtcaePanelId, 'p1');
    });

    test('falls back gracefully on missing optional fields', () {
      final c = VocabCondition.fromJson({'id': 'c2'});
      expect(c.displayName, '(unnamed)');
      expect(c.category, 'other');
      expect(c.icd10Code, isNull);
      expect(c.proCtcaePanelId, isNull);
    });
  });

  group('VocabSymptomTerm.fromJson', () {
    test('reads full row with attributes', () {
      final json = {
        'id': 't1',
        'display_name': 'Nausea',
        'body_system': 'gi',
        'pro_ctcae_code': 'GI01',
        'attributes': ['frequency', 'severity'],
        'plain_language': 'feeling sick to your stomach',
      };
      final t = VocabSymptomTerm.fromJson(json);
      expect(t.id, 't1');
      expect(t.displayName, 'Nausea');
      expect(t.bodySystem, 'gi');
      expect(t.proCtcaeCode, 'GI01');
      expect(t.attributes, ['frequency', 'severity']);
      expect(t.plainLanguage, 'feeling sick to your stomach');
    });

    test('handles missing attributes', () {
      final t = VocabSymptomTerm.fromJson({
        'id': 't2',
        'display_name': 'Fatigue',
      });
      expect(t.attributes, isEmpty);
      expect(t.bodySystem, 'general');
      expect(t.plainLanguage, isNull);
    });
  });

  group('VocabSymptomPanel.fromJson', () {
    test('reads term_ids list', () {
      final p = VocabSymptomPanel.fromJson({
        'id': 'p1',
        'name': 'Core chemo symptoms',
        'term_ids': ['t1', 't2', 't3'],
      });
      expect(p.id, 'p1');
      expect(p.name, 'Core chemo symptoms');
      expect(p.termIds, ['t1', 't2', 't3']);
    });

    test('handles missing term_ids', () {
      final p = VocabSymptomPanel.fromJson({'id': 'p2'});
      expect(p.termIds, isEmpty);
      expect(p.name, 'Symptoms');
    });
  });
}
