import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../../home/presentation/web_video_object_url_stub.dart'
    if (dart.library.html) '../../home/presentation/web_video_object_url_web.dart';

/// Plays an authorized V2 attachment using a short-lived browser object URL.
class SyncV2WebMediaViewer extends StatefulWidget {
  const SyncV2WebMediaViewer({
    super.key,
    required this.label,
    required this.video,
    required this.loadBytes,
    required this.isActive,
  });

  final String label;
  final bool video;
  final Future<Uint8List> Function() loadBytes;
  final bool Function() isActive;

  @override
  State<SyncV2WebMediaViewer> createState() => _SyncV2WebMediaViewerState();
}

class _SyncV2WebMediaViewerState extends State<SyncV2WebMediaViewer> {
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  String? _url;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _mime {
    final extension = widget.label.split('.').last.toLowerCase();
    return switch (extension) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'ogg' || 'opus' => 'audio/ogg',
      'flac' => 'audio/flac',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _load() async {
    Uint8List? bytes;
    try {
      bytes = await widget.loadBytes();
      if (!mounted || !widget.isActive()) return;
      final url = createWebVideoObjectUrl(bytes, _mime);
      if (url == null) throw StateError('Media unavailable');
      _url = url;
      if (widget.video) {
        final video = VideoPlayerController.networkUrl(Uri.parse(url));
        _video = video;
        await video.initialize();
      } else {
        final audio = AudioPlayer();
        _audio = audio;
        await audio.setUrl(url);
      }
      if (!mounted || !widget.isActive()) return;
      setState(() => _ready = true);
    } catch (_) {
      if (mounted && widget.isActive()) setState(() => _failed = true);
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  @override
  void dispose() {
    final video = _video;
    final audio = _audio;
    if (video != null) unawaited(video.dispose());
    if (audio != null) unawaited(audio.dispose());
    final url = _url;
    if (url != null) revokeWebVideoObjectUrl(url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ja = Localizations.localeOf(context).languageCode == 'ja';
    return Dialog(
      child: SizedBox(
        width: 640,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: ja ? '閉じる' : 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    ja
                        ? '再生できません。ダウンロードして確認してください。'
                        : 'Unable to play this file. Download it to open it.',
                  ),
                )
              else if (!_ready)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )
              else if (widget.video)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _video!,
                  builder: (context, value, _) => Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .5,
                        ),
                        child: AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(_video!),
                        ),
                      ),
                      VideoProgressIndicator(_video!, allowScrubbing: true),
                      IconButton(
                        tooltip: value.isPlaying
                            ? (ja ? '一時停止' : 'Pause')
                            : (ja ? '再生' : 'Play'),
                        onPressed: () =>
                            value.isPlaying ? _video!.pause() : _video!.play(),
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ],
                  ),
                )
              else
                StreamBuilder<PlayerState>(
                  stream: _audio!.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return IconButton(
                      tooltip: playing
                          ? (ja ? '一時停止' : 'Pause')
                          : (ja ? '再生' : 'Play'),
                      onPressed: () =>
                          playing ? _audio!.pause() : _audio!.play(),
                      icon: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                      ),
                      iconSize: 48,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
