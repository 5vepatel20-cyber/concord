import 'package:concord/data/repositories/document_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimal [Ref] implementation using noSuchMethod.
/// Never actually called in decode tests because [MockDocumentRepository]
/// overrides [decode] and [decodeAnonymously].
class _MockRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _mockRef = _MockRef();

/// A [DocumentRepository] with overridable decode methods.
class MockDocumentRepository extends DocumentRepository {
  MockDocumentRepository() : super(_mockRef);

  DocumentDecodeResult? mockDecode;
  DocumentDecodeResult? mockDecodeAnonymously;
  Object Function()? mockDecodeThrows;
  Object Function()? mockDecodeAnonymouslyThrows;

  @override
  Future<DocumentDecodeResult> decode({
    required String ocrText,
    String? imageBase64,
    String imageMime = 'image/jpeg',
    String kind = 'other',
    String readingLevel = 'normal',
  }) async {
    if (mockDecodeThrows != null) {
      final err = mockDecodeThrows!();
      throw err is Exception ? err : Exception(err.toString());
    }
    if (mockDecode != null) return mockDecode!;
    throw StateError(
      'MockDocumentRepository.decode() called but mockDecode was not set',
    );
  }

  @override
  Future<DocumentDecodeResult> decodeAnonymously({
    String ocrText = '',
    String? imageBase64,
    String imageMime = 'image/jpeg',
    String readingLevel = 'normal',
  }) async {
    if (mockDecodeAnonymouslyThrows != null) {
      final err = mockDecodeAnonymouslyThrows!();
      throw err is Exception ? err : Exception(err.toString());
    }
    if (mockDecodeAnonymously != null) return mockDecodeAnonymously!;
    throw StateError(
      'MockDocumentRepository.decodeAnonymously() called but mockDecodeAnonymously was not set',
    );
  }
}
