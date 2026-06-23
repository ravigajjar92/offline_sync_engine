import 'dart:async';

import 'sync_event.dart';

/// Broadcasts [SyncEvent]s to any number of listeners.
///
/// Wraps a broadcast `StreamController`. Late subscribers receive only future
/// events (no replay), which matches typical UI binding semantics.
class EventBus {
  final StreamController<SyncEvent> _controller =
      StreamController<SyncEvent>.broadcast(sync: false);

  Stream<SyncEvent> get stream => _controller.stream;

  bool get isClosed => _controller.isClosed;

  void emit(SyncEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}
