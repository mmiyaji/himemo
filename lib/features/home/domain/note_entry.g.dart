// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NoteAttachment _$NoteAttachmentFromJson(Map<String, dynamic> json) =>
    _NoteAttachment(
      type: $enumDecode(_$AttachmentTypeEnumMap, json['type']),
      label: json['label'] as String,
      filePath: json['filePath'] as String?,
      previewBytesBase64: json['previewBytesBase64'] as String?,
    );

Map<String, dynamic> _$NoteAttachmentToJson(_NoteAttachment instance) =>
    <String, dynamic>{
      'type': _$AttachmentTypeEnumMap[instance.type]!,
      'label': instance.label,
      'filePath': instance.filePath,
      'previewBytesBase64': instance.previewBytesBase64,
    };

const _$AttachmentTypeEnumMap = {
  AttachmentType.photo: 'photo',
  AttachmentType.video: 'video',
  AttachmentType.audio: 'audio',
};

_NoteBlock _$NoteBlockFromJson(Map<String, dynamic> json) => _NoteBlock(
  type: $enumDecode(_$NoteBlockTypeEnumMap, json['type']),
  text: json['text'] as String?,
  attachment: json['attachment'] == null
      ? null
      : NoteAttachment.fromJson(json['attachment'] as Map<String, dynamic>),
);

Map<String, dynamic> _$NoteBlockToJson(_NoteBlock instance) =>
    <String, dynamic>{
      'type': _$NoteBlockTypeEnumMap[instance.type]!,
      'text': instance.text,
      'attachment': instance.attachment,
    };

const _$NoteBlockTypeEnumMap = {
  NoteBlockType.paragraph: 'paragraph',
  NoteBlockType.photo: 'photo',
  NoteBlockType.video: 'video',
  NoteBlockType.audio: 'audio',
};

_NoteEntry _$NoteEntryFromJson(Map<String, dynamic> json) => _NoteEntry(
  id: json['id'] as String,
  vaultId: json['vaultId'] as String,
  title: json['title'] as String,
  body: json['body'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
  deviceId: json['deviceId'] as String?,
  contentHash: json['contentHash'] as String?,
  attachments:
      (json['attachments'] as List<dynamic>?)
          ?.map((e) => NoteAttachment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <NoteAttachment>[],
  blocks:
      (json['blocks'] as List<dynamic>?)
          ?.map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <NoteBlock>[],
  tags:
      (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  isPinned: json['isPinned'] as bool? ?? false,
  revision: (json['revision'] as num?)?.toInt() ?? 1,
  syncState:
      $enumDecodeNullable(_$NoteSyncStateEnumMap, json['syncState']) ??
      NoteSyncState.localOnly,
  editorMode:
      $enumDecodeNullable(_$NoteEditorModeEnumMap, json['editorMode']) ??
      NoteEditorMode.rich,
);

Map<String, dynamic> _$NoteEntryToJson(_NoteEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'vaultId': instance.vaultId,
      'title': instance.title,
      'body': instance.body,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
      'deviceId': instance.deviceId,
      'contentHash': instance.contentHash,
      'attachments': instance.attachments,
      'blocks': instance.blocks,
      'tags': instance.tags,
      'isPinned': instance.isPinned,
      'revision': instance.revision,
      'syncState': _$NoteSyncStateEnumMap[instance.syncState]!,
      'editorMode': _$NoteEditorModeEnumMap[instance.editorMode]!,
    };

const _$NoteSyncStateEnumMap = {
  NoteSyncState.localOnly: 'localOnly',
  NoteSyncState.pendingUpload: 'pendingUpload',
  NoteSyncState.synced: 'synced',
  NoteSyncState.pendingDelete: 'pendingDelete',
  NoteSyncState.conflict: 'conflict',
};

const _$NoteEditorModeEnumMap = {
  NoteEditorMode.quick: 'quick',
  NoteEditorMode.rich: 'rich',
};
