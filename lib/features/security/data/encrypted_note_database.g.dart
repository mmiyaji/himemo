// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'encrypted_note_database.dart';

// ignore_for_file: type=lint
class $EncryptedNotesTable extends EncryptedNotes
    with TableInfo<$EncryptedNotesTable, EncryptedNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EncryptedNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vaultIdMeta = const VerificationMeta(
    'vaultId',
  );
  @override
  late final GeneratedColumn<String> vaultId = GeneratedColumn<String>(
    'vault_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedPayloadMeta = const VerificationMeta(
    'encryptedPayload',
  );
  @override
  late final GeneratedColumn<String> encryptedPayload = GeneratedColumn<String>(
    'encrypted_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtEpochMsMeta = const VerificationMeta(
    'createdAtEpochMs',
  );
  @override
  late final GeneratedColumn<int> createdAtEpochMs = GeneratedColumn<int>(
    'created_at_epoch_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtEpochMsMeta = const VerificationMeta(
    'updatedAtEpochMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtEpochMs = GeneratedColumn<int>(
    'updated_at_epoch_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtEpochMsMeta = const VerificationMeta(
    'deletedAtEpochMs',
  );
  @override
  late final GeneratedColumn<int> deletedAtEpochMs = GeneratedColumn<int>(
    'deleted_at_epoch_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    vaultId,
    encryptedPayload,
    createdAtEpochMs,
    updatedAtEpochMs,
    deletedAtEpochMs,
    isPinned,
    revision,
    syncState,
    deviceId,
    contentHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'encrypted_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<EncryptedNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('vault_id')) {
      context.handle(
        _vaultIdMeta,
        vaultId.isAcceptableOrUnknown(data['vault_id']!, _vaultIdMeta),
      );
    } else if (isInserting) {
      context.missing(_vaultIdMeta);
    }
    if (data.containsKey('encrypted_payload')) {
      context.handle(
        _encryptedPayloadMeta,
        encryptedPayload.isAcceptableOrUnknown(
          data['encrypted_payload']!,
          _encryptedPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedPayloadMeta);
    }
    if (data.containsKey('created_at_epoch_ms')) {
      context.handle(
        _createdAtEpochMsMeta,
        createdAtEpochMs.isAcceptableOrUnknown(
          data['created_at_epoch_ms']!,
          _createdAtEpochMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtEpochMsMeta);
    }
    if (data.containsKey('updated_at_epoch_ms')) {
      context.handle(
        _updatedAtEpochMsMeta,
        updatedAtEpochMs.isAcceptableOrUnknown(
          data['updated_at_epoch_ms']!,
          _updatedAtEpochMsMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at_epoch_ms')) {
      context.handle(
        _deletedAtEpochMsMeta,
        deletedAtEpochMs.isAcceptableOrUnknown(
          data['deleted_at_epoch_ms']!,
          _deletedAtEpochMsMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStateMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EncryptedNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EncryptedNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      vaultId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vault_id'],
      )!,
      encryptedPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_payload'],
      )!,
      createdAtEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_epoch_ms'],
      )!,
      updatedAtEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_epoch_ms'],
      ),
      deletedAtEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at_epoch_ms'],
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
    );
  }

  @override
  $EncryptedNotesTable createAlias(String alias) {
    return $EncryptedNotesTable(attachedDatabase, alias);
  }
}

class EncryptedNote extends DataClass implements Insertable<EncryptedNote> {
  final String id;
  final String vaultId;
  final String encryptedPayload;
  final int createdAtEpochMs;
  final int? updatedAtEpochMs;
  final int? deletedAtEpochMs;
  final bool isPinned;
  final int revision;
  final String syncState;
  final String? deviceId;
  final String? contentHash;
  const EncryptedNote({
    required this.id,
    required this.vaultId,
    required this.encryptedPayload,
    required this.createdAtEpochMs,
    this.updatedAtEpochMs,
    this.deletedAtEpochMs,
    required this.isPinned,
    required this.revision,
    required this.syncState,
    this.deviceId,
    this.contentHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['vault_id'] = Variable<String>(vaultId);
    map['encrypted_payload'] = Variable<String>(encryptedPayload);
    map['created_at_epoch_ms'] = Variable<int>(createdAtEpochMs);
    if (!nullToAbsent || updatedAtEpochMs != null) {
      map['updated_at_epoch_ms'] = Variable<int>(updatedAtEpochMs);
    }
    if (!nullToAbsent || deletedAtEpochMs != null) {
      map['deleted_at_epoch_ms'] = Variable<int>(deletedAtEpochMs);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    map['revision'] = Variable<int>(revision);
    map['sync_state'] = Variable<String>(syncState);
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    return map;
  }

  EncryptedNotesCompanion toCompanion(bool nullToAbsent) {
    return EncryptedNotesCompanion(
      id: Value(id),
      vaultId: Value(vaultId),
      encryptedPayload: Value(encryptedPayload),
      createdAtEpochMs: Value(createdAtEpochMs),
      updatedAtEpochMs: updatedAtEpochMs == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAtEpochMs),
      deletedAtEpochMs: deletedAtEpochMs == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAtEpochMs),
      isPinned: Value(isPinned),
      revision: Value(revision),
      syncState: Value(syncState),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
    );
  }

  factory EncryptedNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EncryptedNote(
      id: serializer.fromJson<String>(json['id']),
      vaultId: serializer.fromJson<String>(json['vaultId']),
      encryptedPayload: serializer.fromJson<String>(json['encryptedPayload']),
      createdAtEpochMs: serializer.fromJson<int>(json['createdAtEpochMs']),
      updatedAtEpochMs: serializer.fromJson<int?>(json['updatedAtEpochMs']),
      deletedAtEpochMs: serializer.fromJson<int?>(json['deletedAtEpochMs']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      revision: serializer.fromJson<int>(json['revision']),
      syncState: serializer.fromJson<String>(json['syncState']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'vaultId': serializer.toJson<String>(vaultId),
      'encryptedPayload': serializer.toJson<String>(encryptedPayload),
      'createdAtEpochMs': serializer.toJson<int>(createdAtEpochMs),
      'updatedAtEpochMs': serializer.toJson<int?>(updatedAtEpochMs),
      'deletedAtEpochMs': serializer.toJson<int?>(deletedAtEpochMs),
      'isPinned': serializer.toJson<bool>(isPinned),
      'revision': serializer.toJson<int>(revision),
      'syncState': serializer.toJson<String>(syncState),
      'deviceId': serializer.toJson<String?>(deviceId),
      'contentHash': serializer.toJson<String?>(contentHash),
    };
  }

  EncryptedNote copyWith({
    String? id,
    String? vaultId,
    String? encryptedPayload,
    int? createdAtEpochMs,
    Value<int?> updatedAtEpochMs = const Value.absent(),
    Value<int?> deletedAtEpochMs = const Value.absent(),
    bool? isPinned,
    int? revision,
    String? syncState,
    Value<String?> deviceId = const Value.absent(),
    Value<String?> contentHash = const Value.absent(),
  }) => EncryptedNote(
    id: id ?? this.id,
    vaultId: vaultId ?? this.vaultId,
    encryptedPayload: encryptedPayload ?? this.encryptedPayload,
    createdAtEpochMs: createdAtEpochMs ?? this.createdAtEpochMs,
    updatedAtEpochMs: updatedAtEpochMs.present
        ? updatedAtEpochMs.value
        : this.updatedAtEpochMs,
    deletedAtEpochMs: deletedAtEpochMs.present
        ? deletedAtEpochMs.value
        : this.deletedAtEpochMs,
    isPinned: isPinned ?? this.isPinned,
    revision: revision ?? this.revision,
    syncState: syncState ?? this.syncState,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
  );
  EncryptedNote copyWithCompanion(EncryptedNotesCompanion data) {
    return EncryptedNote(
      id: data.id.present ? data.id.value : this.id,
      vaultId: data.vaultId.present ? data.vaultId.value : this.vaultId,
      encryptedPayload: data.encryptedPayload.present
          ? data.encryptedPayload.value
          : this.encryptedPayload,
      createdAtEpochMs: data.createdAtEpochMs.present
          ? data.createdAtEpochMs.value
          : this.createdAtEpochMs,
      updatedAtEpochMs: data.updatedAtEpochMs.present
          ? data.updatedAtEpochMs.value
          : this.updatedAtEpochMs,
      deletedAtEpochMs: data.deletedAtEpochMs.present
          ? data.deletedAtEpochMs.value
          : this.deletedAtEpochMs,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      revision: data.revision.present ? data.revision.value : this.revision,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedNote(')
          ..write('id: $id, ')
          ..write('vaultId: $vaultId, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('createdAtEpochMs: $createdAtEpochMs, ')
          ..write('updatedAtEpochMs: $updatedAtEpochMs, ')
          ..write('deletedAtEpochMs: $deletedAtEpochMs, ')
          ..write('isPinned: $isPinned, ')
          ..write('revision: $revision, ')
          ..write('syncState: $syncState, ')
          ..write('deviceId: $deviceId, ')
          ..write('contentHash: $contentHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    vaultId,
    encryptedPayload,
    createdAtEpochMs,
    updatedAtEpochMs,
    deletedAtEpochMs,
    isPinned,
    revision,
    syncState,
    deviceId,
    contentHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EncryptedNote &&
          other.id == this.id &&
          other.vaultId == this.vaultId &&
          other.encryptedPayload == this.encryptedPayload &&
          other.createdAtEpochMs == this.createdAtEpochMs &&
          other.updatedAtEpochMs == this.updatedAtEpochMs &&
          other.deletedAtEpochMs == this.deletedAtEpochMs &&
          other.isPinned == this.isPinned &&
          other.revision == this.revision &&
          other.syncState == this.syncState &&
          other.deviceId == this.deviceId &&
          other.contentHash == this.contentHash);
}

class EncryptedNotesCompanion extends UpdateCompanion<EncryptedNote> {
  final Value<String> id;
  final Value<String> vaultId;
  final Value<String> encryptedPayload;
  final Value<int> createdAtEpochMs;
  final Value<int?> updatedAtEpochMs;
  final Value<int?> deletedAtEpochMs;
  final Value<bool> isPinned;
  final Value<int> revision;
  final Value<String> syncState;
  final Value<String?> deviceId;
  final Value<String?> contentHash;
  final Value<int> rowid;
  const EncryptedNotesCompanion({
    this.id = const Value.absent(),
    this.vaultId = const Value.absent(),
    this.encryptedPayload = const Value.absent(),
    this.createdAtEpochMs = const Value.absent(),
    this.updatedAtEpochMs = const Value.absent(),
    this.deletedAtEpochMs = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.revision = const Value.absent(),
    this.syncState = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EncryptedNotesCompanion.insert({
    required String id,
    required String vaultId,
    required String encryptedPayload,
    required int createdAtEpochMs,
    this.updatedAtEpochMs = const Value.absent(),
    this.deletedAtEpochMs = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.revision = const Value.absent(),
    required String syncState,
    this.deviceId = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       vaultId = Value(vaultId),
       encryptedPayload = Value(encryptedPayload),
       createdAtEpochMs = Value(createdAtEpochMs),
       syncState = Value(syncState);
  static Insertable<EncryptedNote> custom({
    Expression<String>? id,
    Expression<String>? vaultId,
    Expression<String>? encryptedPayload,
    Expression<int>? createdAtEpochMs,
    Expression<int>? updatedAtEpochMs,
    Expression<int>? deletedAtEpochMs,
    Expression<bool>? isPinned,
    Expression<int>? revision,
    Expression<String>? syncState,
    Expression<String>? deviceId,
    Expression<String>? contentHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (vaultId != null) 'vault_id': vaultId,
      if (encryptedPayload != null) 'encrypted_payload': encryptedPayload,
      if (createdAtEpochMs != null) 'created_at_epoch_ms': createdAtEpochMs,
      if (updatedAtEpochMs != null) 'updated_at_epoch_ms': updatedAtEpochMs,
      if (deletedAtEpochMs != null) 'deleted_at_epoch_ms': deletedAtEpochMs,
      if (isPinned != null) 'is_pinned': isPinned,
      if (revision != null) 'revision': revision,
      if (syncState != null) 'sync_state': syncState,
      if (deviceId != null) 'device_id': deviceId,
      if (contentHash != null) 'content_hash': contentHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EncryptedNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? vaultId,
    Value<String>? encryptedPayload,
    Value<int>? createdAtEpochMs,
    Value<int?>? updatedAtEpochMs,
    Value<int?>? deletedAtEpochMs,
    Value<bool>? isPinned,
    Value<int>? revision,
    Value<String>? syncState,
    Value<String?>? deviceId,
    Value<String?>? contentHash,
    Value<int>? rowid,
  }) {
    return EncryptedNotesCompanion(
      id: id ?? this.id,
      vaultId: vaultId ?? this.vaultId,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      createdAtEpochMs: createdAtEpochMs ?? this.createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
      deletedAtEpochMs: deletedAtEpochMs ?? this.deletedAtEpochMs,
      isPinned: isPinned ?? this.isPinned,
      revision: revision ?? this.revision,
      syncState: syncState ?? this.syncState,
      deviceId: deviceId ?? this.deviceId,
      contentHash: contentHash ?? this.contentHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (vaultId.present) {
      map['vault_id'] = Variable<String>(vaultId.value);
    }
    if (encryptedPayload.present) {
      map['encrypted_payload'] = Variable<String>(encryptedPayload.value);
    }
    if (createdAtEpochMs.present) {
      map['created_at_epoch_ms'] = Variable<int>(createdAtEpochMs.value);
    }
    if (updatedAtEpochMs.present) {
      map['updated_at_epoch_ms'] = Variable<int>(updatedAtEpochMs.value);
    }
    if (deletedAtEpochMs.present) {
      map['deleted_at_epoch_ms'] = Variable<int>(deletedAtEpochMs.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedNotesCompanion(')
          ..write('id: $id, ')
          ..write('vaultId: $vaultId, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('createdAtEpochMs: $createdAtEpochMs, ')
          ..write('updatedAtEpochMs: $updatedAtEpochMs, ')
          ..write('deletedAtEpochMs: $deletedAtEpochMs, ')
          ..write('isPinned: $isPinned, ')
          ..write('revision: $revision, ')
          ..write('syncState: $syncState, ')
          ..write('deviceId: $deviceId, ')
          ..write('contentHash: $contentHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$EncryptedNoteDatabase extends GeneratedDatabase {
  _$EncryptedNoteDatabase(QueryExecutor e) : super(e);
  $EncryptedNoteDatabaseManager get managers =>
      $EncryptedNoteDatabaseManager(this);
  late final $EncryptedNotesTable encryptedNotes = $EncryptedNotesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [encryptedNotes];
}

typedef $$EncryptedNotesTableCreateCompanionBuilder =
    EncryptedNotesCompanion Function({
      required String id,
      required String vaultId,
      required String encryptedPayload,
      required int createdAtEpochMs,
      Value<int?> updatedAtEpochMs,
      Value<int?> deletedAtEpochMs,
      Value<bool> isPinned,
      Value<int> revision,
      required String syncState,
      Value<String?> deviceId,
      Value<String?> contentHash,
      Value<int> rowid,
    });
typedef $$EncryptedNotesTableUpdateCompanionBuilder =
    EncryptedNotesCompanion Function({
      Value<String> id,
      Value<String> vaultId,
      Value<String> encryptedPayload,
      Value<int> createdAtEpochMs,
      Value<int?> updatedAtEpochMs,
      Value<int?> deletedAtEpochMs,
      Value<bool> isPinned,
      Value<int> revision,
      Value<String> syncState,
      Value<String?> deviceId,
      Value<String?> contentHash,
      Value<int> rowid,
    });

class $$EncryptedNotesTableFilterComposer
    extends Composer<_$EncryptedNoteDatabase, $EncryptedNotesTable> {
  $$EncryptedNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vaultId => $composableBuilder(
    column: $table.vaultId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtEpochMs => $composableBuilder(
    column: $table.createdAtEpochMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtEpochMs => $composableBuilder(
    column: $table.updatedAtEpochMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAtEpochMs => $composableBuilder(
    column: $table.deletedAtEpochMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EncryptedNotesTableOrderingComposer
    extends Composer<_$EncryptedNoteDatabase, $EncryptedNotesTable> {
  $$EncryptedNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vaultId => $composableBuilder(
    column: $table.vaultId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtEpochMs => $composableBuilder(
    column: $table.createdAtEpochMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtEpochMs => $composableBuilder(
    column: $table.updatedAtEpochMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAtEpochMs => $composableBuilder(
    column: $table.deletedAtEpochMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EncryptedNotesTableAnnotationComposer
    extends Composer<_$EncryptedNoteDatabase, $EncryptedNotesTable> {
  $$EncryptedNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get vaultId =>
      $composableBuilder(column: $table.vaultId, builder: (column) => column);

  GeneratedColumn<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtEpochMs => $composableBuilder(
    column: $table.createdAtEpochMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtEpochMs => $composableBuilder(
    column: $table.updatedAtEpochMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAtEpochMs => $composableBuilder(
    column: $table.deletedAtEpochMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );
}

class $$EncryptedNotesTableTableManager
    extends
        RootTableManager<
          _$EncryptedNoteDatabase,
          $EncryptedNotesTable,
          EncryptedNote,
          $$EncryptedNotesTableFilterComposer,
          $$EncryptedNotesTableOrderingComposer,
          $$EncryptedNotesTableAnnotationComposer,
          $$EncryptedNotesTableCreateCompanionBuilder,
          $$EncryptedNotesTableUpdateCompanionBuilder,
          (
            EncryptedNote,
            BaseReferences<
              _$EncryptedNoteDatabase,
              $EncryptedNotesTable,
              EncryptedNote
            >,
          ),
          EncryptedNote,
          PrefetchHooks Function()
        > {
  $$EncryptedNotesTableTableManager(
    _$EncryptedNoteDatabase db,
    $EncryptedNotesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EncryptedNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EncryptedNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EncryptedNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> vaultId = const Value.absent(),
                Value<String> encryptedPayload = const Value.absent(),
                Value<int> createdAtEpochMs = const Value.absent(),
                Value<int?> updatedAtEpochMs = const Value.absent(),
                Value<int?> deletedAtEpochMs = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EncryptedNotesCompanion(
                id: id,
                vaultId: vaultId,
                encryptedPayload: encryptedPayload,
                createdAtEpochMs: createdAtEpochMs,
                updatedAtEpochMs: updatedAtEpochMs,
                deletedAtEpochMs: deletedAtEpochMs,
                isPinned: isPinned,
                revision: revision,
                syncState: syncState,
                deviceId: deviceId,
                contentHash: contentHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String vaultId,
                required String encryptedPayload,
                required int createdAtEpochMs,
                Value<int?> updatedAtEpochMs = const Value.absent(),
                Value<int?> deletedAtEpochMs = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> revision = const Value.absent(),
                required String syncState,
                Value<String?> deviceId = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EncryptedNotesCompanion.insert(
                id: id,
                vaultId: vaultId,
                encryptedPayload: encryptedPayload,
                createdAtEpochMs: createdAtEpochMs,
                updatedAtEpochMs: updatedAtEpochMs,
                deletedAtEpochMs: deletedAtEpochMs,
                isPinned: isPinned,
                revision: revision,
                syncState: syncState,
                deviceId: deviceId,
                contentHash: contentHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EncryptedNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$EncryptedNoteDatabase,
      $EncryptedNotesTable,
      EncryptedNote,
      $$EncryptedNotesTableFilterComposer,
      $$EncryptedNotesTableOrderingComposer,
      $$EncryptedNotesTableAnnotationComposer,
      $$EncryptedNotesTableCreateCompanionBuilder,
      $$EncryptedNotesTableUpdateCompanionBuilder,
      (
        EncryptedNote,
        BaseReferences<
          _$EncryptedNoteDatabase,
          $EncryptedNotesTable,
          EncryptedNote
        >,
      ),
      EncryptedNote,
      PrefetchHooks Function()
    >;

class $EncryptedNoteDatabaseManager {
  final _$EncryptedNoteDatabase _db;
  $EncryptedNoteDatabaseManager(this._db);
  $$EncryptedNotesTableTableManager get encryptedNotes =>
      $$EncryptedNotesTableTableManager(_db, _db.encryptedNotes);
}
