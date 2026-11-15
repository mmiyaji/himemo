import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../security/data/encryption_service.dart';
import 'sync_v2_history.dart';

/// The cloud sees an opaque record ID and an authenticated encrypted header.
class SyncV2HeaderCodec {
  SyncV2HeaderCodec(this._encryption);

  final EncryptionService _encryption;
  static final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  Future<String> seal(
    SyncV2Change change, {
    required String generationId,
    required SecretKey syncKey,
  }) {
    if (change.payloadDigest case final digest?) {
      if (!_sha256Hex.hasMatch(digest)) {
        throw const FormatException('Invalid sync v2 payload digest');
      }
    }
    return _encryption.encryptBytes(
      clearBytes: utf8.encode(canonicalHeader(change)),
      secretKey: syncKey,
      additionalData: _context(generationId, change.id),
    );
  }

  Future<SyncV2Change> open(
    String encryptedHeader, {
    required String generationId,
    required String recordId,
    required SecretKey syncKey,
  }) async {
    if (encryptedHeader.length > 1024 * 1024) {
      throw const FormatException('Sync v2 header too large');
    }
    final bytes = await _encryption.decryptBytes(
      encodedPayload: encryptedHeader,
      secretKey: syncKey,
      additionalData: _context(generationId, recordId),
    );
    if (bytes.length > 512 * 1024) {
      throw const FormatException('Sync v2 header too large');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded case {
      'v': final int version,
      'kind': 'change',
      'profile': final String profileId,
      'note': final String noteId,
      'parents': final List<Object?> parents,
      'op': final String operation,
      'payload': final Object? digest,
    }) {
      if (version != 1 ||
          decoded.length != 7 ||
          profileId.isEmpty ||
          profileId.length > 1024 ||
          noteId.isEmpty ||
          noteId.length > 1024 ||
          parents.length > 4096 ||
          parents.any(
            (parent) =>
                parent is! String || parent.isEmpty || parent.length > 1024,
          ) ||
          parents.toSet().length != parents.length ||
          (digest != null &&
              (digest is! String || !_sha256Hex.hasMatch(digest)))) {
        throw const FormatException('Invalid sync v2 header');
      }
      return SyncV2Change(
        id: recordId,
        profileId: profileId,
        noteId: noteId,
        operation: switch (operation) {
          'upsert' => SyncV2Operation.upsert,
          'delete' => SyncV2Operation.delete,
          _ => throw const FormatException('Unknown sync v2 operation'),
        },
        parentIds: parents.cast<String>().toSet(),
        payloadDigest: digest as String?,
      );
    }
    throw const FormatException('Invalid sync v2 header');
  }

  String canonicalHeader(SyncV2Change change) {
    if ([
          change.profileId,
          change.noteId,
          ...change.parentIds,
        ].any((id) => id.isEmpty || id.length > 1024) ||
        change.parentIds.length > 4096) {
      throw const FormatException('Invalid sync v2 header identity');
    }
    final encoded = jsonEncode({
      'v': 1,
      'kind': 'change',
      'profile': change.profileId,
      'note': change.noteId,
      'parents': change.parentIds.toList()..sort(),
      'op': change.operation.name,
      'payload': change.payloadDigest,
    });
    if (utf8.encode(encoded).length > 512 * 1024) {
      throw const FormatException('Sync v2 header too large');
    }
    return encoded;
  }

  List<int> _context(String generationId, String recordId) {
    if (generationId.isEmpty ||
        generationId.length > 1024 ||
        recordId.isEmpty ||
        recordId.length > 1024) {
      throw const FormatException('Missing sync v2 record identity');
    }
    return utf8.encode(
      jsonEncode(['himemo.sync.v2.header', generationId, recordId]),
    );
  }
}
