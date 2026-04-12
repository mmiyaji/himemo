import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../home/domain/note_entry.dart';

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

@DriftDatabase(tables: [EncryptedNotes])
class EncryptedNoteDatabase extends _$EncryptedNoteDatabase {
  EncryptedNoteDatabase._(super.executor);

  factory EncryptedNoteDatabase({
    QueryExecutor? executor,
    Future<Directory> Function()? directoryProvider,
  }) {
    if (executor != null) {
      return EncryptedNoteDatabase._(executor);
    }
    return EncryptedNoteDatabase._(
      LazyDatabase(() async {
        final directory =
            await (directoryProvider ?? getApplicationSupportDirectory)();
        final file = File(path.join(directory.path, 'himemo_notes.sqlite'));
        return NativeDatabase.createInBackground(file);
      }),
    );
  }

  @override
  int get schemaVersion => 1;

  Future<List<EncryptedNoteRecord>> loadAll() async {
    final rows =
        await (select(encryptedNotes)
              ..orderBy([
                (table) => OrderingTerm.desc(table.isPinned),
                (table) => OrderingTerm.desc(table.updatedAtEpochMs),
                (table) => OrderingTerm.desc(table.createdAtEpochMs),
              ]))
            .get();
    return rows.map(_mapRow).toList(growable: false);
  }

  Future<void> replaceAll(List<EncryptedNoteRecord> records) async {
    await transaction(() async {
      final incomingIds = records.map((record) => record.id).toSet();
      if (incomingIds.isEmpty) {
        await delete(encryptedNotes).go();
      } else {
        await (delete(
          encryptedNotes,
        )..where((table) => table.id.isNotIn(incomingIds))).go();
      }

      for (final record in records) {
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
