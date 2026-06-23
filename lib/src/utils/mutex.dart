import 'dart:async';

/// Single-slot mutex. `synchronized()` runs at most one closure at a time and
/// queues subsequent callers FIFO.
///
/// Re-entrancy is NOT supported; calling `synchronized` from inside an already
/// running critical section will deadlock the caller.
class Mutex {
  Future<void> _last = Future<void>.value();

  Future<T> synchronized<T>(FutureOr<T> Function() body) {
    final completer = Completer<T>();
    final previous = _last;
    _last = completer.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {});

    previous.whenComplete(() async {
      try {
        final result = await body();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }
}
