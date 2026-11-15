@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';

void main() {
  test(
    'normal sessions authenticate all wrapper identities and key length',
    () async {
      final encryption = EncryptionService();
      final syncKey = SecretKey(List.filled(32, 9));
      Future<String> wrap(List<int> bytes) => encryption.encryptBytes(
        clearBytes: bytes,
        secretKey: syncKey,
        additionalData: utf8.encode(
          jsonEncode([
            'himemo-sync-v2-registration',
            1,
            'a',
            'g',
            'normal-sync-wrap',
            'p',
            'k',
          ]),
        ),
      );
      final wrapped = await wrap(List.filled(32, 7));
      final session = await SyncV2UnlockedProfileKey.unlockNormal(
        encryption: encryption,
        accountId: 'a',
        generationId: 'g',
        profileId: 'p',
        keyId: 'k',
        syncWrap: wrapped,
        syncKey: syncKey,
      );
      expect(
        [session.generationId, session.profileId, session.keyId],
        ['g', 'p', 'k'],
      );
      expect(await session.key.extractBytes(), List.filled(32, 7));
      session.destroy();
      for (var index = 0; index < 4; index++) {
        final ids = ['a', 'g', 'p', 'k'];
        ids[index] = 'altered';
        await expectLater(
          SyncV2UnlockedProfileKey.unlockNormal(
            encryption: encryption,
            accountId: ids[0],
            generationId: ids[1],
            profileId: ids[2],
            keyId: ids[3],
            syncWrap: wrapped,
            syncKey: syncKey,
          ),
          throwsA(isA<HimemoDecryptionException>()),
        );
      }
      await expectLater(
        SyncV2UnlockedProfileKey.unlockNormal(
          encryption: encryption,
          accountId: 'a',
          generationId: 'g',
          profileId: 'p',
          keyId: 'k',
          syncWrap: await wrap([7]),
          syncKey: syncKey,
        ),
        throwsFormatException,
      );
      syncKey.destroy();
    },
  );

  test('portable key format rejects unsupported and malformed records', () {
    final wrap = jsonEncode({
      'version': 1,
      'nonce': base64Encode(List.filled(12, 0)),
      'cipherText': base64Encode(List.filled(32, 0)),
      'mac': base64Encode(List.filled(16, 0)),
    });
    final record = SyncV2WrappedProfileKey(
      profileId: 'p',
      keyId: 'k',
      salt: base64Encode(List.filled(16, 0)),
      passphraseWrap: wrap,
      adminWrap: wrap,
    );
    final valid = record.toJson();
    expect(SyncV2WrappedProfileKey.fromJson(valid).toJson(), valid);
    for (final field in [
      'format',
      'version',
      'profileId',
      'keyId',
      'salt',
      'passphraseWrap',
      'adminWrap',
    ]) {
      for (final invalid in [null, '', 2, 'x' * 5000]) {
        expect(
          () => SyncV2WrappedProfileKey.fromJson({...valid, field: invalid}),
          throwsFormatException,
          reason: '$field=$invalid',
        );
      }
    }
    for (final field in (valid['kdf'] as Map).keys) {
      final kdf = Map<String, dynamic>.from(valid['kdf'] as Map);
      kdf[field as String] = field == 'algorithm' ? 'pbkdf2' : 1;
      expect(
        () => SyncV2WrappedProfileKey.fromJson({...valid, 'kdf': kdf}),
        throwsFormatException,
      );
    }
    expect(
      () => SyncV2WrappedProfileKey.fromJson({...valid, 'extra': true}),
      throwsFormatException,
    );
    expect(
      () => SyncV2WrappedProfileKey.fromJson({
        ...valid,
        'salt': base64UrlEncode(List.filled(16, 255)),
      }),
      throwsFormatException,
    );
    final malformed = jsonDecode(wrap) as Map<String, dynamic>;
    malformed['nonce'] = 'bad';
    expect(
      () => SyncV2WrappedProfileKey.fromJson({
        ...valid,
        'adminWrap': jsonEncode(malformed),
      }),
      throwsFormatException,
    );
  });

  test(
    'admin-only profile keys round-trip and never run password KDF',
    () async {
      const generation = 'generation-admin-only';
      final service = SyncV2ProfileKeys(EncryptionService());
      final profileKey = SecretKey(
        List<int>.generate(32, (index) => index + 4),
      );
      final adminKey = SecretKey(List<int>.filled(32, 71));
      final record = await service.wrapAdminOnly(
        generationId: generation,
        profileId: 'admin-profile',
        keyId: 'admin-key',
        profileKey: profileKey,
        adminKey: adminKey,
      );
      final json = record.toJson();
      expect(json.keys.toSet(), {
        'format',
        'version',
        'mode',
        'profileId',
        'keyId',
        'adminWrap',
      });
      expect(json['version'], 2);
      expect(json['mode'], 'admin-only');
      expect(json.containsKey('kdf'), isFalse);
      expect(json.containsKey('salt'), isFalse);
      expect(json.containsKey('passphraseWrap'), isFalse);

      final parsed = SyncV2WrappedProfileKey.fromJson(json);
      expect(parsed.toJson(), json);
      expect(parsed.adminOnly, isTrue);
      final unlocked = await service.unlockForAdmin(
        generationId: generation,
        record: parsed,
        adminKey: adminKey,
      );
      expect(await unlocked.extractBytes(), await profileKey.extractBytes());
      unlocked.destroy();
      await expectLater(
        service.unlockForAdmin(
          generationId: generation,
          record: parsed,
          adminKey: SecretKey(List<int>.filled(32, 72)),
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );

      // A password supplied to the private-profile flow cannot match this
      // record; skipping it also proves this call does not invoke Argon2id.
      expect(
        await service.unlockMatching(
          generationId: generation,
          records: [parsed],
          passphrase: 'any-private-password',
        ),
        isEmpty,
      );

      for (final invalid in [
        {...json, 'version': 3},
        {...json, 'mode': 'other'},
        {...json, 'extra': true},
        {...json, 'kdf': <String, Object>{}},
      ]) {
        expect(
          () => SyncV2WrappedProfileKey.fromJson(invalid),
          throwsFormatException,
        );
      }
      final invalidVersionType = {...json, 'version': 2.0};
      expect(
        () => SyncV2WrappedProfileKey.fromJson(invalidVersionType),
        throwsFormatException,
      );

      // Adding a password later emits the unchanged v1 record format, while
      // preserving the same raw profile key under its administrator wrapper.
      final passwordConfigured = await service.wrap(
        generationId: generation,
        profileId: 'admin-profile',
        keyId: 'admin-key',
        profileKey: profileKey,
        passphrase: 'new-private-password',
        adminKey: adminKey,
      );
      expect(passwordConfigured.toJson()['version'], 1);
      expect(passwordConfigured.toJson().keys.toSet(), {
        'format',
        'version',
        'kdf',
        'profileId',
        'keyId',
        'salt',
        'passphraseWrap',
        'adminWrap',
      });
      final migrated = await service.unlockForAdmin(
        generationId: generation,
        record: passwordConfigured,
        adminKey: adminKey,
      );
      expect(await migrated.extractBytes(), await profileKey.extractBytes());
      migrated.destroy();
      profileKey.destroy();
      adminKey.destroy();
    },
  );

  test('shared passphrase matches profiles and admin unwrap is generation-bound', () async {
    const generation = 'generation-1';
    final adminKey = SecretKey(List<int>.filled(32, 41));
    final service = SyncV2ProfileKeys(EncryptionService());
    final profileKeys = [
      SecretKey(List<int>.generate(32, (index) => index)),
      SecretKey(List<int>.generate(32, (index) => index + 32)),
      SecretKey(List<int>.generate(32, (index) => 255 - index)),
    ];

    final wrapped = <SyncV2WrappedProfileKey>[];
    for (var i = 0; i < profileKeys.length; i++) {
      wrapped.add(
        await service.wrap(
          generationId: generation,
          profileId: 'profile-${i + 1}',
          keyId: 'key-${i + 1}',
          profileKey: profileKeys[i],
          passphrase: i == 2 ? 'different passphrase' : 'shared passphrase',
          adminKey: adminKey,
        ),
      );
    }

    for (var i = 0; i < wrapped.length; i++) {
      wrapped[i] = SyncV2WrappedProfileKey.fromJson(
        jsonDecode(jsonEncode(wrapped[i].toJson())) as Map<String, dynamic>,
      );
    }
    expect(wrapped.first.toJson()['kdf'], {
      'algorithm': 'argon2id',
      'algorithmVersion': 19,
      'memoryKiB': 65536,
      'iterations': 3,
      'parallelism': 4,
      'hashLength': 32,
    });
    for (final field in ['profileId', 'keyId']) {
      final altered = wrapped.first.toJson()..[field] = 'tampered';
      await expectLater(
        service.unlockForAdmin(
          generationId: generation,
          record: SyncV2WrappedProfileKey.fromJson(altered),
          adminKey: adminKey,
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
    }
    await expectLater(
      service.unlockMatching(
        generationId: generation,
        records: [wrapped.first, wrapped.first],
        passphrase: 'shared passphrase',
      ),
      throwsFormatException,
    );
    final sessions = await service.unlockMatchingSessions(
      generationId: generation,
      records: wrapped,
      passphrase: 'shared passphrase',
    );
    expect(sessions.keys, {'profile-1', 'profile-2'});
    for (final entry in sessions.entries) {
      expect(entry.value.generationId, generation);
      expect(entry.value.profileId, entry.key);
      expect(entry.value.keyId, entry.key.replaceFirst('profile', 'key'));
      expect(
        await entry.value.key.extractBytes(),
        await profileKeys[entry.key == 'profile-1' ? 0 : 1].extractBytes(),
      );
      entry.value.destroy();
    }
    final adminSession = await service.unlockForAdminSession(
      generationId: generation,
      record: wrapped[2],
      adminKey: adminKey,
    );
    expect(
      [adminSession.generationId, adminSession.profileId, adminSession.keyId],
      [generation, 'profile-3', 'key-3'],
    );
    expect(
      await adminSession.key.extractBytes(),
      await profileKeys[2].extractBytes(),
    );
    adminSession.destroy();
    final timer = Stopwatch()..start();
    var previousTick = 0;
    var maximumGap = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final elapsed = timer.elapsedMilliseconds;
      final gap = elapsed - previousTick;
      if (gap > maximumGap) maximumGap = gap;
      previousTick = elapsed;
    });
    final Map<String, SecretKey> matches;
    try {
      matches = await service.unlockMatching(
        generationId: generation,
        records: wrapped,
        passphrase: 'shared passphrase',
      );
      final tailGap = timer.elapsedMilliseconds - previousTick;
      if (tailGap > maximumGap) maximumGap = tailGap;
      debugPrint(
        'sync v2 key benchmark: profiles=3 elapsed_ms=${timer.elapsedMilliseconds} max_event_loop_gap_ms=$maximumGap web=$kIsWeb',
      );
    } finally {
      heartbeat.cancel();
    }
    expect(matches.keys, {'profile-1', 'profile-2'});
    expect(
      await matches['profile-1']!.extractBytes(),
      await profileKeys[0].extractBytes(),
    );
    expect(
      await matches['profile-2']!.extractBytes(),
      await profileKeys[1].extractBytes(),
    );

    final adminOpened = await service.unlockForAdmin(
      generationId: generation,
      record: wrapped[2],
      adminKey: adminKey,
    );
    expect(
      await adminOpened.extractBytes(),
      await profileKeys[2].extractBytes(),
    );

    await expectLater(
      service.unlockForAdmin(
        generationId: 'different-generation',
        record: wrapped[2],
        adminKey: adminKey,
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );
    await expectLater(
      service.unlockForAdmin(
        generationId: generation,
        record: wrapped[2],
        adminKey: SecretKey(List<int>.filled(32, 42)),
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );

    for (final key in matches.values) {
      key.destroy();
    }
    adminOpened.destroy();
    for (final key in profileKeys) {
      key.destroy();
    }
  });
}
