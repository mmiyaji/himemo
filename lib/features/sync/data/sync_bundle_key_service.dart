import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../../security/data/secure_key_value_store.dart';

abstract class CloudSyncBundleKeyStore {
  Future<String?> readBackupCode();

  Future<void> writeBackupCode(String backupCode);
}

class SyncBundleKeyService {
  SyncBundleKeyService({
    required SecureKeyValueStore secureStore,
    required List<int> Function() keyFactory,
    SecureKeyValueStore? fallbackStore,
    CloudSyncBundleKeyStore? cloudStore,
    this.storageKey = 'security.sync_bundle_key.v1',
  }) : _secureStore = secureStore,
       _fallbackStore = fallbackStore,
       _cloudStore = cloudStore,
       _keyFactory = keyFactory;

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

  Future<String> fingerprint() async {
    final bytes = await _readOrCreateBytes();
    final digest = sha256.convert(bytes).toString();
    return digest.substring(0, 12);
  }

  Future<String> exportBackupCode() async {
    final bytes = await _readOrCreateBytes();
    return '$backupCodePrefix${base64Encode(bytes)}';
  }

  Future<String> importBackupCode(String rawCode) async {
    final bytes = _parseBackupCode(rawCode);
    await _secureStore.write(storageKey, base64Encode(bytes));
    await _cloudStore?.writeBackupCode(_backupCodeForBytes(bytes));
    return fingerprint();
  }

  String previewBackupCodeFingerprint(String rawCode) {
    final bytes = _parseBackupCode(rawCode);
    final digest = sha256.convert(bytes).toString();
    return digest.substring(0, 12);
  }

  Future<List<int>> _readOrCreateBytes() async {
    final cloud = _cloudStore;
    if (cloud != null) {
      try {
        final cloudBackupCode = await cloud.readBackupCode();
        if (cloudBackupCode != null && cloudBackupCode.isNotEmpty) {
          final bytes = _parseBackupCode(cloudBackupCode);
          await _secureStore.write(storageKey, base64Encode(bytes));
          return bytes;
        }
      } catch (_) {
        // Keep the app usable offline or while the cloud account is reconnecting.
      }
    }

    final existing = await _secureStore.read(storageKey);
    if (existing != null && existing.isNotEmpty) {
      final bytes = base64Decode(existing);
      await _publishCloudKeyIfMissing(bytes);
      return bytes;
    }

    final fallback = _fallbackStore;
    if (fallback != null) {
      final fallbackValue = await fallback.read(storageKey);
      if (fallbackValue != null && fallbackValue.isNotEmpty) {
        await _secureStore.write(storageKey, fallbackValue);
        final bytes = base64Decode(fallbackValue);
        await _publishCloudKeyIfMissing(bytes);
        return bytes;
      }
    }

    final generated = _keyFactory();
    await _secureStore.write(storageKey, base64Encode(generated));
    await _cloudStore?.writeBackupCode(_backupCodeForBytes(generated));
    return generated;
  }

  Future<void> _publishCloudKeyIfMissing(List<int> bytes) async {
    final cloud = _cloudStore;
    if (cloud == null) {
      return;
    }
    try {
      final existing = await cloud.readBackupCode();
      if (existing == null || existing.isEmpty) {
        await cloud.writeBackupCode(_backupCodeForBytes(bytes));
      }
    } catch (_) {
      // Sync can continue with the local key; the next successful cloud
      // operation will publish the key.
    }
  }

  String _backupCodeForBytes(List<int> bytes) {
    return '$backupCodePrefix${base64Encode(bytes)}';
  }

  List<int> _parseBackupCode(String rawCode) {
    final normalized = rawCode.trim();
    if (!normalized.startsWith(backupCodePrefix)) {
      throw const FormatException('Unsupported sync key format.');
    }
    final encoded = normalized.substring(backupCodePrefix.length).trim();
    final bytes = base64Decode(encoded);
    if (bytes.length < 16) {
      throw const FormatException('Sync key is too short.');
    }
    return bytes;
  }
}
