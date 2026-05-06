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
    final stored = await _secureStore.read('$storagePrefix$vaultId');
    if (stored == null || stored.isEmpty) {
      return false;
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
      _unlockedProfileKeys[vaultId] = SecretKey(dataKeyBytes);
      return true;
    } catch (_) {
      return false;
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
}
