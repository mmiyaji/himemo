import 'package:video_player/video_player.dart';

VideoPlayerController createLocalVideoController(String filePath) {
  return VideoPlayerController.networkUrl(Uri.file(filePath));
}
