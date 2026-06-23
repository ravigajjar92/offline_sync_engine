import 'package:meta/meta.dart';

/// Outcome of a single [SyncApiClient.execute] call.
///
/// The transport layer (Dio/http/Chopper/GraphQL/etc.) is responsible for
/// mapping its native response shape onto one of the [SyncResponse]
/// constructors below.
@immutable
class SyncResponse {
  final SyncResponseStatus status;
  final int? statusCode;

  /// Server-decoded body, if any.
  final Object? body;

  /// Useful when conflict resolution needs the server's "updatedAt" or full
  /// remote record. Populated for [SyncResponseStatus.conflict].
  final Map<String, dynamic>? serverState;

  /// Error message — populated for non-success outcomes.
  final String? error;

  const SyncResponse._({
    required this.status,
    this.statusCode,
    this.body,
    this.serverState,
    this.error,
  });

  const SyncResponse.success({int? statusCode, Object? body})
      : this._(
          status: SyncResponseStatus.success,
          statusCode: statusCode,
          body: body,
        );

  const SyncResponse.failure({
    required String error,
    int? statusCode,
    Object? body,
  }) : this._(
          status: SyncResponseStatus.failure,
          error: error,
          statusCode: statusCode,
          body: body,
        );

  const SyncResponse.conflict({
    Map<String, dynamic>? serverState,
    int? statusCode,
    Object? body,
    String? error,
  }) : this._(
          status: SyncResponseStatus.conflict,
          serverState: serverState,
          statusCode: statusCode,
          body: body,
          error: error,
        );

  bool get isSuccess => status == SyncResponseStatus.success;
  bool get isFailure => status == SyncResponseStatus.failure;
  bool get isConflict => status == SyncResponseStatus.conflict;

  @override
  String toString() =>
      'SyncResponse(${status.name}, code: $statusCode, error: $error)';
}

enum SyncResponseStatus { success, failure, conflict }