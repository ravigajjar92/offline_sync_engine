import 'package:meta/meta.dart';

import '../models/sync_job.dart';

/// Sealed hierarchy of events emitted by `OfflineSync.events`.
///
/// Use a switch / pattern match for exhaustive handling:
/// ```dart
/// OfflineSync.events.listen((event) => switch (event) {
///   JobSucceeded(:final job) => ...,
///   JobFailed(:final job, :final error) => ...,
///   _ => null,
/// });
/// ```
@immutable
sealed class SyncEvent {
  final DateTime timestamp;
  SyncEvent() : timestamp = DateTime.now();

  @override
  String toString() => '$runtimeType@${timestamp.toIso8601String()}';
}

final class SyncStarted extends SyncEvent {
  final int pendingCount;
  SyncStarted(this.pendingCount);
}

final class SyncCompleted extends SyncEvent {
  final int processed;
  final int succeeded;
  final int failed;
  SyncCompleted({
    required this.processed,
    required this.succeeded,
    required this.failed,
  });
}

final class SyncPaused extends SyncEvent {}

final class SyncResumed extends SyncEvent {}

final class JobQueued extends SyncEvent {
  final SyncJob job;
  JobQueued(this.job);
}

final class JobProcessing extends SyncEvent {
  final SyncJob job;
  JobProcessing(this.job);
}

final class JobSucceeded extends SyncEvent {
  final SyncJob job;
  JobSucceeded(this.job);
}

final class JobFailed extends SyncEvent {
  final SyncJob job;
  final Object error;
  final bool willRetry;
  JobFailed(this.job, this.error, {this.willRetry = false});
}

final class ConflictDetected extends SyncEvent {
  final SyncJob job;
  final Map<String, dynamic>? serverState;
  ConflictDetected(this.job, this.serverState);
}

final class ConnectivityRestored extends SyncEvent {}

final class ConnectivityLost extends SyncEvent {}
