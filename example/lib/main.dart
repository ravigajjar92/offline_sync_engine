import 'dart:async';

import 'package:flutter/material.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';
import 'package:path_provider/path_provider.dart';

import 'fake_remote_api.dart';

/// End-to-end demo:
///   1. Toggle network on / off using the AppBar switch.
///   2. Press "Add Job" to enqueue an HTTP POST.
///   3. Watch pending / failed / success counters update live.
///   4. When network is restored, queued jobs flush automatically.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final docsDir = await getApplicationDocumentsDirectory();
  final api = FakeRemoteApi();

  await OfflineSync.initialize(
    config: const OfflineSyncConfig(
      maxRetries: 3,
      retryDelay: Duration(milliseconds: 500),
      autoSync: true,
      syncOnConnectivity: true,
      loggingEnabled: true,
      strategy: ConflictStrategy.lastWriteWins,
    ),
    storage: FileStorageProvider(path: '${docsDir.path}/offline_sync_queue.json'),
    apiClient: api,
  );

  runApp(DemoApp(api: api));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key, required this.api});
  final FakeRemoteApi api;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OfflineSync Demo',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: HomeScreen(api: api),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final FakeRemoteApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _log = [];
  List<SyncJob> _all = const [];
  StreamSubscription<SyncEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = OfflineSync.events.listen(_onEvent);
    _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(SyncEvent event) {
    setState(() {
      _log.insert(0, _formatEvent(event));
      if (_log.length > 100) _log.removeLast();
    });
    _refresh();
  }

  String _formatEvent(SyncEvent e) => switch (e) {
        JobQueued(:final job) => 'queued ${job.id.substring(0, 8)}',
        JobProcessing(:final job) =>
          'processing ${job.id.substring(0, 8)} (retry ${job.retryCount})',
        JobSucceeded(:final job) => 'succeeded ${job.id.substring(0, 8)}',
        JobFailed(:final job, :final willRetry) =>
          'failed ${job.id.substring(0, 8)} (willRetry=$willRetry)',
        ConflictDetected(:final job) => 'conflict ${job.id.substring(0, 8)}',
        ConnectivityRestored() => '✓ connectivity restored',
        ConnectivityLost() => '✗ connectivity lost',
        SyncStarted(:final pendingCount) => '▶ sync started ($pendingCount pending)',
        SyncCompleted(:final succeeded, :final failed) =>
          '■ sync completed (ok=$succeeded, fail=$failed)',
        SyncPaused() => '⏸ sync paused',
        SyncResumed() => '▶ sync resumed',
      };

  Future<void> _refresh() async {
    final all = await OfflineSync.allJobs();
    if (mounted) setState(() => _all = all);
  }

  Future<void> _addJob() async {
    final id = DateTime.now().millisecondsSinceEpoch;
    await OfflineSync.enqueue(
      method: HttpMethod.post,
      endpoint: '/orders',
      payload: {'id': id, 'qty': 1},
    );
  }

  int _count(SyncJobStatus s) => _all.where((j) => j.status == s).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OfflineSync Demo'),
        actions: [
          Row(
            children: [
              const Text('Network'),
              Switch(
                value: widget.api.online,
                onChanged: (v) => setState(() => widget.api.online = v),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Job'),
        onPressed: _addJob,
      ),
      body: Column(
        children: [
          _StatsBar(
            pending: _count(SyncJobStatus.pending),
            success: _count(SyncJobStatus.success),
            failed: _count(SyncJobStatus.failed),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: OverflowBar(
              alignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: OfflineSync.sync,
                  child: const Text('Sync Now'),
                ),
                OutlinedButton(
                  onPressed: OfflineSync.pause,
                  child: const Text('Pause'),
                ),
                OutlinedButton(
                  onPressed: OfflineSync.resume,
                  child: const Text('Resume'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await OfflineSync.clear();
                    _refresh();
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _JobList(jobs: _all, onRemove: (id) async {
                    await OfflineSync.remove(id);
                    _refresh();
                  }),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _LogPanel(log: _log)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.pending,
    required this.success,
    required this.failed,
  });
  final int pending;
  final int success;
  final int failed;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int value, Color color) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Chip(
            backgroundColor: color.withValues(alpha: .15),
            label: Text('$label: $value'),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          chip('Pending', pending, Colors.orange),
          chip('Success', success, Colors.green),
          chip('Failed', failed, Colors.red),
        ],
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({required this.jobs, required this.onRemove});
  final List<SyncJob> jobs;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const Center(child: Text('No jobs yet — press “Add Job”'));
    }
    return ListView.separated(
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final j = jobs[i];
        return ListTile(
          dense: true,
          leading: Icon(
            switch (j.status) {
              SyncJobStatus.success => Icons.check_circle,
              SyncJobStatus.failed => Icons.error,
              SyncJobStatus.conflict => Icons.warning,
              SyncJobStatus.processing => Icons.sync,
              SyncJobStatus.pending => Icons.hourglass_bottom,
            },
            color: switch (j.status) {
              SyncJobStatus.success => Colors.green,
              SyncJobStatus.failed => Colors.red,
              SyncJobStatus.conflict => Colors.amber,
              SyncJobStatus.processing => Colors.blue,
              SyncJobStatus.pending => Colors.grey,
            },
          ),
          title: Text('${j.method.wireName} ${j.endpoint}'),
          subtitle: Text(
            'id=${j.id.substring(0, 8)} • retry=${j.retryCount}'
            '${j.lastError != null ? ' • ${j.lastError}' : ''}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onRemove(j.id),
          ),
        );
      },
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.log});
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: log.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          log[i],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
