import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('measures profile key unlock latency and event loop delay', (
    _,
  ) async {
    final service = SyncV2ProfileKeys(EncryptionService());
    final admin = SecretKey(List<int>.filled(32, 1));
    final profile = SecretKey(List<int>.filled(32, 2));
    final records = <SyncV2WrappedProfileKey>[];
    for (var index = 0; index < 3; index++) {
      records.add(
        await service.wrap(
          generationId: 'benchmark',
          profileId: 'profile-$index',
          keyId: 'key',
          profileKey: profile,
          passphrase: 'synthetic benchmark passphrase',
          adminKey: admin,
        ),
      );
    }
    final results = <String, Object>{};
    for (final count in [1, 3]) {
      final clock = Stopwatch()..start();
      var previousTick = 0;
      var maximumGap = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final elapsed = clock.elapsedMilliseconds;
        final gap = elapsed - previousTick;
        if (gap > maximumGap) maximumGap = gap;
        previousTick = elapsed;
      });
      try {
        final matched = await service.unlockMatching(
          generationId: 'benchmark',
          records: records.take(count),
          passphrase: 'synthetic benchmark passphrase',
        );
        final tailGap = clock.elapsedMilliseconds - previousTick;
        if (tailGap > maximumGap) maximumGap = tailGap;
        expect(matched, hasLength(count));
        for (final key in matched.values) {
          key.destroy();
        }
        results['profiles_$count'] = {
          'elapsed_ms': clock.elapsedMilliseconds,
          'max_event_loop_gap_ms': maximumGap,
        };
      } finally {
        timer.cancel();
      }
    }
    binding.reportData = results;
    profile.destroy();
    admin.destroy();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
