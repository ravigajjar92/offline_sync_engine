import '../models/sync_job.dart';
import '../models/sync_job_status.dart';
import 'storage_provider.dart';

/// Process-local, non-persistent [StorageProvider].
///
/// Ideal for tests and ephemeral use cases. For production use, swap in a
/// persistent provider such as [FileStorageProvider] (or your own Hive / Isar
/// / sqflite / Drift implementation).
class InMemoryStorageProvider implements StorageProvider {
  final Map<String, SyncJob> _jobs = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    _jobs.clear();
  }

  @override
  Future<void> saveJob(SyncJob job) async {
    _jobs[job.id] = job;
  }

  @override
  Future<SyncJob?> getJob(String id) async => _jobs[id];

  @override
  Future<List<SyncJob>> getAllJobs() async => _jobs.values.toList();

  @override
  Future<List<SyncJob>> getJobsByStatus(SyncJobStatus status) async =>
      _jobs.values.where((j) => j.status == status).toList();

  @override
  Future<void> updateJob(SyncJob job) async {
    if (_jobs.containsKey(job.id)) _jobs[job.id] = job;
  }

  @override
  Future<void> deleteJob(String id) async {
    _jobs.remove(id);
  }

  @override
  Future<void> clear() async {
    _jobs.clear();
  }
}
