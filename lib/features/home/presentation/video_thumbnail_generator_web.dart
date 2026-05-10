// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

Future<Uint8List?> generateVideoThumbnailBytes(XFile sourceFile) async {
  final bytes = await sourceFile.readAsBytes();
  if (bytes.isEmpty) {
    return null;
  }

  final mimeType = sourceFile.mimeType?.isNotEmpty == true
      ? sourceFile.mimeType!
      : 'video/mp4';
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final video = html.VideoElement()
    ..src = url
    ..muted = true
    ..preload = 'metadata';

  try {
    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 8));
    final duration = video.duration.isFinite ? video.duration : 0.0;
    final seekTime = duration <= 0.35 ? 0.0 : 0.25;
    if (seekTime > 0) {
      video.currentTime = seekTime;
      await video.onSeeked.first.timeout(const Duration(seconds: 8));
    }

    final sourceWidth = video.videoWidth;
    final sourceHeight = video.videoHeight;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return null;
    }

    const maxWidth = 360;
    final scale = math.min(1.0, maxWidth / sourceWidth);
    final width = math.max(1, (sourceWidth * scale).round());
    final height = math.max(1, (sourceHeight * scale).round());
    final canvas = html.CanvasElement(width: width, height: height);
    final context = canvas.context2D;
    context.drawImageScaled(video, 0, 0, width, height);

    final dataUrl = canvas.toDataUrl('image/jpeg', 0.72);
    final comma = dataUrl.indexOf(',');
    if (comma == -1) {
      return null;
    }
    return Uint8List.fromList(base64Decode(dataUrl.substring(comma + 1)));
  } on TimeoutException {
    return null;
  } finally {
    video.removeAttribute('src');
    video.load();
    html.Url.revokeObjectUrl(url);
  }
}
