import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'authentication_throttle.dart';
import 'encryption_service.dart';
import 'secure_key_value_store.dart';
import 'sync_v2_profile_keys.dart';

/// Local passphrase protection. The caller verifies imported recovery keys
/// against the cloud registration before configuring this store.
class SyncV2AdminStore {
  SyncV2AdminStore(
    this._store,
    EncryptionService encryption, {
    required this.generationId,
  }) : _keys = SyncV2ProfileKeys(encryption);

  final SecureKeyValueStore _store;
  final SyncV2ProfileKeys _keys;
  final String generationId;
  String get storageKey => 'sync.v2.admin.${Uri.encodeComponent(generationId)}';

  Future<void> configure({
    required SecretKey adminKey,
    required String password,
  }) async {
    if (password.length < 12) {
      throw ArgumentError('Use at least 12 characters.');
    }
    final wrapped = await _keys.wrap(
      generationId: generationId,
      profileId: 'admin',
      keyId: 'admin',
      profileKey: adminKey,
      passphrase: password,
      adminKey: adminKey,
    );
    final encoded = jsonEncode(wrapped.toJson());
    await _store.write(storageKey, encoded);
    if (await _store.read(storageKey) != encoded) {
      throw StateError('Admin passphrase persistence failed.');
    }
    await AuthenticationThrottle(
      store: _store,
      storageKey: '$storageKey.attempts',
    ).reset();
  }

  Future<SecretKey?> unlock(String password) async {
    SecretKey? result;
    try {
      await AuthenticationThrottle(
        store: _store,
        storageKey: '$storageKey.attempts',
      ).verify(() async {
        final raw = await _store.read(storageKey);
        if (raw == null || password.isEmpty) return false;
        final record = SyncV2WrappedProfileKey.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (record.profileId != 'admin' || record.keyId != 'admin') {
          throw const FormatException('Invalid admin identity');
        }
        final matches = await _keys.unlockMatching(
          generationId: generationId,
          records: [record],
          passphrase: password,
        );
        result = matches['admin'];
        return result != null;
      });
      return result;
    } catch (_) {
      result?.destroy();
      rethrow;
    }
  }

  Future<String> encodeRecoveryCode(SecretKey adminKey) async {
    final bytes = await adminKey.extractBytes();
    if (bytes.length != 32 ||
        generationId.isEmpty ||
        generationId.length > 1024) {
      throw const FormatException('Invalid admin recovery identity');
    }
    return 'himemo-admin-v2:${base64Url.encode(utf8.encode(jsonEncode({'generation': generationId, 'key': base64Encode(bytes)})))}';
  }

  SecretKey decodeRecoveryCode(String code) {
    try {
      const prefix = 'himemo-admin-v2:';
      if (!code.startsWith(prefix) || code.length > 4096) {
        throw const FormatException();
      }
      final encoded = code.substring(prefix.length);
      final bytes = base64Url.decode(encoded);
      if (base64Url.encode(bytes) != encoded) throw const FormatException();
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map ||
          json.length != 2 ||
          json['generation'] != generationId ||
          generationId.isEmpty ||
          generationId.length > 1024 ||
          json['key'] is! String) {
        throw const FormatException();
      }
      final key = base64Decode(json['key'] as String);
      if (key.length != 32 || base64Encode(key) != json['key']) {
        throw const FormatException();
      }
      return SecretKey(key);
    } catch (_) {
      throw const FormatException('Invalid admin recovery code');
    }
  }
}
