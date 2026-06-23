import '../models/sync_job.dart';
import '../models/sync_job_status.dart';

/// Persistence contract for the offline queue.
///
/// Implementations are responsible for durably storing [SyncJob] records so
/// that the queue survives app restarts, device restarts, and process kills.
///
/// Implementations need NOT be thread-safe; the [SyncManager] serializes calls
/// behind a mutex. They MUST, however, be safe to call from any isolate the
/// host app uses (i.e. don't capture closures on root-isolate objects).
abstract class StorageProvider {
  /// Open underlying resources (DB connection, file handles). Idempotent.
  Future<void> initialize();

  /// Release underlying resources.
  Future<void> dispose();

  /// Insert or overwrite a job by id.
  Future<void> saveJob(SyncJob job);

  /// Return the job with [id], or `null` if not present.
  Future<SyncJob?> getJob(String id);

  /// Return every job. Ordering is not guaranteed; sort at the call site.
  Future<List<SyncJob>> getAllJobs();

  /// Return jobs filtered by status.
  Future<List<SyncJob>> getJobsByStatus(SyncJobStatus status);

  /// Update an existing job (no-op if id is absent).
  Future<void> updateJob(SyncJob job);

  /// Delete the job with [id] (no-op if id is absent).
  Future<void> deleteJob(String id);

  /// Remove every job. Used by `OfflineSync.clear()`.
  Future<void> clear();
}
