import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

void main() {
  late Directory tempDir;
  late String filePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_sync_test_');
    filePath = '${tempDir.path}/queue.json';
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('persists jobs across provider instances', () async {
    final first = FileStorageProvider(path: filePath);
    await first.initialize();
    final job = SyncJob(
      id: 'p1',
      endpoint: '/orders',
      method: HttpMethod.post,
      payload: const {'a': 1},
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );
    await first.saveJob(job);
    await first.dispose();

    final second = FileStorageProvider(path: filePath);
    await second.initialize();
    final reloaded = await second.getJob('p1');
    expect(reloaded, isNotNull);
    expect(reloaded!.endpoint, '/orders');
    expect(reloaded.payload, const {'a': 1});
    await second.dispose();
  });

  test('deleteJob removes the entry and re-persists', () async {
    final p = FileStorageProvider(path: filePath);
    await p.initialize();
    final job = SyncJob(
      id: 'p2',
      endpoint: '/x',
      method: HttpMethod.post,
      payload: const {},
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );
    await p.saveJob(job);
    await p.deleteJob(job.id);
    await p.dispose();

    final reload = FileStorageProvider(path: filePath);
    await reload.initialize();
    expect(await reload.getJob('p2'), isNull);
    await reload.dispose();
  });

  test('clear wipes the file', () async {
    final p = FileStorageProvider(path: filePath);
    await p.initialize();
    for (var i = 0; i < 3; i++) {
      await p.saveJob(SyncJob(
        id: 'j$i',
        endpoint: '/x',
        method: HttpMethod.post,
        payload: const {},
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      ));
    }
    await p.clear();
    await p.dispose();

    final reload = FileStorageProvider(path: filePath);
    await reload.initialize();
    expect(await reload.getAllJobs(), isEmpty);
    await reload.dispose();
  });

  test('getJobsByStatus filters correctly', () async {
    final p = FileStorageProvider(path: filePath);
    await p.initialize();
    await p.saveJob(SyncJob(
      id: 'pending',
      endpoint: '/a',
      method: HttpMethod.post,
      payload: const {},
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    ));
    await p.saveJob(SyncJob(
      id: 'failed',
      endpoint: '/b',
      method: HttpMethod.post,
      payload: const {},
      createdAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
      status: SyncJobStatus.failed,
    ));
    final pending = await p.getJobsByStatus(SyncJobStatus.pending);
    expect(pending.map((j) => j.id), ['pending']);
    final failed = await p.getJobsByStatus(SyncJobStatus.failed);
    expect(failed.map((j) => j.id), ['failed']);
    await p.dispose();
  });
}
