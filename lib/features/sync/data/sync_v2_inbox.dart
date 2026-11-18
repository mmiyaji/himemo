import 'dart:convert' show utf8, jsonEncode, base64UrlEncode;

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../../security/data/encrypted_note_database_executor.dart';
import '../../security/data/encryption_service.dart';
import 'sync_v2_header_codec.dart';
import 'sync_v2_history.dart';

typedef SyncV2RemoteHeader = ({String id, String encryptedHeader});
typedef SyncV2Publication = ({
  String id,
  String encryptedHeader,
  Uint8List? encryptedPayload,
});

/// Durable inbox for one or more v2 generations. Cursors describe headers
/// staged for processing, not note bodies already applied.
class SyncV2Inbox extends GeneratedDatabase {
  SyncV2Inbox(super.executor, this._codec, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  factory SyncV2Inbox.open(SyncV2HeaderCodec codec) =>
      SyncV2Inbox(createSyncV2DatabaseExecutor(), codec);

  final SyncV2HeaderCodec _codec;
  final DateTime Function() _now;
  static const maxFetchAttempts = 5;
  static const maxPublicationPayloadBytes = 16 * 1024 * 1024;
  static const maxPublicationHeaderBytes = 65536;
  static final _publicationIdPattern = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');

  @override
  int get schemaVersion => 4;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''
        CREATE TABLE sync_v2_inbox (
          generation_id TEXT NOT NULL,
          record_id TEXT NOT NULL,
          encrypted_header TEXT NOT NULL,
          encrypted_payload BLOB,
          PRIMARY KEY (generation_id, record_id)
        ) WITHOUT ROWID
      ''');
      await customStatement('''
        CREATE TABLE sync_v2_cursors (
          generation_id TEXT PRIMARY KEY NOT NULL,
          cursor TEXT NOT NULL
        ) WITHOUT ROWID
      ''');
      await customStatement('''
        CREATE TABLE sync_v2_outbox (
          sequence INTEGER PRIMARY KEY,
          generation_id TEXT NOT NULL,
          record_id TEXT NOT NULL,
          encrypted_header TEXT NOT NULL,
          encrypted_payload BLOB,
          UNIQUE (generation_id, record_id)
        )
      ''');
      await customStatement('''
        CREATE INDEX sync_v2_outbox_order
        ON sync_v2_outbox (generation_id, sequence)
      ''');
      await _createPendingPayloads();
      await _createFailures();
      await _createNoteIndex();
    },
    onUpgrade: (_, from, _) async {
      await transaction(() async {
        if (from < 2) {
          await _createPendingPayloads();
          // Refetch authenticated headers to rebuild pending payload requests.
          await customStatement('DELETE FROM sync_v2_cursors');
        }
        if (from < 3) await _createFailures();
        if (from < 4) await _createNoteIndex();
      });
    },
  );

  // Identities and latest-state snapshots stay encrypted. Keyed lookup tokens
  // and opaque parent edges reveal local grouping/graph structure, but never
  // profile/note names or contents.
  Future<void> _createNoteIndex() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_v2_header_index (
        generation_id TEXT NOT NULL, record_id TEXT NOT NULL,
        profile_token TEXT NOT NULL, note_token TEXT NOT NULL,
        PRIMARY KEY (generation_id, record_id)
      ) WITHOUT ROWID
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS sync_v2_headers_by_note
      ON sync_v2_header_index (generation_id, note_token, record_id)
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_v2_note_parents (
        generation_id TEXT NOT NULL, record_id TEXT NOT NULL,
        parent_id TEXT NOT NULL,
        PRIMARY KEY (generation_id, parent_id, record_id)
      ) WITHOUT ROWID
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_v2_note_states (
        generation_id TEXT NOT NULL, profile_token TEXT NOT NULL,
        note_token TEXT NOT NULL, first_record_id TEXT NOT NULL,
        encrypted_state TEXT,
        PRIMARY KEY (generation_id, profile_token, note_token)
      ) WITHOUT ROWID
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_v2_unindexed_headers (
        generation_id TEXT NOT NULL, record_id TEXT NOT NULL,
        PRIMARY KEY (generation_id, record_id)
      ) WITHOUT ROWID
    ''');
    // Migration needs no key. Authentication/backfill happens on first read.
    await customStatement('''
      INSERT OR IGNORE INTO sync_v2_unindexed_headers
      SELECT i.generation_id, i.record_id FROM sync_v2_inbox i
      LEFT JOIN sync_v2_header_index x
        ON x.generation_id = i.generation_id AND x.record_id = i.record_id
      WHERE x.record_id IS NULL
    ''');
  }

  Future<String> noteIndexToken({
    required String generationId,
    required String profileId,
    String? noteId,
    required SecretKey syncKey,
  }) async => base64UrlEncode(
    (await Hmac.sha256().calculateMac(
      utf8.encode(
        jsonEncode([
          'himemo.sync.v2.note-index.1',
          generationId,
          profileId,
          noteId,
        ]),
      ),
      secretKey: syncKey,
    )).bytes,
  );

  Future<void> _indexChange(
    String generationId,
    SyncV2Change change,
    SecretKey syncKey,
  ) async {
    final profile = await noteIndexToken(
      generationId: generationId,
      profileId: change.profileId,
      syncKey: syncKey,
    );
    final note = await noteIndexToken(
      generationId: generationId,
      profileId: change.profileId,
      noteId: change.noteId,
      syncKey: syncKey,
    );
    await customStatement(
      '''
      INSERT INTO sync_v2_header_index VALUES (?, ?, ?, ?)
      ON CONFLICT(generation_id, record_id) DO NOTHING
    ''',
      [generationId, change.id, profile, note],
    );
    for (final parent in change.parentIds) {
      await customStatement(
        '''
        INSERT OR IGNORE INTO sync_v2_note_parents VALUES (?, ?, ?)
      ''',
        [generationId, change.id, parent],
      );
    }
    await customStatement(
      '''
      INSERT INTO sync_v2_note_states VALUES (?, ?, ?, ?, NULL)
      ON CONFLICT(generation_id, profile_token, note_token) DO UPDATE SET
        first_record_id = MIN(first_record_id, excluded.first_record_id),
        encrypted_state = NULL
    ''',
      [generationId, profile, note, change.id],
    );
    // A missing parent can arrive later in another note/profile. Its children
    // must be revalidated instead of silently keeping their pending snapshot.
    await customStatement(
      '''
      UPDATE sync_v2_note_states SET encrypted_state = NULL
      WHERE generation_id = ? AND (profile_token, note_token) IN (
        SELECT x.profile_token, x.note_token FROM sync_v2_note_parents p
        JOIN sync_v2_header_index x
          ON x.generation_id = p.generation_id AND x.record_id = p.record_id
        WHERE p.generation_id = ? AND p.parent_id = ?
      )
    ''',
      [generationId, generationId, change.id],
    );
    await customStatement(
      '''
      DELETE FROM sync_v2_unindexed_headers
      WHERE generation_id = ? AND record_id = ?
    ''',
      [generationId, change.id],
    );
  }

  Future<
    List<({String noteToken, String firstRecordId, String? encryptedState})>
  >
  readNoteStates({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
  }) async {
    while (true) {
      final rows = await customSelect(
        '''
        SELECT i.record_id, i.encrypted_header FROM sync_v2_unindexed_headers u
        JOIN sync_v2_inbox i
          ON i.generation_id = u.generation_id AND i.record_id = u.record_id
        WHERE u.generation_id = ? ORDER BY u.record_id LIMIT 100
      ''',
        variables: [Variable.withString(generationId)],
      ).get();
      for (final row in rows) {
        final change = await _codec.open(
          row.read<String>('encrypted_header'),
          generationId: generationId,
          recordId: row.read<String>('record_id'),
          syncKey: syncKey,
        );
        await _indexChange(generationId, change, syncKey);
      }
      if (rows.length < 100) break;
    }
    final token = await noteIndexToken(
      generationId: generationId,
      profileId: profileId,
      syncKey: syncKey,
    );
    final rows = await customSelect(
      '''
      SELECT note_token, first_record_id, encrypted_state FROM sync_v2_note_states
      WHERE generation_id = ? AND profile_token = ? ORDER BY first_record_id
    ''',
      variables: [
        Variable.withString(generationId),
        Variable.withString(token),
      ],
    ).get();
    // A wrong SYNC key must fail even when its opaque lookup matches no notes.
    if (rows.isEmpty) {
      final first = await readPage(generationId: generationId, limit: 1);
      if (first.isNotEmpty) {
        await _codec.open(
          first.single.encryptedHeader,
          generationId: generationId,
          recordId: first.single.id,
          syncKey: syncKey,
        );
      }
    }
    return [
      for (final row in rows)
        (
          noteToken: row.read<String>('note_token'),
          firstRecordId: row.read<String>('first_record_id'),
          encryptedState: row.readNullable<String>('encrypted_state'),
        ),
    ];
  }

  Future<List<SyncV2RemoteHeader>> readIndexedNoteHistory({
    required String generationId,
    required String noteToken,
  }) async {
    final rows = await customSelect(
      '''
      SELECT i.record_id, i.encrypted_header FROM sync_v2_header_index x
      JOIN sync_v2_inbox i
        ON i.generation_id = x.generation_id AND i.record_id = x.record_id
      WHERE x.generation_id = ? AND x.note_token = ? ORDER BY x.record_id
    ''',
      variables: [
        Variable.withString(generationId),
        Variable.withString(noteToken),
      ],
    ).get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('record_id'),
          encryptedHeader: row.read<String>('encrypted_header'),
        ),
    ];
  }

  Future<SyncV2RemoteHeader?> readHeader(String generationId, String id) async {
    final row = await customSelect(
      '''
      SELECT encrypted_header FROM sync_v2_inbox
      WHERE generation_id = ? AND record_id = ?
    ''',
      variables: [Variable.withString(generationId), Variable.withString(id)],
    ).getSingleOrNull();
    return row == null
        ? null
        : (id: id, encryptedHeader: row.read<String>('encrypted_header'));
  }

  Future<void> writeNoteState({
    required String generationId,
    required String profileId,
    required String noteToken,
    required String encryptedState,
    required SecretKey syncKey,
  }) async {
    final token = await noteIndexToken(
      generationId: generationId,
      profileId: profileId,
      syncKey: syncKey,
    );
    await customStatement(
      '''
      UPDATE sync_v2_note_states SET encrypted_state = ?
      WHERE generation_id = ? AND profile_token = ? AND note_token = ?
    ''',
      [encryptedState, generationId, token, noteToken],
    );
  }

  Future<void> _createFailures() => customStatement('''
    CREATE TABLE sync_v2_failures (
      generation_id TEXT NOT NULL,
      record_id TEXT NOT NULL,
      phase TEXT NOT NULL,
      reason TEXT NOT NULL,
      encrypted_header TEXT,
      attempts INTEGER NOT NULL,
      retry_at INTEGER,
      PRIMARY KEY (generation_id, record_id, phase)
    ) WITHOUT ROWID
  ''');

  Future<void> _createPendingPayloads() => customStatement('''
    CREATE TABLE sync_v2_pending_payloads (
      generation_id TEXT NOT NULL,
      record_id TEXT NOT NULL,
      PRIMARY KEY (generation_id, record_id)
    ) WITHOUT ROWID
  ''');

  Future<String?> readCursor(String generationId) async {
    final row = await customSelect(
      'SELECT cursor FROM sync_v2_cursors WHERE generation_id = ?',
      variables: [Variable.withString(generationId)],
    ).getSingleOrNull();
    return row?.read<String>('cursor');
  }

  /// A stale caller must refetch from the stored cursor. Header insertion and
  /// cursor advancement share a transaction so a crash cannot skip a page.
  Future<bool> stagePage({
    required String generationId,
    required String? expectedCursor,
    required String nextCursor,
    required List<SyncV2RemoteHeader> records,
    required SecretKey syncKey,
    List<({String id, String reason})> remoteIssues = const [],
  }) {
    if (generationId.isEmpty || nextCursor.isEmpty) {
      throw const FormatException('Missing sync v2 generation or cursor');
    }
    return transaction(() async {
      if (await readCursor(generationId) != expectedCursor) return false;
      for (final issue in remoteIssues) {
        await recordFetchFailure(
          generationId: generationId,
          recordId: issue.id,
          phase: 'remote',
          reason: issue.reason,
          permanent: issue.reason != 'record_unavailable',
        );
      }
      for (final record in records) {
        await customStatement(
          "DELETE FROM sync_v2_failures WHERE generation_id = ? AND record_id = ? AND phase = 'remote'",
          [generationId, record.id],
        );
        final SyncV2Change incoming;
        try {
          incoming = await _codec.open(
            record.encryptedHeader,
            generationId: generationId,
            recordId: record.id,
            syncKey: syncKey,
          );
        } on HimemoDecryptionException {
          await _recordFailure(
            generationId,
            record.id,
            'header',
            'authentication_failed',
            encryptedHeader: record.encryptedHeader,
          );
          continue;
        } on FormatException {
          await _recordFailure(
            generationId,
            record.id,
            'header',
            'invalid_header',
            encryptedHeader: record.encryptedHeader,
          );
          continue;
        }
        final previous = await customSelect(
          '''
          SELECT encrypted_header FROM sync_v2_inbox
          WHERE generation_id = ? AND record_id = ?
          ''',
          variables: [
            Variable.withString(generationId),
            Variable.withString(record.id),
          ],
        ).getSingleOrNull();
        if (previous != null) {
          final stored = await _codec.open(
            previous.read<String>('encrypted_header'),
            generationId: generationId,
            recordId: record.id,
            syncKey: syncKey,
          );
          if (_codec.canonicalHeader(stored) !=
              _codec.canonicalHeader(incoming)) {
            await _recordFailure(
              generationId,
              record.id,
              'header',
              'change_id_collision',
              encryptedHeader: record.encryptedHeader,
            );
            continue;
          }
        } else {
          await customStatement(
            '''
            INSERT INTO sync_v2_inbox (generation_id, record_id, encrypted_header)
            VALUES (?, ?, ?)
            ''',
            [generationId, record.id, record.encryptedHeader],
          );
          await _indexChange(generationId, incoming, syncKey);
        }
        await customStatement(
          "DELETE FROM sync_v2_failures WHERE generation_id = ? AND record_id = ? AND phase = 'header' AND reason != 'change_id_collision'",
          [generationId, record.id],
        );
        if (incoming.payloadDigest != null) {
          await customStatement(
            '''
            INSERT OR IGNORE INTO sync_v2_pending_payloads
            SELECT generation_id, record_id FROM sync_v2_inbox
            WHERE generation_id = ? AND record_id = ? AND encrypted_payload IS NULL
            ''',
            [generationId, record.id],
          );
        }
      }
      await customStatement(
        '''
        INSERT INTO sync_v2_cursors VALUES (?, ?)
        ON CONFLICT(generation_id) DO UPDATE SET cursor = excluded.cursor
        ''',
        [generationId, nextCursor],
      );
      return true;
    });
  }

  Future<List<SyncV2RemoteHeader>> readPage({
    required String generationId,
    String afterId = '',
    required int limit,
  }) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final rows = await customSelect(
      '''
      SELECT record_id, encrypted_header FROM sync_v2_inbox
      WHERE generation_id = ? AND record_id > ?
      ORDER BY record_id LIMIT ?
      ''',
      variables: [
        Variable.withString(generationId),
        Variable.withString(afterId),
        Variable.withInt(limit),
      ],
    ).get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('record_id'),
          encryptedHeader: row.read<String>('encrypted_header'),
        ),
    ];
  }

  /// Persists a payload whose digest is authenticated by the staged header.
  Future<void> storePayload({
    required String generationId,
    required String recordId,
    required Uint8List encryptedPayload,
    required SecretKey syncKey,
  }) async {
    final bytes = Uint8List.fromList(encryptedPayload);
    await transaction(() async {
      final row = await customSelect(
        '''
        SELECT encrypted_header FROM sync_v2_inbox
        WHERE generation_id = ? AND record_id = ?
        ''',
        variables: [
          Variable.withString(generationId),
          Variable.withString(recordId),
        ],
      ).getSingleOrNull();
      if (row == null) throw const FormatException('Unknown sync v2 record');
      final change = await _codec.open(
        row.read<String>('encrypted_header'),
        generationId: generationId,
        recordId: recordId,
        syncKey: syncKey,
      );
      if (change.payloadDigest != sha256.convert(bytes).toString()) {
        throw const FormatException('Sync v2 payload digest mismatch');
      }
      await customStatement(
        '''
        UPDATE sync_v2_inbox SET encrypted_payload = ?
        WHERE generation_id = ? AND record_id = ?
        ''',
        [bytes, generationId, recordId],
      );
      await customStatement(
        '''
        DELETE FROM sync_v2_pending_payloads
        WHERE generation_id = ? AND record_id = ?
        ''',
        [generationId, recordId],
      );
      await retryPayload(generationId: generationId, recordId: recordId);
    });
  }

  Future<List<String>> readPendingPayloadIds({
    required String generationId,
    required int limit,
  }) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final rows = await customSelect(
      '''
      SELECT p.record_id FROM sync_v2_pending_payloads p
      LEFT JOIN sync_v2_failures f
        ON f.generation_id = p.generation_id AND f.record_id = p.record_id AND f.phase = 'payload'
      WHERE p.generation_id = ?
        AND (f.record_id IS NULL OR (f.retry_at IS NOT NULL AND f.retry_at <= ?))
      ORDER BY p.record_id LIMIT ?
      ''',
      variables: [
        Variable.withString(generationId),
        Variable.withInt(_now().millisecondsSinceEpoch),
        Variable.withInt(limit),
      ],
    ).get();
    return [for (final row in rows) row.read<String>('record_id')];
  }

  /// Failure evidence is committed before a cursor can move past the record.
  Future<void> _recordFailure(
    String generationId,
    String recordId,
    String phase,
    String reason, {
    String? encryptedHeader,
    int attempts = 1,
    int? retryAt,
  }) => customStatement(
    '''
    INSERT INTO sync_v2_failures
      (generation_id, record_id, phase, reason, encrypted_header, attempts, retry_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(generation_id, record_id, phase) DO UPDATE SET
      reason = excluded.reason, encrypted_header = excluded.encrypted_header,
      attempts = excluded.attempts, retry_at = excluded.retry_at
  ''',
    [generationId, recordId, phase, reason, encryptedHeader, attempts, retryAt],
  );

  Future<void> recordFetchFailure({
    required String generationId,
    required String recordId,
    required String phase,
    required String reason,
    required bool permanent,
  }) => transaction(() async {
    final previous = await customSelect(
      "SELECT attempts FROM sync_v2_failures WHERE generation_id = ? AND record_id = ? AND phase = ?",
      variables: [
        Variable.withString(generationId),
        Variable.withString(recordId),
        Variable.withString(phase),
      ],
    ).getSingleOrNull();
    final attempts = (previous?.read<int>('attempts') ?? 0) + 1;
    final retryAt = permanent || attempts >= maxFetchAttempts
        ? null
        : _now()
              .add(Duration(seconds: 30 * (1 << (attempts - 1))))
              .millisecondsSinceEpoch;
    await _recordFailure(
      generationId,
      recordId,
      phase,
      reason,
      attempts: attempts,
      retryAt: retryAt,
    );
  });

  Future<List<String>> readRetryableHeaderIds(
    String generationId,
    int limit,
  ) async {
    final rows = await customSelect(
      "SELECT record_id FROM sync_v2_failures WHERE generation_id = ? AND phase = 'remote' AND retry_at <= ? ORDER BY record_id LIMIT ?",
      variables: [
        Variable.withString(generationId),
        Variable.withInt(_now().millisecondsSinceEpoch),
        Variable.withInt(limit),
      ],
    ).get();
    return [for (final row in rows) row.read<String>('record_id')];
  }

  Future<
    List<({String id, String phase, String reason, int attempts, int? retryAt})>
  >
  readFailures(String generationId) async {
    final rows = await customSelect(
      'SELECT record_id, phase, reason, attempts, retry_at FROM sync_v2_failures WHERE generation_id = ? ORDER BY record_id, phase',
      variables: [Variable.withString(generationId)],
    ).get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('record_id'),
          phase: row.read<String>('phase'),
          reason: row.read<String>('reason'),
          attempts: row.read<int>('attempts'),
          retryAt: row.readNullable<int>('retry_at'),
        ),
    ];
  }

  /// Explicit repair can retry a quarantined body after its remote asset is fixed.
  Future<void> retryPayload({
    required String generationId,
    required String recordId,
  }) => customStatement(
    "DELETE FROM sync_v2_failures WHERE generation_id = ? AND record_id = ? AND phase = 'payload'",
    [generationId, recordId],
  );

  /// Explicit repair refetches a bad/missing header using the normal verifier.
  Future<void> retryHeader({
    required String generationId,
    required String recordId,
  }) => transaction(() async {
    await _recordFailure(
      generationId,
      recordId,
      'remote',
      'record_unavailable',
      attempts: 0,
      retryAt: _now().millisecondsSinceEpoch,
    );
    await customStatement(
      "DELETE FROM sync_v2_failures WHERE generation_id = ? AND record_id = ? AND phase = 'header'",
      [generationId, recordId],
    );
  });

  Future<Uint8List?> readPayload({
    required String generationId,
    required String recordId,
  }) async {
    final row = await customSelect(
      '''
      SELECT encrypted_payload FROM sync_v2_inbox
      WHERE generation_id = ? AND record_id = ?
      ''',
      variables: [
        Variable.withString(generationId),
        Variable.withString(recordId),
      ],
    ).getSingleOrNull();
    return row?.readNullable<Uint8List>('encrypted_payload');
  }

  /// Queues the original ciphertext for all subsequent publication attempts.
  Future<void> queuePublication({
    required String generationId,
    required SyncV2Change change,
    required Uint8List? encryptedPayload,
    required SecretKey syncKey,
  }) async {
    final bytes = encryptedPayload == null
        ? null
        : Uint8List.fromList(encryptedPayload);
    if (change.payloadDigest !=
        (bytes == null ? null : sha256.convert(bytes).toString())) {
      throw const FormatException('Sync v2 payload digest mismatch');
    }
    await transaction(() async {
      final previous = await customSelect(
        '''
        SELECT encrypted_header FROM sync_v2_inbox
        WHERE generation_id = ? AND record_id = ?
        ''',
        variables: [
          Variable.withString(generationId),
          Variable.withString(change.id),
        ],
      ).getSingleOrNull();
      if (previous != null) {
        final existing = await _codec.open(
          previous.read<String>('encrypted_header'),
          generationId: generationId,
          recordId: change.id,
          syncKey: syncKey,
        );
        if (_codec.canonicalHeader(existing) !=
            _codec.canonicalHeader(change)) {
          throw const FormatException('Conflicting sync v2 change ID');
        }
        return;
      }
      final header = await _codec.seal(
        change,
        generationId: generationId,
        syncKey: syncKey,
      );
      if (!_publicationIdPattern.hasMatch(change.id)) {
        throw const FormatException('Invalid sync v2 publication ID');
      }
      final headerBytes = utf8.encode(header).length;
      if (headerBytes == 0 ||
          headerBytes > maxPublicationHeaderBytes ||
          (bytes != null &&
              (bytes.isEmpty || bytes.length > maxPublicationPayloadBytes))) {
        throw const FormatException(
          'Sync v2 publication exceeds CloudKit limits',
        );
      }
      await customStatement(
        '''
        INSERT INTO sync_v2_inbox (
          generation_id, record_id, encrypted_header, encrypted_payload
        ) VALUES (?, ?, ?, ?)
        ''',
        [generationId, change.id, header, bytes],
      );
      await _indexChange(generationId, change, syncKey);
      await customStatement(
        '''
        INSERT INTO sync_v2_outbox (
          generation_id, record_id, encrypted_header, encrypted_payload
        ) VALUES (?, ?, ?, ?)
        ''',
        [generationId, change.id, header, bytes],
      );
    });
  }

  Future<List<SyncV2Publication>> readOutbox({
    required String generationId,
    required int limit,
  }) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final rows = await customSelect(
      '''
      SELECT record_id, encrypted_header, encrypted_payload
      FROM sync_v2_outbox WHERE generation_id = ?
      ORDER BY sequence LIMIT ?
      ''',
      variables: [Variable.withString(generationId), Variable.withInt(limit)],
    ).get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('record_id'),
          encryptedHeader: row.read<String>('encrypted_header'),
          encryptedPayload: row.readNullable<Uint8List>('encrypted_payload'),
        ),
    ];
  }

  Future<void> acknowledgePublication({
    required String generationId,
    required SyncV2Publication publication,
  }) => customStatement(
    '''
    DELETE FROM sync_v2_outbox
    WHERE generation_id = ? AND record_id = ? AND encrypted_header = ?
    ''',
    [generationId, publication.id, publication.encryptedHeader],
  );

  /// Retains local history while moving an irrecoverable upload out of queue.
  Future<void> quarantinePublication({
    required String generationId,
    required SyncV2Publication publication,
    required String reason,
  }) => transaction(() async {
    await _recordFailure(
      generationId,
      publication.id,
      'publication',
      reason,
      encryptedHeader: publication.encryptedHeader,
    );
    await customStatement(
      '''
      DELETE FROM sync_v2_outbox
      WHERE generation_id = ? AND record_id = ? AND encrypted_header = ?
      ''',
      [generationId, publication.id, publication.encryptedHeader],
    );
  });

  /// Requeues a quarantined upload from intact local ciphertext for repair.
  Future<void> retryPublication({
    required String generationId,
    required String recordId,
  }) => transaction(() async {
    final quarantined = await customSelect(
      "SELECT 1 AS found FROM sync_v2_failures WHERE generation_id = ? AND record_id = ? AND phase = 'publication'",
      variables: [
        Variable.withString(generationId),
        Variable.withString(recordId),
      ],
    ).getSingleOrNull();
    if (quarantined == null) return;
    await customStatement(
      '''
      INSERT OR IGNORE INTO sync_v2_outbox
        (sequence, generation_id, record_id, encrypted_header, encrypted_payload)
      SELECT (SELECT COALESCE(MIN(sequence), 0) - 1 FROM sync_v2_outbox),
        i.generation_id, i.record_id, i.encrypted_header, i.encrypted_payload
      FROM sync_v2_inbox i
      JOIN sync_v2_failures f
        ON f.generation_id = i.generation_id AND f.record_id = i.record_id
        AND f.phase = 'publication' AND f.encrypted_header = i.encrypted_header
      WHERE i.generation_id = ? AND i.record_id = ?
      ''',
      [generationId, recordId],
    );
    await customStatement(
      "DELETE FROM sync_v2_failures WHERE generation_id = ? AND record_id = ? AND phase = 'publication'",
      [generationId, recordId],
    );
  });
}
