import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/result/result.dart';
import '../models/task.dart';
import '../supabase/supabase_provider.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref);
});

class TaskRepository {
  TaskRepository(this._ref);
  final Ref _ref;

  Future<Result<List<Task>, AppError>> fetchAll({String? status}) async {
    try {
      final apiBase = _ref.read(apiBaseUrlProvider);
      final session = _ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) {
        return const Err(
          AppError(
            kind: AppErrorKind.auth,
            code: 'no_session',
            message: 'Not signed in',
          ),
        );
      }
      final queryParams = status != null ? '?status=$status' : '';
      final uri = Uri.parse('$apiBase/api/tasks$queryParams');
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer ${session.accessToken}'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return Err(
          AppError(
            kind: AppErrorKind.network,
            code: 'fetch_failed',
            message: 'GET /api/tasks returned ${response.statusCode}',
          ),
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['tasks'] as List)
          .map((j) => Task.fromJson(j as Map<String, dynamic>))
          .toList();
      return Ok(list);
    } catch (e) {
      return Err(
        AppError(
          kind: AppErrorKind.network,
          code: 'fetch_failed',
          message: e.toString(),
        ),
      );
    }
  }

  Future<Result<Task, AppError>> create({
    required String title,
    String category = 'admin',
    DateTime? dueAt,
    String? assignedTo,
  }) async {
    try {
      final apiBase = _ref.read(apiBaseUrlProvider);
      final session = _ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) {
        return const Err(
          AppError(
            kind: AppErrorKind.auth,
            code: 'no_session',
            message: 'Not signed in',
          ),
        );
      }
      final uri = Uri.parse('$apiBase/api/tasks');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'title': title,
              'category': category,
              if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
              if (assignedTo != null) 'assigned_to': assignedTo,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 201) {
        return Err(
          AppError(
            kind: AppErrorKind.network,
            code: 'create_failed',
            message: 'POST /api/tasks returned ${response.statusCode}',
          ),
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final task = Task.fromJson(body['task'] as Map<String, dynamic>);
      return Ok(task);
    } catch (e) {
      return Err(
        AppError(
          kind: AppErrorKind.network,
          code: 'create_failed',
          message: e.toString(),
        ),
      );
    }
  }

  Future<Result<Task, AppError>> update({
    required String taskId,
    String? title,
    String? status,
    String? category,
    DateTime? dueAt,
    String? assignedTo,
  }) async {
    try {
      final apiBase = _ref.read(apiBaseUrlProvider);
      final session = _ref.read(supabaseClientProvider).auth.currentSession;
      if (session == null) {
        return const Err(
          AppError(
            kind: AppErrorKind.auth,
            code: 'no_session',
            message: 'Not signed in',
          ),
        );
      }
      final uri = Uri.parse('$apiBase/api/tasks/$taskId');
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (status != null) body['status'] = status;
      if (category != null) body['category'] = category;
      if (dueAt != null) body['due_at'] = dueAt.toUtc().toIso8601String();
      if (assignedTo != null) body['assigned_to'] = assignedTo;
      final response = await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return Err(
          AppError(
            kind: AppErrorKind.network,
            code: 'update_failed',
            message: 'PATCH /api/tasks/$taskId returned ${response.statusCode}',
          ),
        );
      }
      final resp = jsonDecode(response.body) as Map<String, dynamic>;
      final task = Task.fromJson(resp['task'] as Map<String, dynamic>);
      return Ok(task);
    } catch (e) {
      return Err(
        AppError(
          kind: AppErrorKind.network,
          code: 'update_failed',
          message: e.toString(),
        ),
      );
    }
  }
}
