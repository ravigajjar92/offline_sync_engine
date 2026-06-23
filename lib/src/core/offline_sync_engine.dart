import 'dart:async';

import '../events/event_bus.dart';
import '../events/sync_event.dart';
import '../exceptions/sync_exception.dart';
import '../models/http_method.dart';
import '../models/sync_job.dart';
import '../network/connectivity_monitor.dart';
import '../network/sync_api_client.dart';
import '../repository/queue_repository.dart';
import '../repository/queue_repository_impl.dart';
import '../storage/storage_provider.dart';
import '../sync/sync_manager.dart';
import '../utils/logger.dart';
import 'offline_sync_config.dart';

/// Instance-based engine. Wraps the composition root that the static
/// [OfflineSync] facade delegates to.
///
/// Construct directly when you need multiple engines in the same app (e.g.
/// per-tenant queues) or for unit testing. Otherwise, use [OfflineSync].
class OfflineSyncEngine {
  final OfflineSyncConfig config;
  final StorageProvider storage;
  final QueueRepository repository;
  final SyncApiClient apiClient;
  final ConnectivityMonitor connectivity;
  final SyncManager manager;
  final EventBus _bus;
  final SyncLogger logger;

  bool _disposed = false;

  OfflineSyncEngine._({
    required this.config,
    required this.storage,
    required this.repository,
    required this.apiClient,
    required this.connectivity,
    required this.manager,
    required EventBus bus,
    required this.logger,
  }) : _bus = bus;

  /// Compose all collaborators and start listening for connectivity.
  static Future<OfflineSyncEngine> initialize({
    required OfflineSyncConfig config,
    required StorageProvider storage,
    required SyncApiClient apiClient,
    ConnectivityMonitor? connectivity,
    SyncLogger? logger,
    DateTime Function()? clock,
  }) async {
    final effectiveLogger = logger ??
        (config.loggingEnabled
            ? const ConsoleLogger()
            : const NoopLogger());
    final monitor = connectivity ?? ConnectivityPlusMonitor();
    final bus = EventBus();
    final repo = QueueRepositoryImpl(storage: storage, clock: clock);

    await storage.initialize();

    final manager = SyncManager(
      repository: repo,
      apiClient: apiClient,
      connectivity: monitor,
      bus: bus,
      config: config,
      logger: effectiveLogger,
      clock: clock,
    );
    manager.start();

    return OfflineSyncEngine._(
      config: config,
      storage: storage,
      repository: repo,
      apiClient: apiClient,
      connectivity: monitor,
      manager: manager,
      bus: bus,
      logger: effectiveLogger,
    );
  }

  Stream<SyncEvent> get events => _bus.stream;

  void _ensureAlive() {
    if (_disposed) {
      throw const SyncStateException('OfflineSyncEngine is disposed.');
    }
  }

  Future<SyncJob> enqueue({
    required HttpMethod method,
    required String endpoint,
    Map<String, dynamic>? payload,
    Map<String, String>? headers,
  }) async {
    _ensureAlive();
    final job = await repository.enqueue(
      method: method,
      endpoint: endpoint,
      payload: payload ?? const {},
      headers: headers,
    );
    _bus.emit(JobQueued(job));
    logger.info('Enqueued ${job.method.wireName} ${job.endpoint} as ${job.id}');
    if (config.autoSync) {
      unawaited(manager.sync());
    }
    return job;
  }

  Future<void> sync() {
    _ensureAlive();
    return manager.sync();
  }

  Future<void> remove(String jobId) {
    _ensureAlive();
    return repository.remove(jobId);
  }

  Future<List<SyncJob>> pendingJobs() {
    _ensureAlive();
    return repository.findPending();
  }

  Future<List<SyncJob>> failedJobs() {
    _ensureAlive();
    return repository.findFailed();
  }

  Future<List<SyncJob>> allJobs() {
    _ensureAlive();
    return repository.findAll();
  }

  Future<void> clear() {
    _ensureAlive();
    return repository.clear();
  }

  Future<void> pause() {
    _ensureAlive();
    return manager.pause();
  }

  Future<void> resume() {
    _ensureAlive();
    return manager.resume();
  }

  Future<void> stop() {
    _ensureAlive();
    return manager.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await manager.dispose();
    await connectivity.dispose();
    await storage.dispose();
    await _bus.close();
  }
}
