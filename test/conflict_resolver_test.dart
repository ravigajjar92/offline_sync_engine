import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

void main() {
  SyncJob job(DateTime updatedAt) => SyncJob(
        id: 'j',
        endpoint: '/x',
        method: HttpMethod.put,
        payload: const {'v': 1},
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );

  group('ConflictResolver.fromStrategy', () {
    test('lastWriteWins picks newer server timestamp', () {
      final r = ConflictResolver.fromStrategy(ConflictStrategy.lastWriteWins);
      final local = job(DateTime.utc(2024, 1, 1));
      final decision = r.resolve(
        localJob: local,
        serverState: {'updatedAt': DateTime.utc(2024, 6, 1).toIso8601String()},
      );
      expect(decision, ConflictDecision.keepServer);
    });

    test('lastWriteWins picks local when local is newer', () {
      final r = ConflictResolver.fromStrategy(ConflictStrategy.lastWriteWins);
      final local = job(DateTime.utc(2024, 12, 1));
      final decision = r.resolve(
        localJob: local,
        serverState: {'updatedAt': DateTime.utc(2024, 6, 1).toIso8601String()},
      );
      expect(decision, ConflictDecision.keepClient);
    });

    test('lastWriteWins defaults to client when server has no updatedAt', () {
      final r = ConflictResolver.fromStrategy(ConflictStrategy.lastWriteWins);
      expect(
        r.resolve(localJob: job(DateTime.utc(2024)), serverState: null),
        ConflictDecision.keepClient,
      );
      expect(
        r.resolve(localJob: job(DateTime.utc(2024)), serverState: const {}),
        ConflictDecision.keepClient,
      );
      expect(
        r.resolve(
            localJob: job(DateTime.utc(2024)),
            serverState: const {'updatedAt': 'not-a-date'}),
        ConflictDecision.keepClient,
      );
    });

    test('serverWins always returns keepServer', () {
      final r = ConflictResolver.fromStrategy(ConflictStrategy.serverWins);
      expect(
        r.resolve(localJob: job(DateTime.utc(2024)), serverState: null),
        ConflictDecision.keepServer,
      );
    });

    test('clientWins always returns keepClient', () {
      final r = ConflictResolver.fromStrategy(ConflictStrategy.clientWins);
      expect(
        r.resolve(
          localJob: job(DateTime.utc(2024)),
          serverState: {'updatedAt': DateTime.utc(2099).toIso8601String()},
        ),
        ConflictDecision.keepClient,
      );
    });
  });
}
