import 'package:meta/meta.dart';

import '../models/conflict_strategy.dart';
import '../models/sync_job.dart';

/// Decision returned by a [ConflictResolver].
enum ConflictDecision {
  /// Discard the local change; the server's version is authoritative.
  keepServer,

  /// Force-overwrite the server with the local change (engine will retry
  /// the original request, typically as a PUT/PATCH).
  keepClient,

  /// Engine cannot resolve automatically — surface as a `failed` job and emit
  /// a [ConflictDetected] event for the application to resolve.
  manual,
}

/// Strategy for reconciling a conflict between local job state and the
/// server's current state.
abstract class ConflictResolver {
  ConflictDecision resolve({
    required SyncJob localJob,
    required Map<String, dynamic>? serverState,
  });

  /// Factory: pick the implementation that matches [strategy].
  factory ConflictResolver.fromStrategy(ConflictStrategy strategy) {
    return switch (strategy) {
      ConflictStrategy.lastWriteWins => const LastWriteWinsResolver(),
      ConflictStrategy.serverWins => const ServerWinsResolver(),
      ConflictStrategy.clientWins => const ClientWinsResolver(),
    };
  }
}

/// Newer `updatedAt` wins. If `serverState` is missing `updatedAt`, defers to
/// the client.
@immutable
class LastWriteWinsResolver implements ConflictResolver {
  const LastWriteWinsResolver();

  @override
  ConflictDecision resolve({
    required SyncJob localJob,
    required Map<String, dynamic>? serverState,
  }) {
    final raw = serverState?['updatedAt'];
    if (raw is! String) return ConflictDecision.keepClient;
    final serverUpdatedAt = DateTime.tryParse(raw);
    if (serverUpdatedAt == null) return ConflictDecision.keepClient;
    return serverUpdatedAt.isAfter(localJob.updatedAt)
        ? ConflictDecision.keepServer
        : ConflictDecision.keepClient;
  }
}

@immutable
class ServerWinsResolver implements ConflictResolver {
  const ServerWinsResolver();
  @override
  ConflictDecision resolve({
    required SyncJob localJob,
    required Map<String, dynamic>? serverState,
  }) =>
      ConflictDecision.keepServer;
}

@immutable
class ClientWinsResolver implements ConflictResolver {
  const ClientWinsResolver();
  @override
  ConflictDecision resolve({
    required SyncJob localJob,
    required Map<String, dynamic>? serverState,
  }) =>
      ConflictDecision.keepClient;
}
