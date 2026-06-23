import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../exceptions/sync_exception.dart';
import '../models/sync_job.dart';
import '../models/sync_job_status.dart';
import 'storage_provider.dart';

/// JSON-file-backed [StorageProvider].
///
/// Reads the entire queue into memory on [initialize] and rewrites the file
/// on every mutation. Best suited for small-to-medium queues (hundreds to a
/// few thousand jobs) which is the typical offline-sync workload.
///
/// For larger workloads, implement [StorageProvider] against Hive / Isar /
/// sqflite / Drift.
///
/// Not supported on web (uses `dart:io`). For web, supply a custom
/// [StorageProvider] that wraps `package:web` storage or IndexedDB.
class FileStorageProvider implements StorageProvider {
  final File _file;
  final Map<String, SyncJob> _jobs = {};
  bool _initialized = false;
  Future<void> _writeChain = Future.value();

  FileStorageProvider({required String path}) : _file = File(path);

  /// Construct from a [File] (handy in tests that use `Directory.systemTemp`).
  FileStorageProvider.fromFile(this._file);

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (!await _file.exists()) {
        await _file.create(recursive: true);
        await _file.writeAsString('[]', flush: true);
      }
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) {
        _initialized = true;
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const StorageException(
          'Queue file is corrupt: expected a JSON array at the top level.',
        );
      }
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final job = SyncJob.fromJson(Map<String, dynamic>.from(entry));
        _jobs[job.id] = job;
      }
      _initialized = true;
    } on StorageException {
      rethrow;
    } catch (e, st) {
      throw StorageException(
        'Failed to initialize file storage at ${_file.path}',
        cause: e,
        causeStackTrace: st,
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _writeChain;
    _jobs.clear();
    _initialized = false;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const StorageException(
        'FileStorageProvider used before initialize().',
      );
    }
  }

  /// Serialize disk writes so a fast burst of saves can't interleave on disk.
  Future<void> _persist() {
    _writeChain = _writeChain.then((_) async {
      final encoded =
          jsonEncode(_jobs.values.map((j) => j.toJson()).toList(growable: false));
      try {
        await _file.writeAsString(encoded, flush: true);
      } catch (e, st) {
        throw StorageException(
          'Failed to write queue file at ${_file.path}',
          cause: e,
          causeStackTrace: st,
        );
      }
    });
    return _writeChain;
  }

  @override
  Future<void> saveJob(SyncJob job) async {
    _ensureInitialized();
    _jobs[job.id] = job;
    await _persist();
  }

  @override
  Future<SyncJob?> getJob(String id) async {
    _ensureInitialized();
    return _jobs[id];
  }

  @override
  Future<List<SyncJob>> getAllJobs() async {
    _ensureInitialized();
    return _jobs.values.toList();
  }

  @override
  Future<List<SyncJob>> getJobsByStatus(SyncJobStatus status) async {
    _ensureInitialized();
    return _jobs.values.where((j) => j.status == status).toList();
  }

  @override
  Future<void> updateJob(SyncJob job) async {
    _ensureInitialized();
    if (!_jobs.containsKey(job.id)) return;
    _jobs[job.id] = job;
    await _persist();
  }

  @override
  Future<void> deleteJob(String id) async {
    _ensureInitialized();
    if (_jobs.remove(id) != null) await _persist();
  }

  @override
  Future<void> clear() async {
    _ensureInitialized();
    _jobs.clear();
    await _persist();
  }
}
