class Task {
  const Task({
    required this.id,
    required this.patientId,
    required this.title,
    this.dueAt,
    this.category = 'admin',
    this.status = 'open',
    this.source = 'manual',
    this.assignedTo,
    this.createdAt,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String,
    patientId: j['patient_id'] as String,
    title: j['title'] as String,
    dueAt: j['due_at'] != null ? DateTime.parse(j['due_at'] as String) : null,
    category: j['category'] as String? ?? 'admin',
    status: j['status'] as String? ?? 'open',
    source: j['source'] as String? ?? 'manual',
    assignedTo: j['assigned_to'] as String?,
    createdAt: j['created_at'] != null
        ? DateTime.parse(j['created_at'] as String)
        : null,
  );

  final String id;
  final String patientId;
  final String title;
  final DateTime? dueAt;
  final String category;
  final String status;
  final String source;
  final String? assignedTo;
  final DateTime? createdAt;

  bool get isDone => status == 'done';

  Map<String, dynamic> toJson() => {
    'id': id,
    'patient_id': patientId,
    'title': title,
    'due_at': dueAt?.toUtc().toIso8601String(),
    'category': category,
    'status': status,
    'source': source,
    'assigned_to': assignedTo,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };
}
