import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_publisher.dart';

class _CommitThenLoseResponse implements SyncV2WriteTransport {
  final Map<String, SyncV2Publication> remote = {};
  final List<SyncV2Publication> attempts = [];
  bool loseFirstResponse = true;

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) async {
    final snapshot = (
      id: publication.id,
      encryptedHeader: publication.encryptedHeader,
      encryptedPayload: publication.encryptedPayload == null
          ? null
          : Uint8List.fromList(publication.encryptedPayload!),
    );
    attempts.add(snapshot);
    final previous = remote[publication.id];
    if (previous != null) {
      if (previous.encryptedHeader != publication.encryptedHeader ||
          !_sameBytes(
            previous.encryptedPayload,
            publication.encryptedPayload,
          )) {
        throw StateError('Remote ID was replayed with different bytes');
      }
    } else {
      remote[publication.id] = snapshot;
    }

    if (loseFirstResponse) {
      loseFirstResponse = false;
      throw StateError('Simulated lost response after remote commit');
    }
  }

  bool _sameBytes(Uint8List? left, Uint8List? right) {
    if (left == null || right == null) return left == right;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

class _PermanentFirstFailure implements SyncV2WriteTransport {
  _PermanentFirstFailure([this.code = 'cloudkit_v2_recordCollision']);

  final String code;
  final List<String> attempts = [];
  final List<String> published = [];
  bool repaired = false;

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) async {
    attempts.add(publication.id);
    if (publication.id == 'broken' && !repaired) {
      throw PlatformException(code: code);
    }
    published.add(publication.id);
  }
}

void main() {
  late SyncV2Inbox inbox;
  late SyncV2HeaderCodec headerCodec;
  late SyncV2PayloadCodec payloadCodec;
  final syncKey = SecretKey(List<int>.filled(32, 21));
  final profileKey = SecretKey(List<int>.filled(32, 34));
  final wrongProfileKey = SecretKey(List<int>.filled(32, 35));
  const generationId = 'generation-1';

  setUp(() {
    final encryption = EncryptionService();
    headerCodec = SyncV2HeaderCodec(encryption);
    payloadCodec = SyncV2PayloadCodec(encryption);
    inbox = SyncV2Inbox(NativeDatabase.memory(), headerCodec);
  });

  tearDown(() async {
    await inbox.close();
  });

  test(
    'retries committed publication byte for byte and retains local history',
    () async {
      const body = {
        'text': 'private note',
        'tags': ['one', 'two'],
      };
      final sealed = await payloadCodec.seal(
        generationId: generationId,
        changeId: 'change-1',
        profileId: 'profile-1',
        noteId: 'note-1',
        parentIds: const {},
        body: body,
        profileKey: profileKey,
      );
      await inbox.queuePublication(
        generationId: generationId,
        change: sealed.change,
        encryptedPayload: sealed.encryptedPayload,
        syncKey: syncKey,
      );

      final transport = _CommitThenLoseResponse();
      final publisher = SyncV2Publisher(transport, inbox);
      await expectLater(
        publisher.publishPage(generationId: generationId, limit: 10),
        throwsStateError,
      );

      expect(transport.remote, hasLength(1));
      final queuedAfterLostResponse = await inbox.readOutbox(
        generationId: generationId,
        limit: 10,
      );
      expect(queuedAfterLostResponse, hasLength(1));
      expect(transport.attempts, hasLength(1));

      expect(
        await publisher.publishPage(generationId: generationId, limit: 10),
        1,
      );
      expect(transport.attempts, hasLength(2));
      expect(transport.remote, hasLength(1));
      expect(
        transport.attempts[1].encryptedHeader,
        transport.attempts[0].encryptedHeader,
      );
      expect(
        transport.attempts[1].encryptedPayload,
        orderedEquals(transport.attempts[0].encryptedPayload!),
      );
      expect(
        await inbox.readOutbox(generationId: generationId, limit: 10),
        isEmpty,
      );

      // Acknowledgement removes only the pending upload; the encrypted local
      // history remains available for subsequent sync and recovery.
      final localHeader = await inbox.readPage(
        generationId: generationId,
        limit: 10,
      );
      expect(localHeader, hasLength(1));
      expect(localHeader.single.id, sealed.change.id);
      final openedChange = await headerCodec.open(
        localHeader.single.encryptedHeader,
        generationId: generationId,
        recordId: sealed.change.id,
        syncKey: syncKey,
      );
      expect(
        headerCodec.canonicalHeader(openedChange),
        headerCodec.canonicalHeader(sealed.change),
      );
      final localPayload = await inbox.readPayload(
        generationId: generationId,
        recordId: sealed.change.id,
      );
      expect(localPayload, orderedEquals(sealed.encryptedPayload));
      expect(
        await payloadCodec.open(
          generationId: generationId,
          change: openedChange,
          encryptedPayload: localPayload!,
          profileKey: profileKey,
        ),
        body,
      );
    },
  );

  test('encrypted body cannot be opened with another profile key', () async {
    final sealed = await payloadCodec.seal(
      generationId: generationId,
      changeId: 'change-key-check',
      profileId: 'profile-1',
      noteId: 'note-1',
      parentIds: const {},
      body: const {'text': 'belongs to profile one'},
      profileKey: profileKey,
    );

    await expectLater(
      payloadCodec.open(
        generationId: generationId,
        change: sealed.change,
        encryptedPayload: sealed.encryptedPayload,
        profileKey: wrongProfileKey,
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );
  });

  test(
    'strict workspace blocks referencing notes until failed chunks retry first',
    () async {
      for (final id in ['broken', 'referencing-note']) {
        final sealed = await payloadCodec.seal(
          generationId: generationId,
          changeId: id,
          profileId: 'profile-1',
          noteId: id == 'broken' ? 'blob_chunk' : 'note_reference',
          parentIds: {},
          profileKey: profileKey,
          body: id == 'broken'
              ? {'type': 'attachment-chunk', 'bytes': 'AQ=='}
              : {
                  'type': 'note',
                  'attachments': ['blob_chunk'],
                },
        );
        await inbox.queuePublication(
          generationId: generationId,
          change: sealed.change,
          encryptedPayload: sealed.encryptedPayload,
          syncKey: syncKey,
        );
      }
      final transport = _PermanentFirstFailure();
      final publisher = SyncV2Publisher(transport, inbox);
      expect(
        await publisher.publishPage(
          generationId: generationId,
          limit: 10,
          stopOnQuarantine: true,
        ),
        0,
      );
      expect(transport.attempts, ['broken']);
      expect(transport.published, isEmpty);
      transport.repaired = true;
      expect(
        await publisher.publishPage(
          generationId: generationId,
          limit: 10,
          stopOnQuarantine: true,
        ),
        0,
      );
      expect(transport.attempts, ['broken']);
      await inbox.retryPublication(
        generationId: generationId,
        recordId: 'broken',
      );
      expect(
        await publisher.publishPage(
          generationId: generationId,
          limit: 10,
          stopOnQuarantine: true,
        ),
        2,
      );
      expect(transport.published, ['broken', 'referencing-note']);
    },
  );

  test(
    'quarantines permanent failures and continues within processing limit',
    () async {
      for (final id in ['broken', 'next']) {
        final change = SyncV2Change(
          id: id,
          profileId: 'profile-1',
          noteId: 'note-$id',
          operation: SyncV2Operation.delete,
          parentIds: const {},
        );
        await inbox.queuePublication(
          generationId: generationId,
          change: change,
          encryptedPayload: null,
          syncKey: syncKey,
        );
      }
      final transport = _PermanentFirstFailure();
      final publisher = SyncV2Publisher(transport, inbox);
      expect(
        await publisher.publishPage(generationId: generationId, limit: 2),
        1,
      );
      expect(transport.published, ['next']);
      expect(
        await inbox.readOutbox(generationId: generationId, limit: 10),
        isEmpty,
      );
      final failure = (await inbox.readFailures(generationId)).single;
      expect(
        (failure.id, failure.phase, failure.reason),
        ('broken', 'publication', 'recordCollision'),
      );
      expect(failure.retryAt, isNull);

      await inbox.retryPublication(
        generationId: generationId,
        recordId: 'broken',
      );
      expect(
        (await inbox.readOutbox(
          generationId: generationId,
          limit: 10,
        )).single.id,
        'broken',
      );
      expect(await inbox.readFailures(generationId), isEmpty);
    },
  );

  test(
    'publication page bounds processed records including quarantines',
    () async {
      for (final id in ['broken', 'next']) {
        await inbox.queuePublication(
          generationId: generationId,
          change: SyncV2Change(
            id: id,
            profileId: 'profile-1',
            noteId: 'note-$id',
            operation: SyncV2Operation.delete,
            parentIds: const {},
          ),
          encryptedPayload: null,
          syncKey: syncKey,
        );
      }
      final publisher = SyncV2Publisher(_PermanentFirstFailure(), inbox);
      expect(
        await publisher.publishPage(generationId: generationId, limit: 1),
        0,
      );
      expect(
        (await inbox.readOutbox(
          generationId: generationId,
          limit: 10,
        )).map((entry) => entry.id),
        ['next'],
      );
    },
  );

  for (final failure in {
    '12': 'invalidArguments',
    '16': 'assetFileNotFound',
    '17': 'assetFileModified',
  }.entries) {
    test('native ${failure.key} quarantines only the failed record', () async {
      for (final id in ['broken', 'next']) {
        final sealed = await payloadCodec.seal(
          generationId: generationId,
          changeId: id,
          profileId: 'profile-1',
          noteId: 'note-$id',
          parentIds: const {},
          body: const {'text': 'retain original ciphertext'},
          profileKey: profileKey,
        );
        await inbox.queuePublication(
          generationId: generationId,
          change: sealed.change,
          encryptedPayload: sealed.encryptedPayload,
          syncKey: syncKey,
        );
      }
      final original = (await inbox.readOutbox(
        generationId: generationId,
        limit: 2,
      )).first;
      expect(original.id, 'broken');
      final transport = _PermanentFirstFailure(failure.key);
      expect(
        await SyncV2Publisher(
          transport,
          inbox,
        ).publishPage(generationId: generationId, limit: 2),
        1,
      );
      expect(transport.attempts, ['broken', 'next']);
      expect(transport.published, ['next']);
      expect(
        await inbox.readOutbox(generationId: generationId, limit: 2),
        isEmpty,
      );
      expect(
        (await inbox.readFailures(generationId)).single.reason,
        failure.value,
      );
      await inbox.retryPublication(
        generationId: generationId,
        recordId: 'broken',
      );
      final retried = (await inbox.readOutbox(
        generationId: generationId,
        limit: 2,
      )).single;
      expect(retried.id, original.id);
      expect(retried.encryptedHeader, original.encryptedHeader);
      expect(
        retried.encryptedPayload,
        orderedEquals(original.encryptedPayload!),
      );
      expect(await inbox.readFailures(generationId), isEmpty);
    });
  }

  for (final code in ['3', '4', '6', '7', '9', '25', '27', '36', 'unknown']) {
    test(
      'global or unknown failure $code stops and retains the queue',
      () async {
        for (final id in ['broken', 'next']) {
          await inbox.queuePublication(
            generationId: generationId,
            change: SyncV2Change(
              id: id,
              profileId: 'profile-1',
              noteId: 'note-$id',
              operation: SyncV2Operation.delete,
              parentIds: const {},
            ),
            encryptedPayload: null,
            syncKey: syncKey,
          );
        }
        final transport = _PermanentFirstFailure(code);
        await expectLater(
          SyncV2Publisher(
            transport,
            inbox,
          ).publishPage(generationId: generationId, limit: 2),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
        expect(transport.attempts, ['broken']);
        expect(transport.published, isEmpty);
        expect(
          (await inbox.readOutbox(
            generationId: generationId,
            limit: 2,
          )).map((entry) => entry.id),
          ['broken', 'next'],
        );
        expect(await inbox.readFailures(generationId), isEmpty);
      },
    );
  }

  test('retryPublication does not requeue acknowledged history', () async {
    final change = SyncV2Change(
      id: 'acknowledged',
      profileId: 'profile-1',
      noteId: 'note-1',
      operation: SyncV2Operation.delete,
      parentIds: const {},
    );
    await inbox.queuePublication(
      generationId: generationId,
      change: change,
      encryptedPayload: null,
      syncKey: syncKey,
    );
    final publication = (await inbox.readOutbox(
      generationId: generationId,
      limit: 1,
    )).single;
    await inbox.acknowledgePublication(
      generationId: generationId,
      publication: publication,
    );
    await inbox.retryPublication(
      generationId: generationId,
      recordId: 'acknowledged',
    );
    expect(
      await inbox.readOutbox(generationId: generationId, limit: 1),
      isEmpty,
    );
  });
}
