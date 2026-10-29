import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../../security/data/secure_key_value_store.dart';
import '../../security/data/storage_serial_executor.dart';

abstract class CloudSyncBundleKeyStore {
  Future<String?> readBackupCode();
}

abstract class DeletableCloudSyncBundleKeyStore {
  Future<void> deleteBackupCode();
}

class SyncBundleKeyService {
  SyncBundleKeyService({
    required this._secureStore,
    required this._keyFactory,
    this._fallbackStore,
    this._cloudStore,
    this.storageKey = 'security.sync_bundle_key.v1',
  });

  // Optional cloud adapter is retained for compatibility tests. Production
  // migrates Drive keys after authentication in SyncProviderController.
  static const backupCodePrefix = 'himemo-sync-key-v1:';

  final SecureKeyValueStore _secureStore;
  final SecureKeyValueStore? _fallbackStore;
  final CloudSyncBundleKeyStore? _cloudStore;
  final List<int> Function() _keyFactory;
  final String storageKey;

  Future<SecretKey> obtainOrCreate() async {
    final bytes = await _readOrCreateBytes();
    return SecretKey(bytes);
  }

  Future<SecretKey> requireExisting() async {
    final bytes = await _readExistingBytes();
    if (bytes == null) {
      throw StateError('Sync bundle key is not available.');
    }
    return SecretKey(bytes);
  }

  Future<String> fingerprint() async {
    final bytes = await _readOrCreateBytes();
    return _fullFingerprintForBytes(bytes).substring(0, 12);
  }

  Future<String> fullFingerprint() async {
    final bytes = await _readOrCreateBytes();
    return _fullFingerprintForBytes(bytes);
  }

  Future<String?> existingFullFingerprint() async {
    final bytes = await _readExistingBytes();
    return bytes == null ? null : _fullFingerprintForBytes(bytes);
  }

  Future<String> exportBackupCode() async {
    final bytes = await _readOrCreateBytes();
    return '$backupCodePrefix${base64Encode(bytes)}';
  }

  Future<String?> exportExistingBackupCode() async {
    final bytes = await _readExistingBytes();
    return bytes == null ? null : _backupCodeForBytes(bytes);
  }

  Future<String> importBackupCode(String rawCode) =>
      StorageSerialExecutor.run(_secureStore, storageKey, () async {
        final bytes = _parseBackupCode(rawCode);
        await _verifyCloudKey(bytes);
        await _persistBytes(bytes);
        return _fullFingerprintForBytes(bytes).substring(0, 12);
      });

  String previewBackupCodeFingerprint(String rawCode) {
    final bytes = _parseBackupCode(rawCode);
    return _fullFingerprintForBytes(bytes).substring(0, 12);
  }

  bool backupCodesMatch(String leftCode, String rightCode) {
    return _sameKeyBytes(
      _parseBackupCode(leftCode),
      _parseBackupCode(rightCode),
    );
  }

  Future<List<int>> _readOrCreateBytes() => StorageSerialExecutor.run(
    _secureStore,
    storageKey,
    _readOrCreateBytesUnlocked,
  );

  Future<List<int>> _readOrCreateBytesUnlocked() async {
    final existing = await _readExistingBytesUnlocked();
    if (existing != null) {
      return existing;
    }

    final generated = _keyFactory();
    if (generated.length != 32) {
      throw StateError('Sync key factory must generate exactly 32 bytes.');
    }
    await _persistBytes(generated);
    return generated;
  }

  Future<List<int>?> _readExistingBytes() => StorageSerialExecutor.run(
    _secureStore,
    storageKey,
    _readExistingBytesUnlocked,
  );

  Future<void> _persistBytes(List<int> bytes) async {
    final encoded = base64Encode(bytes);
    await _secureStore.write(storageKey, encoded);
    if (await _secureStore.read(storageKey) != encoded) {
      throw StateError('Sync key persistence could not be confirmed.');
    }
  }

  Future<List<int>?> _readExistingBytesUnlocked() async {
    final existing = await _secureStore.read(storageKey);
    if (existing != null) {
      final bytes = _decodeStoredKey(existing);
      await _verifyCloudKey(bytes);
      return bytes;
    }

    final fallback = _fallbackStore;
    if (fallback != null) {
      final fallbackValue = await fallback.read(storageKey);
      if (fallbackValue != null) {
        final bytes = _decodeStoredKey(fallbackValue);
        await _verifyCloudKey(bytes);
        await _persistBytes(bytes);
        return bytes;
      }
    }

    // Cloud storage is read only for migrating releases that escrowed the raw
    // recovery key beside the encrypted bundle. New keys are never uploaded.
    final cloud = _cloudStore;
    if (cloud != null) {
      String? cloudBackupCode;
      try {
        cloudBackupCode = await cloud.readBackupCode();
      } catch (_) {
        // A fallback or a newly generated key can still be used offline. An
        // invalid reachable cloud record is deliberately not ignored below.
      }
      if (cloudBackupCode != null && cloudBackupCode.isNotEmpty) {
        final bytes = _parseBackupCode(cloudBackupCode);
        await _persistBytes(bytes);
        return bytes;
      }
    }
    return null;
  }

  Future<void> _verifyCloudKey(List<int> bytes) async {
    final cloud = _cloudStore;
    if (cloud == null) {
      return;
    }
    String? existing;
    try {
      existing = await cloud.readBackupCode();
    } catch (_) {
      // Keep the app usable offline. A reachable cloud record is validated
      // below instead of silently replacing the local source of truth.
      return;
    }
    if (existing == null || existing.isEmpty) {
      return;
    }
    final cloudBytes = _parseBackupCode(existing);
    if (!_sameKeyBytes(bytes, cloudBytes)) {
      throw StateError(
        'The cloud sync key does not match this device. Import the correct recovery key before syncing.',
      );
    }
  }

  String _backupCodeForBytes(List<int> bytes) {
    return '$backupCodePrefix${base64Encode(bytes)}';
  }

  String _fullFingerprintForBytes(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  List<int> _parseBackupCode(String rawCode) {
    final normalized = rawCode.trim();
    if (!normalized.startsWith(backupCodePrefix)) {
      throw const FormatException('Unsupported sync key format.');
    }
    final encoded = normalized.substring(backupCodePrefix.length).trim();
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) {
      throw const FormatException('Sync key must contain exactly 32 bytes.');
    }
    return bytes;
  }

  List<int> _decodeStoredKey(String encoded) {
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) {
      throw const FormatException('Stored sync key must contain 32 bytes.');
    }
    return bytes;
  }

  bool _sameKeyBytes(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
