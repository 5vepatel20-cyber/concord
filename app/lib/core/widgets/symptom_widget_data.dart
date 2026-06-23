import 'package:home_widget/home_widget.dart';

import '../storage/database.dart';

/// Stateless service that pushes data to the home-screen widget via
/// HomeWidget.  The native side (SymptomWidgetProvider on Android /
/// ConcordWidget on iOS) reads from the same SharedPreferences / UserDefaults
/// store and renders a summary card.
class SymptomWidgetService {
  SymptomWidgetService._();

  static const _statusKey = 'symptom_status';
  static const _gradeKey = 'symptom_grade';
  static const _gradeTextKey = 'symptom_grade_text';
  static const _pendingKey = 'pending_sync_count';

  /// Direct update — call with the exact status / grade you want the widget
  /// to display.
  static Future<void> updateWithStatus({
    required String status,
    int grade = -1,
    String gradeText = '',
    int pendingSyncCount = 0,
  }) async {
    await Future.wait([
      HomeWidget.saveWidgetData(_statusKey, status),
      HomeWidget.saveWidgetData(_gradeKey, grade),
      HomeWidget.saveWidgetData(_gradeTextKey, gradeText),
      HomeWidget.saveWidgetData(_pendingKey, pendingSyncCount),
    ]);
    await HomeWidget.updateWidget(androidName: 'SymptomWidgetProvider');
  }

  /// Refresh the widget from the local offline-queue state.  Shows a generic
  /// "All caught up" / "Syncing…" message based on pending count.
  static Future<void> updateFromDatabase(DatabaseLike db) async {
    final pendingReports = await db.pendingSymptomReports();
    final pendingMeds = await db.pendingMedicationDrafts();
    final pendingAdherence = await db.pendingAdherenceDrafts();
    final pendingCount =
        pendingReports.length + pendingMeds.length + pendingAdherence.length;

    await updateWithStatus(
      status: pendingCount > 0
          ? 'Symptoms saved \u2014 syncing\u2026'
          : 'All caught up \u2728',
      pendingSyncCount: pendingCount,
    );
  }
}
