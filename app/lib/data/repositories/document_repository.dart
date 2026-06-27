import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../supabase/supabase_provider.dart';

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(ref);
});

class DocumentDecodeResult {
  final String documentId;
  final String summary;
  final Map<String, dynamic> extraction;

  DocumentDecodeResult({
    required this.documentId,
    required this.summary,
    required this.extraction,
  });

  List<Map<String, dynamic>> get extractedLabs =>
      (extraction['extracted_labs'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>() ??
      [];

  List<String> get medications =>
      (extraction['medications'] as List<dynamic>?)?.cast<String>() ?? [];

  List<String> get diagnoses =>
      (extraction['diagnoses'] as List<dynamic>?)?.cast<String>() ?? [];

  List<String> get suggestedQuestions =>
      (extraction['suggested_questions'] as List<dynamic>?)?.cast<String>() ??
      [];

  List<String> get criticalFlags =>
      (extraction['critical_flags'] as List<dynamic>?)?.cast<String>() ?? [];

  String get docType => extraction['doc_type'] as String? ?? 'Unknown';
}

class DocumentRepository {
  DocumentRepository(this._ref);

  final Ref _ref;

  Future<DocumentDecodeResult> decode({
    required String ocrText,
    String kind = 'other',
    String readingLevel = 'normal',
  }) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      throw StateError('Cannot decode documents without an auth session');
    }

    final response = await http
        .post(
          Uri.parse('$apiBase/api/documents/decode'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode({
            'ocr_text': ocrText,
            'kind': kind,
            'reading_level': readingLevel,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Document decode failed: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return DocumentDecodeResult(
      documentId: body['document_id'] as String,
      summary: body['summary'] as String,
      extraction: body['extraction'] as Map<String, dynamic>,
    );
  }

  /// No-login decode for the viral wedge. Calls the public endpoint which does
  /// not require auth and does not persist the document.
  Future<DocumentDecodeResult> decodeAnonymously({
    required String ocrText,
    String readingLevel = 'normal',
  }) async {
    final apiBase = _ref.read(apiBaseUrlProvider);

    final response = await http
        .post(
          Uri.parse('$apiBase/api/documents/decode-public'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'ocr_text': ocrText,
            'reading_level': readingLevel,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Document decode failed: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final extraction = body['extraction'] as Map<String, dynamic>;
    return DocumentDecodeResult(
      documentId: 'anon',
      summary: body['summary'] as String,
      extraction: extraction,
    );
  }
}
