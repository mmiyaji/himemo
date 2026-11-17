import 'package:himemo/features/home/domain/note_entry.dart';

/// Infers an attachment category from a picked file's name.
///
/// Unknown or missing extensions remain generic files. This is only a display
/// and metadata hint; it does not inspect or validate file contents.
AttachmentType syncV2AttachmentTypeForFilename(String filename) {
  final basename = filename.replaceAll('\\', '/').split('/').last;
  final dot = basename.lastIndexOf('.');
  if (dot <= 0 || dot == basename.length - 1) return AttachmentType.file;

  return switch (basename.substring(dot + 1).toLowerCase()) {
    'jpg' ||
    'jpeg' ||
    'png' ||
    'gif' ||
    'webp' ||
    'heic' ||
    'heif' => AttachmentType.photo,
    'mp4' || 'm4v' || 'mov' || 'webm' || 'mkv' => AttachmentType.video,
    'mp3' ||
    'm4a' ||
    'aac' ||
    'wav' ||
    'flac' ||
    'ogg' ||
    'opus' => AttachmentType.audio,
    _ => AttachmentType.file,
  };
}
