import 'dart:async';
import 'dart:math';

import 'package:offline_sync_engine/offline_sync_engine.dart';

/// In-process fake that simulates a flaky remote service for the demo.
///
/// Toggle [online] from the UI to simulate going offline. While offline,
/// every request fails — exactly the path the sync engine is designed to
/// handle gracefully.
class FakeRemoteApi implements SyncApiClient {
  bool online = true;

  /// Probability that a request fails even while "online" (transient flake).
  double flakeRate;

  final _rng = Random();

  FakeRemoteApi({this.flakeRate = 0.0});

  @override
  Future<SyncResponse> execute(SyncJob job) async {
    // Pretend a real network round-trip.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!online) {
      return const SyncResponse.failure(error: 'Offline (simulated)');
    }
    if (_rng.nextDouble() < flakeRate) {
      return const SyncResponse.failure(error: 'Flaky 500 (simulated)');
    }
    return SyncResponse.success(statusCode: 201, body: {'echo': job.payload});
  }
}
