import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'encryption_service.dart';
import 'secure_key_value_store.dart';
import 'secret_verifier_store.dart';
import 'storage_serial_executor.dart';

class PrivateVaultSecretStore extends SecretVerifierStore {
  // Keep explicit parameters: the migration also owns this store reference.
  // ignore: use_super_parameters
  PrivateVaultSecretStore({
    required SecureKeyValueStore secureStore,
    required EncryptionService encryptionService,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    String storageKey = 'security.private_vault.verifier.v1',
    this.legacySaltKey = 'security.private_vault_salt',
    this.legacyDigestKey = 'security.private_vault_digest',
  }) : _secureStore = secureStore,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance,
       super(
         secureStore: secureStore,
         encryptionService: encryptionService,
         storageKey: storageKey,
       );

  final SecureKeyValueStore _secureStore;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String legacySaltKey;
  final String legacyDigestKey;

  @override
  Future<bool> hasSecret() =>
      StorageSerialExecutor.run(_secureStore, storageKey, () async {
        final current = await _secureStore.read(storageKey);
        if (current != null && current.isNotEmpty) return true;
        final prefs = await _sharedPreferencesProvider();
        final salt = prefs.getString(legacySaltKey);
        final verifier = prefs.getString(legacyDigestKey);
        if (salt == null || verifier == null) return false;
        final payload = jsonEncode({'salt': salt, 'verifier': verifier});
        await _secureStore.write(storageKey, payload);
        if (await _secureStore.read(storageKey) != payload) {
          // Keep the recoverable legacy verifier until durable storage is confirmed.
          throw StateError('Private secret migration persistence failed.');
        }
        await prefs.remove(legacySaltKey);
        await prefs.remove(legacyDigestKey);
        return true;
      });

  @override
  Future<bool> verifyWithoutThrottle(String secret) async {
    if (!await hasSecret()) return false;
    return super.verifyWithoutThrottle(secret);
  }

  @override
  Future<void> clear() async {
    await super.clear();
    final prefs = await _sharedPreferencesProvider();
    await prefs.remove(legacySaltKey);
    await prefs.remove(legacyDigestKey);
  }
}
