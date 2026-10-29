import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../security/data/encryption_service.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/master_key_service.dart';
import 'google_drive_sync_transport.dart' show SyncBundleKind;
import 'sync_engine.dart';
import 'sync_bundle_key_service.dart';
import 'sync_exclusion_retention.dart';
import 'sync_bundle_coverage.dart';

class StoredSyncBundle {
  const StoredSyncBundle({
    required this.reference,
    required this.noteCount,
    required this.attachmentCount,
  });

  final String reference;
  final int noteCount;
  final int attachmentCount;
}

class SecureSyncBundleStore {
  SecureSyncBundleStore({
    required this._encryptionService,
    required this._syncBundleKeyService,
    this.attachmentStore,
    this._legacyMasterKeyService,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.webStorageKey = 'sync.bundle.latest',
    this.fileName = 'latest_sync_bundle.enc',
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final EncryptionService _encryptionService;
  final SyncBundleKeyService _syncBundleKeyService;
  final EncryptedAttachmentStore? attachmentStore;
  final MasterKeyService? _legacyMasterKeyService;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String webStorageKey;
  final String fileName;

  Future<StoredSyncBundle> writeBundle(
    PreparedSyncSnapshot snapshot, {
    List<Map<String, dynamic>> privateProfiles = const <Map<String, dynamic>>[],
    List<PreparedEncryptedPrivateSyncNote> encryptedPrivateNotes =
        const <PreparedEncryptedPrivateSyncNote>[],
    bool inlineAttachments = false,
    String bundleKind = SyncBundleKind.full,
    SyncExclusionRetention? exclusionRetention,
    SyncBundleCoverage? coverage,
    String? uploadId,
    Map<String, String> uploadReceipts = const {},
  }) async {
    final key = await _syncBundleKeyService.obtainOrCreate();
    final payload = await _encryptSyncBundleJson(
      payload: await _syncBundlePayload(
        snapshot,
        privateProfiles: privateProfiles,
        encryptedPrivateNotes: encryptedPrivateNotes,
        inlineAttachments: inlineAttachments,
        bundleKind: bundleKind,
        exclusionRetention: exclusionRetention,
        coverage: coverage,
        uploadId: uploadId,
        uploadReceipts: uploadReceipts,
      ),
      secretKey: key,
    );

    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      await prefs.setString(webStorageKey, payload);
      return StoredSyncBundle(
        reference: webStorageKey,
        noteCount: snapshot.notes.length + encryptedPrivateNotes.length,
        attachmentCount: snapshot.attachments.length,
      );
    }

    final directory = await _directoryProvider();
    final file = File(path.join(directory.path, 'sync_exports', fileName));
    await file.create(recursive: true);
    await file.writeAsString(payload, flush: true);
    return StoredSyncBundle(
      reference: file.path,
      noteCount: snapshot.notes.length + encryptedPrivateNotes.length,
      attachmentCount: snapshot.attachments.length,
    );
  }

  Future<String?> readEncryptedBundlePayload(String reference) async {
    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      return prefs.getString(reference);
    }
    final file = File(reference);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  Future<StoredSyncBundle> writeEncryptedBundlePayload(
    String encodedPayload, {
    required int noteCount,
    required int attachmentCount,
    String? fileNameOverride,
  }) async {
    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      await prefs.setString(webStorageKey, encodedPayload);
      return StoredSyncBundle(
        reference: webStorageKey,
        noteCount: noteCount,
        attachmentCount: attachmentCount,
      );
    }

    final directory = await _directoryProvider();
    final file = File(
      path.join(directory.path, 'sync_exports', fileNameOverride ?? fileName),
    );
    await file.create(recursive: true);
    await file.writeAsString(encodedPayload, flush: true);
    return StoredSyncBundle(
      reference: file.path,
      noteCount: noteCount,
      attachmentCount: attachmentCount,
    );
  }

  Future<StoredSyncBundle?> readStoredEncryptedBundle({
    String? fileNameOverride,
  }) async {
    final reference = kIsWeb
        ? webStorageKey
        : path.join(
            (await _directoryProvider()).path,
            'sync_exports',
            fileNameOverride ?? fileName,
          );
    final encodedPayload = await readEncryptedBundlePayload(reference);
    if (encodedPayload == null || encodedPayload.isEmpty) {
      return null;
    }
    final decoded = await readBundleJson(reference);
    if (decoded == null) {
      return null;
    }
    final notes =
        (decoded['notes'] as List<dynamic>? ?? const <dynamic>[]).length;
    final encryptedPrivateNotes =
        (decoded['encryptedPrivateNotes'] as List<dynamic>? ??
                const <dynamic>[])
            .length;
    final attachments =
        (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[]).length;
    return StoredSyncBundle(
      reference: reference,
      noteCount: notes + encryptedPrivateNotes,
      attachmentCount: attachments,
    );
  }

  Future<String> writeAttachmentObjectPayload(
    PreparedSyncAttachment attachment,
  ) async {
    final key = await _syncBundleKeyService.obtainOrCreate();
    var bytesBase64 = attachment.bytesBase64;
    var encryptedPayload = attachment.encryptedPayload;
    if (encryptedPayload == null && attachment.encryptedFilePath != null) {
      final store = attachmentStore;
      if (store == null) {
        throw StateError(
          'Attachment store is required to read encrypted upload payload.',
        );
      }
      encryptedPayload = await store.readStoredPayload(
        attachment.encryptedFilePath!,
      );
      if (encryptedPayload == null || encryptedPayload.isEmpty) {
        throw StateError('Local encrypted attachment payload is unavailable.');
      }
      _verifyAttachmentContentHash(attachment, utf8.encode(encryptedPayload));
    }
    if (bytesBase64.isEmpty && attachment.filePath != null) {
      final store = attachmentStore;
      if (store == null) {
        throw StateError(
          'Attachment store is required to read upload payload.',
        );
      }
      final bytes = await store.readAttachment(
        attachment.filePath!,
        type: attachment.type,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Local attachment payload is no longer available.');
      }
      _verifyAttachmentContentHash(attachment, bytes);
      bytesBase64 = base64Encode(bytes);
    }
    return _encryptSyncBundleJson(
      payload: {
        'objectVersion': 1,
        'kind': 'attachment',
        'id': attachment.id,
        'contentHash': attachment.contentHash,
        'type': attachment.type.name,
        'label': attachment.label,
        'sizeBytes': attachment.sizeBytes,
        if (bytesBase64.isNotEmpty) 'bytesBase64': bytesBase64,
        if (encryptedPayload?.isNotEmpty == true)
          'encryptedPayload': encryptedPayload,
      },
      secretKey: key,
    );
  }

  Future<Map<String, dynamic>> readAttachmentObjectPayload(
    String encodedPayload,
  ) {
    return _decryptBundleJson(encodedPayload);
  }

  /// Verifies that a remote payload belongs to the current sync key without
  /// accepting the legacy device master-key fallback.
  Future<void> validateRemotePayloadWithSyncKey(String encodedPayload) async {
    final syncKey = await _syncBundleKeyService.requireExisting();
    await _decryptSyncBundleJson(
      encodedPayload: encodedPayload,
      secretKey: syncKey,
    );
  }

  Future<Map<String, dynamic>?> readBundleJson(String reference) async {
    final payload = await readEncryptedBundlePayload(reference);
    if (payload == null || payload.isEmpty) {
      return null;
    }
    return _decryptBundleJson(payload);
  }

  /// Decrypts a downloaded bundle payload without first writing it to the
  /// local "latest bundle" slot. Conflict review uses this to inspect older
  /// delta records while keeping the actual latest bundle selected.
  Future<Map<String, dynamic>> readRemoteBundlePayloadJson(
    String encodedPayload,
  ) {
    return _decryptBundleJson(encodedPayload);
  }

  Future<Map<String, dynamic>> _decryptBundleJson(String payload) async {
    final syncKey = await _syncBundleKeyService.requireExisting();
    try {
      return await _decryptSyncBundleJson(
        encodedPayload: payload,
        secretKey: syncKey,
      );
    } catch (error, stackTrace) {
      final legacy = _legacyMasterKeyService;
      if (legacy == null) {
        rethrow;
      }
      try {
        final legacyKey = await legacy.readExisting();
        if (legacyKey == null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        return await _decryptSyncBundleJson(
          encodedPayload: payload,
          secretKey: legacyKey,
        );
      } catch (_) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Future<Map<String, dynamic>> _syncBundlePayload(
    PreparedSyncSnapshot snapshot, {
    required List<Map<String, dynamic>> privateProfiles,
    required List<PreparedEncryptedPrivateSyncNote> encryptedPrivateNotes,
    required bool inlineAttachments,
    required String bundleKind,
    SyncExclusionRetention? exclusionRetention,
    SyncBundleCoverage? coverage,
    String? uploadId,
    Map<String, String> uploadReceipts = const {},
  }) async {
    final attachments = <Map<String, dynamic>>[];
    for (final attachment in snapshot.attachments) {
      var payload = attachment;
      if (inlineAttachments &&
          payload.bytesBase64.isEmpty &&
          payload.filePath != null) {
        final store = attachmentStore;
        if (store == null) {
          throw StateError('Attachment store is required for inline export.');
        }
        final bytes = await store.readAttachment(
          payload.filePath!,
          type: payload.type,
        );
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Local attachment payload is no longer available.');
        }
        payload = PreparedSyncAttachment(
          id: payload.id,
          type: payload.type,
          label: payload.label,
          bytesBase64: base64Encode(bytes),
          encryptedPayload: payload.encryptedPayload,
          contentHash: payload.contentHash,
          sizeBytes: payload.sizeBytes,
        );
      } else if (inlineAttachments &&
          payload.encryptedPayload == null &&
          payload.encryptedFilePath != null) {
        final store = attachmentStore;
        if (store == null) {
          throw StateError('Attachment store is required for inline export.');
        }
        final encryptedPayload = await store.readStoredPayload(
          payload.encryptedFilePath!,
        );
        if (encryptedPayload == null || encryptedPayload.isEmpty) {
          throw StateError(
            'Local encrypted attachment payload is unavailable.',
          );
        }
        _verifyAttachmentContentHash(payload, utf8.encode(encryptedPayload));
        payload = PreparedSyncAttachment(
          id: payload.id,
          type: payload.type,
          label: payload.label,
          encryptedPayload: encryptedPayload,
          contentHash: payload.contentHash,
          sizeBytes: payload.sizeBytes,
        );
      }
      attachments.add(payload.toJson(inlineBytes: inlineAttachments));
    }
    return {
      'bundleVersion': inlineAttachments ? 2 : 3,
      'uploadId': ?uploadId,
      if (uploadId != null) 'syncProtocol': 2,
      if (uploadReceipts.isNotEmpty) 'uploadReceipts': uploadReceipts,
      'mode': 'changes',
      'bundleKind': bundleKind,
      if (exclusionRetention != null)
        'exclusionRetention': exclusionRetention.toJson(),
      if (coverage != null) 'coverage': coverage.toJson(),
      'deviceId': snapshot.deviceId,
      'exportedAt': snapshot.exportedAt.toIso8601String(),
      if (!inlineAttachments) 'attachmentStorage': 'objects',
      'summary': {
        'totalChanges': snapshot.summary.totalChanges,
        'upserts': snapshot.summary.upserts,
        'deletes': snapshot.summary.deletes,
        'lastQueuedAt': snapshot.summary.lastQueuedAt?.toIso8601String(),
      },
      'notes': [
        for (final entry in snapshot.notes)
          {'action': entry.action.name, 'note': entry.note.toJson()},
      ],
      'privateProfiles': privateProfiles,
      if (encryptedPrivateNotes.isNotEmpty)
        'encryptedPrivateNotes': [
          for (final entry in encryptedPrivateNotes) entry.toJson(),
        ],
      'attachments': attachments,
    };
  }

  void _verifyAttachmentContentHash(
    PreparedSyncAttachment attachment,
    List<int> bytes,
  ) {
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != attachment.contentHash) {
      throw StateError('sync.error.attachment_object_hash_mismatch');
    }
  }

  Future<String> _encryptSyncBundleJson({
    required Map<String, dynamic> payload,
    required SecretKey secretKey,
  }) async {
    if (kIsWeb) {
      return _encryptionService.encryptJson(
        payload: payload,
        secretKey: secretKey,
      );
    }
    final keyBytes = await secretKey.extractBytes();
    return Isolate.run(
      () => EncryptionService().encryptJson(
        payload: payload,
        secretKey: SecretKey(keyBytes),
      ),
    );
  }

  Future<Map<String, dynamic>> _decryptSyncBundleJson({
    required String encodedPayload,
    required SecretKey secretKey,
  }) async {
    if (kIsWeb) {
      return _encryptionService.decryptJson(
        encodedPayload: encodedPayload,
        secretKey: secretKey,
      );
    }
    final keyBytes = await secretKey.extractBytes();
    return Isolate.run(
      () => EncryptionService().decryptJson(
        encodedPayload: encodedPayload,
        secretKey: SecretKey(keyBytes),
      ),
    );
  }
}
