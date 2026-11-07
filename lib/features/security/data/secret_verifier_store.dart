import 'dart:convert';

import 'authentication_throttle.dart';
import 'encryption_service.dart';
import 'secure_key_value_store.dart';
import 'storage_serial_executor.dart';

/// Shared verifier encoding and comparison for app PIN and local secrets.
class SecretVerifierStore {
  SecretVerifierStore({
    required this._secureStore,
    required this._encryptionService,
    required this.storageKey,
    SecureKeyValueStore? attemptStore,
  }) : _throttle = AuthenticationThrottle(
         store: attemptStore ?? _secureStore,
         storageKey: '$storageKey.attempts.v1',
       );

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final String storageKey;
  final AuthenticationThrottle _throttle;

  Future<bool> hasSecret() async {
    final payload = await _secureStore.read(storageKey);
    return payload != null && payload.isNotEmpty;
  }

  Future<void> configure(String secret) async {
    final salt = _encryptionService.generateSalt();
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: secret,
      salt: salt,
    );
    await StorageSerialExecutor.run(_secureStore, storageKey, () async {
      final payload = jsonEncode({
        'salt': base64Encode(salt),
        'verifier': verifier,
      });
      await _secureStore.write(storageKey, payload);
      if (await _secureStore.read(storageKey) != payload) {
        throw StateError('Secret verifier persistence failed.');
      }
    });
    await _throttle.reset();
  }

  Future<bool> verify(String secret) =>
      _throttle.verify(() => verifyWithoutThrottle(secret));

  /// Only call inside an outer authentication throttle that counts this guess.
  Future<bool> verifyWithoutThrottle(String secret) async {
    final payload = await _secureStore.read(storageKey);
    if (payload == null || payload.isEmpty) return false;
    final decoded = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    final actual = await _encryptionService.deriveSecretVerifier(
      secret: secret,
      salt: base64Decode(decoded['salt'] as String),
    );
    return constantTimeVerifierEquals(decoded['verifier'] as String, actual);
  }

  Future<void> clear() async {
    await StorageSerialExecutor.run(
      _secureStore,
      storageKey,
      () => _secureStore.delete(storageKey),
    );
    await _throttle.reset();
  }
}

bool constantTimeVerifierEquals(String left, String right) {
  final a = utf8.encode(left);
  final b = utf8.encode(right);
  var difference = a.length ^ b.length;
  final length = a.length > b.length ? a.length : b.length;
  for (var index = 0; index < length; index++) {
    difference |=
        (index < a.length ? a[index] : 0) ^ (index < b.length ? b[index] : 0);
  }
  return difference == 0;
}
