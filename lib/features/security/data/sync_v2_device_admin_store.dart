import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secure_key_value_store.dart';

/// Stores an administrator key in the device's secure key-value store.
///
/// Callers must authenticate the administrator in the settings flow and
/// verify the account and generation against the cloud before saving or using
/// a key returned by this store. This class performs storage validation only.
class SyncV2DeviceAdminStore {
  SyncV2DeviceAdminStore(
    this._store, {
    Future<String?> Function(bool create)? installationId,
  }) : _installationId = installationId ?? _testInstallationId;

  final SecureKeyValueStore _store;
  final Future<String?> Function(bool create) _installationId;

  // Keeps tests and isolated in-memory callers deterministic. Production
  // callers must provide a persistent, installation-scoped identifier.
  static Future<String?> _testInstallationId(bool create) async =>
      'test-installation';

  String storageKey({
    required String installationId,
    required String accountId,
    required String generationId,
  }) {
    _validateIdentity(accountId, generationId);
    _validateInstallationId(installationId);
    final installation = base64Url
        .encode(utf8.encode(installationId))
        .replaceAll('=', '');
    final account = base64Url
        .encode(utf8.encode(accountId))
        .replaceAll('=', '');
    final generation = base64Url
        .encode(utf8.encode(generationId))
        .replaceAll('=', '');
    return 'security.sync_v2.device_admin.$installation.$account.$generation.v1';
  }

  Future<void> save({
    required String accountId,
    required String generationId,
    required SecretKey adminKey,
  }) async {
    final installationId = await _installationId(true);
    if (installationId == null) {
      throw StateError('Could not establish device installation identity');
    }
    _validateInstallationId(installationId);
    final key = await adminKey.extractBytes();
    if (key.length != 32) {
      throw const FormatException('Invalid device administrator key');
    }
    final encoded = jsonEncode({
      'version': 1,
      'installation': installationId,
      'account': accountId,
      'generation': generationId,
      'key': base64Encode(key),
    });
    final storageKey = this.storageKey(
      installationId: installationId,
      accountId: accountId,
      generationId: generationId,
    );
    await _store.write(storageKey, encoded);
    final readback = await _store.read(storageKey);
    if (readback == null) {
      throw StateError('Could not persist device administrator key');
    }
    final verified = _decode(
      readback,
      expectedInstallationId: installationId,
      expectedAccountId: accountId,
      expectedGenerationId: generationId,
    );
    try {
      if (readback != encoded ||
          base64Encode(await verified.extractBytes()) != base64Encode(key)) {
        throw StateError('Device administrator key readback failed');
      }
    } finally {
      verified.destroy();
    }
  }

  /// Returns a caller-owned key, or null when this device has no matching key.
  Future<SecretKey?> read({
    required String accountId,
    required String generationId,
  }) async {
    final installationId = await _installationId(false);
    if (installationId == null) return null;
    _validateInstallationId(installationId);
    final raw = await _store.read(
      storageKey(
        installationId: installationId,
        accountId: accountId,
        generationId: generationId,
      ),
    );
    if (raw == null) return null;
    return _decode(
      raw,
      expectedInstallationId: installationId,
      expectedAccountId: accountId,
      expectedGenerationId: generationId,
    );
  }

  /// Removes only the entry for the current installation, account and
  /// generation. It never creates an installation identifier while deleting.
  Future<void> delete({
    required String accountId,
    required String generationId,
  }) async {
    final installationId = await _installationId(false);
    if (installationId == null) return;
    _validateInstallationId(installationId);
    final key = storageKey(
      installationId: installationId,
      accountId: accountId,
      generationId: generationId,
    );
    await _store.delete(key);
    if (await _store.read(key) != null) {
      throw StateError('Could not delete device administrator key');
    }
  }

  SecretKey _decode(
    String raw, {
    required String expectedInstallationId,
    required String expectedAccountId,
    required String expectedGenerationId,
  }) {
    try {
      if (utf8.encode(raw).length > 8192) throw const FormatException();
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value.length != 5 ||
          !value.keys.toSet().containsAll({
            'version',
            'installation',
            'account',
            'generation',
            'key',
          }) ||
          value['version'] is! int ||
          value['version'] != 1 ||
          value['installation'] != expectedInstallationId ||
          value['account'] != expectedAccountId ||
          value['generation'] != expectedGenerationId ||
          value['key'] is! String) {
        throw const FormatException();
      }
      final encodedKey = value['key'] as String;
      final bytes = base64Decode(encodedKey);
      if (bytes.length != 32 || base64Encode(bytes) != encodedKey) {
        throw const FormatException();
      }
      return SecretKey(bytes);
    } catch (_) {
      throw const FormatException('Invalid stored device administrator key');
    }
  }

  void _validateIdentity(String accountId, String generationId) {
    if (accountId.isEmpty ||
        accountId.length > 1024 ||
        generationId.isEmpty ||
        generationId.length > 1024) {
      throw const FormatException('Invalid device administrator identity');
    }
  }

  void _validateInstallationId(String installationId) {
    if (installationId.isEmpty || installationId.length > 1024) {
      throw const FormatException('Invalid device installation identity');
    }
  }
}
