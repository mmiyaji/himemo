@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/device_identity_store.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';
import 'package:himemo/features/sync/data/sync_engine.dart';

// Snapshot preparation receives an explicit change set and must not access DB.
class _UnusedDatabase implements EncryptedNoteDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'browser prepares and encrypts a lazy attachment without isolates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secure = MemorySecureKeyValueStore();
      final encryption = EncryptionService();
      final master = MasterKeyService(
        secureStore: secure,
        keyFactory: encryption.generateKeyBytes,
      );
      final attachments = EncryptedAttachmentStore(
        encryptionService: encryption,
        masterKeyService: master,
      );
      final bytes = Uint8List.fromList([9, 8, 7, 6]);
      final reference = await attachments.storeAttachment(
        XFile.fromData(bytes, name: 'web.bin'),
        type: AttachmentType.file,
      );
      final note = NoteEntry(
        id: 'web-note',
        vaultId: 'everyday',
        title: 'Web demo',
        body: '',
        createdAt: DateTime.utc(2026),
        attachments: [
          NoteAttachment(
            type: AttachmentType.file,
            label: 'web.bin',
            filePath: reference,
          ),
        ],
      );
      final engine = SyncEngine(
        database: _UnusedDatabase(),
        attachmentStore: attachments,
        deviceIdentityStore: DeviceIdentityStore(),
      );
      final snapshot = await engine.prepareSnapshot(
        [note],
        pendingChanges: [
          PendingNoteChangeRecord(
            noteId: note.id,
            vaultId: note.vaultId,
            revision: 1,
            action: PendingNoteChangeAction.upsert,
            queuedAt: note.createdAt,
          ),
        ],
      );
      expect(snapshot.attachments.single.bytesBase64, isEmpty);
      final bundleStore = SecureSyncBundleStore(
        encryptionService: encryption,
        syncBundleKeyService: SyncBundleKeyService(
          secureStore: secure,
          keyFactory: encryption.generateKeyBytes,
        ),
        attachmentStore: attachments,
      );
      final payload = await bundleStore.writeAttachmentObjectPayload(
        snapshot.attachments.single,
      );
      final decoded = await bundleStore.readAttachmentObjectPayload(payload);
      expect(base64Decode(decoded['bytesBase64'] as String), bytes);
    },
  );
}
