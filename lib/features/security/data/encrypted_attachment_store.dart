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
  }) : _encryptionService = encryptionService,
       _masterKeyService = masterKeyService,
       _profileDataKeyService = profileDataKeyService,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final EncryptionService _encryptionService;
  final MasterKeyService _masterKeyService;
  final ProfileDataKeyService? _profileDataKeyService;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String webPrefix;
  final String webStoragePrefix;
  final String vaultStoragePrefix;

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
      await prefs.setString('$webStoragePrefix$id', encrypted);
      return '$webPrefix$id';
    }

    final directory = await _directoryProvider();
    final fileName = _attachmentId(type, sourceFile.name);
    final file = File(path.join(directory.path, 'attachments', fileName));
    await file.create(recursive: true);
    await file.writeAsString(encrypted, flush: true);
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
      await prefs.setString('$webStoragePrefix$id', encodedPayload);
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
    return _encryptionService.decryptBytes(
      encodedPayload: encrypted,
      secretKey: key,
      additionalData: _aad(type),
    );
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

  Future<void> deleteAttachment(String storedReference) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
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
  }

  Future<int> storagePayloadSizeBytes() async {
    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      var total = 0;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(webStoragePrefix)) {
          continue;
        }
        total += utf8.encode(prefs.getString(key) ?? '').length;
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

  Future<String?> _readPayload(String storedReference) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      return prefs.getString('$webStoragePrefix$id');
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
      await prefs.setString('$webStoragePrefix$id', payload);
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

  Future<String> _attachmentVaultId(String storedReference) async {
    final prefs = await _sharedPreferencesProvider();
    return prefs.getString('$vaultStoragePrefix$storedReference') ?? 'everyday';
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
