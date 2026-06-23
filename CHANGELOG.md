## 1.0.0

Initial release.

* Clean Architecture across `core`, `models`, `storage`, `repository`, `sync`,
  `conflict`, `network`, `events`, `exceptions`, `utils`.
* `OfflineSync` static facade + `OfflineSyncEngine` instance API.
* Persistent FIFO queue via `StorageProvider` abstraction.
  * `InMemoryStorageProvider` for tests and ephemeral state.
  * `FileStorageProvider` (JSON-file-backed, mobile / desktop persistence).
* `SyncManager` with single-job-at-a-time mutex, FIFO processing, exponential
  backoff retries, pause / resume / stop control, conflict resolution.
* `RetryPolicy` implementing `delay = baseDelay * 2^retryCount`.
* `ConflictResolver` strategies: `lastWriteWins`, `serverWins`, `clientWins`.
* `ConnectivityMonitor` abstraction + `ConnectivityPlusMonitor` default +
  `FakeConnectivityMonitor` test double.
* `SyncApiClient` abstraction + `HttpSyncClient` reference implementation.
* Sealed `SyncEvent` hierarchy + broadcast `EventBus`.
* Typed `SyncException` hierarchy (`StorageException`, `NetworkException`,
  `ConflictException`, `SyncStateException`).
* Comprehensive unit test suite (44+ tests) covering queue, retry, sync,
  connectivity, conflict, persistence, and event ordering.
* Example app demonstrating offline queueing and auto-flush on reconnect.
