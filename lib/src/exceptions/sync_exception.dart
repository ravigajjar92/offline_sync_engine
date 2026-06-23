/// Base type for every exception thrown by the offline sync engine.
///
/// Catch [SyncException] to handle any package error uniformly; catch a
/// specific subclass for fine-grained handling.
sealed class SyncException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? causeStackTrace;

  const SyncException(this.message, {this.cause, this.causeStackTrace});

  String get _kind;

  @override
  String toString() {
    final c = cause == null ? '' : ' (cause: $cause)';
    return '$_kind: $message$c';
  }
}

/// Persistence layer failed (read/write/init).
final class StorageException extends SyncException {
  const StorageException(super.message, {super.cause, super.causeStackTrace});
  @override
  String get _kind => 'StorageException';
}

/// Transport layer failed before/while/after sending a request.
final class NetworkException extends SyncException {
  /// HTTP status code, if the failure occurred *after* receiving a response.
  final int? statusCode;

  const NetworkException(
    super.message, {
    this.statusCode,
    super.cause,
    super.causeStackTrace,
  });

  @override
  String get _kind => 'NetworkException';
}

/// Server reported a conflict that the configured strategy could not resolve.
final class ConflictException extends SyncException {
  const ConflictException(super.message, {super.cause, super.causeStackTrace});
  @override
  String get _kind => 'ConflictException';
}

/// Engine was used incorrectly (e.g. enqueue before initialize).
final class SyncStateException extends SyncException {
  const SyncStateException(super.message, {super.cause, super.causeStackTrace});
  @override
  String get _kind => 'SyncStateException';
}