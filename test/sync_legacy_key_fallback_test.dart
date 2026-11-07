import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';

void main() {
  for (final malformedLegacy in [false, true]) {
    test(
      'fallback keeps the original decryption error (malformed legacy: $malformedLegacy)',
      () async {
        final secure = MemorySecureKeyValueStore();
        var creations = 0;
        final master = MasterKeyService(
          secureStore: secure,
          keyFactory: () {
            creations++;
            return List.filled(32, 7);
          },
        );
        if (malformedLegacy) {
          await secure.write('security.master_key.v1', 'invalid-encoding');
        }
        final encryption = EncryptionService();
        final sync = SyncBundleKeyService(
          secureStore: secure,
          keyFactory: () => List.filled(32, 1),
        );
        await sync.obtainOrCreate();
        final payload = await encryption.encryptJson(
          payload: {'notes': []},
          secretKey: SecretKey(List.filled(32, 2)),
        );
        final bundles = SecureSyncBundleStore(
          encryptionService: encryption,
          syncBundleKeyService: sync,
          legacyMasterKeyService: master,
        );
        await expectLater(
          bundles.readRemoteBundlePayloadJson(payload),
          throwsA(isA<HimemoDecryptionException>()),
        );
        expect(creations, 0);
        expect(
          await secure.read('security.master_key.v1'),
          malformedLegacy ? 'invalid-encoding' : isNull,
        );
      },
    );
  }
}
