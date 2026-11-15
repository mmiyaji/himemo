import 'dart:typed_data';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';

void main() {
  late NativeDatabase executor;
  late SyncV2Inbox inbox;
  late SyncV2HeaderCodec codec;
  late DateTime now;
  Directory? migrationDirectory;
  final key = SecretKey(List<int>.filled(32, 17));

  setUp(() {
    executor = NativeDatabase.memory();
    codec = SyncV2HeaderCodec(EncryptionService());
    now = DateTime.utc(2026, 11, 11);
    inbox = SyncV2Inbox(executor, codec, now: () => now);
  });

  tearDown(() async {
    await inbox.close();
    await migrationDirectory?.delete(recursive: true);
    migrationDirectory = null;
  });

  test('upgrading the inbox preserves its cursor and unpublished ciphertext', () async {
    await inbox.close();
    migrationDirectory = await Directory.systemTemp.createTemp(
      'himemo-v2-inbox-migration-',
    );
    final file = File('${migrationDirectory!.path}/inbox.sqlite');
    inbox = SyncV2Inbox(NativeDatabase(file), codec);
    final deletion = SyncV2Change(
      id: 'queued',
      profileId: 'profile',
      noteId: 'note',
      operation: SyncV2Operation.delete,
      parentIds: const {},
    );
    await inbox.queuePublication(
      generationId: 'generation',
      change: deletion,
      encryptedPayload: null,
      syncKey: key,
    );
    await inbox.stagePage(
      generationId: 'generation',
      expectedCursor: null,
      nextCursor: 'saved-cursor',
      records: const [],
      syncKey: key,
    );
    final original = (await inbox.readOutbox(
      generationId: 'generation',
      limit: 10,
    )).single;
    // Recreate the schema that was used before failure tracking was introduced.
    await inbox.customStatement('DROP TABLE sync_v2_failures');
    await inbox.customStatement('PRAGMA user_version = 2');
    await inbox.close();
    inbox = SyncV2Inbox(NativeDatabase(file), codec);
    expect(await inbox.readCursor('generation'), 'saved-cursor');
    expect(await inbox.readOutbox(generationId: 'generation', limit: 10), [
      original,
    ]);
    expect(await inbox.readFailures('generation'), isEmpty);
  });

  SyncV2Change change(
    String id, {
    String noteId = 'note-1',
    String digest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  }) => SyncV2Change(
    id: id,
    profileId: 'profile-1',
    noteId: noteId,
    parentIds: const {},
    operation: SyncV2Operation.upsert,
    payloadDigest: digest,
  );

  Future<SyncV2RemoteHeader> seal(
    SyncV2Change value,
    String generation,
  ) async => (
    id: value.id,
    encryptedHeader: await codec.seal(
      value,
      generationId: generation,
      syncKey: key,
    ),
  );

  test(
    'quarantines an invalid header and commits valid headers with the cursor',
    () async {
      const generation = 'generation-1';
      final valid = await seal(change('a'), generation);

      expect(
        await inbox.stagePage(
          generationId: generation,
          expectedCursor: null,
          nextCursor: 'page-1',
          records: [valid, (id: 'z', encryptedHeader: 'not-encrypted')],
          syncKey: key,
        ),
        isTrue,
      );

      expect(await inbox.readCursor(generation), 'page-1');
      expect(await inbox.readPage(generationId: generation, limit: 10), [
        valid,
      ]);
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        ['a'],
      );
      expect((await inbox.readFailures(generation)).single.id, 'z');
    },
  );

  test(
    'stages only upsert payloads and clears pending state after valid storage',
    () async {
      const generation = 'generation-1';
      final goodPayload = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final upsert = await seal(
        change('upsert', digest: sha256.convert(goodPayload).toString()),
        generation,
      );
      final deletion = SyncV2Change(
        id: 'delete',
        profileId: 'profile-1',
        noteId: 'note-deleted',
        parentIds: const {},
        operation: SyncV2Operation.delete,
      );
      final deleteHeader = await seal(deletion, generation);

      expect(
        await inbox.stagePage(
          generationId: generation,
          expectedCursor: null,
          nextCursor: 'cursor-1',
          records: [upsert, deleteHeader],
          syncKey: key,
        ),
        isTrue,
      );
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        ['upsert'],
      );

      final wrongPayload = Uint8List.fromList([1, 2, 3]);
      await expectLater(
        inbox.storePayload(
          generationId: generation,
          recordId: 'upsert',
          encryptedPayload: wrongPayload,
          syncKey: key,
        ),
        throwsFormatException,
      );
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        ['upsert'],
      );

      await inbox.storePayload(
        generationId: generation,
        recordId: 'upsert',
        encryptedPayload: goodPayload,
        syncKey: key,
      );
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        isEmpty,
      );
      expect(
        await inbox.readPayload(generationId: generation, recordId: 'upsert'),
        goodPayload,
      );
    },
  );

  test('stale expected cursor writes neither records nor cursor', () async {
    const generation = 'generation-1';
    final first = await seal(change('a'), generation);
    expect(
      await inbox.stagePage(
        generationId: generation,
        expectedCursor: null,
        nextCursor: 'page-1',
        records: [first],
        syncKey: key,
      ),
      isTrue,
    );

    final stale = await seal(change('b'), generation);
    expect(
      await inbox.stagePage(
        generationId: generation,
        expectedCursor: null,
        nextCursor: 'page-2',
        records: [stale],
        syncKey: key,
      ),
      isFalse,
    );

    expect(await inbox.readCursor(generation), 'page-1');
    expect(
      (await inbox.readPage(
        generationId: generation,
        limit: 10,
      )).map((record) => record.id),
      ['a'],
    );
  });

  test(
    'transient fetch failures back off and stop after five attempts',
    () async {
      final clocked = inbox;
      await clocked.stagePage(
        generationId: 'generation',
        expectedCursor: null,
        nextCursor: 'next',
        records: [await seal(change('a'), 'generation')],
        syncKey: key,
        remoteIssues: [
          (id: 'deleted', reason: 'remote_deleted'),
          (id: 'retry-header', reason: 'record_unavailable'),
        ],
      );
      for (
        var attempt = 1;
        attempt <= SyncV2Inbox.maxFetchAttempts;
        attempt++
      ) {
        await clocked.recordFetchFailure(
          generationId: 'generation',
          recordId: 'a',
          phase: 'payload',
          reason: 'payload_unavailable',
          permanent: false,
        );
        expect(
          await clocked.readPendingPayloadIds(
            generationId: 'generation',
            limit: 10,
          ),
          isEmpty,
        );
        now = now.add(const Duration(hours: 1));
        expect(
          await clocked.readPendingPayloadIds(
            generationId: 'generation',
            limit: 10,
          ),
          attempt < SyncV2Inbox.maxFetchAttempts ? ['a'] : isEmpty,
        );
      }
      final failures = await clocked.readFailures('generation');
      expect(failures.first.attempts, 5);
      expect(failures.first.retryAt, isNull);
      expect(await clocked.readRetryableHeaderIds('generation', 10), [
        'retry-header',
      ]);
      await clocked.retryPayload(generationId: 'generation', recordId: 'a');
      expect(
        await clocked.readPendingPayloadIds(
          generationId: 'generation',
          limit: 10,
        ),
        ['a'],
      );
    },
  );

  test(
    'rejects divergent reuse of an ID and accepts a resealed equivalent',
    () async {
      const generation = 'generation-1';
      final original = await seal(change('same-id'), generation);
      expect(
        await inbox.stagePage(
          generationId: generation,
          expectedCursor: null,
          nextCursor: 'page-1',
          records: [original],
          syncKey: key,
        ),
        isTrue,
      );

      final equivalent = await seal(change('same-id'), generation);
      expect(equivalent.encryptedHeader, isNot(original.encryptedHeader));
      expect(
        await inbox.stagePage(
          generationId: generation,
          expectedCursor: 'page-1',
          nextCursor: 'page-2',
          records: [equivalent],
          syncKey: key,
        ),
        isTrue,
      );
      expect(await inbox.readCursor(generation), 'page-2');
      expect(
        await inbox.readPage(generationId: generation, limit: 10),
        hasLength(1),
      );

      final divergent = await seal(
        change('same-id', noteId: 'different-note'),
        generation,
      );
      expect(
        await inbox.stagePage(
          generationId: generation,
          expectedCursor: 'page-2',
          nextCursor: 'page-3',
          records: [divergent],
          syncKey: key,
        ),
        isTrue,
      );
      expect(await inbox.readCursor(generation), 'page-3');
      expect(
        (await inbox.readFailures(generation)).single.reason,
        'change_id_collision',
      );
      expect(
        (await inbox.readPage(generationId: generation, limit: 10)).single,
        original,
      );
    },
  );

  test('rejects CloudKit publication IDs and payloads before saving', () async {
    final invalidId = SyncV2Change(
      id: 'bad/id',
      profileId: 'profile',
      noteId: 'note',
      operation: SyncV2Operation.delete,
      parentIds: const {},
    );
    await expectLater(
      inbox.queuePublication(
        generationId: 'generation',
        change: invalidId,
        encryptedPayload: null,
        syncKey: key,
      ),
      throwsFormatException,
    );
    final deletion = SyncV2Change(
      id: 'valid',
      profileId: 'profile',
      noteId: 'note',
      operation: SyncV2Operation.upsert,
      parentIds: const {},
      payloadDigest: sha256
          .convert(Uint8List(SyncV2Inbox.maxPublicationPayloadBytes + 1))
          .toString(),
    );
    await expectLater(
      inbox.queuePublication(
        generationId: 'generation',
        change: deletion,
        encryptedPayload: Uint8List(SyncV2Inbox.maxPublicationPayloadBytes + 1),
        syncKey: key,
      ),
      throwsFormatException,
    );
    final oversizedHeader = SyncV2Change(
      id: 'long-header',
      profileId: 'profile',
      noteId: List.filled(50000, 'x').join(),
      operation: SyncV2Operation.delete,
      parentIds: const {},
    );
    await expectLater(
      inbox.queuePublication(
        generationId: 'generation',
        change: oversizedHeader,
        encryptedPayload: null,
        syncKey: key,
      ),
      throwsFormatException,
    );
    expect(
      await inbox.readOutbox(generationId: 'generation', limit: 10),
      isEmpty,
    );
  });

  test('keeps records and cursors separate across generations', () async {
    final generationOne = await seal(change('shared-id'), 'generation-1');
    final generationTwo = await seal(
      change('shared-id', noteId: 'generation-two-note'),
      'generation-2',
    );

    for (final entry in [
      ('generation-1', 'cursor-one', generationOne),
      ('generation-2', 'cursor-two', generationTwo),
    ]) {
      expect(
        await inbox.stagePage(
          generationId: entry.$1,
          expectedCursor: null,
          nextCursor: entry.$2,
          records: [entry.$3],
          syncKey: key,
        ),
        isTrue,
      );
    }

    expect(await inbox.readCursor('generation-1'), 'cursor-one');
    expect(await inbox.readCursor('generation-2'), 'cursor-two');
    final first = await inbox.readPage(generationId: 'generation-1', limit: 10);
    final second = await inbox.readPage(
      generationId: 'generation-2',
      limit: 10,
    );
    expect(first.map((record) => record.id), ['shared-id']);
    expect(second.map((record) => record.id), ['shared-id']);
    expect(
      codec.canonicalHeader(
        await codec.open(
          first.single.encryptedHeader,
          generationId: 'generation-1',
          recordId: 'shared-id',
          syncKey: key,
        ),
      ),
      codec.canonicalHeader(change('shared-id')),
    );
    expect(
      codec.canonicalHeader(
        await codec.open(
          second.single.encryptedHeader,
          generationId: 'generation-2',
          recordId: 'shared-id',
          syncKey: key,
        ),
      ),
      codec.canonicalHeader(change('shared-id', noteId: 'generation-two-note')),
    );
  });
}
