import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

class _Headers extends SyncV2HeaderCodec {
  _Headers(super.encryption);
  int opens = 0;

  @override
  Future<SyncV2Change> open(
    String encryptedHeader, {
    required String generationId,
    required String recordId,
    required SecretKey syncKey,
  }) {
    opens++;
    return super.open(
      encryptedHeader,
      generationId: generationId,
      recordId: recordId,
      syncKey: syncKey,
    );
  }
}

class _Device {
  _Device({File? file, QueryInterceptor? interceptor}) {
    final encryption = EncryptionService();
    headers = _Headers(encryption);
    final executor = file == null
        ? NativeDatabase.memory()
        : NativeDatabase(file);
    inbox = SyncV2Inbox(
      interceptor == null ? executor : executor.interceptWith(interceptor),
      headers,
    );
    notes = SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    );
  }

  static final key = SecretKey(List.filled(32, 17));
  late final _Headers headers;
  late final SyncV2Inbox inbox;
  late final SyncV2NoteRepository notes;

  Future<void> add(
    String id, {
    String note = 'note_secret',
    String profile = 'profile_secret',
    String generation = 'g',
    Set<String> parents = const {},
  }) => inbox.queuePublication(
    generationId: generation,
    change: SyncV2Change(
      id: id,
      profileId: profile,
      noteId: note,
      operation: SyncV2Operation.delete,
      parentIds: parents,
    ),
    encryptedPayload: null,
    syncKey: key,
  );

  Future<Map<String, SyncV2NoteSnapshot>> read({
    String profile = 'profile_secret',
    String generation = 'g',
    String? prefix,
    SecretKey? key,
  }) => notes.readProfile(
    generationId: generation,
    profileId: profile,
    syncKey: key ?? _Device.key,
    noteIdPrefix: prefix,
  );

  Future<SyncV2NoteSnapshot> oracle(String note) => notes.readNote(
    generationId: 'g',
    profileId: 'profile_secret',
    noteId: note,
    syncKey: key,
  );
}

class _InvalidationPlans extends QueryInterceptor {
  final plans = <List<String>>[];

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.contains('UPDATE sync_v2_note_states') &&
        statement.contains('sync_v2_note_parents')) {
      final rows = await executor.runSelect(
        'EXPLAIN QUERY PLAN $statement',
        args,
      );
      plans.add([for (final row in rows) row['detail'] as String]);
    }
    await executor.runCustom(statement, args);
  }
}

void _same(SyncV2NoteSnapshot actual, SyncV2NoteSnapshot expected) {
  expect(actual.headIds, expected.headIds);
  expect(actual.pendingIds, expected.pendingIds);
  expect(actual.hasConflict, expected.hasConflict);
  expect(actual.canCompareVersions, expected.canCompareVersions);
}

void main() {
  late _Device d;
  Directory? migrationDirectory;
  setUp(() {
    d = _Device();
  });
  tearDown(() async {
    await d.inbox.close();
    await migrationDirectory?.delete(recursive: true);
    migrationDirectory = null;
  });

  test(
    'projection retains conflict heads, deletes and transitive pending parents',
    () async {
      await d.add('root');
      await d.add('left', parents: {'root'});
      await d.add('right', parents: {'root'});
      await d.add('pending', parents: {'missing'});
      await d.add('pending_child', parents: {'pending'});
      final initial = (await d.read())['note_secret']!;
      _same(initial, await d.oracle('note_secret'));
      expect(initial.headIds, {'left', 'right'});
      expect(initial.pendingIds, {'pending', 'pending_child'});
      // An out-of-order ancestor invalidates the whole note, including its
      // transitive descendants. A merge then consumes every conflict head.
      await d.add('missing', parents: {'left'});
      final after = (await d.read())['note_secret']!;
      _same(after, await d.oracle('note_secret'));
      expect(after.headIds, {'pending_child', 'right'});
      expect(after.pendingIds, isEmpty);
      await d.add('merge', parents: after.headIds);
      final merged = (await d.read())['note_secret']!;
      _same(merged, await d.oracle('note_secret'));
      expect(merged.headIds, {'merge'});
    },
  );

  test('late cross-profile parent invalidates cached pending state and fails closed', () async {
    await d.add('child', parents: {'external'});
    expect((await d.read())['note_secret']!.pendingIds, {'child'});
    await d.add('external', profile: 'other_profile', note: 'other_note');
    await expectLater(d.read(), throwsFormatException);
    await expectLater(d.oracle('note_secret'), throwsFormatException);
  });

  test(
    'prefix excludes cyclic attachment history but unfiltered read rejects it',
    () async {
      await d.add('ok');
      await d.add('cycle_a', note: 'attachment_secret', parents: {'cycle_b'});
      await d.add('cycle_b', note: 'attachment_secret', parents: {'cycle_a'});
      expect((await d.read(prefix: 'note_')).keys, ['note_secret']);
      await expectLater(d.read(), throwsFormatException);
    },
  );

  test(
    'warm prefix list does not reopen valid excluded attachment histories',
    () async {
      await d.add('note_head');
      for (var n = 0; n < 20; n++) {
        for (var v = 0; v < 3; v++) {
          await d.add(
            'attachment_${n}_$v',
            note: 'blob_$n',
            parents: v == 0 ? {} : {'attachment_${n}_${v - 1}'},
          );
        }
      }
      expect((await d.read(prefix: 'note_')).keys, ['note_secret']);
      d.headers.opens = 0;
      expect((await d.read(prefix: 'note_')).keys, ['note_secret']);
      expect(
        d.headers.opens,
        1,
        reason: 'Only the selected note head is authenticated again',
      );
      await d.add('cycle_a', note: 'blob_cycle', parents: {'cycle_b'});
      await d.add('cycle_b', note: 'blob_cycle', parents: {'cycle_a'});
      expect((await d.read(prefix: 'note_')).keys, ['note_secret']);
      expect((await d.read(prefix: 'note_')).keys, ['note_secret']);
      await expectLater(d.read(), throwsFormatException);
    },
  );

  test(
    'prefix identity lookup rejects a substituted first-record ID',
    () async {
      await d.add('selected');
      await d.add('excluded', note: 'blob_secret');
      await d.inbox.customStatement(
        "UPDATE sync_v2_note_states SET first_record_id = 'excluded' WHERE first_record_id = 'selected'",
      );
      await expectLater(d.read(prefix: 'note_'), throwsFormatException);
    },
  );

  test(
    'dependency invalidation uses the complete per-profile note primary key',
    () async {
      await d.inbox.close();
      final queries = _InvalidationPlans();
      d = _Device(interceptor: queries);
      await d.add('child', parents: {'parent'});
      await d.add('parent', note: 'another', profile: 'other_profile');
      expect(queries.plans, hasLength(2));
      for (final plan in queries.plans) {
        expect(
          plan,
          contains(
            contains(
              'sync_v2_note_states USING PRIMARY KEY (generation_id=? AND profile_token=? AND note_token=?)',
            ),
          ),
          reason: 'The actual production UPDATE must avoid a generation-wide state scan',
        );
      }
    },
  );

  test(
    'projection and invalidations roll back with the caller transaction',
    () async {
      await d.add('old');
      await d.read();
      await expectLater(
        d.inbox.transaction(() async {
          await d.add('uncommitted', parents: {'old'});
          expect((await d.read())['note_secret']!.headIds, {'uncommitted'});
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect((await d.read())['note_secret']!.headIds, {'old'});
      expect(
        (await d.inbox.readOutbox(
          generationId: 'g',
          limit: 10,
        )).map((r) => r.id),
        ['old'],
      );
    },
  );

  test(
    'profile/generation namespaces and wrong SYNC keys remain isolated',
    () async {
      await d.add('a');
      await d.add('b', profile: 'other_profile');
      await d.add('a', generation: 'other_generation');
      expect((await d.read())['note_secret']!.headIds, {'a'});
      expect((await d.read(profile: 'other_profile'))['note_secret']!.headIds, {
        'b',
      });
      expect(
        (await d.read(generation: 'other_generation'))['note_secret']!.headIds,
        {'a'},
      );
      await expectLater(
        d.read(key: SecretKey(List.filled(32, 99))),
        throwsA(isA<HimemoDecryptionException>()),
      );
      expect(await d.read(profile: 'absent'), isEmpty);
    },
  );

  test(
    'projection storage contains only opaque tokens and encrypted state',
    () async {
      await d.add('change');
      await d.read();
      for (final table in [
        'sync_v2_header_index',
        'sync_v2_note_states',
        'sync_v2_note_parents',
      ]) {
        final rows = await d.inbox.customSelect('SELECT * FROM $table').get();
        for (final row in rows) {
          expect(row.data.toString(), isNot(contains('profile_secret')));
          expect(row.data.toString(), isNot(contains('note_secret')));
        }
      }
      await d.add('another', note: 'note_other_secret');
      await d.read();
      final rows = await d.inbox
          .customSelect(
            'SELECT encrypted_state FROM sync_v2_note_states ORDER BY first_record_id',
          )
          .get();
      // Authenticated context prevents swapping projections between notes.
      await d.inbox.customStatement(
        'UPDATE sync_v2_note_states SET encrypted_state = ?',
        [rows.first.read<String>('encrypted_state')],
      );
      await expectLater(d.read(), throwsA(isA<HimemoDecryptionException>()));
    },
  );

  test('remote headers invalidate heads while late payloads stay live in cached projections', () async {
    final payloads = SyncV2PayloadCodec(EncryptionService());
    final prepared = await payloads.seal(
      generationId: 'g',
      changeId: 'remote_body',
      profileId: 'profile_secret',
      noteId: 'note_secret',
      parentIds: {},
      body: {'text': 'never persisted in plaintext'},
      profileKey: SecretKey(List.filled(32, 29)),
    );
    Future<void> receive(SyncV2Change change, String cursor) async {
      final header = await d.headers.seal(
        change,
        generationId: 'g',
        syncKey: _Device.key,
      );
      expect(
        await d.inbox.stagePage(
          generationId: 'g',
          expectedCursor: await d.inbox.readCursor('g'),
          nextCursor: cursor,
          records: [(id: change.id, encryptedHeader: header)],
          syncKey: _Device.key,
        ),
        isTrue,
      );
    }

    await receive(prepared.change, 'one');
    final missing = (await d.read())['note_secret']!;
    expect(missing.headIds, {'remote_body'});
    expect(missing.versions.single.payloadAvailable, isFalse);
    expect(missing.canCompareVersions, isFalse);
    await d.inbox.storePayload(
      generationId: 'g',
      recordId: 'remote_body',
      encryptedPayload: prepared.encryptedPayload,
      syncKey: _Device.key,
    );
    final available = (await d.read())['note_secret']!;
    expect(available.versions.single.payloadAvailable, isTrue);
    expect(
      available.versions.single.body,
      isNull,
      reason: 'Profile remains locked',
    );
    await receive(
      SyncV2Change(
        id: 'remote_delete',
        profileId: 'profile_secret',
        noteId: 'note_secret',
        operation: SyncV2Operation.delete,
        parentIds: {'remote_body'},
      ),
      'two',
    );
    final deleted = (await d.read())['note_secret']!;
    expect(deleted.headIds, {'remote_delete'});
    expect(deleted.versions.single.isDeleted, isTrue);
    _same(deleted, await d.oracle('note_secret'));
  });

  test('v3 database lazily backfills once and retains encrypted history after reopen', () async {
    final dir = await Directory.systemTemp.createTemp('himemo-v2-projection-');
    migrationDirectory = dir;
    await d.inbox.close();
    final file = File('${dir.path}/inbox.sqlite');
    d = _Device(file: file);
    await d.add('old');
    await d.add('new', parents: {'old'});
    final original = await d.inbox.readOutbox(generationId: 'g', limit: 10);
    for (final table in [
      'sync_v2_header_index',
      'sync_v2_note_parents',
      'sync_v2_note_states',
      'sync_v2_unindexed_headers',
    ]) {
      await d.inbox.customStatement('DROP TABLE $table');
    }
    await d.inbox.customStatement('PRAGMA user_version = 3');
    await d.inbox.close();
    d = _Device(file: file);
    expect((await d.read())['note_secret']!.headIds, {'new'});
    expect(await d.inbox.readOutbox(generationId: 'g', limit: 10), original);
    await d.inbox.close();
    d = _Device(file: file);
    d.headers.opens = 0;
    expect((await d.read())['note_secret']!.headIds, {'new'});
    expect(
      d.headers.opens,
      1,
      reason: 'Persisted projection opens only the current head',
    );
    final pending = await d.inbox
        .customSelect('SELECT * FROM sync_v2_unindexed_headers')
        .get();
    expect(pending, isEmpty);
  });

  test('cached list read decrypts current heads instead of generation history', () async {
    const notes = 10;
    const revisions = 30;
    for (var n = 0; n < notes; n++) {
      for (var v = 0; v < revisions; v++) {
        await d.add(
          'c_${n}_$v',
          note: 'note_$n',
          parents: v == 0 ? {} : {'c_${n}_${v - 1}'},
        );
        await d.add(
          'other_${n}_$v',
          profile: 'other_profile',
          note: 'other_$n',
          parents: v == 0 ? {} : {'other_${n}_${v - 1}'},
        );
      }
    }
    // Baseline performs the original full-generation authenticated scan.
    d.headers.opens = 0;
    final baseline = Stopwatch()..start();
    final history = <SyncV2Change>[];
    var after = '';
    while (true) {
      final page = await d.inbox.readPage(
        generationId: 'g',
        afterId: after,
        limit: 100,
      );
      for (final record in page) {
        history.add(
          await d.headers.open(
            record.encryptedHeader,
            generationId: 'g',
            recordId: record.id,
            syncKey: _Device.key,
          ),
        );
      }
      if (page.length < 100) break;
      after = page.last.id;
    }
    for (var n = 0; n < notes; n++) {
      resolveSyncV2History(
        history.where(
          (c) => c.profileId == 'profile_secret' && c.noteId == 'note_$n',
        ),
      );
    }
    baseline.stop();
    final baselineOpens = d.headers.opens;
    // Builds each dirty note once, outside the warm measurement.
    await d.read();
    d.headers.opens = 0;
    final optimized = Stopwatch()..start();
    final actual = await d.read();
    optimized.stop();
    expect(actual.length, notes);
    expect(baselineOpens, notes * revisions * 2);
    expect(d.headers.opens, notes);
    for (var n = 0; n < notes; n++) {
      expect(actual['note_$n']!.headIds, {'c_${n}_${revisions - 1}'});
    }
    // Time is diagnostic only; deterministic work counts guard the regression.
    // ignore: avoid_print
    print(
      'Sync v2 list benchmark: $baselineOpens history headers / ${baseline.elapsedMicroseconds}us; ${d.headers.opens} head headers / ${optimized.elapsedMicroseconds}us',
    );
    // Changing one note must not rescan unrelated histories.
    await d.add('changed', note: 'note_0', parents: {'c_0_${revisions - 1}'});
    d.headers.opens = 0;
    expect((await d.read())['note_0']!.headIds, {'changed'});
    expect(d.headers.opens, revisions + 1 + notes);
  });
}
