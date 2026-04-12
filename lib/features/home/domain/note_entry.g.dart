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

_NoteEntry _$NoteEntryFromJson(Map<String, dynamic> json) => _NoteEntry(
  id: json['id'] as String,
  vaultId: json['vaultId'] as String,
  title: json['title'] as String,
  body: json['body'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  attachments:
      (json['attachments'] as List<dynamic>?)
          ?.map((e) => NoteAttachment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <NoteAttachment>[],
  isPinned: json['isPinned'] as bool? ?? false,
);

Map<String, dynamic> _$NoteEntryToJson(_NoteEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'vaultId': instance.vaultId,
      'title': instance.title,
      'body': instance.body,
      'createdAt': instance.createdAt.toIso8601String(),
      'attachments': instance.attachments,
      'isPinned': instance.isPinned,
    };
