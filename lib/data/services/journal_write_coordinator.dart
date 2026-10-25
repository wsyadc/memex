import 'dart:async';

/// Serializes local capture commits with backup snapshot creation.
/// Queue draining must finish before a backup acquires this lease.
class JournalWriteCoordinator {
  JournalWriteCoordinator._();

  static Future<void> _tail = Future<void>.value();

  static Future<JournalWriteLease> acquire() async {
    final previous = _tail;
    final completion = Completer<void>();
    _tail = completion.future;
    await previous;
    return JournalWriteLease._(completion);
  }

  static Future<T> protect<T>(Future<T> Function() operation) async {
    final lease = await acquire();
    try {
      return await operation();
    } finally {
      lease.release();
    }
  }
}

class JournalWriteLease {
  JournalWriteLease._(this._completion);
  final Completer<void> _completion;

  void release() {
    if (!_completion.isCompleted) _completion.complete();
  }
}
