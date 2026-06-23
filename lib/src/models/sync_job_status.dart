/// Lifecycle state of a [SyncJob] inside the queue.
enum SyncJobStatus {
  /// Waiting to be processed.
  pending,

  /// Currently being executed by the [SyncManager].
  processing,

  /// Completed successfully.
  success,

  /// Exhausted all retries.
  failed,

  /// Server reported a conflict; awaits resolution.
  conflict;

  bool get isTerminal => this == success || this == failed;
  bool get isRetryable => this == pending || this == conflict;

  static SyncJobStatus fromName(String value) =>
      SyncJobStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => throw ArgumentError('Unknown SyncJobStatus: $value'),
      );
}
