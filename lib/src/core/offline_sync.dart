import 'dart:async';

import '../events/sync_event.dart';
import '../exceptions/sync_exception.dart';
import '../models/http_method.dart';
import '../models/sync_job.dart';
import '../network/connectivity_monitor.dart';
import '../network/sync_api_client.dart';
import '../storage/in_memory_storage_provider.dart';
import '../storage/storage_provider.dart';
import '../utils/logger.dart';
import 'offline_sync_config.dart';
import 'offline_sync_engine.dart';

/// Static facade — the entry point most apps will use.
///
/// Internally delegates to a singleton [OfflineSyncEngine]. Apps that need
/// multiple isolated queues (per-tenant, per-account, etc.) should construct
/// [OfflineSyncEngine] directly instead.
class OfflineSync {
  OfflineSync._();

  static OfflineSyncEngine? _engine;

  /// Whether [initialize] has been called and the engine is ready.
  static bool get isInitialized => _engine != null;

  /// Underlying engine instance. Throws if [initialize] hasn't completed.
  static OfflineSyncEngine get instance {
    final e = _engine;
    if (e == null) {
      throw const SyncStateException(
        'OfflineSync.initialize() must be awaited before use.',
      );
    }
    return e;
  }

  /// Compose the engine. Idempotent — a second call with the same arguments
  /// is a no-op; a second call with different arguments throws.
  ///
  /// Defaults:
  ///   * [storage]      — [InMemoryStorageProvider] (NOT persistent — provide
  ///                      `FileStorageProvider` or your own implementation for
  ///                      production).
  ///   * [apiClient]    — **required**. The package never makes assumptions
  ///                      about your transport.
  ///   * [connectivity] — [ConnectivityPlusMonitor].
  ///   * [logger]       — [ConsoleLogger] when `config.loggingEnabled`,
  ///                      otherwise [NoopLogger].
  static Future<void> initialize({
    required OfflineSyncConfig config,
    required SyncApiClient apiClient,
    StorageProvider? storage,
    ConnectivityMonitor? connectivity,
    SyncLogger? logger,
  }) async {
    if (_engine != null) return;
    _engine = await OfflineSyncEngine.initialize(
      config: config,
      storage: storage ?? InMemoryStorageProvider(),
      apiClient: apiClient,
      connectivity: connectivity,
      logger: logger,
    );
  }

  /// Add a job to the queue. Returns the persisted [SyncJob].
  static Future<SyncJob> enqueue({
    required HttpMethod method,
    required String endpoint,
    Map<String, dynamic>? payload,
    Map<String, String>? headers,
  }) =>
      instance.enqueue(
        method: method,
        endpoint: endpoint,
        payload: payload,
        headers: headers,
      );

  /// Trigger queue processing manually. No-op if already syncing or paused.
  static Future<void> sync() => instance.sync();

  /// Drop a single job by id.
  static Future<void> remove(String jobId) => instance.remove(jobId);

  /// FIFO list of jobs still waiting to be sent.
  static Future<List<SyncJob>> pendingJobs() => instance.pendingJobs();

  /// Jobs that exhausted all retries.
  static Future<List<SyncJob>> failedJobs() => instance.failedJobs();

  /// All jobs regardless of status.
  static Future<List<SyncJob>> allJobs() => instance.allJobs();

  /// Drop the entire queue.
  static Future<void> clear() => instance.clear();

  /// Pause the queue. The in-flight job's current attempt is allowed to
  /// finish; subsequent processing stops until [resume].
  static Future<void> pause() => instance.pause();

  /// Resume processing. Triggers a sync if [OfflineSyncConfig.autoSync].
  static Future<void> resume() => instance.resume();

  /// Halt processing immediately. Use [sync] to start again.
  static Future<void> stop() => instance.stop();

  /// Typed event stream. Use a `switch` on the sealed [SyncEvent] hierarchy
  /// for exhaustive handling.
  static Stream<SyncEvent> get events => instance.events;

  /// Tear down. Closes storage, connectivity, the event bus.
  ///
  /// Mostly useful for tests; production apps typically initialize once at
  /// startup and live alongside the process.
  static Future<void> dispose() async {
    final e = _engine;
    _engine = null;
    if (e != null) await e.dispose();
  }
}
