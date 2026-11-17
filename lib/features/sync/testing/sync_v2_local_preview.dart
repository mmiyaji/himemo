// Development-only local V2 workspace support; not imported by production.
import 'package:drift/drift.dart' show Variable;
import 'package:himemo/features/security/data/encrypted_note_database_executor.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

/// This registry holds only the encrypted registration proof. Recovery and
/// administrator credentials remain in the process-local secure store.
class LocalPreviewRegistration
    implements SyncV2GenerationRegistrationTransport {
  LocalPreviewRegistration(this.inbox);
  final SyncV2Inbox inbox;
  static const account = 'himemo-web-local-preview';

  Future<void> _ensureTable() => inbox.customStatement('''
    CREATE TABLE IF NOT EXISTS local_preview_registration (
      singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
      encrypted_proof TEXT NOT NULL
    )
  ''');

  @override
  Future<String> readCurrentAccountId() async => account;
  @override
  Future<void> prepareGeneration(String generationId) async {}
  @override
  Future<String?> readRegistration() async {
    await _ensureTable();
    final row = await inbox
        .customSelect(
          'SELECT encrypted_proof FROM local_preview_registration WHERE singleton = 1',
        )
        .getSingleOrNull();
    return row?.read<String>('encrypted_proof');
  }

  @override
  Future<void> publishRegistration(String encryptedProof) async {
    await _ensureTable();
    await inbox.transaction(() async {
      await inbox.customStatement(
        'INSERT OR IGNORE INTO local_preview_registration (singleton, encrypted_proof) VALUES (1, ?)',
        [encryptedProof],
      );
      final row = await inbox
          .customSelect(
            'SELECT encrypted_proof FROM local_preview_registration WHERE singleton = ?',
            variables: [Variable.withInt(1)],
          )
          .getSingle();
      if (row.read<String>('encrypted_proof') != encryptedProof) {
        throw const SyncV2RegistrationConflict();
      }
    });
  }
}

SyncV2WorkspaceController createLocalPreviewController() {
  final encryption = EncryptionService();
  final store = MemorySecureKeyValueStore();
  final enrollment = SyncV2EnrollmentStore(store);
  final headers = SyncV2HeaderCodec(encryption);
  final inbox = SyncV2Inbox(
    createSyncV2LocalPreviewDatabaseExecutor(),
    headers,
  );
  final registration = LocalPreviewRegistration(inbox);
  return SyncV2WorkspaceController(
    inbox: inbox,
    repository: SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    ),
    store: store,
    enrollments: enrollment,
    registrationTransport: registration,
    registrationFactory: (_) =>
        SyncV2GenerationRegistration(registration, enrollment),
    // Local database only: this does not publish, download or contact iCloud.
    syncOperation: () async => (
      headersStaged: false,
      hasMoreHeaders: false,
      downloadedPayloads: 0,
      publishedChanges: 0,
      errors: <String>[],
    ),
    activate: () async {},
    deactivate: () async {},
    supported: true,
    automaticSync: false,
  );
}
