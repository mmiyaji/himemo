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
    this.enableLocalAdminAccess = true,
  }) : _secureStore = secureStore,
       _encryptionService = encryptionService,
       _normalMasterKeyService = normalMasterKeyService;

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final MasterKeyService _normalMasterKeyService;
  final String storagePrefix;
  final bool enableLocalAdminAccess;
  final Map<String, SecretKey> _unlockedProfileKeys = {};
  int _lockGeneration = 0;

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
    final generation = ++_lockGeneration;
    final dataKeyBytes = _encryptionService.generateKeyBytes();
    final dataKey = SecretKey(dataKeyBytes);
    final salt = _encryptionService.generateSalt();
    final passwordKey = await _derivePasswordKey(password, salt);
    final wrappedDataKey = await _encryptionService.encryptBytes(
      clearBytes: dataKeyBytes,
      secretKey: passwordKey,
      additionalData: _profileKeyAad(vaultId),
    );
    final payload = <String, dynamic>{
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'salt': base64Encode(salt),
      'wrappedDataKey': wrappedDataKey,
    };
    await _secureStore.write('$storagePrefix$vaultId', jsonEncode(payload));
    try {
      await _persistAdminWrapping(
        vaultId: vaultId,
        dataKeyBytes: dataKeyBytes,
        profilePayload: payload,
      );
    } catch (_) {
      // The password-wrapped profile key is usable even if the optional
      // device-local convenience wrap cannot be persisted.
    }
    if (generation == _lockGeneration) {
      _unlockedProfileKeys[vaultId] = dataKey;
    }
  }

  Future<bool> unlockProfile({
    required String vaultId,
    required String password,
  }) async {
    final generation = _lockGeneration;
    final profilePayload = await _readProfilePayload(vaultId);
    final dataKeyBytes = await _unwrapProfileKey(
      vaultId: vaultId,
      password: password,
      profilePayload: profilePayload,
    );
    if (dataKeyBytes == null) {
      return false;
    }
    if (generation != _lockGeneration) {
      return false;
    }
    if (profilePayload == null ||
        await _profilePayloadChanged(vaultId, profilePayload) ||
        generation != _lockGeneration) {
      return false;
    }
    try {
      await _persistAdminWrapping(
        vaultId: vaultId,
        dataKeyBytes: dataKeyBytes,
        profilePayload: profilePayload,
      );
    } catch (_) {}
    if (await _profilePayloadChanged(vaultId, profilePayload)) {
      return false;
    }
    if (generation != _lockGeneration) {
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
    Map<String, dynamic>? profilePayload,
  }) async {
    final decoded = profilePayload ?? await _readProfilePayload(vaultId);
    if (decoded == null) {
      return null;
    }
    try {
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
    _lockGeneration++;
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
    final payload = <String, dynamic>{
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'salt': base64Encode(salt),
      'wrappedDataKey': wrappedDataKey,
    };
    await _secureStore.write('$storagePrefix$vaultId', jsonEncode(payload));
    try {
      await _persistAdminWrapping(
        vaultId: vaultId,
        dataKeyBytes: dataKeyBytes,
        profilePayload: payload,
      );
    } catch (_) {}
    return true;
  }

  /// Unlocks private profiles using device-local admin wraps.
  /// Profiles without a valid local wrap are returned in [missingVaultIds].
  Future<List<String>> unlockProfilesForAdmin(Iterable<String> vaultIds) async {
    if (!enableLocalAdminAccess) {
      return vaultIds.where(isProfileDataKeyPrivateVaultId).toSet().toList();
    }
    final missing = <String>[];
    final seen = <String>{};
    final requested = vaultIds.toList();
    final generation = _lockGeneration;
    for (var index = 0; index < requested.length; index++) {
      if (generation != _lockGeneration) {
        for (final remaining in requested.skip(index)) {
          if (seen.add(remaining) &&
              isProfileDataKeyPrivateVaultId(remaining)) {
            missing.add(remaining);
          }
        }
        break;
      }
      final vaultId = requested[index];
      if (!seen.add(vaultId) || !isProfileDataKeyPrivateVaultId(vaultId)) {
        continue;
      }
      final profilePayload = await _readProfilePayload(vaultId);
      if (profilePayload == null) {
        missing.add(vaultId);
        continue;
      }
      final fingerprint = await _profilePayloadFingerprint(profilePayload);
      final adminStored = await _secureStore.read(_adminStorageKey(vaultId));
      var unlocked = false;
      if (adminStored != null && adminStored.isNotEmpty) {
        try {
          final decoded = Map<String, dynamic>.from(
            jsonDecode(adminStored) as Map,
          );
          if (decoded['version'] == 1 &&
              decoded['fingerprint'] == fingerprint &&
              decoded['wrappedDataKey'] is String) {
            final masterKey = await _normalMasterKeyService.obtainOrCreate();
            final dataKeyBytes = await _encryptionService.decryptBytes(
              encodedPayload: decoded['wrappedDataKey'] as String,
              secretKey: masterKey,
              additionalData: _adminKeyAad(vaultId, fingerprint),
            );
            if (!await _profilePayloadChanged(vaultId, profilePayload) &&
                generation == _lockGeneration) {
              _unlockedProfileKeys[vaultId] = SecretKey(dataKeyBytes);
              unlocked = true;
            }
          }
        } catch (_) {
          unlocked = false;
        }
      }
      if (!unlocked) {
        if (generation != _lockGeneration) {
          missing.add(vaultId);
          continue;
        }
        _unlockedProfileKeys.remove(vaultId);
        missing.add(vaultId);
      }
    }
    return missing;
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
      _lockGeneration++;
      await _secureStore.write(storageKey, jsonEncode(payload));
      if (existing != null && existing.isNotEmpty) {
        final oldPayload = await _readProfilePayload(vaultId, stored: existing);
        if (oldPayload == null ||
            await _profilePayloadFingerprint(oldPayload) !=
                await _profilePayloadFingerprint(payload)) {
          _unlockedProfileKeys.remove(vaultId);
          await _secureStore.delete(_adminStorageKey(vaultId));
        }
      }
      imported += 1;
    }
    return imported;
  }

  bool isProfileUnlocked(String vaultId) {
    return _unlockedProfileKeys.containsKey(vaultId);
  }

  Future<void> deleteProfileKey(String vaultId) async {
    _lockGeneration++;
    _unlockedProfileKeys.remove(vaultId);
    await _secureStore.delete('$storagePrefix$vaultId');
    await _secureStore.delete(_adminStorageKey(vaultId));
  }

  void lockProfile(String vaultId) {
    _lockGeneration++;
    _unlockedProfileKeys.remove(vaultId);
  }

  void lockAllPrivateProfiles({String? exceptVaultId}) {
    _lockGeneration++;
    if (exceptVaultId == null) {
      _unlockedProfileKeys.clear();
      return;
    }
    final retained = _unlockedProfileKeys[exceptVaultId];
    _unlockedProfileKeys.clear();
    if (retained != null) {
      _unlockedProfileKeys[exceptVaultId] = retained;
    }
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

  String _adminStorageKey(String vaultId) => '$storagePrefix.admin.$vaultId';

  List<int> _adminKeyAad(String vaultId, String fingerprint) =>
      utf8.encode('profile-data-key-admin:$vaultId:$fingerprint');

  Future<Map<String, dynamic>?> _readProfilePayload(
    String vaultId, {
    String? stored,
  }) async {
    final value = stored ?? await _secureStore.read('$storagePrefix$vaultId');
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(value) as Map);
      return _isValidWrappedKey(decoded) ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _profilePayloadFingerprint(
    Map<String, dynamic> payload,
  ) async {
    final canonical = <String, dynamic>{
      'version': payload['version'],
      'kdf': payload['kdf'],
      'salt': payload['salt'],
      'wrappedDataKey': payload['wrappedDataKey'],
    };
    final bytes = utf8.encode(jsonEncode(canonical));
    final digest = await Sha256().hash(bytes);
    return base64UrlEncode(digest.bytes);
  }

  Future<bool> _profilePayloadChanged(
    String vaultId,
    Map<String, dynamic>? snapshot,
  ) async {
    if (snapshot == null) return true;
    final current = await _readProfilePayload(vaultId);
    if (current == null) return true;
    return await _profilePayloadFingerprint(snapshot) !=
        await _profilePayloadFingerprint(current);
  }

  Future<void> _persistAdminWrapping({
    required String vaultId,
    required List<int> dataKeyBytes,
    required Map<String, dynamic> profilePayload,
  }) async {
    if (!enableLocalAdminAccess) return;
    final fingerprint = await _profilePayloadFingerprint(profilePayload);
    final masterKey = await _normalMasterKeyService.obtainOrCreate();
    final wrapped = await _encryptionService.encryptBytes(
      clearBytes: dataKeyBytes,
      secretKey: masterKey,
      additionalData: _adminKeyAad(vaultId, fingerprint),
    );
    await _secureStore.write(
      _adminStorageKey(vaultId),
      jsonEncode({
        'version': 1,
        'fingerprint': fingerprint,
        'wrappedDataKey': wrapped,
      }),
    );
  }

  bool _isValidWrappedKey(Map<String, dynamic> decoded) {
    return decoded['version'] == 1 &&
        decoded['kdf'] == 'pbkdf2-sha256' &&
        decoded['salt'] is String &&
        (decoded['salt'] as String).isNotEmpty &&
        decoded['wrappedDataKey'] is String &&
        (decoded['wrappedDataKey'] as String).isNotEmpty;
  }
}
