import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

void main() {
  group('SyncJob serialization', () {
    final reference = SyncJob(
      id: 'abc',
      endpoint: '/orders',
      method: HttpMethod.post,
      payload: const {'qty': 3},
      headers: const {'authorization': 'Bearer x'},
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 2),
      retryCount: 2,
      status: SyncJobStatus.failed,
      lastError: 'HTTP 500',
    );

    test('round-trips through JSON', () {
      final encoded = reference.toJson();
      final decoded = SyncJob.fromJson(encoded);
      expect(decoded, reference);
      expect(decoded.method, HttpMethod.post);
      expect(decoded.status, SyncJobStatus.failed);
      expect(decoded.payload, const {'qty': 3});
      expect(decoded.headers, const {'authorization': 'Bearer x'});
      expect(decoded.lastError, 'HTTP 500');
      expect(decoded.retryCount, 2);
    });

    test('copyWith preserves id and createdAt', () {
      final mutated = reference.copyWith(status: SyncJobStatus.success);
      expect(mutated.id, reference.id);
      expect(mutated.createdAt, reference.createdAt);
      expect(mutated.status, SyncJobStatus.success);
    });

    test('clearError removes lastError', () {
      final cleared = reference.copyWith(clearError: true);
      expect(cleared.lastError, isNull);
    });

    test('equality is by id', () {
      final twin = reference.copyWith(status: SyncJobStatus.success);
      expect(twin, reference);
      expect(twin.hashCode, reference.hashCode);
    });
  });
}
