import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'encryption_service.dart';
import 'master_key_service.dart';
import 'secure_key_value_store.dart';

const profileDataKeyLegacyPrivateVaultId = 'private';
const profileDataKeyCustomPrivateVaultPrefix = 'private_profile:';

bool isProfileDataKeyPrivateVaultId(String vaultId) {
  return vaultId == profileDataKeyLegacyPrivateVaultId ||
      vaultId.startsWith(profileDataKeyCustomPrivateVaultPrefix);
}

class ProfileDataKeyService {
  ProfileDataKeyService({
    required SecureKeyValueStore secureStore,
    required EncryptionService encryptionService,
    required MasterKeyService normalMasterKeyService,
    this.storagePrefix = 'security.profile_data_key.v1.',
  }) : _secureStore = secureStore,
       _encryptionService = encryptionService,
       _normalMasterKeyService = normalMasterKeyService;

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final MasterKeyService _normalMasterKeyService;
  final String storagePrefix;
  final Map<String, SecretKey> _unlockedProfileKeys = {};

  Future<SecretKey?> keyForVault(String vaultId) async {
    if (!isProfileDataKeyPrivateVaultId(vaultId)) {
      return _normalMasterKeyService.obtainOrCreate();
    }
    return _unlockedProfileKeys[vaultId];
  }

  Future<void> configureProfile({
    required String vaultId,
    required String password,
  }) async {
    final dataKeyBytes = _encryptionService.generateKeyBytes();
    final dataKey = SecretKey(dataKeyBytes);
    final salt = _encryptionService.generateSalt();
    final passwordKey = await _derivePasswordKey(password, salt);
    final wrappedDataKey = await _encryptionService.encryptBytes(
      clearBytes: dataKeyBytes,
      secretKey: passwordKey,
      additionalData: _profileKeyAad(vaultId),
    );
    await _secureStore.write(
      '$storagePrefix$vaultId',
      jsonEncode({
        'version': 1,
        'kdf': 'pbkdf2-sha256',
        'salt': base64Encode(salt),
        'wrappedDataKey': wrappedDataKey,
      }),
    );
    _unlockedProfileKeys[vaultId] = dataKey;
  }

  Future<bool> unlockProfile({
    required String vaultId,
    required String password,
  }) async {
    final dataKeyBytes = await _unwrapProfileKey(
      vaultId: vaultId,
      password: password,
    );
    if (dataKeyBytes == null) {
      return false;
    }
    _unlockedProfileKeys[vaultId] = SecretKey(dataKeyBytes);
    return true;
  }

  Future<bool> verifyProfilePassword({
    required String vaultId,
    required String password,
  }) async {
    return await _unwrapProfileKey(vaultId: vaultId, password: password) !=
        null;
  }

  Future<List<int>?> _unwrapProfileKey({
    required String vaultId,
    required String password,
  }) async {
    final stored = await _secureStore.read('$storagePrefix$vaultId');
    if (stored == null || stored.isEmpty) {
      return null;
    }
    try {
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      final passwordKey = await _derivePasswordKey(
        password,
        base64Decode(decoded['salt'] as String),
      );
      final dataKeyBytes = await _encryptionService.decryptBytes(
        encodedPayload: decoded['wrappedDataKey'] as String,
        secretKey: passwordKey,
        additionalData: _profileKeyAad(vaultId),
      );
      return dataKeyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<bool> changeProfilePassword({
    required String vaultId,
    required String newPassword,
  }) async {
    final dataKey = _unlockedProfileKeys[vaultId];
    if (dataKey == null) {
      return false;
    }
    final dataKeyBytes = await dataKey.extractBytes();
    final salt = _encryptionService.generateSalt();
    final passwordKey = await _derivePasswordKey(newPassword, salt);
    final wrappedDataKey = await _encryptionService.encryptBytes(
      clearBytes: dataKeyBytes,
      secretKey: passwordKey,
      additionalData: _profileKeyAad(vaultId),
    );
    await _secureStore.write(
      '$storagePrefix$vaultId',
      jsonEncode({
        'version': 1,
        'kdf': 'pbkdf2-sha256',
        'salt': base64Encode(salt),
        'wrappedDataKey': wrappedDataKey,
      }),
    );
    return true;
  }

  Future<Map<String, dynamic>?> exportWrappedProfileKey(String vaultId) async {
    if (!isProfileDataKeyPrivateVaultId(vaultId)) {
      return null;
    }
    final stored = await _secureStore.read('$storagePrefix$vaultId');
    if (stored == null || stored.isEmpty) {
      return null;
    }
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(stored) as Map);
      if (!_isValidWrappedKey(decoded)) {
        return null;
      }
      return <String, dynamic>{'vaultId': vaultId, ...decoded};
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> exportWrappedProfileKeys(
    Iterable<String> vaultIds,
  ) async {
    final exported = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final vaultId in vaultIds) {
      if (!seen.add(vaultId)) {
        continue;
      }
      final wrapped = await exportWrappedProfileKey(vaultId);
      if (wrapped != null) {
        exported.add(wrapped);
      }
    }
    return exported;
  }

  Future<int> importWrappedProfileKeys(
    Iterable<dynamic> entries, {
    bool overwrite = false,
  }) async {
    var imported = 0;
    for (final raw in entries) {
      if (raw is! Map) {
        continue;
      }
      final decoded = Map<String, dynamic>.from(raw);
      final vaultId = decoded['vaultId'] as String?;
      if (vaultId == null || !isProfileDataKeyPrivateVaultId(vaultId)) {
        continue;
      }
      final payload = Map<String, dynamic>.from(decoded)..remove('vaultId');
      if (!_isValidWrappedKey(payload)) {
        continue;
      }
      final storageKey = '$storagePrefix$vaultId';
      final existing = await _secureStore.read(storageKey);
      if (!overwrite && existing != null && existing.isNotEmpty) {
        continue;
      }
      await _secureStore.write(storageKey, jsonEncode(payload));
      imported += 1;
    }
    return imported;
  }

  bool isProfileUnlocked(String vaultId) {
    return _unlockedProfileKeys.containsKey(vaultId);
  }

  Future<void> deleteProfileKey(String vaultId) async {
    _unlockedProfileKeys.remove(vaultId);
    await _secureStore.delete('$storagePrefix$vaultId');
  }

  void lockProfile(String vaultId) {
    _unlockedProfileKeys.remove(vaultId);
  }

  void lockAllPrivateProfiles() {
    _unlockedProfileKeys.clear();
  }

  Future<SecretKey> _derivePasswordKey(String password, List<int> salt) async {
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: password,
      salt: salt,
    );
    return SecretKey(base64Decode(verifier));
  }

  List<int> _profileKeyAad(String vaultId) =>
      utf8.encode('profile-data-key:$vaultId');

  bool _isValidWrappedKey(Map<String, dynamic> decoded) {
    return decoded['version'] == 1 &&
        decoded['kdf'] == 'pbkdf2-sha256' &&
        decoded['salt'] is String &&
        (decoded['salt'] as String).isNotEmpty &&
        decoded['wrappedDataKey'] is String &&
        (decoded['wrappedDataKey'] as String).isNotEmpty;
  }
}
