import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

/// Smoke test: confirms the public barrel export wires up the API surface
/// the README documents. Per-component behavior is covered by the dedicated
/// suites (retry_policy_test, queue_repository_test, sync_manager_test, etc.).
void main() {
  test('public API surface is exported', () {
    expect(HttpMethod.post, isA<HttpMethod>());
    expect(SyncJobStatus.pending, isA<SyncJobStatus>());
    expect(ConflictStrategy.lastWriteWins, isA<ConflictStrategy>());
    expect(const OfflineSyncConfig().maxRetries, 5);
    expect(InMemoryStorageProvider(), isA<StorageProvider>());
  });
}
