import 'dart:async';

import '../conflict/conflict_resolver.dart';
import '../core/offline_sync_config.dart';
import '../events/event_bus.dart';
import '../events/sync_event.dart';
import '../models/sync_job.dart';
import '../models/sync_job_status.dart';
import '../models/sync_response.dart';
import '../network/connectivity_monitor.dart';
import '../network/sync_api_client.dart';
import '../repository/queue_repository.dart';
import '../utils/logger.dart';
import '../utils/mutex.dart';
import 'retry_policy.dart';

enum _JobOutcome { success, failed, conflictManual, aborted }

/// Orchestrates queue processing: FIFO ordering, single-job-at-a-time
/// execution, exponential-backoff retries, conflict resolution, event
/// emission, and pause / resume / stop control.
class SyncManager {
  final QueueRepository _repo;
  final SyncApiClient _apiClient;
  final ConnectivityMonitor _connectivity;
  final EventBus _bus;
  final OfflineSyncConfig _config;
  final ConflictResolver _resolver;
  final RetryPolicy _retryPolicy;
  final SyncLogger _logger;
  final DateTime Function() _clock;

  final Mutex _syncMutex = Mutex();
  StreamSubscription<bool>? _connectivitySub;

  bool _syncing = false;
  bool _paused = false;
  bool _stopRequested = false;
  bool _disposed = false;

  /// Completed when something asks the loop to wake up early (pause / stop /
  /// resume). Replaced after each consumption.
  Completer<void> _wake = Completer<void>();

  SyncManager({
    required QueueRepository repository,
    required SyncApiClient apiClient,
    required ConnectivityMonitor connectivity,
    required EventBus bus,
    required OfflineSyncConfig config,
    SyncLogger? logger,
    DateTime Function()? clock,
  })  : _repo = repository,
        _apiClient = apiClient,
        _connectivity = connectivity,
        _bus = bus,
        _config = config,
        _resolver = ConflictResolver.fromStrategy(config.strategy),
        _retryPolicy = RetryPolicy(
          baseDelay: config.retryDelay,
          maxRetries: config.maxRetries,
        ),
        _logger = logger ?? const NoopLogger(),
        _clock = clock ?? DateTime.now;

  /// Begin listening for connectivity transitions. Idempotent.
  void start() {
    if (_connectivitySub != null || _disposed) return;
    _connectivitySub = _connectivity.changes.listen(_onConnectivityChange);
  }

  bool get isSyncing => _syncing;
  bool get isPaused => _paused;
  bool get isStopped => _stopRequested;

  /// Process the queue.
  ///
  /// Re-entrant calls return immediately while another sync is in flight —
  /// the in-flight loop will pick up jobs queued after it started, so callers
  /// rarely need to invoke `sync()` directly.
  Future<void> sync() async {
    if (_disposed) return;
    if (_paused || _stopRequested) return;
    if (_syncing) return;

    await _syncMutex.synchronized(() async {
      if (_paused || _stopRequested || _disposed) return;
      _syncing = true;
      _stopRequested = false;
      try {
        await _runLoop();
      } finally {
        _syncing = false;
      }
    });
  }

  Future<void> _runLoop() async {
    final initialPending = await _repo.findPending();
    if (initialPending.isEmpty) {
      _bus.emit(SyncCompleted(processed: 0, succeeded: 0, failed: 0));
      return;
    }

    _bus.emit(SyncStarted(initialPending.length));
    _logger.info('Sync started with ${initialPending.length} pending job(s)');

    var processed = 0, succeeded = 0, failed = 0;
    final aborted = <Object>[]; // sentinel

    while (true) {
      if (_paused || _stopRequested || _disposed) break;
      final pending = await _repo.findPending();
      if (pending.isEmpty) break;
      final job = pending.first;

      final outcome = await _processJob(job);
      processed++;
      switch (outcome) {
        case _JobOutcome.success:
          succeeded++;
        case _JobOutcome.failed:
        case _JobOutcome.conflictManual:
          failed++;
        case _JobOutcome.aborted:
          aborted.add(job.id);
          break;
      }
      if (outcome == _JobOutcome.aborted) break;
    }

    _bus.emit(SyncCompleted(
      processed: processed,
      succeeded: succeeded,
      failed: failed,
    ));
    _logger.info(
      'Sync completed: processed=$processed, succeeded=$succeeded, '
      'failed=$failed${aborted.isNotEmpty ? ', aborted' : ''}',
    );
  }

  /// Execute a single job with retry + backoff + conflict resolution.
  ///
  /// On failure the job's `retryCount` is incremented and persisted. If the
  /// post-increment count exceeds `maxRetries`, the job is marked `failed`;
  /// otherwise it stays `pending` for the next loop iteration (which will
  /// apply backoff before re-attempting it).
  Future<_JobOutcome> _processJob(SyncJob initialJob) async {
    var job = initialJob;
    var failedCount = initialJob.retryCount;

    while (true) {
      if (_paused || _stopRequested || _disposed) {
        // Restore status to pending so the next sync resumes it.
        if (job.status == SyncJobStatus.processing) {
          await _repo.update(job.copyWith(
            status: SyncJobStatus.pending,
            updatedAt: _clock(),
          ));
        }
        return _JobOutcome.aborted;
      }

      // Pre-attempt backoff (skip on the very first attempt of this job).
      if (failedCount > 0) {
        final delay = _retryPolicy.nextDelay(failedCount - 1);
        final interrupted = await _interruptibleWait(delay);
        if (interrupted) {
          await _repo.update(job.copyWith(
            status: SyncJobStatus.pending,
            updatedAt: _clock(),
          ));
          return _JobOutcome.aborted;
        }
      }

      job = job.copyWith(
        status: SyncJobStatus.processing,
        updatedAt: _clock(),
      );
      await _repo.update(job);
      _bus.emit(JobProcessing(job));
      _logger.info('Processing ${job.id} (attempt ${failedCount + 1})');

      final response = await _safeExecute(job);

      if (response.isSuccess) {
        job = job.copyWith(
          status: SyncJobStatus.success,
          retryCount: failedCount,
          updatedAt: _clock(),
          clearError: true,
        );
        await _repo.update(job);
        _bus.emit(JobSucceeded(job));
        _logger.info('Job ${job.id} succeeded');
        return _JobOutcome.success;
      }

      if (response.isConflict) {
        _bus.emit(ConflictDetected(job, response.serverState));
        _logger.warning('Conflict on ${job.id} (server-state present: '
            '${response.serverState != null})');
        final decision = _resolver.resolve(
          localJob: job,
          serverState: response.serverState,
        );
        switch (decision) {
          case ConflictDecision.keepServer:
            // Local change is no longer needed; close out the job.
            job = job.copyWith(
              status: SyncJobStatus.success,
              retryCount: failedCount,
              updatedAt: _clock(),
              clearError: true,
            );
            await _repo.update(job);
            _bus.emit(JobSucceeded(job));
            _logger.info('Conflict on ${job.id}: server wins → job closed');
            return _JobOutcome.success;

          case ConflictDecision.keepClient:
            failedCount++;
            if (failedCount > _config.maxRetries) {
              job = job.copyWith(
                status: SyncJobStatus.failed,
                retryCount: failedCount,
                lastError: response.error ?? 'Conflict persisted past max retries',
                updatedAt: _clock(),
              );
              await _repo.update(job);
              _bus.emit(JobFailed(job, response.error ?? 'Conflict',
                  willRetry: false));
              _logger.error('Job ${job.id} failed (conflict, retries exhausted)');
              return _JobOutcome.failed;
            }
            job = job.copyWith(
              status: SyncJobStatus.pending,
              retryCount: failedCount,
              lastError: response.error,
              updatedAt: _clock(),
            );
            await _repo.update(job);
            continue;

          case ConflictDecision.manual:
            job = job.copyWith(
              status: SyncJobStatus.conflict,
              retryCount: failedCount,
              lastError: response.error ?? 'Manual resolution required',
              updatedAt: _clock(),
            );
            await _repo.update(job);
            _bus.emit(JobFailed(job, response.error ?? 'Conflict',
                willRetry: false));
            return _JobOutcome.conflictManual;
        }
      }

      // Plain failure.
      failedCount++;
      if (failedCount > _config.maxRetries) {
        job = job.copyWith(
          status: SyncJobStatus.failed,
          retryCount: failedCount,
          lastError: response.error,
          updatedAt: _clock(),
        );
        await _repo.update(job);
        _bus.emit(JobFailed(job, response.error ?? 'Failed',
            willRetry: false));
        _logger.error('Job ${job.id} failed permanently: ${response.error}');
        return _JobOutcome.failed;
      }
      job = job.copyWith(
        status: SyncJobStatus.pending,
        retryCount: failedCount,
        lastError: response.error,
        updatedAt: _clock(),
      );
      await _repo.update(job);
      _bus.emit(JobFailed(job, response.error ?? 'Failed', willRetry: true));
      _logger.warning(
          'Job ${job.id} failed (attempt $failedCount/${_config.maxRetries}): '
          '${response.error}');
    }
  }

  Future<SyncResponse> _safeExecute(SyncJob job) async {
    try {
      return await _apiClient.execute(job);
    } catch (e, st) {
      _logger.error('Transport threw for ${job.id}',
          error: e, stackTrace: st);
      return SyncResponse.failure(error: 'Transport error: $e');
    }
  }

  /// Wait [duration], unless `pause`/`stop`/`dispose` wakes us first.
  /// Returns `true` if interrupted, `false` if the full delay elapsed.
  Future<bool> _interruptibleWait(Duration duration) async {
    if (duration <= Duration.zero) return _paused || _stopRequested;
    final timerFuture = Future<void>.delayed(duration);
    await Future.any<void>([timerFuture, _wake.future]);
    return _paused || _stopRequested || _disposed;
  }

  void _signalWake() {
    if (!_wake.isCompleted) _wake.complete();
    _wake = Completer<void>();
  }

  Future<void> pause() async {
    if (_paused || _disposed) return;
    _paused = true;
    _signalWake();
    _bus.emit(SyncPaused());
    _logger.info('Sync paused');
  }

  Future<void> resume() async {
    if (!_paused || _disposed) return;
    _paused = false;
    _signalWake();
    _bus.emit(SyncResumed());
    _logger.info('Sync resumed');
    if (_config.autoSync) {
      unawaited(sync());
    }
  }

  Future<void> stop() async {
    if (_stopRequested || _disposed) return;
    _stopRequested = true;
    _signalWake();
    _logger.info('Sync stop requested');
  }

  /// Convenience: opposite of [stop]. Clears the stop flag without forcing a
  /// sync — callers can subsequently invoke [sync].
  void reset() {
    _stopRequested = false;
  }

  void _onConnectivityChange(bool online) {
    if (_disposed) return;
    if (online) {
      _bus.emit(ConnectivityRestored());
      _logger.info('Connectivity restored');
      if (_config.autoSync && _config.syncOnConnectivity && !_paused) {
        unawaited(sync());
      }
    } else {
      _bus.emit(ConnectivityLost());
      _logger.info('Connectivity lost');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopRequested = true;
    _signalWake();
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}
