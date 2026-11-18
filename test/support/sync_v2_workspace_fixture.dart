import 'package:drift/native.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_session.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_preview.dart';

Future<SyncV2WorkspaceController> createSyncV2TestWorkspace({
  bool register = true,
  Future<SyncV2ICloudProgress> Function()? syncOperation,
}) async {
  final encryption = EncryptionService();
  final store = MemorySecureKeyValueStore();
  final headers = SyncV2HeaderCodec(encryption);
  final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
  final registration = LocalPreviewRegistration(inbox);
  final enrollments = SyncV2EnrollmentStore(store);
  final controller = SyncV2WorkspaceController(
    inbox: inbox,
    repository: SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    ),
    store: store,
    enrollments: enrollments,
    registrationTransport: registration,
    registrationFactory: (_) =>
        SyncV2GenerationRegistration(registration, enrollments),
    syncOperation:
        syncOperation ??
        () async => (
          headersStaged: false,
          hasMoreHeaders: false,
          downloadedPayloads: 0,
          publishedChanges: 0,
          errors: <String>[],
        ),
    supported: true,
    automaticSync: false,
  );
  await controller.initialize();
  if (register) {
    await controller.prepareNew('1234');
    await controller.confirmSetup();
  }
  return controller;
}
