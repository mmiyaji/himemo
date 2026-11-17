import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../home/domain/note_entry.dart';
import '../../security/data/encrypted_attachment_store.dart';
import 'sync_v2_attachment_service.dart';
import 'sync_v2_note_store.dart';

/// The v1 viewers keep their file/temp-cache API. Drafts stay local and encrypted;
/// committed references are read through the v2 catalog and unlocked session.
class SyncV2AttachmentStore extends EncryptedAttachmentStore {
  SyncV2AttachmentStore({
    required super.encryptionService,
    required super.masterKeyService,
    required SyncV2NoteStoreSession? Function() session,
    required this._noteStore,
    Future<Directory> Function()? directoryProvider,
    Future<Directory> Function()? temporaryDirectoryProvider,
    super.sharedPreferencesProvider,
  }) : _session = session,
       super(
         directoryProvider: () async => Directory(
           path.join(
             (await (directoryProvider ?? getApplicationSupportDirectory)())
                 .path,
             'sync_v2_drafts',
           ),
         ),
         temporaryDirectoryProvider: () async => Directory(
           path.join(
             (await (temporaryDirectoryProvider ?? getTemporaryDirectory)())
                 .path,
             'sync_v2',
           ),
         ),
         webPrefix: 'v2-draft://',
         webStoragePrefix: 'attachments.v2.draft.',
         vaultStoragePrefix: 'attachments.v2.vault.',
         keyForVault: (vaultId) async {
           final current = session();
           if (current == null) throw SyncV2NoteStoreLocked(vaultId);
           final access =
               current.profiles[SyncV2NoteStore.profileIdFor(current, vaultId)];
           if (access == null) throw SyncV2NoteStoreLocked(vaultId);
           return access.key;
         },
       );

  final SyncV2NoteStoreSession? Function() _session;
  final SyncV2NoteStore Function() _noteStore;
  static const prefix = 'v2attachment:';

  void _checkSession(SyncV2NoteStoreSession? before) {
    final after = _session();
    if (before == null ||
        after == null ||
        before.generationId != after.generationId ||
        before.profiles.entries.any(
          (entry) => !identical(after.profiles[entry.key], entry.value),
        )) {
      throw const SyncV2NoteStoreLocked('attachment');
    }
  }

  @override
  Future<String?> storeAttachment(
    XFile sourceFile, {
    required AttachmentType type,
  }) async {
    final before = _session();
    _checkSession(before);
    if (await sourceFile.length() > SyncV2AttachmentService.maxBytes) {
      throw const FormatException('Attachments over 64 MiB are not supported.');
    }
    final result = await super.storeAttachment(sourceFile, type: type);
    _checkSession(before);
    return result;
  }

  @override
  Future<List<int>?> readAttachment(
    String storedReference, {
    required AttachmentType type,
  }) async {
    if (storedReference.startsWith(prefix)) {
      return _noteStore().readAttachment(
        storedReference.substring(prefix.length),
        type,
      );
    }
    final before = _session();
    _checkSession(before);
    final bytes = await super.readAttachment(storedReference, type: type);
    try {
      _checkSession(before);
      return bytes;
    } catch (_) {
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      rethrow;
    }
  }

  @override
  Future<void> protectAttachmentForVault(
    String storedReference, {
    required AttachmentType type,
    required String vaultId,
  }) async {
    final current = _session();
    if (current == null ||
        !current.profiles.containsKey(
          SyncV2NoteStore.profileIdFor(current, vaultId),
        )) {
      throw SyncV2NoteStoreLocked(vaultId);
    }
    if (storedReference.startsWith(prefix)) return;
    await super.protectAttachmentForVault(
      storedReference,
      type: type,
      vaultId: vaultId,
    );
    _checkSession(current);
  }

  // Chunks are immutable sync history and may be shared by other notes.
  @override
  Future<void> deleteAttachment(String storedReference) async {
    if (storedReference.startsWith(prefix)) return;
    await super.deleteAttachment(storedReference);
  }

  @override
  Future<StoredAttachmentPayloadMetadata?> storedPayloadMetadata(
    String storedReference,
  ) async {
    if (!storedReference.startsWith(prefix)) {
      return super.storedPayloadMetadata(storedReference);
    }
    try {
      final context = _noteStore().attachmentContext(
        storedReference.substring(prefix.length),
      );
      return StoredAttachmentPayloadMetadata(
        sizeBytes: context.reference.size,
        modifiedAtMillis: null,
      );
    } on SyncV2NoteStoreLocked {
      return null;
    }
  }

  @override
  Future<int?> estimateStoredAttachmentPayloadBytes(
    String storedReference,
  ) async {
    if (!storedReference.startsWith(prefix)) {
      return super.estimateStoredAttachmentPayloadBytes(storedReference);
    }
    return (await storedPayloadMetadata(storedReference))?.sizeBytes;
  }

  @override
  Future<Map<String, Object?>> storedPayloadDiagnostics(
    String storedReference,
  ) async {
    if (!storedReference.startsWith(prefix)) {
      return super.storedPayloadDiagnostics(storedReference);
    }
    return {
      'payloadLocation': 'sync-v2',
      'sizeBytes': (await storedPayloadMetadata(storedReference))?.sizeBytes,
    };
  }

  // Legacy sync must never publish staged or v2 ciphertext using its own format.
  @override
  Future<String?> readStoredPayload(String storedReference) async => null;

  @override
  Future<String?> storeEncryptedPayload({
    required String encodedPayload,
    required AttachmentType type,
    required String fileNameHint,
    String vaultId = 'everyday',
  }) async {
    throw UnsupportedError(
      'Legacy attachment payloads are disabled with Sync v2.',
    );
  }

  @override
  Future<bool> migrateLegacyPrivateAttachment(
    String storedReference, {
    required AttachmentType type,
    required String vaultId,
  }) async => false;
}
