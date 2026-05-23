import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

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

class StoredAttachmentPayloadMetadata {
  const StoredAttachmentPayloadMetadata({
    required this.sizeBytes,
    required this.modifiedAtMillis,
  });

  final int sizeBytes;
  final int? modifiedAtMillis;
}

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
  static const _binaryPayloadStringPrefix = 'binary:';
  static const _materializedDeleteMarkerExtension = '.himemo-delete-after';
  static const _backgroundEncryptionThresholdBytes = 8 * 1024 * 1024;
  static const _backgroundDecryptionThresholdChars = 512 * 1024;

  Future<String?> storeAttachment(
    XFile sourceFile, {
    required AttachmentType type,
  }) async {
    final bytes = await sourceFile.readAsBytes();
    final key = await _masterKeyService.obtainOrCreate();
    final encrypted = await _encryptAttachmentBytesForStorage(
      bytes: bytes,
      key: key,
      type: type,
    );

    if (kIsWeb) {
      final id = _attachmentId(type, sourceFile.name);
      final prefs = await _sharedPreferencesProvider();
      await _writeWebPayload(id, utf8.decode(encrypted), prefs);
      final reference = '$webPrefix$id';
      await prefs.setString('$vaultStoragePrefix$reference', 'everyday');
      return reference;
    }

    final directory = await _directoryProvider();
    final fileName = _attachmentId(type, sourceFile.name);
    final file = File(path.join(directory.path, 'attachments', fileName));
    await file.create(recursive: true);
    await file.writeAsBytes(encrypted, flush: true);
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
    await file.writeAsBytes(
      _attachmentPayloadStringToBytes(encodedPayload),
      flush: true,
    );
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
    final encrypted = await _encryptAttachmentBytesForStorage(
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      key: key,
      type: type,
    );
    return _attachmentPayloadBytesToString(encrypted);
  }

  Future<List<int>?> readAttachment(
    String storedReference, {
    required AttachmentType type,
  }) async {
    final encryptedPayload = await _readPayload(storedReference);
    if (encryptedPayload == null || encryptedPayload.isEmpty) {
      return null;
    }
    final vaultId = await _attachmentVaultId(storedReference);
    final key = await _keyForVault(vaultId);
    if (key == null) {
      throw StateError('Attachment key is unavailable for $vaultId.');
    }
    try {
      return await _decryptAttachmentBytesFromStorage(
        encodedPayload: encryptedPayload,
        key: key,
        additionalData: _aad(type),
      );
    } catch (_) {
      if (vaultId == 'everyday') {
        rethrow;
      }
      final normalKey = await _masterKeyService.obtainOrCreate();
      return _decryptAttachmentBytesFromStorage(
        encodedPayload: encryptedPayload,
        key: normalKey,
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
    final encrypted = await _encryptAttachmentBytesForStorage(
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      key: key,
      type: type,
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

  Future<int?> estimateStoredAttachmentPayloadBytes(
    String storedReference,
  ) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      final stored = prefs.getString('$webStoragePrefix$id');
      if (stored == null) {
        return null;
      }
      if (stored.startsWith(_webIndexedDbMarker)) {
        final payload = await _webPayloadStore.get(
          stored.substring(_webIndexedDbMarker.length),
        );
        return payload?.length;
      }
      return stored.length;
    }
    if (kIsWeb) {
      return null;
    }
    final file = await _resolveStoredFile(storedReference);
    if (!await file.exists()) {
      return null;
    }
    return file.length();
  }

  Future<StoredAttachmentPayloadMetadata?> storedPayloadMetadata(
    String storedReference,
  ) async {
    if (storedReference.startsWith(webPrefix) || kIsWeb) {
      final sizeBytes = await estimateStoredAttachmentPayloadBytes(
        storedReference,
      );
      return sizeBytes == null
          ? null
          : StoredAttachmentPayloadMetadata(
              sizeBytes: sizeBytes,
              modifiedAtMillis: null,
            );
    }
    final file = await _resolveStoredFile(storedReference);
    if (!await file.exists()) {
      return null;
    }
    final stat = await file.stat();
    return StoredAttachmentPayloadMetadata(
      sizeBytes: stat.size,
      modifiedAtMillis: stat.modified.toUtc().millisecondsSinceEpoch,
    );
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
      encryptedPayloadChars = _isBinaryAttachmentPayloadFile(resolvedFile)
          ? null
          : (await resolvedFile.readAsString()).length;
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

  Future<Uint8List?> _readPayload(String storedReference) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      final payload = await _readWebPayload(id, prefs);
      return payload == null ? null : Uint8List.fromList(utf8.encode(payload));
    }

    if (kIsWeb) {
      return null;
    }

    final file = await _resolveStoredFile(storedReference);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<void> _writePayload(String storedReference, Uint8List payload) async {
    if (storedReference.startsWith(webPrefix)) {
      final id = storedReference.substring(webPrefix.length);
      final prefs = await _sharedPreferencesProvider();
      await _writeWebPayload(
        id,
        _attachmentPayloadBytesToString(payload),
        prefs,
      );
      return;
    }

    if (kIsWeb) {
      return;
    }

    final file = await _resolveStoredFile(storedReference);
    await file.create(recursive: true);
    await file.writeAsBytes(payload, flush: true);
  }

  Future<String?> readStoredPayload(String storedReference) async {
    final payload = await _readPayload(storedReference);
    return payload == null ? null : _attachmentPayloadBytesToString(payload);
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

  Future<Uint8List> _encryptAttachmentBytesForStorage({
    required Uint8List bytes,
    required SecretKey key,
    required AttachmentType type,
  }) async {
    final additionalData = _aad(type);
    if (kIsWeb) {
      final encoded = await _encryptionService.encryptBytes(
        clearBytes: bytes,
        secretKey: key,
        additionalData: additionalData,
      );
      return Uint8List.fromList(utf8.encode(encoded));
    }
    if (bytes.lengthInBytes < _backgroundEncryptionThresholdBytes) {
      final keyBytes = await key.extractBytes();
      return _encryptAttachmentPayloadBinary(
        bytes: bytes,
        keyBytes: keyBytes,
        additionalData: additionalData,
      );
    }

    final keyBytes = await key.extractBytes();
    final request = _AttachmentEncryptionRequest(
      clearBytes: TransferableTypedData.fromList([bytes]),
      keyBytes: keyBytes,
      additionalData: additionalData,
    );
    final transferable = await Isolate.run(
      () => _encryptAttachmentPayload(request),
    );
    return transferable.materialize().asUint8List();
  }

  Future<List<int>> _decryptAttachmentBytesFromStorage({
    required Uint8List encodedPayload,
    required SecretKey key,
    required List<int> additionalData,
  }) async {
    if (_isBinaryAttachmentPayload(encodedPayload)) {
      final keyBytes = await key.extractBytes();
      if (kIsWeb ||
          encodedPayload.lengthInBytes < _backgroundDecryptionThresholdChars) {
        return _decryptAttachmentPayloadBinary(
          encodedPayload: encodedPayload,
          keyBytes: keyBytes,
          additionalData: additionalData,
        );
      }
      final request = _AttachmentDecryptionRequest(
        encodedPayload: TransferableTypedData.fromList([encodedPayload]),
        keyBytes: keyBytes,
        additionalData: additionalData,
      );
      final transferable = await Isolate.run(
        () => _decryptAttachmentPayload(request),
      );
      return transferable.materialize().asUint8List();
    }

    final legacyPayload = utf8.decode(encodedPayload);
    if (kIsWeb || legacyPayload.length < _backgroundDecryptionThresholdChars) {
      return _encryptionService.decryptBytes(
        encodedPayload: legacyPayload,
        secretKey: key,
        additionalData: additionalData,
      );
    }

    final keyBytes = await key.extractBytes();
    final request = _AttachmentDecryptionRequest(
      encodedPayload: TransferableTypedData.fromList([encodedPayload]),
      keyBytes: keyBytes,
      additionalData: additionalData,
    );
    final transferable = await Isolate.run(
      () => _decryptAttachmentPayload(request),
    );
    return transferable.materialize().asUint8List();
  }
}

class _AttachmentEncryptionRequest {
  const _AttachmentEncryptionRequest({
    required this.clearBytes,
    required this.keyBytes,
    required this.additionalData,
  });

  final TransferableTypedData clearBytes;
  final List<int> keyBytes;
  final List<int> additionalData;
}

final Uint8List _attachmentBinaryMagic = Uint8List.fromList([
  0x48,
  0x4d,
  0x41,
  0x32,
]);

String _attachmentPayloadBytesToString(Uint8List payload) {
  if (_isBinaryAttachmentPayload(payload)) {
    return '${EncryptedAttachmentStore._binaryPayloadStringPrefix}${base64Encode(payload)}';
  }
  return utf8.decode(payload);
}

Uint8List _attachmentPayloadStringToBytes(String payload) {
  if (payload.startsWith(EncryptedAttachmentStore._binaryPayloadStringPrefix)) {
    return Uint8List.fromList(
      base64Decode(
        payload.substring(
          EncryptedAttachmentStore._binaryPayloadStringPrefix.length,
        ),
      ),
    );
  }
  return Uint8List.fromList(utf8.encode(payload));
}

bool _isBinaryAttachmentPayload(Uint8List payload) {
  if (payload.lengthInBytes < _attachmentBinaryMagic.length + 2) {
    return false;
  }
  for (var i = 0; i < _attachmentBinaryMagic.length; i++) {
    if (payload[i] != _attachmentBinaryMagic[i]) {
      return false;
    }
  }
  return true;
}

bool _isBinaryAttachmentPayloadFile(File file) {
  final reader = file.openSync();
  try {
    final bytes = reader.readSync(_attachmentBinaryMagic.length + 2);
    return _isBinaryAttachmentPayload(Uint8List.fromList(bytes));
  } finally {
    reader.closeSync();
  }
}

Future<Uint8List> _encryptAttachmentPayloadBinary({
  required Uint8List bytes,
  required List<int> keyBytes,
  required List<int> additionalData,
}) async {
  final algorithm = AesGcm.with256bits();
  final random = Random.secure();
  final nonce = Uint8List.fromList(
    List<int>.generate(algorithm.nonceLength, (_) => random.nextInt(256)),
  );
  final box = await algorithm.encrypt(
    bytes,
    secretKey: SecretKey(keyBytes),
    nonce: nonce,
    aad: additionalData,
  );
  final mac = box.mac.bytes;
  return Uint8List.fromList([
    ..._attachmentBinaryMagic,
    nonce.length,
    mac.length,
    ...nonce,
    ...mac,
    ...box.cipherText,
  ]);
}

Future<Uint8List> _decryptAttachmentPayloadBinary({
  required Uint8List encodedPayload,
  required List<int> keyBytes,
  required List<int> additionalData,
}) async {
  if (!_isBinaryAttachmentPayload(encodedPayload)) {
    throw const HimemoDecryptionException();
  }
  final nonceLength = encodedPayload[4];
  final macLength = encodedPayload[5];
  final nonceStart = _attachmentBinaryMagic.length + 2;
  final macStart = nonceStart + nonceLength;
  final cipherStart = macStart + macLength;
  if (nonceLength <= 0 ||
      macLength <= 0 ||
      cipherStart > encodedPayload.lengthInBytes) {
    throw const HimemoDecryptionException();
  }
  final secretBox = SecretBox(
    encodedPayload.sublist(cipherStart),
    nonce: encodedPayload.sublist(nonceStart, macStart),
    mac: Mac(encodedPayload.sublist(macStart, cipherStart)),
  );
  final clearBytes = await AesGcm.with256bits().decrypt(
    secretBox,
    secretKey: SecretKey(keyBytes),
    aad: additionalData,
  );
  return clearBytes is Uint8List ? clearBytes : Uint8List.fromList(clearBytes);
}

Future<TransferableTypedData> _encryptAttachmentPayload(
  _AttachmentEncryptionRequest request,
) async {
  final bytes = request.clearBytes.materialize().asUint8List();
  final encrypted = await _encryptAttachmentPayloadBinary(
    bytes: bytes,
    keyBytes: request.keyBytes,
    additionalData: request.additionalData,
  );
  return TransferableTypedData.fromList([encrypted]);
}

class _AttachmentDecryptionRequest {
  const _AttachmentDecryptionRequest({
    required this.encodedPayload,
    required this.keyBytes,
    required this.additionalData,
  });

  final TransferableTypedData encodedPayload;
  final List<int> keyBytes;
  final List<int> additionalData;
}

Future<TransferableTypedData> _decryptAttachmentPayload(
  _AttachmentDecryptionRequest request,
) async {
  final payload = request.encodedPayload.materialize().asUint8List();
  final bytes = _isBinaryAttachmentPayload(payload)
      ? await _decryptAttachmentPayloadBinary(
          encodedPayload: payload,
          keyBytes: request.keyBytes,
          additionalData: request.additionalData,
        )
      : await EncryptionService().decryptBytes(
          encodedPayload: utf8.decode(payload),
          secretKey: SecretKey(request.keyBytes),
          additionalData: request.additionalData,
        );
  return TransferableTypedData.fromList([
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  ]);
}
