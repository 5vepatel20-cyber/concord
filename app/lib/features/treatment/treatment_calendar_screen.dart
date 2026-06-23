import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';

/// Treatment calendar (ONB-05). Month grid view of treatment events
/// (infusions, appointments, labs, scans, etc.).
class TreatmentCalendarScreen extends ConsumerStatefulWidget {
  const TreatmentCalendarScreen({super.key});

  @override
  ConsumerState<TreatmentCalendarScreen> createState() =>
      _TreatmentCalendarScreenState();
}

class _TreatmentCalendarScreenState
    extends ConsumerState<TreatmentCalendarScreen> {
  late DateTime _currentMonth;
  DateTime? _selectedDay;
  List<TreatmentEvent> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _selectedDay = now;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final uri = Uri.parse(
        '$apiBase/api/treatment/events'
        '?year=${_currentMonth.year}&month=${_currentMonth.month}',
      );
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer ${session.accessToken}'})
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final raw = (body['events'] as List<dynamic>?) ?? [];
        setState(() {
          _events = raw
              .map((e) => TreatmentEvent.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } else {
        setState(() => _error = 'Failed to load (${res.statusCode})');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TreatmentEvent> get _eventsForSelectedDay {
    if (_selectedDay == null) return [];
    final dayStr = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    return _events.where((e) => e.eventDate == dayStr).toList();
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
      _selectedDay = null;
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
      _selectedDay = null;
    });
    _load();
  }

  Set<DateTime> get _eventDays =>
      _events.map((e) => DateTime.parse(e.eventDate)).toSet();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Treatment calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add event',
            onPressed: () => _showAddDialog(),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: SeverityColors.severe,
                      ),
                      const SizedBox(height: Space.s3),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: SeverityColors.severe,
                        ),
                      ),
                      const SizedBox(height: Space.s3),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  _MonthHeader(
                    current: _currentMonth,
                    onPrev: _previousMonth,
                    onNext: _nextMonth,
                  ),
                  _WeekdayHeader(),
                  _CalendarGrid(
                    currentMonth: _currentMonth,
                    selectedDay: _selectedDay,
                    eventDays: _eventDays,
                    onDaySelected: (d) => setState(() => _selectedDay = d),
                  ),
                  if (_selectedDay != null) ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        Space.s5,
                        Space.s3,
                        Space.s5,
                        Space.s1,
                      ),
                      child: Row(
                        children: [
                          Text(
                            DateFormat.MMMMd().format(_selectedDay!),
                            style: t.textTheme.titleSmall,
                          ),
                          const SizedBox(width: Space.s2),
                          Text(
                            '${_eventsForSelectedDay.length} event${_eventsForSelectedDay.length == 1 ? '' : 's'}',
                            style: t.textTheme.labelSmall?.copyWith(
                              color: Neutrals.slate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _eventsForSelectedDay.isEmpty
                          ? Center(
                              child: Text(
                                'No events on this day.',
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: Neutrals.slate,
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(
                                Space.s5,
                                0,
                                Space.s5,
                                Space.s10,
                              ),
                              children: _eventsForSelectedDay
                                  .map(
                                    (e) => _EventCard(
                                      event: e,
                                      onStatusChange: _updateStatus,
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _updateStatus(TreatmentEvent event, String newStatus) async {
    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      await http.patch(
        Uri.parse('$apiBase/api/treatment/events/${event.id}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: jsonEncode({'status': newStatus}),
      );
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<TreatmentEvent>(
      context: context,
      builder: (ctx) => const _AddEventDialog(),
    );
    if (result != null && mounted) _load();
  }
}

// ── Month header ──────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.current,
    required this.onPrev,
    required this.onNext,
  });
  final DateTime current;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s5,
        vertical: Space.s3,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Text(
            DateFormat.yMMMM().format(current),
            style: t.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

// ── Weekday header ────────────────────────────────────────────────────────────

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      child: Row(
        children: days.map((d) {
          final isWeekend = d == 'Sat' || d == 'Sun';
          return Expanded(
            child: Center(
              child: Text(
                d,
                style: t.textTheme.labelSmall?.copyWith(
                  color: isWeekend ? Neutrals.hint : Neutrals.slate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Calendar grid ─────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.currentMonth,
    required this.selectedDay,
    required this.eventDays,
    required this.onDaySelected,
  });
  final DateTime currentMonth;
  final DateTime? selectedDay;
  final Set<DateTime> eventDays;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = DateTime.now();
    final firstDay = DateTime(currentMonth.year, currentMonth.month, 1);
    final lastDay = DateTime(currentMonth.year, currentMonth.month + 1, 0);
    // Monday = 1, Sunday = 7
    final startWeekday = firstDay.weekday;
    final daysInMonth = lastDay.day;

    final cells = <Widget>[];

    // Empty cells before the 1st.
    for (var i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(currentMonth.year, currentMonth.month, day);
      final isToday =
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isSelected =
          selectedDay != null &&
          date.year == selectedDay!.year &&
          date.month == selectedDay!.month &&
          date.day == selectedDay!.day;
      final hasEvents = eventDays.any(
        (d) =>
            d.year == date.year && d.month == date.month && d.day == date.day,
      );

      cells.add(
        GestureDetector(
          onTap: () => onDaySelected(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? BrandColors.concordBlue
                  : isToday
                  ? BrandColors.concordBlueTint
                  : null,
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day.toString(),
                  style: t.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected || isToday ? FontWeight.w600 : null,
                    color: isSelected
                        ? Colors.white
                        : isToday
                        ? BrandColors.concordBlue
                        : null,
                  ),
                ),
                if (hasEvents)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: SeverityColors.moderate,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        childAspectRatio: 1,
        children: cells,
      ),
    );
  }
}

// ── Event card ────────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onStatusChange});
  final TreatmentEvent event;
  final Function(TreatmentEvent event, String newStatus) onStatusChange;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final icon = _iconForType(event.eventType);
    final color = _colorForType(event.eventType);

    return Card(
      margin: const EdgeInsets.only(bottom: Space.s2),
      child: Padding(
        padding: const EdgeInsets.all(Space.s3),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Space.s2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Space.s1),
                  Row(
                    children: [
                      _Tag(label: _typeLabel(event.eventType), color: color),
                      const SizedBox(width: Space.s1),
                      if (event.eventTime != null)
                        Text(
                          event.eventTime!,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: Neutrals.slate,
                          ),
                        ),
                      if (event.location != null) ...[
                        const SizedBox(width: Space.s2),
                        Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Neutrals.hint,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            event.location!,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.labelSmall?.copyWith(
                              color: Neutrals.hint,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (event.status != 'scheduled')
                    Container(
                      margin: const EdgeInsets.only(top: Space.s1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s2,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(
                          event.status,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Radii.xs),
                      ),
                      child: Text(
                        _statusLabel(event.status),
                        style: t.textTheme.labelSmall?.copyWith(
                          color: _statusColor(event.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (s) => onStatusChange(event, s),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'completed',
                  child: Text('Mark completed'),
                ),
                const PopupMenuItem(
                  value: 'cancelled',
                  child: Text('Cancel event'),
                ),
                const PopupMenuItem(
                  value: 'rescheduled',
                  child: Text('Rescheduled'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'infusion':
        return Icons.iv_bag;
      case 'appointment':
        return Icons.calendar_today;
      case 'lab':
        return Icons.science_outlined;
      case 'scan':
        return Icons.radiology;
      case 'surgery':
        return Icons.local_hospital;
      default:
        return Icons.event_note;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'infusion':
        return const Color(0xFF7B61FF);
      case 'appointment':
        return const Color(0xFF4A90D9);
      case 'lab':
        return const Color(0xFF2ECC71);
      case 'scan':
        return const Color(0xFFE67E22);
      case 'surgery':
        return const Color(0xFFE74C3C);
      default:
        return Neutrals.slate;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'infusion':
        return 'Infusion';
      case 'appointment':
        return 'Appt';
      case 'lab':
        return 'Lab';
      case 'scan':
        return 'Scan';
      case 'surgery':
        return 'Surgery';
      default:
        return 'Other';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return SeverityColors.none;
      case 'cancelled':
        return SeverityColors.severe;
      case 'rescheduled':
        return const Color(0xFFE67E22);
      default:
        return Neutrals.slate;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'rescheduled':
        return 'Rescheduled';
      default:
        return status;
    }
  }
}

// ── Add event dialog ──────────────────────────────────────────────────────────

class _AddEventDialog extends ConsumerStatefulWidget {
  const _AddEventDialog();

  @override
  ConsumerState<_AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends ConsumerState<_AddEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _eventType = 'appointment';
  DateTime _eventDate = DateTime.now();
  TimeOfDay? _eventTime;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final apiBase = ref.read(apiBaseUrlProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) return;

      final body = <String, dynamic>{
        'event_type': _eventType,
        'title': _titleCtrl.text.trim(),
        'event_date': DateFormat('yyyy-MM-dd').format(_eventDate),
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        if (_locCtrl.text.trim().isNotEmpty) 'location': _locCtrl.text.trim(),
        if (_eventTime != null)
          'event_time':
              '${_eventTime!.hour.toString().padLeft(2, '0')}:${_eventTime!.minute.toString().padLeft(2, '0')}',
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      };

      final res = await http
          .post(
            Uri.parse('$apiBase/api/treatment/events'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 201) {
        Navigator.of(context).pop(true);
      } else {
        final msg =
            (jsonDecode(res.body) as Map<String, dynamic>)['error']
                as Map<String, dynamic>? ??
            {};
        setState(
          () => _error = (msg['message'] as String?) ?? 'Failed to create',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('Add treatment event'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              DropdownButtonFormField<String>(
                value: _eventType,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'infusion', child: Text('Infusion')),
                  DropdownMenuItem(
                    value: 'appointment',
                    child: Text('Appointment'),
                  ),
                  DropdownMenuItem(value: 'lab', child: Text('Lab draw')),
                  DropdownMenuItem(
                    value: 'scan',
                    child: Text('Scan / Imaging'),
                  ),
                  DropdownMenuItem(value: 'surgery', child: Text('Surgery')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _eventType = v);
                },
              ),
              const SizedBox(height: Space.s3),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Cycle 3, Day 1',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Space.s3),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _eventDate,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 30),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null && mounted) {
                    setState(() => _eventDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text(DateFormat.yMMMd().format(_eventDate)),
                ),
              ),
              const SizedBox(height: Space.s3),
              InkWell(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime:
                        _eventTime ?? const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (picked != null && mounted) {
                    setState(() => _eventTime = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Time (optional)',
                  ),
                  child: Text(_eventTime?.format(context) ?? 'Not set'),
                ),
              ),
              const SizedBox(height: Space.s3),
              TextFormField(
                controller: _locCtrl,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  hintText: 'e.g. 3rd floor, Infusion center',
                ),
              ),
              const SizedBox(height: Space.s3),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.s2),
                Text(
                  _error!,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: SeverityColors.severe,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add event'),
        ),
      ],
    );
  }
}

// ── Tag chip ──────────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class TreatmentEvent {
  final String id;
  final String eventType;
  final String title;
  final String? description;
  final String? location;
  final String eventDate;
  final String? eventTime;
  final String? endDate;
  final String status;
  final String? notes;

  TreatmentEvent({
    required this.id,
    required this.eventType,
    required this.title,
    this.description,
    this.location,
    required this.eventDate,
    this.eventTime,
    this.endDate,
    required this.status,
    this.notes,
  });

  factory TreatmentEvent.fromJson(Map<String, dynamic> j) => TreatmentEvent(
    id: j['id'] as String? ?? '',
    eventType: j['event_type'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    location: j['location'] as String?,
    eventDate: j['event_date'] as String? ?? '',
    eventTime: j['event_time'] as String?,
    endDate: j['end_date'] as String?,
    status: j['status'] as String? ?? 'scheduled',
    notes: j['notes'] as String?,
  );
}
