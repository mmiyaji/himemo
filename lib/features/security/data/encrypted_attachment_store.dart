import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/domain/note_entry.dart';
import 'encryption_service.dart';
import 'master_key_service.dart';

class EncryptedAttachmentStore {
  EncryptedAttachmentStore({
    required EncryptionService encryptionService,
    required MasterKeyService masterKeyService,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.webPrefix = 'secure-attachment://',
    this.webStoragePrefix = 'attachments.encrypted.',
  }) : _encryptionService = encryptionService,
       _masterKeyService = masterKeyService,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final EncryptionService _encryptionService;
  final MasterKeyService _masterKeyService;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String webPrefix;
  final String webStoragePrefix;

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

  Future<List<int>?> readAttachment(
    String storedReference, {
    required AttachmentType type,
  }) async {
    final encrypted = await _readPayload(storedReference);
    if (encrypted == null || encrypted.isEmpty) {
      return null;
    }
    final key = await _masterKeyService.obtainOrCreate();
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
    final file = File(path.join(directory.path, 'attachments', 'tmp', tempName));
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteAttachment(String storedReference) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      await prefs.remove('$webStoragePrefix$id');
      return;
    }

    if (kIsWeb) {
      return;
    }

    final file = File(storedReference);
    if (await file.exists()) {
      await file.delete();
    }
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

  Future<String?> _readPayload(String storedReference) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      return prefs.getString('$webStoragePrefix$id');
    }

    if (kIsWeb) {
      return null;
    }

    final file = File(storedReference);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  Future<String?> readStoredPayload(String storedReference) {
    return _readPayload(storedReference);
  }

  String _attachmentId(AttachmentType type, String name) {
    final extension = path.extension(name);
    final suffix = extension.isEmpty ? '.bin' : extension;
    return '${DateTime.now().microsecondsSinceEpoch}_${type.name}$suffix.enc';
  }

  List<int> _aad(AttachmentType type) => type.name.codeUnits;
}
