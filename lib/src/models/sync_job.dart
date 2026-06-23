import 'package:meta/meta.dart';

import 'http_method.dart';
import 'sync_job_status.dart';

/// A single unit of work queued for synchronization.
///
/// [SyncJob] is value-type / immutable. Mutations are produced via [copyWith].
/// Equality is by [id]; two jobs with the same id are considered the same job
/// regardless of which field revision you hold.
@immutable
class SyncJob {
  final String id;
  final String endpoint;
  final HttpMethod method;
  final Map<String, dynamic> payload;
  final Map<String, String>? headers;
  final int retryCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncJobStatus status;
  final String? lastError;

  const SyncJob({
    required this.id,
    required this.endpoint,
    required this.method,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.headers,
    this.retryCount = 0,
    this.status = SyncJobStatus.pending,
    this.lastError,
  });

  SyncJob copyWith({
    String? endpoint,
    HttpMethod? method,
    Map<String, dynamic>? payload,
    Map<String, String>? headers,
    int? retryCount,
    DateTime? updatedAt,
    SyncJobStatus? status,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncJob(
      id: id,
      endpoint: endpoint ?? this.endpoint,
      method: method ?? this.method,
      payload: payload ?? this.payload,
      headers: headers ?? this.headers,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'endpoint': endpoint,
        'method': method.name,
        'payload': payload,
        'headers': headers,
        'retryCount': retryCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'status': status.name,
        'lastError': lastError,
      };

  factory SyncJob.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    return SyncJob(
      id: json['id'] as String,
      endpoint: json['endpoint'] as String,
      method: HttpMethod.fromWire(json['method'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      headers: rawHeaders == null
          ? null
          : Map<String, String>.from(rawHeaders as Map),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      status: SyncJobStatus.fromName(
        json['status'] as String? ?? SyncJobStatus.pending.name,
      ),
      lastError: json['lastError'] as String?,
    );
  }

  @override
  bool operator ==(Object other) => other is SyncJob && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SyncJob(id: $id, ${method.wireName} $endpoint, status: ${status.name}, '
      'retry: $retryCount)';
}