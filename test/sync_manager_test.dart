import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

import 'support/fake_api_client.dart';

void main() {
  late InMemoryStorageProvider storage;
  late QueueRepositoryImpl repo;
  late FakeApiClient api;
  late FakeConnectivityMonitor connectivity;
  late EventBus bus;
  late SyncManager manager;

  /// Build a manager. Default config uses zero retry delay so tests don't
  /// have to fake-out backoff timers.
  Future<void> bootstrap({
    OfflineSyncConfig config = const OfflineSyncConfig(
      maxRetries: 3,
      retryDelay: Duration.zero,
      autoSync: false,
      syncOnConnectivity: false,
      loggingEnabled: false,
    ),
  }) async {
    storage = InMemoryStorageProvider();
    await storage.initialize();
    repo = QueueRepositoryImpl(storage: storage);
    api = FakeApiClient();
    connectivity = FakeConnectivityMonitor();
    bus = EventBus();
    manager = SyncManager(
      repository: repo,
      apiClient: api,
      connectivity: connectivity,
      bus: bus,
      config: config,
    );
    manager.start();
  }

  tearDown(() async {
    await manager.dispose();
    await bus.close();
    await storage.dispose();
    await connectivity.dispose();
  });

  group('success path', () {
    test('successful job ends in success status and emits JobSucceeded',
        () async {
      await bootstrap();
      final job = await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/orders',
        payload: const {'qty': 1},
      );
      final events = <SyncEvent>[];
      final sub = bus.stream.listen(events.add);

      await manager.sync();
      await Future<void>.delayed(Duration.zero);

      expect((await storage.getJob(job.id))!.status, SyncJobStatus.success);
      expect(events.whereType<JobSucceeded>(), isNotEmpty);
      expect(events.whereType<SyncStarted>(), isNotEmpty);
      expect(events.whereType<SyncCompleted>(), isNotEmpty);

      await sub.cancel();
    });

    test('multiple jobs process in FIFO order', () async {
      await bootstrap();
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

      await manager.sync();

      expect(api.calls.map((j) => j.id).toList(), [a.id, b.id, c.id]);
    });
  });

  group('failure + retry', () {
    test('retries up to maxRetries then marks failed', () async {
      await bootstrap();
      // 4 failures (1 initial + 3 retries) — all fail.
      api.enqueueResponses(List.filled(
        4,
        const SyncResponse.failure(error: 'boom'),
      ));

      final job = await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/flaky',
        payload: const {},
      );
      await manager.sync();

      final reloaded = (await storage.getJob(job.id))!;
      expect(reloaded.status, SyncJobStatus.failed);
      expect(reloaded.retryCount, 4); // 1 initial + 3 retries
      expect(api.calls.length, 4);
    });

    test('succeeds on retry, ends in success status', () async {
      await bootstrap();
      api.enqueueResponse(const SyncResponse.failure(error: 'flap'));
      api.enqueueResponse(const SyncResponse.success());

      final job = await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/x',
        payload: const {},
      );
      await manager.sync();

      final reloaded = (await storage.getJob(job.id))!;
      expect(reloaded.status, SyncJobStatus.success);
      expect(reloaded.retryCount, 1);
      expect(api.calls.length, 2);
    });

    test('JobFailed events include willRetry flag', () async {
      await bootstrap();
      api.enqueueResponses(
        List.filled(4, const SyncResponse.failure(error: 'down')),
      );

      final failures = <JobFailed>[];
      final sub = bus.stream
          .where((e) => e is JobFailed)
          .cast<JobFailed>()
          .listen(failures.add);

      await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/x',
        payload: const {},
      );
      await manager.sync();

      expect(failures.where((e) => e.willRetry).length, 3);
      expect(failures.where((e) => !e.willRetry).length, 1);

      await sub.cancel();
    });
  });

  group('conflict resolution', () {
    test('serverWins strategy marks job as success', () async {
      await bootstrap(
        config: const OfflineSyncConfig(
          maxRetries: 2,
          retryDelay: Duration.zero,
          autoSync: false,
          syncOnConnectivity: false,
          strategy: ConflictStrategy.serverWins,
        ),
      );
      api.enqueueResponse(const SyncResponse.conflict(serverState: {'v': 2}));

      final job = await repo.enqueue(
        method: HttpMethod.put,
        endpoint: '/x',
        payload: const {'v': 1},
      );
      await manager.sync();

      final reloaded = (await storage.getJob(job.id))!;
      expect(reloaded.status, SyncJobStatus.success);
    });

    test('clientWins strategy retries and eventually wins', () async {
      await bootstrap(
        config: const OfflineSyncConfig(
          maxRetries: 3,
          retryDelay: Duration.zero,
          autoSync: false,
          syncOnConnectivity: false,
          strategy: ConflictStrategy.clientWins,
        ),
      );
      api.enqueueResponse(const SyncResponse.conflict());
      api.enqueueResponse(const SyncResponse.success());

      final job = await repo.enqueue(
        method: HttpMethod.put,
        endpoint: '/x',
        payload: const {},
      );
      await manager.sync();

      final reloaded = (await storage.getJob(job.id))!;
      expect(reloaded.status, SyncJobStatus.success);
      expect(api.calls.length, 2);
    });

    test('lastWriteWins: server newer → keepServer (success)', () async {
      await bootstrap(
        config: const OfflineSyncConfig(
          maxRetries: 2,
          retryDelay: Duration.zero,
          autoSync: false,
          syncOnConnectivity: false,
          strategy: ConflictStrategy.lastWriteWins,
        ),
      );
      api.enqueueResponse(SyncResponse.conflict(
        serverState: {'updatedAt': DateTime.utc(2099).toIso8601String()},
      ));
      final job = await repo.enqueue(
        method: HttpMethod.put,
        endpoint: '/x',
        payload: const {},
      );
      await manager.sync();
      final reloaded = (await storage.getJob(job.id))!;
      expect(reloaded.status, SyncJobStatus.success);
    });

    test('ConflictDetected event fires', () async {
      await bootstrap(
        config: const OfflineSyncConfig(
          maxRetries: 0,
          retryDelay: Duration.zero,
          autoSync: false,
          syncOnConnectivity: false,
          strategy: ConflictStrategy.clientWins,
        ),
      );
      api.enqueueResponse(const SyncResponse.conflict());
      final events = <SyncEvent>[];
      final sub = bus.stream.listen(events.add);

      await repo.enqueue(
        method: HttpMethod.put,
        endpoint: '/x',
        payload: const {},
      );
      await manager.sync();

      expect(events.whereType<ConflictDetected>(), isNotEmpty);
      await sub.cancel();
    });
  });

  group('connectivity', () {
    test('restored connectivity triggers sync when configured', () async {
      await bootstrap(
        config: const OfflineSyncConfig(
          maxRetries: 1,
          retryDelay: Duration.zero,
          autoSync: true,
          syncOnConnectivity: true,
        ),
      );
      await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/x',
        payload: const {},
      );

      // Simulate offline → online.
      connectivity.setOnline(false);
      await Future<void>.delayed(Duration.zero);
      connectivity.setOnline(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(api.calls, isNotEmpty);
    });

    test('emits ConnectivityRestored / ConnectivityLost events', () async {
      await bootstrap(
        config: const OfflineSyncConfig(
          maxRetries: 0,
          retryDelay: Duration.zero,
          autoSync: false,
          syncOnConnectivity: false,
        ),
      );
      final events = <SyncEvent>[];
      final sub = bus.stream.listen(events.add);

      connectivity.setOnline(false);
      await Future<void>.delayed(Duration.zero);
      connectivity.setOnline(true);
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<ConnectivityLost>(), isNotEmpty);
      expect(events.whereType<ConnectivityRestored>(), isNotEmpty);
      await sub.cancel();
    });
  });

  group('pause / resume', () {
    test('pause prevents new sync; resume re-enables', () async {
      await bootstrap();
      await manager.pause();
      await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/x',
        payload: const {},
      );
      await manager.sync();
      expect(api.calls, isEmpty);

      await manager.resume();
      await manager.sync();
      expect(api.calls.length, 1);
    });
  });

  group('thread safety', () {
    test('concurrent sync calls do not duplicate processing', () async {
      await bootstrap();
      await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/x',
        payload: const {},
      );
      // Fire three concurrent sync calls.
      await Future.wait([manager.sync(), manager.sync(), manager.sync()]);
      expect(api.calls.length, 1);
    });
  });

  group('event ordering', () {
    test('emits SyncStarted → JobProcessing → JobSucceeded → SyncCompleted',
        () async {
      await bootstrap();
      final events = <SyncEvent>[];
      final sub = bus.stream.listen(events.add);

      await repo.enqueue(
        method: HttpMethod.post,
        endpoint: '/x',
        payload: const {},
      );
      await manager.sync();
      await Future<void>.delayed(Duration.zero);

      final types = events.map((e) => e.runtimeType.toString()).toList();
      final i0 = types.indexOf('SyncStarted');
      final i1 = types.indexOf('JobProcessing');
      final i2 = types.indexOf('JobSucceeded');
      final i3 = types.indexOf('SyncCompleted');
      expect(i0, greaterThanOrEqualTo(0));
      expect(i1, greaterThan(i0));
      expect(i2, greaterThan(i1));
      expect(i3, greaterThan(i2));

      await sub.cancel();
    });
  });
}
