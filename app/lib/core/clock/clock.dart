// Clock — substitutable time source for tests. Production binds to DateTime.now();
// tests bind to a fixed value. Use this anywhere you'd otherwise call DateTime.now().

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class Clock {
  DateTime now();
  DateTime nowUtc();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

class FixedClock implements Clock {
  const FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
  @override
  DateTime nowUtc() => _now.toUtc();
}

/// Default provider — returns the system clock. Tests override with
/// `clockProvider.overrideWithValue(FixedClock(...))`.
final clockProvider = Provider<Clock>((ref) => const SystemClock());