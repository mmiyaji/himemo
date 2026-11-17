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
    Duration Function(int failures)? delayFor,
  }) : _now = now ?? DateTime.now,
       _delayFor = delayFor ?? _defaultDelay;

  final SecureKeyValueStore _store;
  final String storageKey;
  final DateTime Function() _now;
  final Duration Function(int failures) _delayFor;

  // 5 failures: 30s; subsequent failures double, capped at one hour.
  static Duration _defaultDelay(int count) {
    if (count < 5) return Duration.zero;
    final exponent = (count - 5).clamp(0, 7);
    return Duration(seconds: (30 * (1 << exponent)).clamp(0, 3600));
  }

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
        final delay = _delayFor(count).inMilliseconds.clamp(0, 3600000);
        await _persist(count, _now().millisecondsSinceEpoch + delay);
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

/// One counter per v2 generation, shared by profile and admin passcodes so
/// alternating between them cannot avoid the delay.
String syncV2UnlockAttemptsKey(String generationId) =>
    'sync.v2.unlock.${Uri.encodeComponent(generationId)}.attempts';

/// Delay after [failures] consecutive v2 passcode failures.
Duration syncV2UnlockDelay(int failures) => switch (failures) {
  < 5 => Duration.zero,
  5 => const Duration(seconds: 30),
  6 => const Duration(minutes: 1),
  7 => const Duration(minutes: 5),
  8 => const Duration(minutes: 15),
  _ => const Duration(hours: 1),
};
