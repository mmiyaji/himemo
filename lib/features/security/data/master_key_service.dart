import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secure_key_value_store.dart';
import 'storage_serial_executor.dart';

class MasterKeyService {
  MasterKeyService({
    required this._secureStore,
    required this._keyFactory,
    this._storageKey = 'security.master_key.v1',
  });

  final SecureKeyValueStore _secureStore;
  final List<int> Function() _keyFactory;
  final String _storageKey;

  Future<SecretKey> obtainOrCreate() =>
      StorageSerialExecutor.run(_secureStore, _storageKey, _obtainOrCreate);

  /// Reads the persisted key without creating one when it is absent.
  Future<SecretKey?> readExisting() =>
      StorageSerialExecutor.run(_secureStore, _storageKey, _readExisting);

  Future<SecretKey?> _readExisting() async {
    final existing = await _secureStore.read(_storageKey);
    if (existing == null) return null;
    final bytes = base64Decode(existing);
    if (bytes.length != 32) {
      throw const FormatException('Stored master key must contain 32 bytes.');
    }
    return SecretKey(bytes);
  }

  Future<SecretKey> _obtainOrCreate() async {
    final existing = await _secureStore.read(_storageKey);
    if (existing != null) {
      final bytes = base64Decode(existing);
      if (bytes.length != 32) {
        throw const FormatException('Stored master key must contain 32 bytes.');
      }
      return SecretKey(bytes);
    }

    final generated = _keyFactory();
    if (generated.length != 32) {
      throw StateError('Master key factory must generate exactly 32 bytes.');
    }
    final encoded = base64Encode(generated);
    await _secureStore.write(_storageKey, encoded);
    if (await _secureStore.read(_storageKey) != encoded) {
      throw StateError('Master key persistence could not be confirmed.');
    }
    return SecretKey(generated);
  }
}
