import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

void main() {
  late InMemoryStorageProvider storage;
  late QueueRepositoryImpl repo;

  setUp(() async {
    storage = InMemoryStorageProvider();
    await storage.initialize();
    repo = QueueRepositoryImpl(storage: storage);
  });

  tearDown(() async => storage.dispose());

  test('enqueue persists a job with pending status and unique id', () async {
    final job = await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/orders',
      payload: {'item': 'widget'},
    );
    expect(job.status, SyncJobStatus.pending);
    expect(job.retryCount, 0);
    expect(job.id, isNotEmpty);
    expect(job.createdAt, isNotNull);

    final reloaded = await storage.getJob(job.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.endpoint, '/orders');
  });

  test('update mutates a persisted job by id', () async {
    final job = await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/orders',
      payload: const {},
    );
    final updated = job.copyWith(status: SyncJobStatus.success);
    await repo.update(updated);
    final reloaded = await storage.getJob(job.id);
    expect(reloaded!.status, SyncJobStatus.success);
  });

  test('remove drops the job', () async {
    final job = await repo.enqueue(
      method: HttpMethod.delete,
      endpoint: '/orders/1',
      payload: const {},
    );
    await repo.remove(job.id);
    expect(await storage.getJob(job.id), isNull);
  });

  test('findPending returns pending jobs in FIFO order', () async {
    final a = await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/a',
      payload: const {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/b',
      payload: const {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final c = await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/c',
      payload: const {},
    );

    final pending = await repo.findPending();
    expect(pending.map((j) => j.id).toList(), [a.id, b.id, c.id]);
  });

  test('findFailed only returns failed jobs', () async {
    final job = await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/x',
      payload: const {},
    );
    await repo.update(job.copyWith(status: SyncJobStatus.failed));
    await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/y',
      payload: const {},
    );

    final failed = await repo.findFailed();
    expect(failed, hasLength(1));
    expect(failed.first.endpoint, '/x');
  });

  test('clear drops everything', () async {
    await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/a',
      payload: const {},
    );
    await repo.enqueue(
      method: HttpMethod.post,
      endpoint: '/b',
      payload: const {},
    );
    await repo.clear();
    expect(await repo.findAll(), isEmpty);
  });
}
