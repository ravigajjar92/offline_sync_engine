import '../models/http_method.dart';
import '../models/sync_job.dart';
import '../models/sync_job_status.dart';
import '../storage/storage_provider.dart';
import '../utils/id_generator.dart';
import 'queue_repository.dart';

/// Default [QueueRepository] backed by a [StorageProvider].
///
/// Stateless aside from the injected collaborators — safe to share across the
/// engine. Time is taken from the [DateTime.now] clock by default; supply a
/// [clock] in tests for determinism.
class QueueRepositoryImpl implements QueueRepository {
  final StorageProvider _storage;
  final IdGenerator _idGenerator;
  final DateTime Function() _clock;

  QueueRepositoryImpl({
    required StorageProvider storage,
    IdGenerator? idGenerator,
    DateTime Function()? clock,
  })  : _storage = storage,
        _idGenerator = idGenerator ?? UuidV4IdGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<SyncJob> enqueue({
    required HttpMethod method,
    required String endpoint,
    required Map<String, dynamic> payload,
    Map<String, String>? headers,
  }) async {
    final now = _clock();
    final job = SyncJob(
      id: _idGenerator.generate(),
      endpoint: endpoint,
      method: method,
      payload: payload,
      headers: headers,
      createdAt: now,
      updatedAt: now,
      status: SyncJobStatus.pending,
    );
    await _storage.saveJob(job);
    return job;
  }

  @override
  Future<void> update(SyncJob job) => _storage.updateJob(job);

  @override
  Future<void> remove(String id) => _storage.deleteJob(id);

  @override
  Future<List<SyncJob>> findPending() async {
    final jobs = await _storage.getJobsByStatus(SyncJobStatus.pending);
    jobs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return jobs;
  }

  @override
  Future<List<SyncJob>> findFailed() async {
    final jobs = await _storage.getJobsByStatus(SyncJobStatus.failed);
    jobs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return jobs;
  }

  @override
  Future<List<SyncJob>> findAll() async {
    final jobs = await _storage.getAllJobs();
    jobs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return jobs;
  }

  @override
  Future<void> clear() => _storage.clear();
}
