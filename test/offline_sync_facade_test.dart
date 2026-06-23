import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

import 'support/fake_api_client.dart';

void main() {
  late FakeApiClient api;
  late FakeConnectivityMonitor connectivity;

  setUp(() async {
    api = FakeApiClient();
    connectivity = FakeConnectivityMonitor();
    await OfflineSync.initialize(
      config: const OfflineSyncConfig(
        maxRetries: 2,
        retryDelay: Duration.zero,
        autoSync: false,
        syncOnConnectivity: false,
        loggingEnabled: false,
      ),
      storage: InMemoryStorageProvider(),
      apiClient: api,
      connectivity: connectivity,
    );
  });

  tearDown(() async {
    await OfflineSync.dispose();
  });

  test('enqueue → sync → success end-to-end', () async {
    final job = await OfflineSync.enqueue(
      method: HttpMethod.post,
      endpoint: '/orders',
      payload: const {'qty': 1},
    );
    expect(job.status, SyncJobStatus.pending);

    await OfflineSync.sync();

    final all = await OfflineSync.allJobs();
    expect(all.first.status, SyncJobStatus.success);
  });

  test('pendingJobs returns only pending', () async {
    await OfflineSync.enqueue(
      method: HttpMethod.post,
      endpoint: '/a',
      payload: const {},
    );
    await OfflineSync.enqueue(
      method: HttpMethod.post,
      endpoint: '/b',
      payload: const {},
    );
    expect(await OfflineSync.pendingJobs(), hasLength(2));
  });

  test('remove drops the job', () async {
    final job = await OfflineSync.enqueue(
      method: HttpMethod.post,
      endpoint: '/x',
      payload: const {},
    );
    await OfflineSync.remove(job.id);
    expect(await OfflineSync.pendingJobs(), isEmpty);
  });

  test('clear empties the queue', () async {
    await OfflineSync.enqueue(
      method: HttpMethod.post,
      endpoint: '/x',
      payload: const {},
    );
    await OfflineSync.clear();
    expect(await OfflineSync.allJobs(), isEmpty);
  });

  test('events stream emits JobQueued on enqueue', () async {
    final events = <SyncEvent>[];
    final sub = OfflineSync.events.listen(events.add);

    await OfflineSync.enqueue(
      method: HttpMethod.post,
      endpoint: '/x',
      payload: const {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(events.whereType<JobQueued>(), isNotEmpty);
    await sub.cancel();
  });

  test('throws SyncStateException when not initialized', () async {
    await OfflineSync.dispose();
    expect(
      () => OfflineSync.enqueue(
        method: HttpMethod.post,
        endpoint: '/x',
        payload: const {},
      ),
      throwsA(isA<SyncStateException>()),
    );
    // Re-init for tearDown
    await OfflineSync.initialize(
      config: const OfflineSyncConfig(retryDelay: Duration.zero),
      storage: InMemoryStorageProvider(),
      apiClient: api,
      connectivity: connectivity,
    );
  });
}
