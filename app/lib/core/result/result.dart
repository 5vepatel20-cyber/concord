// Result<T, E> — sealed-class wrapper for "could fail" operations.
// Backend returns a uniform `{error:{code,message}}` envelope; we lift it into
// Result so repository methods are safe to compose and force the UI to handle errors.

sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  /// Returns the ok value or null.
  T? get valueOrNull => switch (this) {
        Ok<T, E>(:final value) => value,
        Err<T, E>() => null,
      };

  /// Returns the error or null.
  E? get errorOrNull => switch (this) {
        Ok<T, E>() => null,
        Err<T, E>(:final error) => error,
      };

  /// Map the success value.
  Result<R, E> map<R>(R Function(T) f) => switch (this) {
        Ok<T, E>(:final value) => Ok<R, E>(f(value)),
        Err<T, E>(:final error) => Err<R, E>(error),
      };
}

class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);
  final T value;
}

class Err<T, E> extends Result<T, E> {
  const Err(this.error);
  final E error;
}

/// App-level error categories. Maps to the backend's `error.code` strings.
enum AppErrorKind {
  /// Network failure (offline, DNS, timeout, etc.). Safe to retry.
  network,

  /// 401 unauthorized — session expired or invalid. Force sign-out.
  unauthorized,

  /// 400 bad_request — validation failure.
  badRequest,

  /// 5xx or unknown server failure.
  server,

  /// Supabase / DB level failure.
  database,

  /// Anything else. Should never happen; surface for debugging.
  unknown,
}

class AppError {
  const AppError({
    required this.kind,
    required this.code,
    required this.message,
    this.cause,
    this.statusCode,
  });

  /// Build from the backend's `{"error":{"code","message"}}` envelope.
  factory AppError.fromBackend(Map<String, dynamic> body, {int? statusCode}) {
    final envelope = body['error'];
    if (envelope is Map) {
      return AppError(
        kind: _kindFromCode(envelope['code']?.toString()),
        code: envelope['code']?.toString() ?? 'unknown',
        message: envelope['message']?.toString() ?? 'Server error',
        statusCode: statusCode,
      );
    }
    return AppError(
      kind: AppErrorKind.unknown,
      code: 'unknown',
      message: body.toString(),
      statusCode: statusCode,
    );
  }

  factory AppError.network(Object cause) => AppError(
        kind: AppErrorKind.network,
        code: 'network',
        message: 'Couldn\'t reach Concord. Check your connection.',
        cause: cause,
      );

  factory AppError.unauthorized({String? detail}) => AppError(
        kind: AppErrorKind.unauthorized,
        code: 'unauthorized',
        message: detail ?? 'Your session ended. Sign in again.',
      );

  final AppErrorKind kind;
  final String code;
  final String message;
  final Object? cause;
  final int? statusCode;

  static AppErrorKind _kindFromCode(String? code) {
    switch (code) {
      case 'missing_bearer':
      case 'empty_token':
      case 'invalid_token':
        return AppErrorKind.unauthorized;
      case 'bad_request':
      case 'unknown_term':
        return AppErrorKind.badRequest;
      case 'term_lookup_failed':
      case 'report_insert_failed':
      case 'response_insert_failed':
        return AppErrorKind.database;
      default:
        return AppErrorKind.server;
    }
  }

  @override
  String toString() => 'AppError($kind:$code)';
}
