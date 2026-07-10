import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';

void main() {
  test('existing export does not create a recovery key', () async {
    var factoryCalls = 0;
    final service = SyncBundleKeyService(
      secureStore: MemorySecureKeyValueStore(),
      keyFactory: () {
        factoryCalls += 1;
        return List<int>.filled(32, 1);
      },
    );

    expect(await service.exportExistingBackupCode(), isNull);
    expect(factoryCalls, 0);
  });

  test('rejects recovery keys that are not exactly 32 bytes', () {
    final service = SyncBundleKeyService(
      secureStore: MemorySecureKeyValueStore(),
      keyFactory: () => List<int>.filled(32, 1),
    );

    expect(
      () => service.previewBackupCodeFingerprint(
        '${SyncBundleKeyService.backupCodePrefix}${base64Encode(List<int>.filled(16, 1))}',
      ),
      throwsFormatException,
    );
  });

  test(
    'does not replace an existing local key with a different cloud key',
    () async {
      final local = List<int>.generate(32, (index) => index);
      final remote = List<int>.generate(32, (index) => 255 - index);
      final secureStore = MemorySecureKeyValueStore();
      await secureStore.write(
        'security.sync_bundle_key.v1',
        base64Encode(local),
      );
      final cloud = _MemoryCloudKeyStore(_backupCode(remote));
      final service = SyncBundleKeyService(
        secureStore: secureStore,
        cloudStore: cloud,
        keyFactory: () => List<int>.filled(32, 7),
      );

      await expectLater(service.requireExisting(), throwsStateError);
      expect(
        await secureStore.read('security.sync_bundle_key.v1'),
        base64Encode(local),
      );
    },
  );

  test(
    'accepts a matching legacy cloud key without rewriting local state',
    () async {
      final key = List<int>.generate(32, (index) => index + 10);
      final secureStore = MemorySecureKeyValueStore();
      await secureStore.write('security.sync_bundle_key.v1', base64Encode(key));
      final cloud = _MemoryCloudKeyStore(_backupCode(key));
      final service = SyncBundleKeyService(
        secureStore: secureStore,
        cloudStore: cloud,
        keyFactory: () => List<int>.filled(32, 7),
      );

      expect(await (await service.requireExisting()).extractBytes(), key);
      expect(
        await secureStore.read('security.sync_bundle_key.v1'),
        base64Encode(key),
      );
    },
  );

  test('rejects key factories that do not generate AES-256 keys', () async {
    final service = SyncBundleKeyService(
      secureStore: MemorySecureKeyValueStore(),
      keyFactory: () => List<int>.filled(24, 1),
    );

    await expectLater(service.obtainOrCreate(), throwsStateError);
  });

  test('compares all recovery-key bytes and keeps full fingerprints', () async {
    final first = List<int>.generate(32, (index) => index);
    final lastByteChanged = [...first]..[31] ^= 1;
    final service = SyncBundleKeyService(
      secureStore: MemorySecureKeyValueStore(),
      keyFactory: () => first,
    );

    expect(
      service.backupCodesMatch(_backupCode(first), _backupCode(first)),
      isTrue,
    );
    expect(
      service.backupCodesMatch(
        _backupCode(first),
        _backupCode(lastByteChanged),
      ),
      isFalse,
    );
    expect(await service.fullFingerprint(), hasLength(64));
  });
}

String _backupCode(List<int> bytes) {
  return '${SyncBundleKeyService.backupCodePrefix}${base64Encode(bytes)}';
}

class _MemoryCloudKeyStore implements CloudSyncBundleKeyStore {
  _MemoryCloudKeyStore(this.value);

  String? value;
  @override
  Future<String?> readBackupCode() async => value;
}
