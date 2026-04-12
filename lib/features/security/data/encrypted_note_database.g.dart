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

class $EncryptedNoteAttachmentsTable extends EncryptedNoteAttachments
    with TableInfo<$EncryptedNoteAttachmentsTable, EncryptedNoteAttachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EncryptedNoteAttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  @override
  List<GeneratedColumn> get $columns => [noteId, position, encryptedPayload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'encrypted_note_attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<EncryptedNoteAttachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId, position};
  @override
  EncryptedNoteAttachment map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EncryptedNoteAttachment(
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      encryptedPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_payload'],
      )!,
    );
  }

  @override
  $EncryptedNoteAttachmentsTable createAlias(String alias) {
    return $EncryptedNoteAttachmentsTable(attachedDatabase, alias);
  }
}

class EncryptedNoteAttachment extends DataClass
    implements Insertable<EncryptedNoteAttachment> {
  final String noteId;
  final int position;
  final String encryptedPayload;
  const EncryptedNoteAttachment({
    required this.noteId,
    required this.position,
    required this.encryptedPayload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['note_id'] = Variable<String>(noteId);
    map['position'] = Variable<int>(position);
    map['encrypted_payload'] = Variable<String>(encryptedPayload);
    return map;
  }

  EncryptedNoteAttachmentsCompanion toCompanion(bool nullToAbsent) {
    return EncryptedNoteAttachmentsCompanion(
      noteId: Value(noteId),
      position: Value(position),
      encryptedPayload: Value(encryptedPayload),
    );
  }

  factory EncryptedNoteAttachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EncryptedNoteAttachment(
      noteId: serializer.fromJson<String>(json['noteId']),
      position: serializer.fromJson<int>(json['position']),
      encryptedPayload: serializer.fromJson<String>(json['encryptedPayload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<String>(noteId),
      'position': serializer.toJson<int>(position),
      'encryptedPayload': serializer.toJson<String>(encryptedPayload),
    };
  }

  EncryptedNoteAttachment copyWith({
    String? noteId,
    int? position,
    String? encryptedPayload,
  }) => EncryptedNoteAttachment(
    noteId: noteId ?? this.noteId,
    position: position ?? this.position,
    encryptedPayload: encryptedPayload ?? this.encryptedPayload,
  );
  EncryptedNoteAttachment copyWithCompanion(
    EncryptedNoteAttachmentsCompanion data,
  ) {
    return EncryptedNoteAttachment(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      position: data.position.present ? data.position.value : this.position,
      encryptedPayload: data.encryptedPayload.present
          ? data.encryptedPayload.value
          : this.encryptedPayload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedNoteAttachment(')
          ..write('noteId: $noteId, ')
          ..write('position: $position, ')
          ..write('encryptedPayload: $encryptedPayload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(noteId, position, encryptedPayload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EncryptedNoteAttachment &&
          other.noteId == this.noteId &&
          other.position == this.position &&
          other.encryptedPayload == this.encryptedPayload);
}

class EncryptedNoteAttachmentsCompanion
    extends UpdateCompanion<EncryptedNoteAttachment> {
  final Value<String> noteId;
  final Value<int> position;
  final Value<String> encryptedPayload;
  final Value<int> rowid;
  const EncryptedNoteAttachmentsCompanion({
    this.noteId = const Value.absent(),
    this.position = const Value.absent(),
    this.encryptedPayload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EncryptedNoteAttachmentsCompanion.insert({
    required String noteId,
    required int position,
    required String encryptedPayload,
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       position = Value(position),
       encryptedPayload = Value(encryptedPayload);
  static Insertable<EncryptedNoteAttachment> custom({
    Expression<String>? noteId,
    Expression<int>? position,
    Expression<String>? encryptedPayload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'note_id': noteId,
      if (position != null) 'position': position,
      if (encryptedPayload != null) 'encrypted_payload': encryptedPayload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EncryptedNoteAttachmentsCompanion copyWith({
    Value<String>? noteId,
    Value<int>? position,
    Value<String>? encryptedPayload,
    Value<int>? rowid,
  }) {
    return EncryptedNoteAttachmentsCompanion(
      noteId: noteId ?? this.noteId,
      position: position ?? this.position,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (encryptedPayload.present) {
      map['encrypted_payload'] = Variable<String>(encryptedPayload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EncryptedNoteAttachmentsCompanion(')
          ..write('noteId: $noteId, ')
          ..write('position: $position, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingNoteChangesTable extends PendingNoteChanges
    with TableInfo<$PendingNoteChangesTable, PendingNoteChange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingNoteChangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
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
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncActionMeta = const VerificationMeta(
    'syncAction',
  );
  @override
  late final GeneratedColumn<String> syncAction = GeneratedColumn<String>(
    'sync_action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queuedAtEpochMsMeta = const VerificationMeta(
    'queuedAtEpochMs',
  );
  @override
  late final GeneratedColumn<int> queuedAtEpochMs = GeneratedColumn<int>(
    'queued_at_epoch_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    noteId,
    vaultId,
    revision,
    syncAction,
    queuedAtEpochMs,
    contentHash,
    deletedAtEpochMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_note_changes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingNoteChange> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('vault_id')) {
      context.handle(
        _vaultIdMeta,
        vaultId.isAcceptableOrUnknown(data['vault_id']!, _vaultIdMeta),
      );
    } else if (isInserting) {
      context.missing(_vaultIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('sync_action')) {
      context.handle(
        _syncActionMeta,
        syncAction.isAcceptableOrUnknown(data['sync_action']!, _syncActionMeta),
      );
    } else if (isInserting) {
      context.missing(_syncActionMeta);
    }
    if (data.containsKey('queued_at_epoch_ms')) {
      context.handle(
        _queuedAtEpochMsMeta,
        queuedAtEpochMs.isAcceptableOrUnknown(
          data['queued_at_epoch_ms']!,
          _queuedAtEpochMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_queuedAtEpochMsMeta);
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
    if (data.containsKey('deleted_at_epoch_ms')) {
      context.handle(
        _deletedAtEpochMsMeta,
        deletedAtEpochMs.isAcceptableOrUnknown(
          data['deleted_at_epoch_ms']!,
          _deletedAtEpochMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId};
  @override
  PendingNoteChange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingNoteChange(
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      vaultId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vault_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      syncAction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_action'],
      )!,
      queuedAtEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queued_at_epoch_ms'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      deletedAtEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at_epoch_ms'],
      ),
    );
  }

  @override
  $PendingNoteChangesTable createAlias(String alias) {
    return $PendingNoteChangesTable(attachedDatabase, alias);
  }
}

class PendingNoteChange extends DataClass
    implements Insertable<PendingNoteChange> {
  final String noteId;
  final String vaultId;
  final int revision;
  final String syncAction;
  final int queuedAtEpochMs;
  final String? contentHash;
  final int? deletedAtEpochMs;
  const PendingNoteChange({
    required this.noteId,
    required this.vaultId,
    required this.revision,
    required this.syncAction,
    required this.queuedAtEpochMs,
    this.contentHash,
    this.deletedAtEpochMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['note_id'] = Variable<String>(noteId);
    map['vault_id'] = Variable<String>(vaultId);
    map['revision'] = Variable<int>(revision);
    map['sync_action'] = Variable<String>(syncAction);
    map['queued_at_epoch_ms'] = Variable<int>(queuedAtEpochMs);
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    if (!nullToAbsent || deletedAtEpochMs != null) {
      map['deleted_at_epoch_ms'] = Variable<int>(deletedAtEpochMs);
    }
    return map;
  }

  PendingNoteChangesCompanion toCompanion(bool nullToAbsent) {
    return PendingNoteChangesCompanion(
      noteId: Value(noteId),
      vaultId: Value(vaultId),
      revision: Value(revision),
      syncAction: Value(syncAction),
      queuedAtEpochMs: Value(queuedAtEpochMs),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      deletedAtEpochMs: deletedAtEpochMs == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAtEpochMs),
    );
  }

  factory PendingNoteChange.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingNoteChange(
      noteId: serializer.fromJson<String>(json['noteId']),
      vaultId: serializer.fromJson<String>(json['vaultId']),
      revision: serializer.fromJson<int>(json['revision']),
      syncAction: serializer.fromJson<String>(json['syncAction']),
      queuedAtEpochMs: serializer.fromJson<int>(json['queuedAtEpochMs']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      deletedAtEpochMs: serializer.fromJson<int?>(json['deletedAtEpochMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<String>(noteId),
      'vaultId': serializer.toJson<String>(vaultId),
      'revision': serializer.toJson<int>(revision),
      'syncAction': serializer.toJson<String>(syncAction),
      'queuedAtEpochMs': serializer.toJson<int>(queuedAtEpochMs),
      'contentHash': serializer.toJson<String?>(contentHash),
      'deletedAtEpochMs': serializer.toJson<int?>(deletedAtEpochMs),
    };
  }

  PendingNoteChange copyWith({
    String? noteId,
    String? vaultId,
    int? revision,
    String? syncAction,
    int? queuedAtEpochMs,
    Value<String?> contentHash = const Value.absent(),
    Value<int?> deletedAtEpochMs = const Value.absent(),
  }) => PendingNoteChange(
    noteId: noteId ?? this.noteId,
    vaultId: vaultId ?? this.vaultId,
    revision: revision ?? this.revision,
    syncAction: syncAction ?? this.syncAction,
    queuedAtEpochMs: queuedAtEpochMs ?? this.queuedAtEpochMs,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    deletedAtEpochMs: deletedAtEpochMs.present
        ? deletedAtEpochMs.value
        : this.deletedAtEpochMs,
  );
  PendingNoteChange copyWithCompanion(PendingNoteChangesCompanion data) {
    return PendingNoteChange(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      vaultId: data.vaultId.present ? data.vaultId.value : this.vaultId,
      revision: data.revision.present ? data.revision.value : this.revision,
      syncAction: data.syncAction.present
          ? data.syncAction.value
          : this.syncAction,
      queuedAtEpochMs: data.queuedAtEpochMs.present
          ? data.queuedAtEpochMs.value
          : this.queuedAtEpochMs,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      deletedAtEpochMs: data.deletedAtEpochMs.present
          ? data.deletedAtEpochMs.value
          : this.deletedAtEpochMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingNoteChange(')
          ..write('noteId: $noteId, ')
          ..write('vaultId: $vaultId, ')
          ..write('revision: $revision, ')
          ..write('syncAction: $syncAction, ')
          ..write('queuedAtEpochMs: $queuedAtEpochMs, ')
          ..write('contentHash: $contentHash, ')
          ..write('deletedAtEpochMs: $deletedAtEpochMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    noteId,
    vaultId,
    revision,
    syncAction,
    queuedAtEpochMs,
    contentHash,
    deletedAtEpochMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingNoteChange &&
          other.noteId == this.noteId &&
          other.vaultId == this.vaultId &&
          other.revision == this.revision &&
          other.syncAction == this.syncAction &&
          other.queuedAtEpochMs == this.queuedAtEpochMs &&
          other.contentHash == this.contentHash &&
          other.deletedAtEpochMs == this.deletedAtEpochMs);
}

class PendingNoteChangesCompanion extends UpdateCompanion<PendingNoteChange> {
  final Value<String> noteId;
  final Value<String> vaultId;
  final Value<int> revision;
  final Value<String> syncAction;
  final Value<int> queuedAtEpochMs;
  final Value<String?> contentHash;
  final Value<int?> deletedAtEpochMs;
  final Value<int> rowid;
  const PendingNoteChangesCompanion({
    this.noteId = const Value.absent(),
    this.vaultId = const Value.absent(),
    this.revision = const Value.absent(),
    this.syncAction = const Value.absent(),
    this.queuedAtEpochMs = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.deletedAtEpochMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingNoteChangesCompanion.insert({
    required String noteId,
    required String vaultId,
    required int revision,
    required String syncAction,
    required int queuedAtEpochMs,
    this.contentHash = const Value.absent(),
    this.deletedAtEpochMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       vaultId = Value(vaultId),
       revision = Value(revision),
       syncAction = Value(syncAction),
       queuedAtEpochMs = Value(queuedAtEpochMs);
  static Insertable<PendingNoteChange> custom({
    Expression<String>? noteId,
    Expression<String>? vaultId,
    Expression<int>? revision,
    Expression<String>? syncAction,
    Expression<int>? queuedAtEpochMs,
    Expression<String>? contentHash,
    Expression<int>? deletedAtEpochMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'note_id': noteId,
      if (vaultId != null) 'vault_id': vaultId,
      if (revision != null) 'revision': revision,
      if (syncAction != null) 'sync_action': syncAction,
      if (queuedAtEpochMs != null) 'queued_at_epoch_ms': queuedAtEpochMs,
      if (contentHash != null) 'content_hash': contentHash,
      if (deletedAtEpochMs != null) 'deleted_at_epoch_ms': deletedAtEpochMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingNoteChangesCompanion copyWith({
    Value<String>? noteId,
    Value<String>? vaultId,
    Value<int>? revision,
    Value<String>? syncAction,
    Value<int>? queuedAtEpochMs,
    Value<String?>? contentHash,
    Value<int?>? deletedAtEpochMs,
    Value<int>? rowid,
  }) {
    return PendingNoteChangesCompanion(
      noteId: noteId ?? this.noteId,
      vaultId: vaultId ?? this.vaultId,
      revision: revision ?? this.revision,
      syncAction: syncAction ?? this.syncAction,
      queuedAtEpochMs: queuedAtEpochMs ?? this.queuedAtEpochMs,
      contentHash: contentHash ?? this.contentHash,
      deletedAtEpochMs: deletedAtEpochMs ?? this.deletedAtEpochMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (vaultId.present) {
      map['vault_id'] = Variable<String>(vaultId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (syncAction.present) {
      map['sync_action'] = Variable<String>(syncAction.value);
    }
    if (queuedAtEpochMs.present) {
      map['queued_at_epoch_ms'] = Variable<int>(queuedAtEpochMs.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (deletedAtEpochMs.present) {
      map['deleted_at_epoch_ms'] = Variable<int>(deletedAtEpochMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingNoteChangesCompanion(')
          ..write('noteId: $noteId, ')
          ..write('vaultId: $vaultId, ')
          ..write('revision: $revision, ')
          ..write('syncAction: $syncAction, ')
          ..write('queuedAtEpochMs: $queuedAtEpochMs, ')
          ..write('contentHash: $contentHash, ')
          ..write('deletedAtEpochMs: $deletedAtEpochMs, ')
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
  late final $EncryptedNoteAttachmentsTable encryptedNoteAttachments =
      $EncryptedNoteAttachmentsTable(this);
  late final $PendingNoteChangesTable pendingNoteChanges =
      $PendingNoteChangesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    encryptedNotes,
    encryptedNoteAttachments,
    pendingNoteChanges,
  ];
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
typedef $$EncryptedNoteAttachmentsTableCreateCompanionBuilder =
    EncryptedNoteAttachmentsCompanion Function({
      required String noteId,
      required int position,
      required String encryptedPayload,
      Value<int> rowid,
    });
typedef $$EncryptedNoteAttachmentsTableUpdateCompanionBuilder =
    EncryptedNoteAttachmentsCompanion Function({
      Value<String> noteId,
      Value<int> position,
      Value<String> encryptedPayload,
      Value<int> rowid,
    });

class $$EncryptedNoteAttachmentsTableFilterComposer
    extends Composer<_$EncryptedNoteDatabase, $EncryptedNoteAttachmentsTable> {
  $$EncryptedNoteAttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EncryptedNoteAttachmentsTableOrderingComposer
    extends Composer<_$EncryptedNoteDatabase, $EncryptedNoteAttachmentsTable> {
  $$EncryptedNoteAttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EncryptedNoteAttachmentsTableAnnotationComposer
    extends Composer<_$EncryptedNoteDatabase, $EncryptedNoteAttachmentsTable> {
  $$EncryptedNoteAttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => column,
  );
}

class $$EncryptedNoteAttachmentsTableTableManager
    extends
        RootTableManager<
          _$EncryptedNoteDatabase,
          $EncryptedNoteAttachmentsTable,
          EncryptedNoteAttachment,
          $$EncryptedNoteAttachmentsTableFilterComposer,
          $$EncryptedNoteAttachmentsTableOrderingComposer,
          $$EncryptedNoteAttachmentsTableAnnotationComposer,
          $$EncryptedNoteAttachmentsTableCreateCompanionBuilder,
          $$EncryptedNoteAttachmentsTableUpdateCompanionBuilder,
          (
            EncryptedNoteAttachment,
            BaseReferences<
              _$EncryptedNoteDatabase,
              $EncryptedNoteAttachmentsTable,
              EncryptedNoteAttachment
            >,
          ),
          EncryptedNoteAttachment,
          PrefetchHooks Function()
        > {
  $$EncryptedNoteAttachmentsTableTableManager(
    _$EncryptedNoteDatabase db,
    $EncryptedNoteAttachmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EncryptedNoteAttachmentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$EncryptedNoteAttachmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EncryptedNoteAttachmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> noteId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> encryptedPayload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EncryptedNoteAttachmentsCompanion(
                noteId: noteId,
                position: position,
                encryptedPayload: encryptedPayload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String noteId,
                required int position,
                required String encryptedPayload,
                Value<int> rowid = const Value.absent(),
              }) => EncryptedNoteAttachmentsCompanion.insert(
                noteId: noteId,
                position: position,
                encryptedPayload: encryptedPayload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EncryptedNoteAttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$EncryptedNoteDatabase,
      $EncryptedNoteAttachmentsTable,
      EncryptedNoteAttachment,
      $$EncryptedNoteAttachmentsTableFilterComposer,
      $$EncryptedNoteAttachmentsTableOrderingComposer,
      $$EncryptedNoteAttachmentsTableAnnotationComposer,
      $$EncryptedNoteAttachmentsTableCreateCompanionBuilder,
      $$EncryptedNoteAttachmentsTableUpdateCompanionBuilder,
      (
        EncryptedNoteAttachment,
        BaseReferences<
          _$EncryptedNoteDatabase,
          $EncryptedNoteAttachmentsTable,
          EncryptedNoteAttachment
        >,
      ),
      EncryptedNoteAttachment,
      PrefetchHooks Function()
    >;
typedef $$PendingNoteChangesTableCreateCompanionBuilder =
    PendingNoteChangesCompanion Function({
      required String noteId,
      required String vaultId,
      required int revision,
      required String syncAction,
      required int queuedAtEpochMs,
      Value<String?> contentHash,
      Value<int?> deletedAtEpochMs,
      Value<int> rowid,
    });
typedef $$PendingNoteChangesTableUpdateCompanionBuilder =
    PendingNoteChangesCompanion Function({
      Value<String> noteId,
      Value<String> vaultId,
      Value<int> revision,
      Value<String> syncAction,
      Value<int> queuedAtEpochMs,
      Value<String?> contentHash,
      Value<int?> deletedAtEpochMs,
      Value<int> rowid,
    });

class $$PendingNoteChangesTableFilterComposer
    extends Composer<_$EncryptedNoteDatabase, $PendingNoteChangesTable> {
  $$PendingNoteChangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vaultId => $composableBuilder(
    column: $table.vaultId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncAction => $composableBuilder(
    column: $table.syncAction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get queuedAtEpochMs => $composableBuilder(
    column: $table.queuedAtEpochMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAtEpochMs => $composableBuilder(
    column: $table.deletedAtEpochMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingNoteChangesTableOrderingComposer
    extends Composer<_$EncryptedNoteDatabase, $PendingNoteChangesTable> {
  $$PendingNoteChangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vaultId => $composableBuilder(
    column: $table.vaultId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncAction => $composableBuilder(
    column: $table.syncAction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queuedAtEpochMs => $composableBuilder(
    column: $table.queuedAtEpochMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAtEpochMs => $composableBuilder(
    column: $table.deletedAtEpochMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingNoteChangesTableAnnotationComposer
    extends Composer<_$EncryptedNoteDatabase, $PendingNoteChangesTable> {
  $$PendingNoteChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get vaultId =>
      $composableBuilder(column: $table.vaultId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get syncAction => $composableBuilder(
    column: $table.syncAction,
    builder: (column) => column,
  );

  GeneratedColumn<int> get queuedAtEpochMs => $composableBuilder(
    column: $table.queuedAtEpochMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAtEpochMs => $composableBuilder(
    column: $table.deletedAtEpochMs,
    builder: (column) => column,
  );
}

class $$PendingNoteChangesTableTableManager
    extends
        RootTableManager<
          _$EncryptedNoteDatabase,
          $PendingNoteChangesTable,
          PendingNoteChange,
          $$PendingNoteChangesTableFilterComposer,
          $$PendingNoteChangesTableOrderingComposer,
          $$PendingNoteChangesTableAnnotationComposer,
          $$PendingNoteChangesTableCreateCompanionBuilder,
          $$PendingNoteChangesTableUpdateCompanionBuilder,
          (
            PendingNoteChange,
            BaseReferences<
              _$EncryptedNoteDatabase,
              $PendingNoteChangesTable,
              PendingNoteChange
            >,
          ),
          PendingNoteChange,
          PrefetchHooks Function()
        > {
  $$PendingNoteChangesTableTableManager(
    _$EncryptedNoteDatabase db,
    $PendingNoteChangesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingNoteChangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingNoteChangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingNoteChangesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> noteId = const Value.absent(),
                Value<String> vaultId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> syncAction = const Value.absent(),
                Value<int> queuedAtEpochMs = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int?> deletedAtEpochMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingNoteChangesCompanion(
                noteId: noteId,
                vaultId: vaultId,
                revision: revision,
                syncAction: syncAction,
                queuedAtEpochMs: queuedAtEpochMs,
                contentHash: contentHash,
                deletedAtEpochMs: deletedAtEpochMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String noteId,
                required String vaultId,
                required int revision,
                required String syncAction,
                required int queuedAtEpochMs,
                Value<String?> contentHash = const Value.absent(),
                Value<int?> deletedAtEpochMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingNoteChangesCompanion.insert(
                noteId: noteId,
                vaultId: vaultId,
                revision: revision,
                syncAction: syncAction,
                queuedAtEpochMs: queuedAtEpochMs,
                contentHash: contentHash,
                deletedAtEpochMs: deletedAtEpochMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingNoteChangesTableProcessedTableManager =
    ProcessedTableManager<
      _$EncryptedNoteDatabase,
      $PendingNoteChangesTable,
      PendingNoteChange,
      $$PendingNoteChangesTableFilterComposer,
      $$PendingNoteChangesTableOrderingComposer,
      $$PendingNoteChangesTableAnnotationComposer,
      $$PendingNoteChangesTableCreateCompanionBuilder,
      $$PendingNoteChangesTableUpdateCompanionBuilder,
      (
        PendingNoteChange,
        BaseReferences<
          _$EncryptedNoteDatabase,
          $PendingNoteChangesTable,
          PendingNoteChange
        >,
      ),
      PendingNoteChange,
      PrefetchHooks Function()
    >;

class $EncryptedNoteDatabaseManager {
  final _$EncryptedNoteDatabase _db;
  $EncryptedNoteDatabaseManager(this._db);
  $$EncryptedNotesTableTableManager get encryptedNotes =>
      $$EncryptedNotesTableTableManager(_db, _db.encryptedNotes);
  $$EncryptedNoteAttachmentsTableTableManager get encryptedNoteAttachments =>
      $$EncryptedNoteAttachmentsTableTableManager(
        _db,
        _db.encryptedNoteAttachments,
      );
  $$PendingNoteChangesTableTableManager get pendingNoteChanges =>
      $$PendingNoteChangesTableTableManager(_db, _db.pendingNoteChanges);
}
