import 'dart:async';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// A queue owner holds a shared SQLite transaction; backup and restore hold an
/// exclusive one. This database lives outside the replaceable journal database,
/// so its lock survives workspace restoration and coordinates separate isolates.
class TaskQueueStorageLock {
  TaskQueueStorageLock._(this._database);

  Database? _database;

  static Future<TaskQueueStorageLock?> tryAcquireShared() =>
      _tryAcquire(exclusive: false);

  static Future<TaskQueueStorageLock> acquireShared({
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _acquire(exclusive: false, timeout: timeout);

  static Future<TaskQueueStorageLock> acquireExclusive({
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _acquire(exclusive: true, timeout: timeout);

  static Future<TaskQueueStorageLock> _acquire({
    required bool exclusive,
    required Duration timeout,
  }) async {
    final elapsed = Stopwatch()..start();
    do {
      final lock = await _tryAcquire(exclusive: exclusive);
      if (lock != null) return lock;
      if (elapsed.elapsed >= timeout) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } while (elapsed.elapsed < timeout);
    throw StateError('后台仍在保存日记，请稍后再备份或恢复。');
  }

  static Future<TaskQueueStorageLock?> _tryAcquire({
    required bool exclusive,
  }) async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = sqlite3.open(
      path.join(directory.path, 'memex_queue_storage_lock.sqlite'),
    );
    try {
      database.execute('PRAGMA busy_timeout=0');
      database.execute(
        'CREATE TABLE IF NOT EXISTS queue_storage_lock (id INTEGER PRIMARY KEY)',
      );
      database.execute(exclusive ? 'BEGIN EXCLUSIVE' : 'BEGIN');
      // BEGIN alone is deferred: this read establishes the shared file lock.
      database.select('SELECT id FROM queue_storage_lock LIMIT 1');
      return TaskQueueStorageLock._(database);
    } on SqliteException catch (error) {
      database.dispose();
      if (error.resultCode == 5 || error.resultCode == 6) return null;
      rethrow;
    } catch (_) {
      database.dispose();
      rethrow;
    }
  }

  void release() {
    final database = _database;
    if (database == null) return;
    _database = null;
    try {
      database.execute('ROLLBACK');
    } finally {
      database.dispose();
    }
  }
}
