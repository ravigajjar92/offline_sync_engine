import '../models/http_method.dart';
import '../models/sync_job.dart';

/// Application-facing queue contract.
///
/// Sits above [StorageProvider] and exposes domain operations rather than raw
/// CRUD. The [SyncManager] only talks to a [QueueRepository] — never to a
/// storage provider directly.
abstract class QueueRepository {
  /// Build a new [SyncJob] from the supplied request fields and persist it.
  /// Returns the newly created job (with id, timestamps, status filled in).
  Future<SyncJob> enqueue({
    required HttpMethod method,
    required String endpoint,
    required Map<String, dynamic> payload,
    Map<String, String>? headers,
  });

  /// Persist mutations to an existing job (status change, retry++, etc.).
  Future<void> update(SyncJob job);

  /// Delete the job with [id].
  Future<void> remove(String id);

  /// Pending jobs in FIFO order (by `createdAt`).
  Future<List<SyncJob>> findPending();

  /// Jobs that exhausted all retries.
  Future<List<SyncJob>> findFailed();

  /// Every job, ordered by `createdAt`.
  Future<List<SyncJob>> findAll();

  /// Drop the entire queue.
  Future<void> clear();
}
