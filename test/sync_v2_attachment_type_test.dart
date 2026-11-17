import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/presentation/sync_v2_attachment_type.dart';

void main() {
  group('syncV2AttachmentTypeForFilename', () {
    test('recognizes common photo extensions case-insensitively', () {
      expect(
        syncV2AttachmentTypeForFilename('photo.JPG'),
        AttachmentType.photo,
      );
      expect(
        syncV2AttachmentTypeForFilename('image.heic'),
        AttachmentType.photo,
      );
    });

    test('recognizes common video and audio extensions', () {
      expect(syncV2AttachmentTypeForFilename('clip.MOV'), AttachmentType.video);
      expect(
        syncV2AttachmentTypeForFilename('recording.m4a'),
        AttachmentType.audio,
      );
    });

    test(
      'uses only the final filename extension and defaults conservatively',
      () {
        expect(
          syncV2AttachmentTypeForFilename(r'C:\\notes\\photo.png'),
          AttachmentType.photo,
        );
        expect(
          syncV2AttachmentTypeForFilename('archive.tar.gz'),
          AttachmentType.file,
        );
        expect(syncV2AttachmentTypeForFilename('.hidden'), AttachmentType.file);
        expect(
          syncV2AttachmentTypeForFilename('no-extension'),
          AttachmentType.file,
        );
        expect(
          syncV2AttachmentTypeForFilename('unknown.xyz'),
          AttachmentType.file,
        );
      },
    );
  });
}
