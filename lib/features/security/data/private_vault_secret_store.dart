import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'encryption_service.dart';
import 'secure_key_value_store.dart';

class PrivateVaultSecretStore {
  PrivateVaultSecretStore({
    required SecureKeyValueStore secureStore,
    required EncryptionService encryptionService,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.storageKey = 'security.private_vault.verifier.v1',
    this.legacySaltKey = 'security.private_vault_salt',
    this.legacyDigestKey = 'security.private_vault_digest',
  }) : _secureStore = secureStore,
       _encryptionService = encryptionService,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String storageKey;
  final String legacySaltKey;
  final String legacyDigestKey;

  Future<bool> hasSecret() async {
    final current = await _secureStore.read(storageKey);
    if (current != null && current.isNotEmpty) {
      return true;
    }

    final prefs = await _sharedPreferencesProvider();
    final legacySalt = prefs.getString(legacySaltKey);
    final legacyDigest = prefs.getString(legacyDigestKey);
    if (legacySalt == null || legacyDigest == null) {
      return false;
    }

    await _secureStore.write(
      storageKey,
      jsonEncode({
        'salt': legacySalt,
        'verifier': legacyDigest,
      }),
    );
    await prefs.remove(legacySaltKey);
    await prefs.remove(legacyDigestKey);
    return true;
  }

  Future<void> configure(String secret) async {
    final salt = _encryptionService.generateSalt();
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: secret,
      salt: salt,
    );
    await _secureStore.write(
      storageKey,
      jsonEncode({
        'salt': base64Encode(salt),
        'verifier': verifier,
      }),
    );
  }

  Future<bool> verify(String secret) async {
    final stored = await _secureStore.read(storageKey);
    if (stored == null || stored.isEmpty) {
      final migrated = await hasSecret();
      if (!migrated) {
        return false;
      }
      return verify(secret);
    }

    final decoded = Map<String, dynamic>.from(
      jsonDecode(stored) as Map<String, dynamic>,
    );
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: secret,
      salt: base64Decode(decoded['salt'] as String),
    );
    return verifier == decoded['verifier'];
  }

  Future<void> clear() async {
    await _secureStore.delete(storageKey);
    final prefs = await _sharedPreferencesProvider();
    await prefs.remove(legacySaltKey);
    await prefs.remove(legacyDigestKey);
  }
}
