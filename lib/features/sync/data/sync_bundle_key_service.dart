import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../../security/data/secure_key_value_store.dart';

class SyncBundleKeyService {
  SyncBundleKeyService({
    required SecureKeyValueStore secureStore,
    required List<int> Function() keyFactory,
    this.storageKey = 'security.sync_bundle_key.v1',
  })  : _secureStore = secureStore,
        _keyFactory = keyFactory;

  static const backupCodePrefix = 'himemo-sync-key-v1:';

  final SecureKeyValueStore _secureStore;
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
    return fingerprint();
  }

  String previewBackupCodeFingerprint(String rawCode) {
    final bytes = _parseBackupCode(rawCode);
    final digest = sha256.convert(bytes).toString();
    return digest.substring(0, 12);
  }

  Future<List<int>> _readOrCreateBytes() async {
    final existing = await _secureStore.read(storageKey);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }

    final generated = _keyFactory();
    await _secureStore.write(storageKey, base64Encode(generated));
    return generated;
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
