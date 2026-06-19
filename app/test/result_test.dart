// Tests for the Result sealed class + AppError envelope parser.
//
// The backend returns a uniform `{error:{code,message}}` envelope on failure;
// AppError.fromBackend must lift that into a typed AppError. Result<T,E> is
// the wrapper every repository method returns.

import 'package:concord/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result<T, E>', () {
    test('Ok carries the value', () {
      const r = Ok<int, AppError>(42);
      expect(r.isOk, isTrue);
      expect(r.isErr, isFalse);
      expect(r.valueOrNull, 42);
      expect(r.errorOrNull, isNull);
    });

    test('Err carries the error', () {
      const r = Err<int, AppError>(
        AppError(kind: AppErrorKind.network, code: 'x', message: 'm'),
      );
      expect(r.isOk, isFalse);
      expect(r.isErr, isTrue);
      expect(r.valueOrNull, isNull);
      expect(r.errorOrNull, isNotNull);
    });

    test('map transforms Ok value', () {
      const r = Ok<int, AppError>(2);
      final mapped = r.map((v) => v * 10);
      expect(mapped, isA<Ok<int, AppError>>());
      expect(mapped.valueOrNull, 20);
    });

    test('map propagates Err unchanged', () {
      const r = Err<int, AppError>(
        AppError(kind: AppErrorKind.server, code: 'x', message: 'm'),
      );
      final mapped = r.map((v) => v * 10);
      expect(mapped, isA<Err<int, AppError>>());
      expect(mapped.errorOrNull?.code, 'x');
    });
  });

  group('AppError.fromBackend', () {
    test('parses standard error envelope', () {
      final body = {
        'error': {'code': 'bad_request', 'message': 'invalid term id'},
      };
      final err = AppError.fromBackend(body, statusCode: 400);
      expect(err.kind, AppErrorKind.badRequest);
      expect(err.code, 'bad_request');
      expect(err.message, 'invalid term id');
      expect(err.statusCode, 400);
    });

    test('maps token error codes to unauthorized', () {
      for (final code in ['missing_bearer', 'empty_token', 'invalid_token']) {
        final err = AppError.fromBackend({
          'error': {'code': code, 'message': 'no'},
        });
        expect(err.kind, AppErrorKind.unauthorized, reason: code);
      }
    });

    test('maps database error codes to database', () {
      for (final code in
          ['term_lookup_failed', 'report_insert_failed', 'response_insert_failed']) {
        final err = AppError.fromBackend({
          'error': {'code': code, 'message': 'no'},
        });
        expect(err.kind, AppErrorKind.database, reason: code);
      }
    });

    test('falls back to server kind for unknown codes', () {
      final err = AppError.fromBackend({
        'error': {'code': 'weird_thing', 'message': 'no'},
      });
      expect(err.kind, AppErrorKind.server);
    });

    test('handles missing error envelope', () {
      final err = AppError.fromBackend({'data': 'weird'});
      expect(err.kind, AppErrorKind.unknown);
      expect(err.code, 'unknown');
    });
  });

  group('AppError factories', () {
    test('AppError.network wraps any cause', () {
      final err = AppError.network(Exception('boom'));
      expect(err.kind, AppErrorKind.network);
      expect(err.code, 'network');
      expect(err.cause, isA<Exception>());
    });

    test('AppError.unauthorized default message', () {
      final err = AppError.unauthorized();
      expect(err.kind, AppErrorKind.unauthorized);
      expect(err.message.toLowerCase(), contains('sign in'));
    });
  });
}
