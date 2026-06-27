// Riverpod provider for the local sqlite database.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Async provider — opens the sqlite file lazily on first read.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  return AppDatabase.instance();
});
