import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/authentication_throttle.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';

void main() {
  test('v2 unlock delay follows the documented schedule', () {
    expect(
      [for (var i = 1; i <= 10; i++) syncV2UnlockDelay(i).inSeconds],
      [0, 0, 0, 0, 30, 60, 300, 900, 3600, 3600],
    );
  });

  test('v2 throttle blocks the fifth failure for 30 seconds and resets', () async {
    var now = DateTime.utc(2026, 11, 17);
    final store = MemorySecureKeyValueStore();
    final throttle = AuthenticationThrottle(
      store: store,
      storageKey: syncV2UnlockAttemptsKey('g'),
      delayFor: syncV2UnlockDelay,
      now: () => now,
    );
    for (var i = 0; i < 5; i++) {
      expect(await throttle.verify(() async => false), isFalse);
    }
    await expectLater(
      throttle.verify(() async => true),
      throwsA(isA<AuthenticationThrottledException>()),
    );
    now = now.add(const Duration(seconds: 31));
    expect(await throttle.verify(() async => true), isTrue);
    expect(await store.read(syncV2UnlockAttemptsKey('g')), isNull);
  });
}
