import 'package:drift/drift.dart';

import '../../home/domain/note_entry.dart';
import 'encrypted_note_database_executor.dart';

part 'encrypted_note_database.g.dart';

class EncryptedNotes extends Table {
  TextColumn get id => text()();

  TextColumn get vaultId => text()();

  TextColumn get encryptedPayload => text()();

  IntColumn get createdAtEpochMs => integer()();

  IntColumn get updatedAtEpochMs => integer().nullable()();

  IntColumn get deletedAtEpochMs => integer().nullable()();

  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  IntColumn get revision => integer().withDefault(const Constant(1))();

  TextColumn get syncState => text()();

  TextColumn get deviceId => text().nullable()();

  TextColumn get contentHash => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class EncryptedNoteAttachments extends Table {
  TextColumn get noteId => text()();

  IntColumn get position => integer()();

  TextColumn get encryptedPayload => text()();

  @override
  Set<Column<Object>> get primaryKey => {noteId, position};
}

class PendingNoteChanges extends Table {
  TextColumn get noteId => text()();

  TextColumn get vaultId => text()();

  IntColumn get revision => integer()();

  TextColumn get syncAction => text()();

  IntColumn get queuedAtEpochMs => integer()();

  TextColumn get contentHash => text().nullable()();

  IntColumn get deletedAtEpochMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {noteId};
}

@DriftDatabase(
  tables: [EncryptedNotes, EncryptedNoteAttachments, PendingNoteChanges],
)
class EncryptedNoteDatabase extends _$EncryptedNoteDatabase {
  EncryptedNoteDatabase._(super.executor);

  factory EncryptedNoteDatabase({
    QueryExecutor? executor,
  }) {
    if (executor != null) {
      return EncryptedNoteDatabase._(executor);
    }
    return EncryptedNoteDatabase._(createEncryptedNoteDatabaseExecutor());
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(encryptedNoteAttachments);
        await m.createTable(pendingNoteChanges);
      }
    },
  );

  Future<List<EncryptedNoteSnapshot>> loadAll() async {
    final rows =
        await (select(encryptedNotes)
              ..orderBy([
                (table) => OrderingTerm.desc(table.isPinned),
                (table) => OrderingTerm.desc(table.updatedAtEpochMs),
                (table) => OrderingTerm.desc(table.createdAtEpochMs),
              ]))
            .get();
    final attachmentRows = await select(encryptedNoteAttachments).get();
    final attachmentsByNote = <String, List<EncryptedAttachmentRecord>>{};
    for (final row in attachmentRows) {
      attachmentsByNote.putIfAbsent(row.noteId, () => <EncryptedAttachmentRecord>[]).add(
        EncryptedAttachmentRecord(
          noteId: row.noteId,
          position: row.position,
          encryptedPayload: row.encryptedPayload,
        ),
      );
    }
    for (final entries in attachmentsByNote.values) {
      entries.sort((left, right) => left.position.compareTo(right.position));
    }
    return rows
        .map(
          (row) => EncryptedNoteSnapshot(
            note: _mapRow(row),
            attachments: attachmentsByNote[row.id] ?? const <EncryptedAttachmentRecord>[],
          ),
        )
        .toList(growable: false);
  }

  Future<List<PendingNoteChangeRecord>> loadPendingChanges() async {
    final rows =
        await (select(pendingNoteChanges)
              ..orderBy([
                (table) => OrderingTerm.desc(table.queuedAtEpochMs),
                (table) => OrderingTerm.desc(table.revision),
              ]))
            .get();
    return rows
        .map(
          (row) => PendingNoteChangeRecord(
            noteId: row.noteId,
            vaultId: row.vaultId,
            revision: row.revision,
            action: PendingNoteChangeAction.values.firstWhere(
              (value) => value.name == row.syncAction,
              orElse: () => PendingNoteChangeAction.upsert,
            ),
            queuedAt: DateTime.fromMillisecondsSinceEpoch(row.queuedAtEpochMs),
            contentHash: row.contentHash,
            deletedAt: row.deletedAtEpochMs == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(row.deletedAtEpochMs!),
          ),
        )
        .toList(growable: false);
  }

  Future<void> replaceAll({
    required List<EncryptedNoteRecord> notes,
    required List<EncryptedAttachmentRecord> attachments,
    required List<PendingNoteChangeRecord> pendingChanges,
  }) async {
    await transaction(() async {
      final incomingIds = notes.map((record) => record.id).toSet();
      if (incomingIds.isEmpty) {
        await delete(encryptedNotes).go();
        await delete(encryptedNoteAttachments).go();
        await delete(pendingNoteChanges).go();
      } else {
        await (delete(
          encryptedNotes,
        )..where((table) => table.id.isNotIn(incomingIds))).go();
        await (delete(
          encryptedNoteAttachments,
        )..where((table) => table.noteId.isNotIn(incomingIds))).go();
        await (delete(
          pendingNoteChanges,
        )..where((table) => table.noteId.isNotIn(incomingIds))).go();
      }

      await delete(encryptedNoteAttachments).go();
      await delete(pendingNoteChanges).go();

      for (final record in notes) {
        await into(encryptedNotes).insertOnConflictUpdate(
          EncryptedNotesCompanion.insert(
            id: record.id,
            vaultId: record.vaultId,
            encryptedPayload: record.encryptedPayload,
            createdAtEpochMs: record.createdAt.millisecondsSinceEpoch,
            updatedAtEpochMs: Value(
              record.updatedAt?.millisecondsSinceEpoch,
            ),
            deletedAtEpochMs: Value(
              record.deletedAt?.millisecondsSinceEpoch,
            ),
            isPinned: Value(record.isPinned),
            revision: Value(record.revision),
            syncState: record.syncState.name,
            deviceId: Value(record.deviceId),
            contentHash: Value(record.contentHash),
          ),
        );
      }

      for (final attachment in attachments) {
        await into(encryptedNoteAttachments).insertOnConflictUpdate(
          EncryptedNoteAttachmentsCompanion.insert(
            noteId: attachment.noteId,
            position: attachment.position,
            encryptedPayload: attachment.encryptedPayload,
          ),
        );
      }

      if (pendingChanges.isNotEmpty) {
        for (final change in pendingChanges) {
          await into(pendingNoteChanges).insertOnConflictUpdate(
            PendingNoteChangesCompanion.insert(
              noteId: change.noteId,
              vaultId: change.vaultId,
              revision: change.revision,
              syncAction: change.action.name,
              queuedAtEpochMs: change.queuedAt.millisecondsSinceEpoch,
              contentHash: Value(change.contentHash),
              deletedAtEpochMs: Value(
                change.deletedAt?.millisecondsSinceEpoch,
              ),
            ),
          );
        }
      }
    });
  }

  EncryptedNoteRecord _mapRow(EncryptedNote row) {
    return EncryptedNoteRecord(
      id: row.id,
      vaultId: row.vaultId,
      encryptedPayload: row.encryptedPayload,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAtEpochMs),
      updatedAt: row.updatedAtEpochMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.updatedAtEpochMs!),
      deletedAt: row.deletedAtEpochMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.deletedAtEpochMs!),
      isPinned: row.isPinned,
      revision: row.revision,
      syncState: NoteSyncState.values.firstWhere(
        (state) => state.name == row.syncState,
        orElse: () => NoteSyncState.localOnly,
      ),
      deviceId: row.deviceId,
      contentHash: row.contentHash,
    );
  }
}

class EncryptedNoteSnapshot {
  const EncryptedNoteSnapshot({
    required this.note,
    required this.attachments,
  });

  final EncryptedNoteRecord note;
  final List<EncryptedAttachmentRecord> attachments;
}

class EncryptedNoteRecord {
  const EncryptedNoteRecord({
    required this.id,
    required this.vaultId,
    required this.encryptedPayload,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
    required this.isPinned,
    required this.revision,
    required this.syncState,
    this.deviceId,
    this.contentHash,
  });

  final String id;
  final String vaultId;
  final String encryptedPayload;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final bool isPinned;
  final int revision;
  final NoteSyncState syncState;
  final String? deviceId;
  final String? contentHash;

  Map<String, dynamic> toPayloadJson() {
    return {
      'id': id,
      'vaultId': vaultId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'isPinned': isPinned,
      'revision': revision,
      'syncState': syncState.name,
      'deviceId': deviceId,
      'contentHash': contentHash,
    };
  }

  factory EncryptedNoteRecord.fromNote({
    required NoteEntry note,
    required String encryptedPayload,
  }) {
    return EncryptedNoteRecord(
      id: note.id,
      vaultId: note.vaultId,
      encryptedPayload: encryptedPayload,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      deletedAt: note.deletedAt,
      isPinned: note.isPinned,
      revision: note.revision,
      syncState: note.syncState,
      deviceId: note.deviceId,
      contentHash: note.contentHash,
    );
  }

  factory EncryptedNoteRecord.fromLegacyPayload({
    required String encryptedPayload,
    required Map<String, dynamic> payload,
  }) {
    return EncryptedNoteRecord(
      id: payload['id'] as String,
      vaultId: payload['vaultId'] as String,
      encryptedPayload: encryptedPayload,
      createdAt: DateTime.parse(payload['createdAt'] as String),
      updatedAt: payload['updatedAt'] == null
          ? null
          : DateTime.parse(payload['updatedAt'] as String),
      deletedAt: payload['deletedAt'] == null
          ? null
          : DateTime.parse(payload['deletedAt'] as String),
      isPinned: payload['isPinned'] as bool? ?? false,
      revision: (payload['revision'] as num?)?.toInt() ?? 1,
      syncState: NoteSyncState.values.firstWhere(
        (state) => state.name == payload['syncState'],
        orElse: () => NoteSyncState.localOnly,
      ),
      deviceId: payload['deviceId'] as String?,
      contentHash: payload['contentHash'] as String?,
    );
  }

  factory EncryptedNoteRecord.fromDatabasePayload({
    required String encryptedPayload,
    required Map<String, dynamic> payload,
    required EncryptedNoteRecord metadata,
  }) {
    final note = NoteEntry.fromJson(payload);
    return EncryptedNoteRecord.fromNote(
      note: note.copyWith(
        createdAt: metadata.createdAt,
        updatedAt: metadata.updatedAt,
        deletedAt: metadata.deletedAt,
        isPinned: metadata.isPinned,
        revision: metadata.revision,
        syncState: metadata.syncState,
        deviceId: metadata.deviceId,
        contentHash: metadata.contentHash,
      ),
      encryptedPayload: encryptedPayload,
    );
  }
}

class EncryptedAttachmentRecord {
  const EncryptedAttachmentRecord({
    required this.noteId,
    required this.position,
    required this.encryptedPayload,
  });

  final String noteId;
  final int position;
  final String encryptedPayload;
}

enum PendingNoteChangeAction { upsert, delete }

class PendingNoteChangeRecord {
  const PendingNoteChangeRecord({
    required this.noteId,
    required this.vaultId,
    required this.revision,
    required this.action,
    required this.queuedAt,
    this.contentHash,
    this.deletedAt,
  });

  final String noteId;
  final String vaultId;
  final int revision;
  final PendingNoteChangeAction action;
  final DateTime queuedAt;
  final String? contentHash;
  final DateTime? deletedAt;
}
