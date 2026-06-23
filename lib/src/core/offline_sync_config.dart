import 'package:meta/meta.dart';

import '../models/conflict_strategy.dart';

/// Tunable behavior of the offline sync engine.
///
/// All fields have sensible defaults. Pass an instance to `OfflineSync.initialize`.
@immutable
class OfflineSyncConfig {
  /// Hard cap on retry attempts AFTER the initial try. Default `5`.
  ///
  /// With the default exponential-backoff [retryDelay] of 2s, a fully failing
  /// job is given up after roughly 2 + 4 + 8 + 16 + 32 = 62 seconds.
  final int maxRetries;

  /// Base interval used in `delay = retryDelay * 2^retryCount`.
  final Duration retryDelay;

  /// When `true`, sync is triggered automatically after [enqueue] and
  /// connectivity transitions.
  final bool autoSync;

  /// When `true`, the engine triggers sync whenever connectivity is restored
  /// (only if [autoSync] is also `true`).
  final bool syncOnConnectivity;

  /// Verbose console logs. Off by default.
  final bool loggingEnabled;

  /// Strategy used when the server reports a conflict.
  final ConflictStrategy strategy;

  const OfflineSyncConfig({
    this.maxRetries = 5,
    this.retryDelay = const Duration(seconds: 2),
    this.autoSync = true,
    this.syncOnConnectivity = true,
    this.loggingEnabled = false,
    this.strategy = ConflictStrategy.lastWriteWins,
  }) : assert(maxRetries >= 0, 'maxRetries must be >= 0');

  OfflineSyncConfig copyWith({
    int? maxRetries,
    Duration? retryDelay,
    bool? autoSync,
    bool? syncOnConnectivity,
    bool? loggingEnabled,
    ConflictStrategy? strategy,
  }) {
    return OfflineSyncConfig(
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      autoSync: autoSync ?? this.autoSync,
      syncOnConnectivity: syncOnConnectivity ?? this.syncOnConnectivity,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      strategy: strategy ?? this.strategy,
    );
  }
}
