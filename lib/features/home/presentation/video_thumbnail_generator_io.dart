import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

Future<Uint8List?> generateVideoThumbnailBytes(XFile sourceFile) async {
  if (sourceFile.path.isEmpty) {
    return null;
  }
  return VideoThumbnail.thumbnailData(
    video: sourceFile.path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 360,
    quality: 72,
    timeMs: 250,
  );
}
