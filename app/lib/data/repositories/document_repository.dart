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
    String? imageBase64,
    String imageMime = 'image/jpeg',
    String kind = 'other',
    String readingLevel = 'normal',
  }) async {
    final apiBase = _ref.read(apiBaseUrlProvider);
    final session = _ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      throw StateError('Cannot decode documents without an auth session');
    }

    final body = <String, dynamic>{
      'ocr_text': ocrText,
      'kind': kind,
      'reading_level': readingLevel,
    };
    if (imageBase64 != null) {
      body['image_base64'] = imageBase64;
      body['image_mime'] = imageMime;
    }

    final response = await http
        .post(
          Uri.parse('$apiBase/api/documents/decode'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Document decode failed: ${response.statusCode} ${response.body}',
      );
    }

    final res = jsonDecode(response.body) as Map<String, dynamic>;
    return DocumentDecodeResult(
      documentId: res['document_id'] as String,
      summary: res['summary'] as String,
      extraction: res['extraction'] as Map<String, dynamic>,
    );
  }

  /// No-login decode for the viral wedge. Calls the public endpoint which does
  /// not require auth and does not persist the document.
  ///
  /// If [imageBase64] is provided (and [ocrText] is empty), the server runs
  /// OCR on the image before decoding. If both are provided, [ocrText] is
  /// used directly.
  Future<DocumentDecodeResult> decodeAnonymously({
    String ocrText = '',
    String? imageBase64,
    String imageMime = 'image/jpeg',
    String readingLevel = 'normal',
  }) async {
    final apiBase = _ref.read(apiBaseUrlProvider);

    final body = <String, dynamic>{'reading_level': readingLevel};
    if (ocrText.isNotEmpty) {
      body['ocr_text'] = ocrText;
    }
    if (imageBase64 != null) {
      body['image_base64'] = imageBase64;
      body['image_mime'] = imageMime;
    }

    final response = await http
        .post(
          Uri.parse('$apiBase/api/documents/decode-public'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Document decode failed: ${response.statusCode} ${response.body}',
      );
    }

    final res = jsonDecode(response.body) as Map<String, dynamic>;
    final extraction = res['extraction'] as Map<String, dynamic>;
    return DocumentDecodeResult(
      documentId: 'anon',
      summary: res['summary'] as String,
      extraction: extraction,
    );
  }
}
