# offline_sync_engine

A production-ready, framework-agnostic **offline-first synchronization engine**
for Flutter. Drop it into any app — Riverpod, Bloc, Provider, GetX, vanilla —
and your write-side operations keep working while offline, flushing
automatically as soon as connectivity returns.

- Persistent FIFO queue
- Automatic retries with exponential backoff (`base * 2^retryCount`)
- Connectivity-driven auto-sync (`connectivity_plus`)
- Pluggable conflict resolution (lastWriteWins / serverWins / clientWins)
- Typed `Stream<SyncEvent>` for UI integration
- Pluggable storage, network and connectivity layers — no opinions imposed
- Clean Architecture, fully unit-tested

---

## Supported transports

- [x] **HTTP / REST** — built-in (`HttpSyncClient`)
- [ ] **GraphQL** — not supported (planned)
- [ ] **WebSocket** — not supported (planned)

---

## Architecture

```
┌────────────────────────────┐
│       Application UI       │
└──────────────┬─────────────┘
               ▼
┌────────────────────────────┐
│      OfflineSync (facade)  │
└──────────────┬─────────────┘
               ▼
┌────────────────────────────┐
│      OfflineSyncEngine     │  ← composition root
└──────────────┬─────────────┘
               ▼
┌────────────────────────────┐
│        SyncManager         │  ← the heart: FIFO, retries, conflicts
└──────────────┬─────────────┘
               ▼
┌────────────────────────────┐
│      QueueRepository       │  ← domain operations on the queue
└──────────────┬─────────────┘
               ▼
┌────────────────────────────┐
│      StorageProvider       │  ← abstraction
└──────────────┬─────────────┘
               ▼
┌────────────────────────────┐
│  In-memory / File / Hive / │
│   Isar / Drift / sqflite   │
└────────────────────────────┘
```

Every layer depends only on the abstraction below it. The package never reaches
across boundaries to touch storage or transport directly.

### Source layout

```
lib/
└── src/
    ├── core/         # OfflineSync facade, engine, config
    ├── models/       # SyncJob, status, method, response
    ├── storage/      # StorageProvider + in-memory / file implementations
    ├── repository/   # QueueRepository + impl
    ├── sync/         # SyncManager, RetryPolicy
    ├── conflict/     # ConflictResolver + strategies
    ├── network/      # SyncApiClient + http impl, ConnectivityMonitor
    ├── events/       # SyncEvent sealed hierarchy + EventBus
    ├── exceptions/   # SyncException + subclasses
    └── utils/        # Logger, IdGenerator, Mutex
```

---

## Installation

```yaml
dependencies:
  offline_sync_engine: ^1.0.0
```

---

## Quick start

```dart
import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();

  await OfflineSync.initialize(
    config: const OfflineSyncConfig(
      maxRetries: 5,
      retryDelay: Duration(seconds: 2),
      autoSync: true,
      syncOnConnectivity: true,
      loggingEnabled: false,
      strategy: ConflictStrategy.lastWriteWins,
    ),
    storage: FileStorageProvider(path: '${docs.path}/offline_sync_queue.json'),
    apiClient: HttpSyncClient(
      baseUrl: Uri.parse('https://api.example.com'),
      defaultHeaders: {'authorization': 'Bearer $token'},
    ),
  );

  runApp(const MyApp());
}
```

### Queue a job

```dart
await OfflineSync.enqueue(
  method: HttpMethod.post,
  endpoint: '/orders',
  payload: order.toJson(),
);
```

If `autoSync` is on (default), the engine attempts to send it immediately when
online and persists it for retry when offline.

### Manual sync

```dart
await OfflineSync.sync();
```

### Observe events

```dart
OfflineSync.events.listen((event) {
  switch (event) {
    JobQueued(:final job)     => debugPrint('queued ${job.id}'),
    JobSucceeded(:final job)  => debugPrint('ok ${job.id}'),
    JobFailed(:final job, :final willRetry) =>
      debugPrint('fail ${job.id} retry=$willRetry'),
    ConflictDetected(:final job) =>
      debugPrint('conflict ${job.id}'),
    ConnectivityRestored()    => debugPrint('online'),
    ConnectivityLost()        => debugPrint('offline'),
    _ => null,
  }
});
```

The `SyncEvent` hierarchy is sealed — a `switch` is exhaustive over every
event type the engine emits.

### Inspect & manage the queue

```dart
final pending = await OfflineSync.pendingJobs();
final failed  = await OfflineSync.failedJobs();
final all     = await OfflineSync.allJobs();

await OfflineSync.remove(jobId);
await OfflineSync.clear();
```

### Pause / resume / stop

```dart
await OfflineSync.pause();
await OfflineSync.resume();
await OfflineSync.stop();
```

---

## Configuration

| Field                 | Default              | Description                                          |
| --------------------- | -------------------- | ---------------------------------------------------- |
| `maxRetries`          | `5`                  | Max retries after the initial attempt.               |
| `retryDelay`          | `Duration(seconds:2)`| Base for exponential backoff.                        |
| `autoSync`            | `true`               | Trigger sync after `enqueue` / on connectivity.      |
| `syncOnConnectivity`  | `true`               | Trigger sync when network is restored.               |
| `loggingEnabled`      | `false`              | Print sync activity to stdout (`ConsoleLogger`).     |
| `strategy`            | `lastWriteWins`      | Conflict-resolution strategy.                        |

### Retry schedule

`delay = retryDelay * 2^retryCount`. With defaults:

| Retry | Delay |
| ----- | ----- |
| 1     | 2s    |
| 2     | 4s    |
| 3     | 8s    |
| 4     | 16s   |
| 5     | 32s   |

After exhausting `maxRetries`, the job's status becomes `SyncJobStatus.failed`
and a `JobFailed(willRetry: false)` event is emitted.

---

## Storage providers

### Bundled

| Provider                  | Persistent | Web  | Use case                             |
| ------------------------- | ---------- | ---- | ------------------------------------ |
| `InMemoryStorageProvider` | no         | yes  | tests, ephemeral demos               |
| `FileStorageProvider`     | yes        | no   | mobile / desktop production default  |

### Swap in another database

Implement `StorageProvider` against your preferred store. Sketches:

<details>
<summary>Hive</summary>

```dart
class HiveStorageProvider implements StorageProvider {
  late final Box<Map> _box;
  @override
  Future<void> initialize() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<Map>('offline_sync_queue');
  }
  @override
  Future<void> saveJob(SyncJob job) => _box.put(job.id, job.toJson());
  @override
  Future<SyncJob?> getJob(String id) async {
    final raw = _box.get(id);
    return raw == null ? null : SyncJob.fromJson(Map<String, dynamic>.from(raw));
  }
  // ... etc
}
```
</details>

<details>
<summary>Isar</summary>

```dart
@collection
class SyncJobModel { /* mirror of SyncJob, plus @Id() id */ }

class IsarStorageProvider implements StorageProvider {
  late final Isar _isar;
  @override
  Future<void> initialize() async {
    _isar = await Isar.open([SyncJobModelSchema]);
  }
  // ... map SyncJob ↔ SyncJobModel and implement the contract
}
```
</details>

<details>
<summary>sqflite / Drift</summary>

Same pattern: define a `sync_jobs` table, map rows ↔ `SyncJob`, implement the
nine `StorageProvider` methods, pass the instance to `OfflineSync.initialize`.
</details>

---

## Network providers

The package ships `HttpSyncClient` (built on `package:http`) as a sensible
default. Plug in your own transport by implementing `SyncApiClient`:

```dart
class DioSyncClient implements SyncApiClient {
  final Dio dio;
  DioSyncClient(this.dio);
  @override
  Future<SyncResponse> execute(SyncJob job) async {
    try {
      final res = await dio.request(
        job.endpoint,
        data: job.payload,
        options: Options(
          method: job.method.wireName,
          headers: job.headers,
          validateStatus: (_) => true,
        ),
      );
      if (res.statusCode! >= 200 && res.statusCode! < 300) {
        return SyncResponse.success(statusCode: res.statusCode, body: res.data);
      }
      if (res.statusCode == 409) {
        return SyncResponse.conflict(
          statusCode: 409,
          serverState: res.data is Map<String, dynamic>
              ? res.data as Map<String, dynamic>
              : null,
        );
      }
      return SyncResponse.failure(
        error: 'HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    } catch (e) {
      return SyncResponse.failure(error: e.toString());
    }
  }
}
```

Same pattern works for Chopper, GraphQL clients, gRPC, REST-over-WebSocket, etc.

---

## Conflict resolution

When `SyncApiClient` returns a `SyncResponse.conflict(serverState: ...)`, the
configured strategy decides:

| Strategy          | Decision                                                              |
| ----------------- | --------------------------------------------------------------------- |
| `lastWriteWins`   | Compares `serverState['updatedAt']` vs `job.updatedAt`; newer wins.   |
| `serverWins`      | Drop the local job; mark as success (no longer needed).               |
| `clientWins`      | Retry the job (counts against the retry budget).                      |

Implement `ConflictResolver` for custom rules.

---

## Exception hierarchy

All package exceptions extend the sealed `SyncException`:

- `StorageException`  — persistence failure
- `NetworkException`  — transport failure
- `ConflictException` — unresolvable conflict
- `SyncStateException`— misuse (e.g. enqueue before initialize)

```dart
try {
  await OfflineSync.enqueue(...);
} on SyncException catch (e) {
  // uniform handling
}
```

---

## Threading & re-entrancy

`SyncManager.sync()` is guarded by a mutex — concurrent calls return
immediately while one loop is in flight. Jobs are processed strictly
one-at-a-time in FIFO order.

---

## Web support

`FileStorageProvider` uses `dart:io` and is not available on web. For web,
implement `StorageProvider` against IndexedDB / `package:web` localStorage,
or use `InMemoryStorageProvider` for ephemeral state.

Everything else (`HttpSyncClient`, `ConnectivityPlusMonitor`, the engine
itself) works on web.

---

## Example app

A runnable demo lives under `example/`. It exposes a network toggle, lets you
queue jobs while offline, and watches them flush automatically when you turn
the network back on. Try it:

```bash
cd example
flutter pub get
flutter run
```

---

## Testing your integration

The package ships test doubles:

- `FakeConnectivityMonitor` — push online/offline transitions from your test.
- `InMemoryStorageProvider` — ephemeral storage.

Combined with a hand-rolled `FakeApiClient` (see `test/support/fake_api_client.dart`)
you can drive the full engine in pure-Dart unit tests with no platform
dependencies.

```dart
test('queues while offline, flushes when online', () async {
  final api = FakeApiClient()..respondWith((_) => const SyncResponse.success());
  final monitor = FakeConnectivityMonitor(initiallyOnline: false);

  await OfflineSync.initialize(
    config: const OfflineSyncConfig(retryDelay: Duration.zero),
    storage: InMemoryStorageProvider(),
    connectivity: monitor,
    apiClient: api,
  );

  await OfflineSync.enqueue(
    method: HttpMethod.post, endpoint: '/x', payload: {});
  expect((await OfflineSync.pendingJobs()).length, 1);

  monitor.setOnline(true);
  await Future.delayed(const Duration(milliseconds: 50));
  expect((await OfflineSync.pendingJobs()).length, 0);
});
```

---

## License

See `LICENSE`.
