import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secure_key_value_store.dart';

class MasterKeyService {
  MasterKeyService({
    required this._secureStore,
    required this._keyFactory,
    this._storageKey = 'security.master_key.v1',
  });

  final SecureKeyValueStore _secureStore;
  final List<int> Function() _keyFactory;
  final String _storageKey;

  Future<SecretKey> obtainOrCreate() async {
    final existing = await _secureStore.read(_storageKey);
    if (existing != null && existing.isNotEmpty) {
      return SecretKey(base64Decode(existing));
    }

    final generated = _keyFactory();
    await _secureStore.write(_storageKey, base64Encode(generated));
    return SecretKey(generated);
  }
}
