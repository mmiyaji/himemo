import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';

import '../../security/data/encryption_service.dart';
import 'sync_v2_history.dart';

/// Encrypts a note body once at edit time. The resulting bytes are reused
/// across publication retries.
class SyncV2PayloadCodec {
  SyncV2PayloadCodec(this._encryption);

  final EncryptionService _encryption;

  Future<({SyncV2Change change, Uint8List encryptedPayload})> seal({
    required String generationId,
    required String changeId,
    required String profileId,
    required String noteId,
    required Set<String> parentIds,
    required Map<String, Object?> body,
    required SecretKey profileKey,
  }) async {
    final parents = Set<String>.of(parentIds);
    final clearBytes = utf8.encode(
      jsonEncode({'v': 1, 'kind': 'note', 'body': body}),
    );
    if (clearBytes.length > 32 * 1024 * 1024) {
      throw const FormatException('Sync v2 body too large');
    }
    final encoded = await _encryption.encryptBytes(
      clearBytes: clearBytes,
      secretKey: profileKey,
      additionalData: _context(generationId, changeId, profileId, noteId),
    );
    final bytes = Uint8List.fromList(utf8.encode(encoded));
    return (
      change: SyncV2Change(
        id: changeId,
        profileId: profileId,
        noteId: noteId,
        operation: SyncV2Operation.upsert,
        parentIds: parents,
        payloadDigest: sha256.convert(bytes).toString(),
      ),
      encryptedPayload: bytes,
    );
  }

  Future<Map<String, Object?>> open({
    required String generationId,
    required SyncV2Change change,
    required Uint8List encryptedPayload,
    required SecretKey profileKey,
  }) async {
    if (encryptedPayload.length > 64 * 1024 * 1024) {
      throw const FormatException('Sync v2 payload too large');
    }
    if (change.payloadDigest != sha256.convert(encryptedPayload).toString()) {
      throw const FormatException('Sync v2 payload digest mismatch');
    }
    final bytes = await _encryption.decryptBytes(
      encodedPayload: utf8.decode(encryptedPayload),
      secretKey: profileKey,
      additionalData: _context(
        generationId,
        change.id,
        change.profileId,
        change.noteId,
      ),
    );
    if (bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('Sync v2 body too large');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?> ||
        decoded.length != 3 ||
        decoded['v'] is! int ||
        decoded['v'] != 1 ||
        decoded['kind'] != 'note' ||
        decoded['body'] is! Map<String, Object?>) {
      throw const FormatException('Invalid sync v2 body');
    }
    return decoded['body'] as Map<String, Object?>;
  }

  List<int> _context(
    String generationId,
    String changeId,
    String profileId,
    String noteId,
  ) {
    if ([
      generationId,
      changeId,
      profileId,
      noteId,
    ].any((id) => id.isEmpty || id.length > 1024)) {
      throw const FormatException('Missing sync v2 payload identity');
    }
    return utf8.encode(
      jsonEncode([
        'himemo.sync.v2.payload',
        generationId,
        changeId,
        profileId,
        noteId,
      ]),
    );
  }
}
