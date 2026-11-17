import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/presentation/sync_v2_media_picker.dart';
import 'package:image_picker/image_picker.dart';

class _FakeImagePicker extends ImagePicker {
  XFile? image;
  XFile? video;
  ImageSource? imageSource;
  ImageSource? videoSource;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    imageSource = source;
    return image;
  }

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    videoSource = source;
    return video;
  }
}

void main() {
  group('SyncV2MediaPicker', () {
    test('returns selected photos and videos with their categories', () async {
      final picker = _FakeImagePicker()
        ..image = XFile('/transient/photo.jpg')
        ..video = XFile('/transient/clip.mp4');
      final adapter = SyncV2MediaPicker(
        picker: picker,
        platform: TargetPlatform.android,
        isWeb: false,
      );

      final photo = await adapter.pickPhoto();
      final video = await adapter.pickVideo(source: ImageSource.camera);

      expect(photo?.file.path, '/transient/photo.jpg');
      expect(photo?.type, AttachmentType.photo);
      expect(picker.imageSource, ImageSource.gallery);
      expect(video?.file.path, '/transient/clip.mp4');
      expect(video?.type, AttachmentType.video);
      expect(picker.videoSource, ImageSource.camera);
    });

    test('returns null when selection is cancelled', () async {
      final adapter = SyncV2MediaPicker(
        picker: _FakeImagePicker(),
        platform: TargetPlatform.iOS,
        isWeb: false,
      );

      expect(await adapter.pickPhoto(), isNull);
      expect(await adapter.pickVideo(), isNull);
    });

    test(
      'rejects unconfigured desktop camera use before opening the picker',
      () async {
        final picker = _FakeImagePicker();
        final adapter = SyncV2MediaPicker(
          picker: picker,
          platform: TargetPlatform.windows,
          isWeb: false,
        );

        await expectLater(
          adapter.pickPhoto(source: ImageSource.camera),
          throwsA(isA<UnsupportedError>()),
        );
        expect(picker.imageSource, isNull);
      },
    );
  });
}
