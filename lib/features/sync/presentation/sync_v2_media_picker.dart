import 'package:flutter/foundation.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:image_picker/image_picker.dart';

/// A transient selection returned to the caller; this adapter never stores it.
class SyncV2PickedMedia {
  const SyncV2PickedMedia({required this.file, required this.type});

  final XFile file;
  final AttachmentType type;
}

/// Selects one photo or video from the gallery or, where supported, a camera.
///
/// A null result means the picker was cancelled. The caller owns the returned
/// XFile for this session and decides whether to read or persist its contents.
class SyncV2MediaPicker {
  SyncV2MediaPicker({
    ImagePicker? picker,
    @visibleForTesting TargetPlatform? platform,
    @visibleForTesting bool? isWeb,
  }) : _picker = picker ?? ImagePicker(),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb;

  final ImagePicker _picker;
  final TargetPlatform _platform;
  final bool _isWeb;

  Future<SyncV2PickedMedia?> pickPhoto({
    ImageSource source = ImageSource.gallery,
  }) async {
    _ensureSupported(source);
    final file = await _picker.pickImage(source: source);
    return file == null
        ? null
        : SyncV2PickedMedia(file: file, type: AttachmentType.photo);
  }

  Future<SyncV2PickedMedia?> pickVideo({
    ImageSource source = ImageSource.gallery,
  }) async {
    _ensureSupported(source);
    final file = await _picker.pickVideo(source: source);
    return file == null
        ? null
        : SyncV2PickedMedia(file: file, type: AttachmentType.video);
  }

  void _ensureSupported(ImageSource source) {
    if (!_isSupportedPlatform(_platform, _isWeb)) {
      throw UnsupportedError(
        'Media selection is not supported on this platform.',
      );
    }
    // image_picker desktop implementations need an app-provided cameraDelegate.
    if (source == ImageSource.camera &&
        !_isWeb &&
        _platform != TargetPlatform.android &&
        _platform != TargetPlatform.iOS) {
      throw UnsupportedError(
        'Camera selection is not configured on this platform.',
      );
    }
  }

  static bool _isSupportedPlatform(TargetPlatform platform, bool isWeb) =>
      isWeb ||
      platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
}
