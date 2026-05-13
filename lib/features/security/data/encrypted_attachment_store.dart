import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/domain/note_entry.dart';
import 'encryption_service.dart';
import 'master_key_service.dart';
import 'profile_data_key_service.dart';
import 'web_attachment_payload_store_stub.dart'
    if (dart.library.html) 'web_attachment_payload_store_web.dart';

class EncryptedAttachmentStore {
  EncryptedAttachmentStore({
    required EncryptionService encryptionService,
    required MasterKeyService masterKeyService,
    ProfileDataKeyService? profileDataKeyService,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.webPrefix = 'secure-attachment://',
    this.webStoragePrefix = 'attachments.encrypted.',
    this.vaultStoragePrefix = 'attachments.vault.',
    WebAttachmentPayloadStore? webPayloadStore,
  }) : _encryptionService = encryptionService,
       _masterKeyService = masterKeyService,
       _profileDataKeyService = profileDataKeyService,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance,
       _webPayloadStore = webPayloadStore ?? WebAttachmentPayloadStore();

  final EncryptionService _encryptionService;
  final MasterKeyService _masterKeyService;
  final ProfileDataKeyService? _profileDataKeyService;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final WebAttachmentPayloadStore _webPayloadStore;
  final String webPrefix;
  final String webStoragePrefix;
  final String vaultStoragePrefix;
  static const _webIndexedDbMarker = 'indexeddb:';
  static const _materializedDeleteMarkerExtension = '.himemo-delete-after';

  Future<String?> storeAttachment(
    XFile sourceFile, {
    required AttachmentType type,
  }) async {
    final bytes = await sourceFile.readAsBytes();
    final key = await _masterKeyService.obtainOrCreate();
    final encrypted = await _encryptionService.encryptBytes(
      clearBytes: bytes,
      secretKey: key,
      additionalData: _aad(type),
    );

    if (kIsWeb) {
      final id = _attachmentId(type, sourceFile.name);
      final prefs = await _sharedPreferencesProvider();
      await _writeWebPayload(id, encrypted, prefs);
      final reference = '$webPrefix$id';
      await prefs.setString('$vaultStoragePrefix$reference', 'everyday');
      return reference;
    }

    final directory = await _directoryProvider();
    final fileName = _attachmentId(type, sourceFile.name);
    final file = File(path.join(directory.path, 'attachments', fileName));
    await file.create(recursive: true);
    await file.writeAsString(encrypted, flush: true);
    final prefs = await _sharedPreferencesProvider();
    await prefs.setString('$vaultStoragePrefix${file.path}', 'everyday');
    return file.path;
  }

  Future<String?> storeEncryptedPayload({
    required String encodedPayload,
    required AttachmentType type,
    required String fileNameHint,
    String vaultId = 'everyday',
  }) async {
    if (kIsWeb) {
      final id = _attachmentId(type, fileNameHint);
      final prefs = await _sharedPreferencesProvider();
      await _writeWebPayload(id, encodedPayload, prefs);
      final reference = '$webPrefix$id';
      await prefs.setString('$vaultStoragePrefix$reference', vaultId);
      return reference;
    }

    final directory = await _directoryProvider();
    final fileName = _attachmentId(type, fileNameHint);
    final file = File(path.join(directory.path, 'attachments', fileName));
    await file.create(recursive: true);
    await file.writeAsString(encodedPayload, flush: true);
    final prefs = await _sharedPreferencesProvider();
    await prefs.setString('$vaultStoragePrefix${file.path}', vaultId);
    return file.path;
  }

  Future<String> encryptAttachmentBytes({
    required List<int> bytes,
    required AttachmentType type,
    String vaultId = 'everyday',
  }) async {
    final key = await _keyForVault(vaultId);
    if (key == null) {
      throw StateError('Attachment key is unavailable for $vaultId.');
    }
    return _encryptionService.encryptBytes(
      clearBytes: bytes,
      secretKey: key,
      additionalData: _aad(type),
    );
  }

  Future<List<int>?> readAttachment(
    String storedReference, {
    required AttachmentType type,
  }) async {
    final encrypted = await _readPayload(storedReference);
    if (encrypted == null || encrypted.isEmpty) {
      return null;
    }
    final vaultId = await _attachmentVaultId(storedReference);
    final key = await _keyForVault(vaultId);
    if (key == null) {
      throw StateError('Attachment key is unavailable for $vaultId.');
    }
    try {
      return await _encryptionService.decryptBytes(
        encodedPayload: encrypted,
        secretKey: key,
        additionalData: _aad(type),
      );
    } catch (_) {
      if (vaultId == 'everyday') {
        rethrow;
      }
      final normalKey = await _masterKeyService.obtainOrCreate();
      return _encryptionService.decryptBytes(
        encodedPayload: encrypted,
        secretKey: normalKey,
        additionalData: _aad(type),
      );
    }
  }

  Future<String?> materializeDecryptedFile(
    String storedReference, {
    required AttachmentType type,
    String? preferredFileName,
  }) async {
    if (kIsWeb) {
      return null;
    }
    final bytes = await readAttachment(storedReference, type: type);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final directory = await _directoryProvider();
    final extension = preferredFileName == null
        ? path.extension(storedReference.replaceAll('.enc', ''))
        : path.extension(preferredFileName);
    final tempName =
        '${DateTime.now().microsecondsSinceEpoch}_${type.name}${extension.isEmpty ? '' : extension}';
    final file = File(
      path.join(directory.path, 'attachments', 'tmp', tempName),
    );
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String?> materializeDecryptedBytes(
    List<int> bytes, {
    required AttachmentType type,
    String? preferredFileName,
  }) async {
    if (kIsWeb || bytes.isEmpty) {
      return null;
    }
    final directory = await _directoryProvider();
    final extension = preferredFileName == null
        ? ''
        : path.extension(preferredFileName);
    final tempName =
        '${DateTime.now().microsecondsSinceEpoch}_${type.name}${extension.isEmpty ? '.bin' : extension}';
    final file = File(
      path.join(directory.path, 'attachments', 'tmp', tempName),
    );
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteAttachment(String storedReference) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      await _webPayloadStore.delete(id);
      await prefs.remove('$webStoragePrefix$id');
      await prefs.remove('$vaultStoragePrefix$storedReference');
      return;
    }

    if (kIsWeb) {
      return;
    }

    final file = await _resolveStoredFile(storedReference);
    if (await file.exists()) {
      await file.delete();
    }
    final prefs = await _sharedPreferencesProvider();
    await prefs.remove('$vaultStoragePrefix$storedReference');
  }

  Future<void> protectAttachmentForVault(
    String storedReference, {
    required AttachmentType type,
    required String vaultId,
  }) async {
    final currentVaultId = await _attachmentVaultId(storedReference);
    if (currentVaultId == vaultId) {
      return;
    }
    final bytes = await readAttachment(storedReference, type: type);
    if (bytes == null) {
      return;
    }
    final key = await _keyForVault(vaultId);
    if (key == null) {
      throw StateError('Attachment key is unavailable for $vaultId.');
    }
    final encrypted = await _encryptionService.encryptBytes(
      clearBytes: bytes,
      secretKey: key,
      additionalData: _aad(type),
    );
    await _writePayload(storedReference, encrypted);
    final prefs = await _sharedPreferencesProvider();
    await prefs.setString('$vaultStoragePrefix$storedReference', vaultId);
  }

  Future<void> deleteMaterializedFile(String filePath) async {
    if (kIsWeb) {
      return;
    }
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    final marker = File(_materializedDeleteMarkerPath(filePath));
    if (await marker.exists()) {
      await marker.delete();
    }
  }

  Future<void> markMaterializedFileForCleanup(
    String filePath, {
    required DateTime deleteAfter,
  }) async {
    if (kIsWeb || filePath.isEmpty) {
      return;
    }
    await cleanupExpiredMaterializedFiles();
    final file = File(filePath);
    if (!await file.exists()) {
      return;
    }
    final marker = File(_materializedDeleteMarkerPath(filePath));
    await marker.create(recursive: true);
    await marker.writeAsString(deleteAfter.toUtc().toIso8601String());
  }

  Future<int> cleanupExpiredMaterializedFiles({DateTime? now}) async {
    if (kIsWeb) {
      return 0;
    }
    final directory = await _directoryProvider();
    final tmpDirectory = Directory(
      path.join(directory.path, 'attachments', 'tmp'),
    );
    if (!await tmpDirectory.exists()) {
      return 0;
    }
    final nowUtc = (now ?? DateTime.now()).toUtc();
    var deletedCount = 0;
    await for (final entity in tmpDirectory.list()) {
      if (entity is! File ||
          !entity.path.endsWith(_materializedDeleteMarkerExtension)) {
        continue;
      }
      final targetPath = entity.path.substring(
        0,
        entity.path.length - _materializedDeleteMarkerExtension.length,
      );
      try {
        final deleteAfter = DateTime.tryParse(await entity.readAsString());
        final target = File(targetPath);
        if (deleteAfter == null || !await target.exists()) {
          await entity.delete();
          continue;
        }
        if (deleteAfter.toUtc().isAfter(nowUtc)) {
          continue;
        }
        await target.delete();
        await entity.delete();
        deletedCount += 1;
      } catch (_) {}
    }
    return deletedCount;
  }

  Future<int> storagePayloadSizeBytes() async {
    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      var total = 0;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(webStoragePrefix)) {
          continue;
        }
        final value = prefs.getString(key) ?? '';
        if (value.startsWith(_webIndexedDbMarker)) {
          final id = value.substring(_webIndexedDbMarker.length);
          total += utf8.encode(await _webPayloadStore.get(id) ?? '').length;
        } else {
          total += utf8.encode(value).length;
        }
      }
      return total;
    }

    final directory = await _directoryProvider();
    final attachmentsDirectory = Directory(
      path.join(directory.path, 'attachments'),
    );
    if (!await attachmentsDirectory.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in attachmentsDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      if (path.split(entity.path).contains('tmp')) {
        continue;
      }
      total += await entity.length();
    }
    return total;
  }

  String _materializedDeleteMarkerPath(String filePath) {
    return '$filePath$_materializedDeleteMarkerExtension';
  }

  Future<int?> attachmentByteLength(
    String storedReference, {
    required AttachmentType type,
  }) async {
    final bytes = await readAttachment(storedReference, type: type);
    return bytes?.length;
  }

  Future<Map<String, Object?>> storedPayloadDiagnostics(
    String storedReference,
  ) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      final stored = prefs.getString('$webStoragePrefix$id');
      String? payload;
      if (stored != null && stored.startsWith(_webIndexedDbMarker)) {
        payload = await _webPayloadStore.get(
          stored.substring(_webIndexedDbMarker.length),
        );
      } else {
        payload = stored;
      }
      return {
        'payloadLocation': 'web',
        'payloadExists': payload != null,
        'encryptedPayloadChars': payload?.length,
      };
    }

    if (kIsWeb) {
      return const {
        'payloadLocation': 'unsupported-web-reference',
        'payloadExists': false,
      };
    }

    final originalFile = File(storedReference);
    final originalExists = await originalFile.exists();
    final resolvedFile = await _resolveStoredFile(storedReference);
    final resolvedExists = await resolvedFile.exists();
    int? resolvedBytes;
    int? encryptedPayloadChars;
    if (resolvedExists) {
      resolvedBytes = await resolvedFile.length();
      encryptedPayloadChars = (await resolvedFile.readAsString()).length;
    }
    return {
      'payloadLocation': 'file',
      'originalFileExists': originalExists,
      'resolvedFileExists': resolvedExists,
      'resolvedFileRef': path.basename(resolvedFile.path),
      'encryptedFileBytes': resolvedBytes,
      'encryptedPayloadChars': encryptedPayloadChars,
    };
  }

  Future<int> deleteUnreferencedAttachments(
    Set<String> retainedReferences,
  ) async {
    var deletedCount = 0;
    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      final references = <String>[];
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(webStoragePrefix)) {
          continue;
        }
        final id = key.substring(webStoragePrefix.length);
        final reference = '$webPrefix$id';
        if (!retainedReferences.contains(reference)) {
          references.add(reference);
        }
      }
      for (final reference in references) {
        await deleteAttachment(reference);
        deletedCount += 1;
      }
      return deletedCount;
    }

    final directory = await _directoryProvider();
    final attachmentsDirectory = Directory(
      path.join(directory.path, 'attachments'),
    );
    if (!await attachmentsDirectory.exists()) {
      return 0;
    }
    await for (final entity in attachmentsDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      if (path.split(entity.path).contains('tmp')) {
        continue;
      }
      if (retainedReferences.contains(entity.path)) {
        continue;
      }
      if (retainedReferences.any(
        (reference) => path.basename(reference) == path.basename(entity.path),
      )) {
        continue;
      }
      await entity.delete();
      final prefs = await _sharedPreferencesProvider();
      await prefs.remove('$vaultStoragePrefix${entity.path}');
      deletedCount += 1;
    }
    return deletedCount;
  }

  Future<String?> _readPayload(String storedReference) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      return _readWebPayload(id, prefs);
    }

    if (kIsWeb) {
      return null;
    }

    final file = await _resolveStoredFile(storedReference);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  Future<void> _writePayload(String storedReference, String payload) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      await _writeWebPayload(id, payload, prefs);
      return;
    }

    if (kIsWeb) {
      return;
    }

    final file = await _resolveStoredFile(storedReference);
    await file.create(recursive: true);
    await file.writeAsString(payload, flush: true);
  }

  Future<String?> readStoredPayload(String storedReference) {
    return _readPayload(storedReference);
  }

  Future<void> _writeWebPayload(
    String id,
    String payload,
    SharedPreferences prefs,
  ) async {
    await _webPayloadStore.put(id, payload);
    await prefs.setString('$webStoragePrefix$id', '$_webIndexedDbMarker$id');
  }

  Future<String?> _readWebPayload(String id, SharedPreferences prefs) async {
    final stored = prefs.getString('$webStoragePrefix$id');
    if (stored == null || stored.isEmpty) {
      return null;
    }
    if (!stored.startsWith(_webIndexedDbMarker)) {
      return stored;
    }
    return _webPayloadStore.get(stored.substring(_webIndexedDbMarker.length));
  }

  Future<String> _attachmentVaultId(String storedReference) async {
    final prefs = await _sharedPreferencesProvider();
    final exact = prefs.getString('$vaultStoragePrefix$storedReference');
    if (exact != null && exact.isNotEmpty) {
      return exact;
    }
    final fileName = path.basename(storedReference);
    if (fileName.isEmpty || fileName == storedReference) {
      return 'everyday';
    }
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(vaultStoragePrefix)) {
        continue;
      }
      final reference = key.substring(vaultStoragePrefix.length);
      if (path.basename(reference) == fileName) {
        return prefs.getString(key) ?? 'everyday';
      }
    }
    return 'everyday';
  }

  Future<SecretKey?> _keyForVault(String vaultId) {
    final profileDataKeyService = _profileDataKeyService;
    if (profileDataKeyService != null) {
      return profileDataKeyService.keyForVault(vaultId);
    }
    return _masterKeyService.obtainOrCreate();
  }

  Future<File> _resolveStoredFile(String storedReference) async {
    final file = File(storedReference);
    if (await file.exists()) {
      return file;
    }

    // iOS can change the app container path across app updates. Older notes
    // may keep an absolute path into the previous container, while the file was
    // migrated by the OS into the new Application Support directory.
    final fileName = path.basename(storedReference);
    if (fileName.isEmpty || fileName == storedReference) {
      return file;
    }
    final directory = await _directoryProvider();
    return File(path.join(directory.path, 'attachments', fileName));
  }

  String _attachmentId(AttachmentType type, String name) {
    final extension = path.extension(name);
    final suffix = extension.isEmpty ? '.bin' : extension;
    return '${DateTime.now().microsecondsSinceEpoch}_${type.name}$suffix.enc';
  }

  List<int> _aad(AttachmentType type) => type.name.codeUnits;
}
