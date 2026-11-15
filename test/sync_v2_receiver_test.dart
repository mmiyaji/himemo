import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';

class _FakeReadTransport implements SyncV2ReadTransport {
  _FakeReadTransport({
    required this.header,
    required this.payloads,
    this.replacementHeader,
    this.expireCursorOnce = false,
  });

  final SyncV2RemoteHeader header;
  final List<Uint8List> payloads;
  final SyncV2RemoteHeader? replacementHeader;
  final bool expireCursorOnce;
  final List<({String generationId, String? cursor, int limit})> headerCalls =
      [];
  final List<({String generationId, String recordId})> payloadCalls = [];
  var _payloadIndex = 0;
  var _didExpireCursor = false;

  @override
  Future<SyncV2RemoteHeader> fetchHeader({
    required String generationId,
    required String recordId,
  }) async => header;

  @override
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  }) async {
    headerCalls.add((generationId: generationId, cursor: cursor, limit: limit));
    if (cursor != null && expireCursorOnce && !_didExpireCursor) {
      _didExpireCursor = true;
      throw const SyncV2CursorExpired();
    }
    if (cursor == null && headerCalls.length == 1) {
      return SyncV2RemotePage(
        nextCursor: 'cursor-1',
        hasMore: true,
        headers: [header],
      );
    }
    if (cursor == null && replacementHeader != null) {
      return SyncV2RemotePage(
        nextCursor: 'cursor-recovered',
        hasMore: false,
        headers: [replacementHeader!],
      );
    }
    return SyncV2RemotePage(
      nextCursor: 'cursor-2',
      hasMore: false,
      headers: const <SyncV2RemoteHeader>[],
    );
  }

  @override
  Future<Uint8List> fetchPayload({
    required String generationId,
    required String recordId,
  }) async {
    payloadCalls.add((generationId: generationId, recordId: recordId));
    return payloads[_payloadIndex++];
  }
}

void main() {
  late NativeDatabase executor;
  late SyncV2Inbox inbox;
  late SyncV2HeaderCodec codec;
  late DateTime now;
  final syncKey = SecretKey(List<int>.filled(32, 23));

  setUp(() {
    executor = NativeDatabase.memory();
    codec = SyncV2HeaderCodec(EncryptionService());
    now = DateTime.utc(2026, 11, 11);
    inbox = SyncV2Inbox(executor, codec, now: () => now);
  });

  tearDown(() async {
    await inbox.close();
  });

  test(
    'retries an individual header after advancing past its failed page',
    () async {
      const generation = 'generation-1';
      final change = SyncV2Change(
        id: 'retry',
        profileId: 'profile',
        noteId: 'note',
        parentIds: const {},
        operation: SyncV2Operation.delete,
      );
      final header = (
        id: 'retry',
        encryptedHeader: await codec.seal(
          change,
          generationId: generation,
          syncKey: syncKey,
        ),
      );
      await inbox.stagePage(
        generationId: generation,
        expectedCursor: null,
        nextCursor: 'cursor-1',
        records: const [],
        syncKey: syncKey,
        remoteIssues: [(id: 'retry', reason: 'record_unavailable')],
      );
      now = now.add(const Duration(minutes: 1));
      final receiver = SyncV2Receiver(
        _FakeReadTransport(header: header, payloads: const []),
        inbox,
      );
      await receiver.pullPage(
        generationId: generation,
        syncKey: syncKey,
        limit: 10,
      );
      expect(await inbox.readCursor(generation), 'cursor-2');
      expect(await inbox.readFailures(generation), isEmpty);
      expect(await inbox.readPage(generationId: generation, limit: 10), [
        header,
      ]);
    },
  );

  test(
    'a corrupt body does not prevent later bodies from downloading',
    () async {
      const generation = 'generation-1';
      final good = Uint8List.fromList(utf8.encode('valid-encrypted-body'));
      final headers = <SyncV2RemoteHeader>[];
      for (final id in ['a', 'b']) {
        headers.add((
          id: id,
          encryptedHeader: await codec.seal(
            SyncV2Change(
              id: id,
              profileId: 'profile',
              noteId: id,
              parentIds: const {},
              operation: SyncV2Operation.upsert,
              payloadDigest: sha256.convert(good).toString(),
            ),
            generationId: generation,
            syncKey: syncKey,
          ),
        ));
      }
      await inbox.stagePage(
        generationId: generation,
        expectedCursor: null,
        nextCursor: 'next',
        records: headers,
        syncKey: syncKey,
      );
      final transport = _FakeReadTransport(
        header: headers.first,
        payloads: [
          Uint8List.fromList([99]),
          good,
        ],
      );
      final receiver = SyncV2Receiver(transport, inbox);
      expect(
        await receiver.pullPendingPayloads(
          generationId: generation,
          syncKey: syncKey,
          limit: 10,
        ),
        1,
      );
      expect(
        await inbox.readPayload(generationId: generation, recordId: 'b'),
        good,
      );
      expect((await inbox.readFailures(generation)).single.id, 'a');
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        isEmpty,
      );
    },
  );

  test(
    'receives authenticated headers and retries a payload digest failure',
    () async {
      const generation = 'generation-1';
      final goodPayload = Uint8List.fromList(utf8.encode('encrypted-payload'));
      final badPayload = Uint8List.fromList(utf8.encode('incorrect-payload'));
      final change = SyncV2Change(
        id: 'record-1',
        profileId: 'profile-1',
        noteId: 'note-1',
        parentIds: const {},
        operation: SyncV2Operation.upsert,
        payloadDigest: sha256.convert(goodPayload).toString(),
      );
      final header = (
        id: change.id,
        encryptedHeader: await codec.seal(
          change,
          generationId: generation,
          syncKey: syncKey,
        ),
      );
      final transport = _FakeReadTransport(
        header: header,
        payloads: [badPayload, goodPayload],
      );
      final receiver = SyncV2Receiver(transport, inbox);

      // The receiver only has the generation sync key; it never receives a
      // profile key or opens the note payload.
      expect(
        await receiver.pullPage(
          generationId: generation,
          syncKey: syncKey,
          limit: 7,
        ),
        (staged: true, hasMore: true),
      );
      expect(transport.headerCalls, [
        (generationId: generation, cursor: null, limit: 7),
      ]);
      expect(await inbox.readCursor(generation), 'cursor-1');
      expect(await inbox.readPage(generationId: generation, limit: 10), [
        header,
      ]);

      // A subsequent request resumes from the stored cursor and observes the
      // next page without needing profile decryption credentials.
      expect(
        await receiver.pullPage(
          generationId: generation,
          syncKey: syncKey,
          limit: 3,
        ),
        (staged: true, hasMore: false),
      );
      expect(transport.headerCalls.last, (
        generationId: generation,
        cursor: 'cursor-1',
        limit: 3,
      ));
      expect(await inbox.readCursor(generation), 'cursor-2');
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        [change.id],
      );

      expect(
        await receiver.pullPendingPayloads(
          generationId: generation,
          syncKey: syncKey,
          limit: 10,
        ),
        0,
      );
      expect(
        await inbox.readPayload(generationId: generation, recordId: change.id),
        isNull,
      );
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        isEmpty,
      );
      expect(
        (await inbox.readFailures(generation)).single.reason,
        'invalid_payload',
      );
      await inbox.retryPayload(generationId: generation, recordId: change.id);

      expect(
        await receiver.pullPendingPayloads(
          generationId: generation,
          syncKey: syncKey,
          limit: 10,
        ),
        1,
      );
      expect(
        await inbox.readPayload(generationId: generation, recordId: change.id),
        goodPayload,
      );
      expect(transport.payloadCalls, [
        (generationId: generation, recordId: change.id),
        (generationId: generation, recordId: change.id),
      ]);
      expect(
        await inbox.readPendingPayloadIds(generationId: generation, limit: 10),
        isEmpty,
      );
      expect(transport.headerCalls, hasLength(2));
    },
  );

  test(
    'expired cursor refetches from null and preserves staged inbox records',
    () async {
      const generation = 'generation-1';
      final firstChange = SyncV2Change(
        id: 'record-a',
        profileId: 'profile-1',
        noteId: 'note-a',
        parentIds: const {},
        operation: SyncV2Operation.upsert,
        payloadDigest: 'a' * 64,
      );
      final nextChange = SyncV2Change(
        id: 'record-b',
        profileId: 'profile-1',
        noteId: 'note-b',
        parentIds: const {},
        operation: SyncV2Operation.upsert,
        payloadDigest: 'b' * 64,
      );
      Future<SyncV2RemoteHeader> seal(SyncV2Change change) async => (
        id: change.id,
        encryptedHeader: await codec.seal(
          change,
          generationId: generation,
          syncKey: syncKey,
        ),
      );
      final firstHeader = await seal(firstChange);
      final replacementHeader = await seal(nextChange);
      final transport = _FakeReadTransport(
        header: firstHeader,
        replacementHeader: replacementHeader,
        expireCursorOnce: true,
        payloads: const [],
      );
      final receiver = SyncV2Receiver(transport, inbox);

      expect(
        await receiver.pullPage(
          generationId: generation,
          syncKey: syncKey,
          limit: 5,
        ),
        (staged: true, hasMore: true),
      );
      expect(await inbox.readCursor(generation), 'cursor-1');

      expect(
        await receiver.pullPage(
          generationId: generation,
          syncKey: syncKey,
          limit: 5,
        ),
        (staged: true, hasMore: false),
      );
      expect(transport.headerCalls.map((call) => call.cursor), [
        null,
        'cursor-1',
        null,
      ]);
      expect(await inbox.readCursor(generation), 'cursor-recovered');
      expect(
        (await inbox.readPage(
          generationId: generation,
          limit: 10,
        )).map((record) => record.id),
        ['record-a', 'record-b'],
      );
    },
  );
}
