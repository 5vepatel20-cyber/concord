// Medication + MedicationAdherence domain models.
//
// Mirrors the public.medication + public.medication_event tables. JSON
// round-trip with the backend. Hand-rolled (no codegen) — same reasoning as
// the rest of the Concord client (avoid build_runner churn on this toolchain).

import 'dart:convert';

enum MedRoute { oral, iv, subQ, topical, inhaled, other }

extension MedRouteX on MedRoute {
  String get wireValue => switch (this) {
    MedRoute.oral => 'oral',
    MedRoute.iv => 'iv',
    MedRoute.subQ => 'sub_q',
    MedRoute.topical => 'topical',
    MedRoute.inhaled => 'inhaled',
    MedRoute.other => 'other',
  };
  static MedRoute fromWire(String s) => switch (s) {
    'oral' => MedRoute.oral,
    'iv' => MedRoute.iv,
    'sub_q' => MedRoute.subQ,
    'topical' => MedRoute.topical,
    'inhaled' => MedRoute.inhaled,
    _ => MedRoute.other,
  };
  String get displayName => switch (this) {
    MedRoute.oral => 'By mouth',
    MedRoute.iv => 'IV',
    MedRoute.subQ => 'Under the skin',
    MedRoute.topical => 'On the skin',
    MedRoute.inhaled => 'Inhaled',
    MedRoute.other => 'Other',
  };
}

enum MedFrequency { daily, weekly, asNeeded }

extension MedFrequencyX on MedFrequency {
  String get wireValue => switch (this) {
    MedFrequency.daily => 'daily',
    MedFrequency.weekly => 'weekly',
    MedFrequency.asNeeded => 'as_needed',
  };
  static MedFrequency fromWire(String s) => switch (s) {
    'daily' => MedFrequency.daily,
    'weekly' => MedFrequency.weekly,
    'as_needed' => MedFrequency.asNeeded,
    _ => MedFrequency.daily,
  };
}

enum AdherenceStatus { taken, skipped, missed, takenLate }

extension AdherenceStatusX on AdherenceStatus {
  String get wireValue => switch (this) {
    AdherenceStatus.taken => 'taken',
    AdherenceStatus.skipped => 'skipped',
    AdherenceStatus.missed => 'missed',
    AdherenceStatus.takenLate => 'taken_late',
  };
  static AdherenceStatus fromWire(String s) => switch (s) {
    'taken' => AdherenceStatus.taken,
    'skipped' => AdherenceStatus.skipped,
    'missed' => AdherenceStatus.missed,
    'taken_late' => AdherenceStatus.takenLate,
    _ => AdherenceStatus.missed,
  };
  String get displayName => switch (this) {
    AdherenceStatus.taken => 'Taken',
    AdherenceStatus.skipped => 'Skipped',
    AdherenceStatus.missed => 'Missed',
    AdherenceStatus.takenLate => 'Taken late',
  };
}

/// Free-form JSON the backend stores in medication.schedule. We model it
/// as a typed wrapper so the UI can render doses without raw map wrangling.
class MedSchedule {
  const MedSchedule({
    required this.frequency,
    this.times = const [],
    this.days = const [],
    this.notes,
  });
  final MedFrequency frequency;
  final List<String> times; // "HH:MM" in 24h, used when frequency != asNeeded
  final List<Weekday> days; // used when frequency == weekly
  final String? notes;

  Map<String, dynamic> toJson() => {
    'frequency': frequency.wireValue,
    if (times.isNotEmpty) 'times': times,
    if (days.isNotEmpty) 'days': days.map((d) => d.wireValue).toList(),
    if (notes != null) 'notes': notes,
  };

  static MedSchedule fromJson(Map<String, dynamic> j) => MedSchedule(
    frequency: MedFrequencyX.fromWire(j['frequency'] as String? ?? 'daily'),
    times: (j['times'] as List?)?.cast<String>() ?? const [],
    days: ((j['days'] as List?) ?? const [])
        .cast<String>()
        .map(WeekdayX.fromWire)
        .toList(),
    notes: j['notes'] as String?,
  );
}

enum Weekday { mon, tue, wed, thu, fri, sat, sun }

extension WeekdayX on Weekday {
  String get wireValue => switch (this) {
    Weekday.mon => 'mon',
    Weekday.tue => 'tue',
    Weekday.wed => 'wed',
    Weekday.thu => 'thu',
    Weekday.fri => 'fri',
    Weekday.sat => 'sat',
    Weekday.sun => 'sun',
  };
  static Weekday fromWire(String s) => switch (s) {
    'mon' => Weekday.mon,
    'tue' => Weekday.tue,
    'wed' => Weekday.wed,
    'thu' => Weekday.thu,
    'fri' => Weekday.fri,
    'sat' => Weekday.sat,
    'sun' => Weekday.sun,
    _ => Weekday.mon,
  };
  String get shortName => switch (this) {
    Weekday.mon => 'Mon',
    Weekday.tue => 'Tue',
    Weekday.wed => 'Wed',
    Weekday.thu => 'Thu',
    Weekday.fri => 'Fri',
    Weekday.sat => 'Sat',
    Weekday.sun => 'Sun',
  };
}

class Medication {
  const Medication({
    required this.id,
    required this.displayName,
    this.dose,
    this.unit,
    this.route = MedRoute.oral,
    this.schedule = const MedSchedule(frequency: MedFrequency.daily),
    this.rxnormCode,
    this.active = true,
    this.createdAt,
    this.sideEffectsWatch,
  });

  /// Server id when known; null when this row is still in the offline
  /// queue (the client UUID is held in the database local_id column).
  final String? id;
  final String displayName;
  final String? dose;
  final String? unit;
  final MedRoute route;
  final MedSchedule schedule;
  final String? rxnormCode;
  final bool active;
  final DateTime? createdAt;
  final String? sideEffectsWatch;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'display_name': displayName,
    if (dose != null) 'dose': dose,
    if (unit != null) 'unit': unit,
    'route': route.wireValue,
    'schedule': schedule.toJson(),
    if (rxnormCode != null) 'rxnorm_code': rxnormCode,
    'active': active,
    if (sideEffectsWatch != null) 'side_effects_watch': sideEffectsWatch,
  };

  static Medication fromJson(Map<String, dynamic> j) => Medication(
    id: j['id'] as String?,
    displayName: j['display_name'] as String,
    dose: j['dose'] as String?,
    unit: j['unit'] as String?,
    route: MedRouteX.fromWire(j['route'] as String? ?? 'oral'),
    schedule: MedSchedule.fromJson(
      (j['schedule'] as Map?)?.cast<String, dynamic>() ??
          const {'frequency': 'daily'},
    ),
    rxnormCode: j['rxnorm_code'] as String?,
    active: j['active'] as bool? ?? true,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
    sideEffectsWatch: j['side_effects_watch'] as String?,
  );

  /// Compact human description: "Tamoxifen 20 mg, By mouth, daily at 08:00".
  String get summary {
    final doseStr = [dose, unit].whereType<String>().join(' ').trim();
    final base = doseStr.isEmpty ? displayName : '$displayName $doseStr';
    final routeStr = route == MedRoute.oral ? '' : ' (${route.displayName})';
    final schedStr = schedule.frequency == MedFrequency.asNeeded
        ? 'as needed'
        : schedule.times.isEmpty
        ? schedule.frequency.wireValue
        : '${schedule.frequency.wireValue} at '
              '${schedule.times.join(", ")}';
    return '$base$routeStr — $schedStr';
  }
}

class AdherenceEvent {
  const AdherenceEvent({
    required this.medicationId,
    required this.scheduledFor,
    required this.status,
    this.loggedAt,
  });

  /// Server id of the parent medication. (For offline drafts we resolve
  /// localId → serverId before POST; see MedicationRepository.)
  final String medicationId;
  final DateTime scheduledFor;
  final AdherenceStatus status;
  final DateTime? loggedAt;

  Map<String, dynamic> toJson() => {
    // medication_id is the URL path parameter, NOT in the body.
    // We don't include it here so a round-trip via toJson -> fromJson
    // preserves the same shape the server expects.
    'status': status.wireValue,
    'scheduled_for': scheduledFor.toUtc().toIso8601String(),
    if (loggedAt != null) 'logged_at': loggedAt!.toUtc().toIso8601String(),
  };

  /// Parse a server response. The server returns the full event row,
  /// including medication_id, so we accept it here but it's not required
  /// for our request-body builder.
  static AdherenceEvent fromJson(Map<String, dynamic> j) => AdherenceEvent(
    medicationId: j['medication_id'] as String? ?? '',
    scheduledFor: DateTime.parse(j['scheduled_for'] as String).toUtc(),
    status: AdherenceStatusX.fromWire(j['status'] as String? ?? 'missed'),
    loggedAt: j['logged_at'] != null
        ? DateTime.parse(j['logged_at'] as String).toUtc()
        : null,
  );
}

/// Helper: encode a Medication draft to a JSON body that
/// `POST /api/medications` accepts.
String encodeMedicationCreate(Medication m) => jsonEncode(m.toJson());

/// Helper: encode an AdherenceEvent to a JSON body that
/// `POST /api/medications/:id/adherence` accepts.
String encodeAdherence(AdherenceEvent e) => jsonEncode(e.toJson());
