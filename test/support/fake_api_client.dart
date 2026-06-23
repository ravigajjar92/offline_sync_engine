import 'package:offline_sync_engine/offline_sync_engine.dart';

/// Test double for [SyncApiClient].
///
/// Configure with [enqueueResponse] / [enqueueResponses] / [respondWith] to
/// shape what `execute` returns. Captures every job that was sent so tests
/// can assert on the call sequence.
class FakeApiClient implements SyncApiClient {
  final List<SyncJob> calls = [];
  final List<SyncResponse Function(SyncJob)> _scripted = [];
  SyncResponse Function(SyncJob)? _default;

  void respondWith(SyncResponse Function(SyncJob) handler) {
    _default = handler;
  }

  void enqueueResponse(SyncResponse response) {
    _scripted.add((_) => response);
  }

  void enqueueHandler(SyncResponse Function(SyncJob) handler) {
    _scripted.add(handler);
  }

  void enqueueResponses(Iterable<SyncResponse> responses) {
    for (final r in responses) {
      enqueueResponse(r);
    }
  }

  @override
  Future<SyncResponse> execute(SyncJob job) async {
    calls.add(job);
    if (_scripted.isNotEmpty) {
      final next = _scripted.removeAt(0);
      return next(job);
    }
    if (_default != null) return _default!(job);
    return const SyncResponse.success();
  }
}
