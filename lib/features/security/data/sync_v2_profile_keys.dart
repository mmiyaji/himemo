import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'encryption_service.dart';

/// Portable encrypted copies of a profile key, never an unlock session.
class SyncV2WrappedProfileKey {
  const SyncV2WrappedProfileKey({
    required this.profileId,
    required this.keyId,
    required this.salt,
    required this.passphraseWrap,
    required this.adminWrap,
    this.adminOnly = false,
  });

  final String profileId;
  final String keyId;
  final String salt;
  final String passphraseWrap;
  final String adminWrap;
  final bool adminOnly;

  static const format = 'himemo.sync.v2.profile-key';
  static const formatVersion = 1;
  static const adminOnlyFormatVersion = 2;
  static const kdfMemoryKiB = 64 * 1024;
  static const kdfIterations = 3;
  static const kdfParallelism = 4;
  static const kdfHashLength = 32;
  // Argon2 v1.3 is encoded as 0x13 (decimal 19), not decimal 13.
  static const kdfAlgorithmVersion = 0x13;

  static const _kdf = <String, Object>{
    'algorithm': 'argon2id',
    'algorithmVersion': kdfAlgorithmVersion,
    'memoryKiB': kdfMemoryKiB,
    'iterations': kdfIterations,
    'parallelism': kdfParallelism,
    'hashLength': kdfHashLength,
  };

  factory SyncV2WrappedProfileKey.fromJson(Map<String, dynamic> json) {
    String string(String name) {
      final value = json[name];
      if (value is! String) {
        throw FormatException('Invalid v2 profile key $name');
      }
      return value;
    }

    if (json['format'] == format &&
        json['version'] is int &&
        json['version'] == adminOnlyFormatVersion) {
      const fields = {
        'format',
        'version',
        'mode',
        'profileId',
        'keyId',
        'adminWrap',
      };
      if (json.length != fields.length ||
          !json.keys.every(fields.contains) ||
          json['mode'] != 'admin-only') {
        throw const FormatException('Unsupported v2 profile key format');
      }
      final record = SyncV2WrappedProfileKey(
        profileId: string('profileId'),
        keyId: string('keyId'),
        salt: '',
        passphraseWrap: '',
        adminWrap: string('adminWrap'),
        adminOnly: true,
      );
      record._validate();
      return record;
    }
    const fields = {
      'format',
      'version',
      'kdf',
      'profileId',
      'keyId',
      'salt',
      'passphraseWrap',
      'adminWrap',
    };
    if (json.length != fields.length ||
        !json.keys.every(fields.contains) ||
        json['format'] != format ||
        json['version'] is! int ||
        json['version'] != formatVersion) {
      throw const FormatException('Unsupported v2 profile key format');
    }
    final kdf = json['kdf'];
    if (kdf is! Map ||
        kdf.length != _kdf.length ||
        !_kdf.entries.every(
          (entry) =>
              kdf[entry.key].runtimeType == entry.value.runtimeType &&
              kdf[entry.key] == entry.value,
        )) {
      throw const FormatException('Unsupported v2 profile key KDF');
    }
    final record = SyncV2WrappedProfileKey(
      profileId: string('profileId'),
      keyId: string('keyId'),
      salt: string('salt'),
      passphraseWrap: string('passphraseWrap'),
      adminWrap: string('adminWrap'),
    );
    record._validate();
    return record;
  }

  Map<String, dynamic> toJson() {
    _validate();
    if (adminOnly) {
      return {
        'format': format,
        'version': adminOnlyFormatVersion,
        'mode': 'admin-only',
        'profileId': profileId,
        'keyId': keyId,
        'adminWrap': adminWrap,
      };
    }
    return {
      'format': format,
      'version': formatVersion,
      'kdf': {..._kdf},
      'profileId': profileId,
      'keyId': keyId,
      'salt': salt,
      'passphraseWrap': passphraseWrap,
      'adminWrap': adminWrap,
    };
  }

  void _validate() {
    for (final id in [profileId, keyId]) {
      if (id.isEmpty || id.length > 1024) {
        throw const FormatException('Invalid v2 profile key identity');
      }
    }
    if (adminOnly) {
      if (salt.isNotEmpty || passphraseWrap.isNotEmpty) {
        throw const FormatException('Invalid admin-only v2 profile key');
      }
      _validateWrap(adminWrap);
      return;
    }
    _base64(salt, 16);
    for (final wrap in [passphraseWrap, adminWrap]) {
      _validateWrap(wrap);
    }
  }

  static void _validateWrap(String wrap) {
    if (wrap.isEmpty || wrap.length > 4096) {
      throw const FormatException('Invalid v2 profile key wrap');
    }
    final box = jsonDecode(wrap);
    if (box is! Map ||
        box.length != 4 ||
        box['version'] is! int ||
        box['version'] != 1) {
      throw const FormatException('Invalid v2 profile key wrap');
    }
    _base64(box['nonce'], 12);
    _base64(box['cipherText'], 32);
    _base64(box['mac'], 16);
  }

  static List<int> _base64(Object? value, int length) {
    if (value is! String || value.length != ((length + 2) ~/ 3) * 4) {
      throw const FormatException('Invalid v2 profile key base64');
    }
    final bytes = base64Decode(value);
    if (bytes.length != length || base64Encode(bytes) != value) {
      throw const FormatException('Invalid v2 profile key base64');
    }
    return bytes;
  }
}

/// A profile key whose identity was authenticated by an encrypted wrapper.
final class SyncV2UnlockedProfileKey {
  SyncV2UnlockedProfileKey._({
    required this.generationId,
    required this.profileId,
    required this.keyId,
    required this.key,
  });

  final String generationId;
  final String profileId;
  final String keyId;
  final SecretKey key;

  void destroy() => key.destroy();

  static Future<SyncV2UnlockedProfileKey> unlockNormal({
    required EncryptionService encryption,
    required String accountId,
    required String generationId,
    required String profileId,
    required String keyId,
    required String syncWrap,
    required SecretKey syncKey,
  }) async {
    if ([
          accountId,
          generationId,
          profileId,
          keyId,
        ].any((id) => id.isEmpty || id.length > 1024) ||
        syncWrap.isEmpty ||
        syncWrap.length > 4096) {
      throw const FormatException('Invalid normal v2 profile key wrapper');
    }
    final bytes = await encryption.decryptBytes(
      encodedPayload: syncWrap,
      secretKey: syncKey,
      additionalData: utf8.encode(
        jsonEncode([
          'himemo-sync-v2-registration',
          1,
          accountId,
          generationId,
          'normal-sync-wrap',
          profileId,
          keyId,
        ]),
      ),
    );
    if (bytes.length != 32) {
      throw const FormatException('Invalid normal v2 profile key length');
    }
    return SyncV2UnlockedProfileKey._(
      generationId: generationId,
      profileId: profileId,
      keyId: keyId,
      key: SecretKey(bytes),
    );
  }
}

class SyncV2ProfileKeys {
  SyncV2ProfileKeys(this._encryption);

  final EncryptionService _encryption;

  Future<Map<String, SyncV2UnlockedProfileKey>> unlockMatchingSessions({
    required String generationId,
    required Iterable<SyncV2WrappedProfileKey> records,
    required String passphrase,
  }) async {
    final snapshot = records.toList();
    final keys = await unlockMatching(
      generationId: generationId,
      records: snapshot,
      passphrase: passphrase,
    );
    final identities = {
      for (final record in snapshot) record.profileId: record,
    };
    return {
      for (final entry in keys.entries)
        entry.key: SyncV2UnlockedProfileKey._(
          generationId: generationId,
          profileId: entry.key,
          keyId: identities[entry.key]!.keyId,
          key: entry.value,
        ),
    };
  }

  Future<SyncV2UnlockedProfileKey> unlockForAdminSession({
    required String generationId,
    required SyncV2WrappedProfileKey record,
    required SecretKey adminKey,
  }) async => SyncV2UnlockedProfileKey._(
    generationId: generationId,
    profileId: record.profileId,
    keyId: record.keyId,
    key: await unlockForAdmin(
      generationId: generationId,
      record: record,
      adminKey: adminKey,
    ),
  );

  Future<SyncV2WrappedProfileKey> wrap({
    required String generationId,
    required String profileId,
    required String keyId,
    required SecretKey profileKey,
    required String passphrase,
    required SecretKey adminKey,
  }) async {
    _validatePassphrase(passphrase);
    _context(generationId, profileId, keyId, 'passphrase');
    final salt = _encryption.generateKeyBytes(length: 16);
    final passphraseKey = await _derive(passphrase, salt);
    try {
      final bytes = await profileKey.extractBytes();
      if (bytes.length != 32) throw ArgumentError('Invalid profile key length');
      return SyncV2WrappedProfileKey(
        profileId: profileId,
        keyId: keyId,
        salt: base64Encode(salt),
        passphraseWrap: await _encryption.encryptBytes(
          clearBytes: bytes,
          secretKey: passphraseKey,
          additionalData: _context(
            generationId,
            profileId,
            keyId,
            'passphrase',
          ),
        ),
        adminWrap: await _encryption.encryptBytes(
          clearBytes: bytes,
          secretKey: adminKey,
          additionalData: _context(generationId, profileId, keyId, 'admin'),
        ),
      );
    } finally {
      passphraseKey.destroy();
    }
  }

  /// Wraps a profile key for administrator recovery without creating a
  /// passphrase wrapper or deriving a passphrase key.
  Future<SyncV2WrappedProfileKey> wrapAdminOnly({
    required String generationId,
    required String profileId,
    required String keyId,
    required SecretKey profileKey,
    required SecretKey adminKey,
  }) async {
    final context = _context(generationId, profileId, keyId, 'admin');
    final bytes = await profileKey.extractBytes();
    if (bytes.length != 32) throw ArgumentError('Invalid profile key length');
    return SyncV2WrappedProfileKey(
      profileId: profileId,
      keyId: keyId,
      salt: '',
      passphraseWrap: '',
      adminWrap: await _encryption.encryptBytes(
        clearBytes: bytes,
        secretKey: adminKey,
        additionalData: context,
      ),
      adminOnly: true,
    );
  }

  /// Call only from the user-driven unlock flow after applying its throttle.
  Future<Map<String, SecretKey>> unlockMatching({
    required String generationId,
    required Iterable<SyncV2WrappedProfileKey> records,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    final matched = <String, SecretKey>{};
    final seenProfiles = <String>{};
    try {
      final validated = records.toList();
      for (final record in validated) {
        record._validate();
        _context(generationId, record.profileId, record.keyId, 'passphrase');
        if (!seenProfiles.add(record.profileId)) {
          throw const FormatException('Duplicate active v2 profile key');
        }
      }
      for (final record in validated) {
        if (record.adminOnly) continue;
        final salt = base64Decode(record.salt);
        if (salt.length != 16) {
          throw const FormatException('Invalid v2 key salt');
        }
        final passphraseKey = await _derive(passphrase, salt);
        try {
          final key = await _unwrap(
            generationId,
            record,
            record.passphraseWrap,
            passphraseKey,
            'passphrase',
          );
          matched[record.profileId] = key;
        } on HimemoDecryptionException {
          // A nonmatching profile is left locked. Continue to find all matches.
        } finally {
          passphraseKey.destroy();
        }
      }
      return matched;
    } catch (_) {
      for (final key in matched.values) {
        key.destroy();
      }
      rethrow;
    }
  }

  Future<SecretKey> unlockForAdmin({
    required String generationId,
    required SyncV2WrappedProfileKey record,
    required SecretKey adminKey,
  }) async {
    record._validate();
    return _unwrap(generationId, record, record.adminWrap, adminKey, 'admin');
  }

  void _validatePassphrase(String passphrase) {
    if (passphrase.isEmpty || passphrase.length > 65536) {
      throw ArgumentError('Invalid profile passphrase length');
    }
  }

  Future<SecretKey> _derive(String passphrase, List<int> salt) async {
    final bytes = await compute(_deriveProfileKeyBytes, (
      passphrase: passphrase,
      salt: salt,
    ), debugLabel: 'sync-v2-argon2id');
    return SecretKey(bytes);
  }

  Future<SecretKey> _unwrap(
    String generationId,
    SyncV2WrappedProfileKey record,
    String encrypted,
    SecretKey wrappingKey,
    String purpose,
  ) async {
    final bytes = await _encryption.decryptBytes(
      encodedPayload: encrypted,
      secretKey: wrappingKey,
      additionalData: _context(
        generationId,
        record.profileId,
        record.keyId,
        purpose,
      ),
    );
    if (bytes.length != 32) {
      throw const FormatException('Invalid v2 profile key');
    }
    return SecretKey(bytes);
  }

  List<int> _context(
    String generation,
    String profile,
    String key,
    String purpose,
  ) {
    if ([
      generation,
      profile,
      key,
    ].any((id) => id.isEmpty || id.length > 1024)) {
      throw const FormatException('Missing v2 profile key identity');
    }
    return utf8.encode(
      jsonEncode([
        'himemo.sync.v2.profile-key',
        generation,
        profile,
        key,
        purpose,
      ]),
    );
  }
}

// Parameters are part of the portable v2 format. Native platforms compute in
// another isolate. Flutter Web uses the library's cooperative Dart fallback.
Future<List<int>> _deriveProfileKeyBytes(
  ({String passphrase, List<int> salt}) request,
) async {
  final input = SecretKey(utf8.encode(request.passphrase));
  SecretKey? derived;
  try {
    derived = await Argon2id(
      parallelism: SyncV2WrappedProfileKey.kdfParallelism,
      memory: SyncV2WrappedProfileKey.kdfMemoryKiB,
      iterations: SyncV2WrappedProfileKey.kdfIterations,
      hashLength: SyncV2WrappedProfileKey.kdfHashLength,
    ).deriveKey(secretKey: input, nonce: request.salt);
    return List<int>.from(await derived.extractBytes());
  } finally {
    input.destroy();
    derived?.destroy();
  }
}
