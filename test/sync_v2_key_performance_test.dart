@Tags(['performance'])
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';

// Run with:
// flutter test test/sync_v2_key_performance_test.dart --reporter expanded
// This measures the host test process, not a native app or an iOS device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports host profile unlock latency and event-loop gaps', () async {
    const generation = 'host-key-benchmark';
    const passphrase = 'synthetic benchmark passphrase';
    final service = SyncV2ProfileKeys(EncryptionService());
    final admin = SecretKey(List<int>.filled(32, 91));
    final originalKeys = <String, SecretKey>{};
    final records = <SyncV2WrappedProfileKey>[];
    final samples = <String, Object>{};
    try {
      // Setup also warms the real Argon2id path. Keep wrapping and correctness
      // assertions outside measured intervals; do not substitute a cheaper KDF.
      for (var index = 0; index < 10; index++) {
        final id = 'profile-$index';
        final key = SecretKey(List<int>.generate(32, (byte) => index + byte));
        originalKeys[id] = key;
        records.add(
          await service.wrap(
            generationId: generation,
            profileId: id,
            keyId: 'key-$index',
            profileKey: key,
            passphrase: passphrase,
            adminKey: admin,
          ),
        );
      }

      for (final count in [1, 3, 10]) {
        final selected = records.take(count).toList();
        final measurement = await _measure(
          () => service.unlockMatchingSessions(
            generationId: generation,
            records: selected,
            passphrase: passphrase,
          ),
        );
        final unlocked = measurement.value;
        try {
          expect(
            unlocked.keys.toSet(),
            selected.map((r) => r.profileId).toSet(),
          );
          for (final record in selected) {
            final session = unlocked[record.profileId]!;
            expect(session.generationId, generation);
            expect(session.profileId, record.profileId);
            expect(session.keyId, record.keyId);
            expect(
              await session.key.extractBytes(),
              await originalKeys[record.profileId]!.extractBytes(),
            );
          }
          samples['profiles_$count'] = measurement.metrics;
        } finally {
          for (final session in unlocked.values) {
            session.destroy();
          }
        }
      }

      final rejected = await service.unlockMatching(
        generationId: generation,
        records: records,
        passphrase: 'incorrect synthetic passphrase',
      );
      try {
        expect(rejected, isEmpty);
      } finally {
        for (final key in rejected.values) {
          key.destroy();
        }
      }

      // Timings are observations, never pass/fail thresholds. Keep one JSON
      // line so an expanded Flutter test log can be archived and compared.
      final report = {
        'environment': {
          'kind': 'host_flutter_test',
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'dart': Platform.version,
          'processors': Platform.numberOfProcessors,
          'debug_mode': kDebugMode,
        },
        'kdf': records.first.toJson()['kdf'],
        'measurement': {
          'samples_per_profile_count': 1,
          'setup_and_correctness_checks_excluded': true,
          'timer_period_ms': _timerPeriod.inMilliseconds,
          'max_gap_includes_final_partial_interval': true,
        },
        'results': samples,
      };
      debugPrint(
        'SYNC_V2_KEY_PERFORMANCE ${jsonEncode(report)}',
        wrapWidth: null,
      );
    } finally {
      for (final key in originalKeys.values) {
        key.destroy();
      }
      admin.destroy();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

const _timerPeriod = Duration(milliseconds: 16);

Future<({T value, Map<String, Object> metrics})> _measure<T>(
  Future<T> Function() operation,
) async {
  final clock = Stopwatch()..start();
  var previousTick = 0;
  var maximumGap = 0;
  var timerTicks = 0;
  final timer = Timer.periodic(_timerPeriod, (_) {
    final now = clock.elapsedMicroseconds;
    maximumGap = math.max(maximumGap, now - previousTick);
    previousTick = now;
    timerTicks++;
  });
  try {
    final value = await operation();
    clock.stop();
    maximumGap = math.max(maximumGap, clock.elapsedMicroseconds - previousTick);
    return (
      value: value,
      metrics: {
        'elapsed_ms': clock.elapsedMicroseconds / 1000,
        'max_event_loop_gap_ms': maximumGap / 1000,
        'timer_ticks': timerTicks,
      },
    );
  } finally {
    timer.cancel();
    clock.stop();
  }
}
