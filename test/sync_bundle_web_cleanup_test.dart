@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('removes scratch bundle copies while retaining pending and selected bundles', () async {
    // Run in a browser so the store takes its Web path, using test preferences
    // because unit tests do not register the shared_preferences Web plugin.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const prefix = 'test.sync.cleanup';
    final store = SecureSyncBundleStore(
      encryptionService: EncryptionService(),
      syncBundleKeyService: SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: () => List<int>.filled(32, 1),
      ),
      webStorageKey: prefix,
    );
    final saved = <String, StoredSyncBundle>{};
    for (final name in [
      'downloaded_sync_bundle.enc',
      'pending_private_sync_bundle.enc',
      'replayed_sync_bundle.enc',
      'missing_attachment_repair_bundle.enc',
    ]) {
      saved[name] = await store.writeEncryptedBundlePayload(
        'test-ciphertext-$name',
        noteCount: 0,
        attachmentCount: 0,
        fileNameOverride: name,
      );
    }
    addTearDown(() async {
      for (final bundle in saved.values) {
        await prefs.remove(bundle.reference);
      }
    });
    expect(
      saved.values.map((bundle) => bundle.reference).toSet(),
      hasLength(4),
    );
    for (final name in [
      'replayed_sync_bundle.enc',
      'missing_attachment_repair_bundle.enc',
    ]) {
      await store.deleteStoredEncryptedBundle(fileNameOverride: name);
      expect(
        await store.readEncryptedBundlePayload(saved[name]!.reference),
        isNull,
      );
    }
    for (final name in [
      'downloaded_sync_bundle.enc',
      'pending_private_sync_bundle.enc',
    ]) {
      expect(
        await store.readEncryptedBundlePayload(saved[name]!.reference),
        'test-ciphertext-$name',
      );
    }
  });
}
