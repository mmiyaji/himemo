import 'dart:convert';

import 'secure_key_value_store.dart';
import 'storage_serial_executor.dart';

class AuthenticationThrottledException implements Exception {
  const AuthenticationThrottledException(this.retryAt);
  final DateTime retryAt;

  @override
  String toString() => 'Too many attempts. Retry after ${retryAt.toLocal()}.';
}

/// Persistent limits for app-managed secrets, independent of OS authentication.
class AuthenticationThrottle {
  AuthenticationThrottle({
    required this._store,
    required this.storageKey,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SecureKeyValueStore _store;
  final String storageKey;
  final DateTime Function() _now;

  Future<bool> verify(Future<bool> Function() check) =>
      StorageSerialExecutor.run(_store, storageKey, () async {
        final raw = await _store.read(storageKey);
        final now = _now().millisecondsSinceEpoch;
        var failures = 0;
        var blockedUntil = 0;
        try {
          if (raw != null) {
            final state = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            failures = state['failures'] as int;
            blockedUntil = state['blockedUntil'] as int;
            if (failures < 0 || blockedUntil < 0) {
              throw const FormatException('Invalid authentication counter.');
            }
          }
        } on FormatException {
          failures = 5;
          blockedUntil = now + 30000;
          await _persist(failures, blockedUntil);
        } on TypeError {
          failures = 5;
          blockedUntil = now + 30000;
          await _persist(failures, blockedUntil);
        }
        // Persist the cap after a backward clock change. Advancing the device
        // clock can still bypass a wall-clock based limit.
        if (blockedUntil > now + 3600000) {
          blockedUntil = now + 3600000;
          await _persist(failures, blockedUntil);
        }
        if (now < blockedUntil) {
          throw AuthenticationThrottledException(
            DateTime.fromMillisecondsSinceEpoch(blockedUntil),
          );
        }
        final matched = await check();
        if (matched) {
          await _store.delete(storageKey);
          return true;
        }
        final count = failures + 1;
        // 5 failures: 30s; subsequent failures double, capped at one hour.
        final exponent = (count - 5).clamp(0, 7);
        final seconds = count < 5 ? 0 : (30 * (1 << exponent)).clamp(0, 3600);
        await _persist(count, _now().millisecondsSinceEpoch + seconds * 1000);
        return false;
      });

  Future<void> _persist(int failures, int blockedUntil) async {
    final encoded = jsonEncode({
      'failures': failures,
      'blockedUntil': blockedUntil,
    });
    await _store.write(storageKey, encoded);
    if (await _store.read(storageKey) != encoded) {
      throw StateError('Authentication attempt persistence failed.');
    }
  }

  Future<void> reset() => StorageSerialExecutor.run(
    _store,
    storageKey,
    () => _store.delete(storageKey),
  );
}
