import 'package:freezed_annotation/freezed_annotation.dart';

part 'note_entry.freezed.dart';
part 'note_entry.g.dart';

enum AttachmentType { photo, video, audio }

@freezed
abstract class NoteAttachment with _$NoteAttachment {
  const factory NoteAttachment({
    required AttachmentType type,
    required String label,
    String? filePath,
    String? previewBytesBase64,
  }) = _NoteAttachment;

  factory NoteAttachment.fromJson(Map<String, dynamic> json) =>
      _$NoteAttachmentFromJson(json);
}

@freezed
abstract class NoteEntry with _$NoteEntry {
  const factory NoteEntry({
    required String id,
    required String vaultId,
    required String title,
    required String body,
    required DateTime createdAt,
    @Default(<NoteAttachment>[]) List<NoteAttachment> attachments,
    @Default(false) bool isPinned,
  }) = _NoteEntry;

  factory NoteEntry.fromJson(Map<String, dynamic> json) =>
      _$NoteEntryFromJson(json);
}
