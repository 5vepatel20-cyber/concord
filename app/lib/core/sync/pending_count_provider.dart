import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/database_provider.dart';

final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final db = await ref.read(appDatabaseProvider.future);
  final symptom = await db.pendingSymptomReports();
  final meds = await db.pendingMedicationDrafts();
  final adherence = await db.pendingAdherenceDrafts();
  return symptom.length + meds.length + adherence.length;
});
