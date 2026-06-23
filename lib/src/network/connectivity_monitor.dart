import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports online/offline transitions.
abstract class ConnectivityMonitor {
  /// Emits `true` when at least one network interface is online,
  /// `false` when fully offline.
  Stream<bool> get changes;

  /// Synchronous best-effort current state. May not be up to date before the
  /// first event arrives on [changes].
  Future<bool> isOnline();

  Future<void> dispose();
}

/// Default monitor backed by `connectivity_plus`.
class ConnectivityPlusMonitor implements ConnectivityMonitor {
  final Connectivity _connectivity;
  late final StreamController<bool> _controller;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool? _lastState;

  ConnectivityPlusMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _controller = StreamController<bool>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  void _start() {
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = _isOnline(results);
      if (_lastState != online) {
        _lastState = online;
        if (!_controller.isClosed) _controller.add(online);
      }
    });
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Stream<bool> get changes => _controller.stream;

  @override
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    final online = _isOnline(results);
    _lastState = online;
    return online;
  }

  @override
  Future<void> dispose() async {
    await _stop();
    await _controller.close();
  }
}

/// Test double — emits whatever you push into [setOnline].
class FakeConnectivityMonitor implements ConnectivityMonitor {
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();
  bool _online;

  FakeConnectivityMonitor({bool initiallyOnline = true})
      : _online = initiallyOnline;

  void setOnline(bool online) {
    if (_online == online) return;
    _online = online;
    _controller.add(online);
  }

  @override
  Stream<bool> get changes => _controller.stream;

  @override
  Future<bool> isOnline() async => _online;

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
