import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';

void main() {
  late EncryptionService encryption;
  late SyncV2HeaderCodec codec;
  final key = SecretKey(List<int>.filled(32, 7));
  const generation = 'generation-1';

  setUp(() {
    encryption = EncryptionService();
    codec = SyncV2HeaderCodec(encryption);
  });

  for (final change in [
    SyncV2Change(
      id: 'record-upsert',
      profileId: 'profile-1',
      noteId: 'note-1',
      parentIds: {'parent-b', 'parent-a'},
      operation: SyncV2Operation.upsert,
      payloadDigest: 'a' * 64,
    ),
    SyncV2Change(
      id: 'record-delete',
      profileId: 'profile-1',
      noteId: 'note-2',
      parentIds: {'parent-a'},
      operation: SyncV2Operation.delete,
    ),
  ]) {
    test('encrypted ${change.operation.name} header round trips', () async {
      final sealed = await codec.seal(
        change,
        generationId: generation,
        syncKey: key,
      );

      final opened = await codec.open(
        sealed,
        generationId: generation,
        recordId: change.id,
        syncKey: key,
      );

      final canonical = jsonDecode(codec.canonicalHeader(change)) as Map;
      expect(canonical['v'], 1);
      expect(canonical['kind'], 'change');
      expect(opened.id, change.id);
      expect(opened.profileId, change.profileId);
      expect(opened.noteId, change.noteId);
      expect(opened.parentIds, change.parentIds);
      expect(opened.operation, change.operation);
      expect(opened.payloadDigest, change.payloadDigest);
    });
  }

  test('authenticated header is bound to record, generation and key', () async {
    final change = SyncV2Change(
      id: 'record-1',
      profileId: 'profile-1',
      noteId: 'note-1',
      parentIds: const {},
      operation: SyncV2Operation.upsert,
      payloadDigest: 'b' * 64,
    );
    final sealed = await codec.seal(
      change,
      generationId: generation,
      syncKey: key,
    );

    await expectLater(
      codec.open(
        sealed,
        generationId: generation,
        recordId: 'different-record',
        syncKey: key,
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );
    await expectLater(
      codec.open(
        sealed,
        generationId: 'different-generation',
        recordId: change.id,
        syncKey: key,
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );
    await expectLater(
      codec.open(
        sealed,
        generationId: generation,
        recordId: change.id,
        syncKey: SecretKey(List<int>.filled(32, 8)),
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );
  });

  test(
    'rejects missing and unsupported authenticated header metadata',
    () async {
      for (final metadata in [
        <String, Object?>{},
        {'v': 1},
        {'kind': 'change'},
        {'v': 2, 'kind': 'change'},
        {'v': 1.0, 'kind': 'change'},
        {'v': 1, 'kind': 'note'},
      ]) {
        final sealed = await encryption.encryptBytes(
          clearBytes: utf8.encode(
            jsonEncode({
              ...metadata,
              'profile': 'p',
              'note': 'n',
              'parents': [],
              'op': 'delete',
              'payload': null,
            }),
          ),
          secretKey: key,
          additionalData: utf8.encode(
            jsonEncode(['himemo.sync.v2.header', generation, 'r']),
          ),
        );
        await expectLater(
          codec.open(
            sealed,
            generationId: generation,
            recordId: 'r',
            syncKey: key,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('rejects malformed authenticated headers and payload digests', () async {
    final aad = utf8.encode(
      jsonEncode(['himemo.sync.v2.header', generation, 'record-1']),
    );
    final malformed = await encryption.encryptBytes(
      clearBytes: utf8.encode(
        jsonEncode({
          'v': 1,
          'kind': 'change',
          'profile': 'profile-1',
          'note': 'note-1',
          'parents': ['parent-1', 'parent-1'],
          'op': 'upsert',
          'payload': 'c' * 64,
        }),
      ),
      secretKey: key,
      additionalData: aad,
    );
    await expectLater(
      codec.open(
        malformed,
        generationId: generation,
        recordId: 'record-1',
        syncKey: key,
      ),
      throwsFormatException,
    );

    final invalidDigest = SyncV2Change(
      id: 'record-1',
      profileId: 'profile-1',
      noteId: 'note-1',
      parentIds: const {},
      operation: SyncV2Operation.upsert,
      payloadDigest: 'not-a-sha256-digest',
    );
    expect(
      () => codec.seal(invalidDigest, generationId: generation, syncKey: key),
      throwsFormatException,
    );
  });
}
