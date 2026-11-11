@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';
import 'package:himemo/features/sync/data/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'web bundle slots isolate cached private payloads from replay',
    () async {
      SharedPreferences.setMockInitialValues({});
      final encryption = EncryptionService();
      final store = SecureSyncBundleStore(
        encryptionService: encryption,
        syncBundleKeyService: SyncBundleKeyService(
          secureStore: MemorySecureKeyValueStore(),
          keyFactory: encryption.generateKeyBytes,
        ),
      );
      Future<String> payload(String deviceId) async {
        final bundle = await store.writeBundle(
          PreparedSyncSnapshot(
            deviceId: deviceId,
            exportedAt: DateTime.utc(2026),
            summary: const SyncQueueSummary(
              totalChanges: 0,
              upserts: 0,
              deletes: 0,
            ),
            notes: const [],
            attachments: const [],
          ),
        );
        return (await store.readEncryptedBundlePayload(bundle.reference))!;
      }

      const pendingSlot = 'pending_private_sync_bundle.enc';
      const legacySlot = 'downloaded_sync_bundle.enc';
      final pending = await payload('pending');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(store.webStorageKey, pending);
      await store.writeEncryptedBundlePayload(
        pending,
        noteCount: 0,
        attachmentCount: 0,
        fileNameOverride: pendingSlot,
      );
      final replay = await payload('replay');
      final outgoing = await store.readStoredEncryptedBundle();
      expect(
        await store.readEncryptedBundlePayload(outgoing!.reference),
        replay,
      );
      await store.writeEncryptedBundlePayload(
        replay,
        noteCount: 0,
        attachmentCount: 0,
        fileNameOverride: 'replayed_sync_bundle.enc',
      );
      final restored = await store.readStoredEncryptedBundle(
        fileNameOverride: pendingSlot,
      );
      expect(
        await store.readEncryptedBundlePayload(restored!.reference),
        pending,
      );
      expect(
        await store.readStoredEncryptedBundle(fileNameOverride: legacySlot),
        isNull,
      );
      final legacy = await store.readStoredEncryptedBundle(
        fileNameOverride: legacySlot,
        allowLegacyWebKey: true,
      );
      expect(
        await store.readEncryptedBundlePayload(legacy!.reference),
        pending,
      );
    },
  );
}
