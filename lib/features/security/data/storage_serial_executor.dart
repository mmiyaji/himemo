import 'dart:async';

import 'secure_key_value_store.dart';

/// Serializes operations for a persisted value across service instances in this
/// isolate. This does not provide a distributed lock across devices/isolates.
/// Not reentrant: never await another run for the same storage identity and key
/// inside an operation; that nested call would wait for its own caller.
class StorageSerialExecutor {
  static final _pending = <Object, Map<String, Future<void>>>{};

  static Future<T> run<T>(
    SecureKeyValueStore store,
    String key,
    Future<T> Function() operation,
  ) async {
    final identity = storageCoordinationIdentity(store);
    final entries = _pending.putIfAbsent(identity, () => {});
    final previous = entries[key];
    final completed = Completer<void>();
    entries[key] = completed.future;
    if (previous != null) await previous;
    try {
      return await operation();
    } finally {
      completed.complete();
      if (identical(entries[key], completed.future)) {
        entries.remove(key);
        if (entries.isEmpty) _pending.remove(identity);
      }
    }
  }
}
