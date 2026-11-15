import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

void main() {
  final encryption = EncryptionService();
  final codec = SyncV2PayloadCodec(encryption);
  final key = SecretKey(List.filled(32, 7));
  const body = <String, Object?>{
    'title': 'note',
    'v': 42,
    'kind': 'user value',
    'nested': {
      'values': [null, true, 123],
    },
  };

  test('versioned payload round trips generic body unchanged', () async {
    final sealed = await codec.seal(
      generationId: 'g',
      changeId: 'c',
      profileId: 'p',
      noteId: 'n',
      parentIds: {},
      body: body,
      profileKey: key,
    );
    final clear = await encryption.decryptBytes(
      encodedPayload: utf8.decode(sealed.encryptedPayload),
      secretKey: key,
      additionalData: utf8.encode(
        jsonEncode(['himemo.sync.v2.payload', 'g', 'c', 'p', 'n']),
      ),
    );
    expect(jsonDecode(utf8.decode(clear)), {
      'v': 1,
      'kind': 'note',
      'body': body,
    });
    expect(
      await codec.open(
        generationId: 'g',
        change: sealed.change,
        encryptedPayload: sealed.encryptedPayload,
        profileKey: key,
      ),
      body,
    );
    for (var index = 0; index < 4; index++) {
      final ids = ['g', 'c', 'p', 'n'];
      ids[index] = 'tampered';
      await expectLater(
        codec.open(
          generationId: ids[0],
          change: SyncV2Change(
            id: ids[1],
            profileId: ids[2],
            noteId: ids[3],
            parentIds: {},
            operation: SyncV2Operation.upsert,
            payloadDigest: sealed.change.payloadDigest,
          ),
          encryptedPayload: sealed.encryptedPayload,
          profileKey: key,
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
    }
  });

  test('rejects authenticated unknown or missing payload metadata', () async {
    for (final envelope in <Object?>[
      body,
      {'body': body},
      {'v': 1, 'body': body},
      {'kind': 'note', 'body': body},
      {'v': 2, 'kind': 'note', 'body': body},
      {'v': 1.0, 'kind': 'note', 'body': body},
      {'v': 1, 'kind': 'change', 'body': body},
      {'v': 1, 'kind': 'note', 'body': []},
      {'v': 1, 'kind': 'note', 'body': body, 'extra': true},
      null,
    ]) {
      final encoded = await encryption.encryptBytes(
        clearBytes: utf8.encode(jsonEncode(envelope)),
        secretKey: key,
        additionalData: utf8.encode(
          jsonEncode(['himemo.sync.v2.payload', 'g', 'c', 'p', 'n']),
        ),
      );
      final bytes = Uint8List.fromList(utf8.encode(encoded));
      await expectLater(
        codec.open(
          generationId: 'g',
          change: SyncV2Change(
            id: 'c',
            profileId: 'p',
            noteId: 'n',
            parentIds: {},
            operation: SyncV2Operation.upsert,
            payloadDigest: sha256.convert(bytes).toString(),
          ),
          encryptedPayload: bytes,
          profileKey: key,
        ),
        throwsFormatException,
      );
    }
  });
}
