import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

Future<int?> probeAudioDurationMs(String path) async {
  if (path.isEmpty) {
    return null;
  }
  final player = AudioPlayer();
  try {
    final duration = await player
        .setFilePath(path)
        .timeout(const Duration(seconds: 5));
    return duration != null && duration > Duration.zero
        ? duration.inMilliseconds
        : null;
  } catch (_) {
    return null;
  } finally {
    await player.dispose();
  }
}

Future<int?> probeVideoDurationMs(String path) async {
  if (path.isEmpty) {
    return null;
  }
  final controller = VideoPlayerController.file(File(path));
  try {
    await controller.initialize().timeout(const Duration(seconds: 5));
    final duration = controller.value.duration;
    return duration > Duration.zero ? duration.inMilliseconds : null;
  } catch (_) {
    return null;
  } finally {
    await controller.dispose();
  }
}
