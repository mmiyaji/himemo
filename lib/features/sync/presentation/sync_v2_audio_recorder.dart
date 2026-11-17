import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

const int syncV2AudioRecordingMaxBytes = 64 * 1024 * 1024;
const int _wavHeaderBytes = 44;
const int _sampleRate = 44100;

/// Uncommitted audio returned to the caller for secure V2 attachment staging.
class SyncV2RecordedAudio {
  const SyncV2RecordedAudio({required this.label, required this.bytes});

  final String label;
  final Uint8List bytes;
}

/// Small seam for lifecycle and size-limit tests without microphone hardware.
abstract interface class SyncV2AudioRecorderBackend {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startPcmStream();
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class _RecordAudioBackend implements SyncV2AudioRecorderBackend {
  _RecordAudioBackend() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startPcmStream() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
      audioInterruption: AudioInterruptionMode.none,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// In-memory audio recorder for the isolated V2 workspace.
///
/// Recording PCM remains in memory only. Cancelling, backgrounding, an error,
/// exceeding the 64 MiB attachment bound, or disposing wipes the buffer before
/// returning. The parent owns the successful result and must stage it through
/// the V2 encrypted attachment flow.
class SyncV2AudioRecorderDialog extends StatefulWidget {
  const SyncV2AudioRecorderDialog({
    super.key,
    this.createBackend = _RecordAudioBackend.new,
  });

  final SyncV2AudioRecorderBackend Function() createBackend;

  @override
  State<SyncV2AudioRecorderDialog> createState() =>
      _SyncV2AudioRecorderDialogState();
}

class _SyncV2AudioRecorderDialogState extends State<SyncV2AudioRecorderDialog>
    with WidgetsBindingObserver {
  late final SyncV2AudioRecorderBackend _backend = widget.createBackend();
  final List<int> _pcm = <int>[];
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _stopping = false;
  bool _starting = false;
  bool _discarding = false;
  bool _busy = false;
  bool _disposed = false;
  int _operation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts and transient system overlays can report `inactive`.
    // Only discard once the app is actually backgrounded or detached.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_discardRecording());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    _wipePcm();
    unawaited(_disposeBackend());
    super.dispose();
  }

  bool _isCurrent(int operation) =>
      mounted && !_disposed && operation == _operation;

  void _wipePcm() {
    _pcm.fillRange(0, _pcm.length, 0);
    _pcm.clear();
  }

  Future<void> _disposeBackend() async {
    if (_recording || _starting) {
      try {
        await _backend.cancel();
      } catch (_) {
        // Always release the recorder even if cancellation fails.
      }
    }
    try {
      await _backend.dispose();
    } catch (_) {
      // The route is already gone; native cleanup is best effort.
    }
  }

  Future<void> _start() async {
    final operation = ++_operation;
    _starting = true;
    setState(() {
      _busy = true;
      _error = null;
      _elapsed = Duration.zero;
    });
    try {
      final permitted = await _backend.hasPermission().timeout(
        const Duration(seconds: 30),
      );
      if (!_isCurrent(operation)) return;
      if (!permitted) {
        setState(
          () => _error = _text(
            'マイクの使用が許可されていません',
            'Microphone permission was denied',
          ),
        );
        return;
      }
      _wipePcm();
      final pendingStream = _backend.startPcmStream();
      late final Stream<Uint8List> stream;
      try {
        stream = await pendingStream.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        unawaited(
          pendingStream.then<void>(
            (_) => _cancelBackend(),
            onError: (Object error, StackTrace stackTrace) {},
          ),
        );
        rethrow;
      }
      if (!_isCurrent(operation)) {
        await _backend.cancel();
        return;
      }
      _subscription = stream.listen(
        _appendPcm,
        onError: (Object error, StackTrace stack) {
          unawaited(_failRecording());
        },
        onDone: () {
          if (_recording && !_stopping && !_disposed) {
            unawaited(_failRecording());
          }
        },
        cancelOnError: true,
      );
      _recording = true;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _recording) {
          setState(() => _elapsed += const Duration(seconds: 1));
        }
      });
      setState(() {});
    } catch (_) {
      if (_isCurrent(operation)) {
        await _backend.cancel();
        _wipePcm();
        setState(
          () => _error = _text('録音を開始できませんでした', 'Could not start recording'),
        );
      }
    } finally {
      _starting = false;
      if (_isCurrent(operation)) setState(() => _busy = false);
    }
  }

  void _appendPcm(Uint8List chunk) {
    if ((!_recording && !_stopping) || _disposed) return;
    final maxPcmBytes = syncV2AudioRecordingMaxBytes - _wavHeaderBytes;
    if (chunk.length > maxPcmBytes - _pcm.length) {
      unawaited(
        _discardRecording(
          error: _text(
            '録音サイズが64 MiBを超えました。録音を破棄しました。',
            'Recording exceeded 64 MiB and was discarded.',
          ),
        ),
      );
      return;
    }
    _pcm.addAll(chunk);
  }

  Future<void> _stopAndReturn() async {
    if (!_recording || _busy) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    _timer?.cancel();
    _stopping = true;
    try {
      await _backend.stop();
      unawaited(_subscription?.cancel());
      _subscription = null;
      if (!_isCurrent(operation)) return;
      _recording = false;
      if (_pcm.isEmpty) {
        _wipePcm();
        setState(
          () => _error = _text('録音データがありません', 'The recording was empty'),
        );
        return;
      }
      final resultBytes = _wavFromPcm(_pcm);
      if (resultBytes.length > syncV2AudioRecordingMaxBytes) {
        resultBytes.fillRange(0, resultBytes.length, 0);
        _wipePcm();
        setState(
          () =>
              _error = _text('録音サイズが64 MiBを超えました', 'Recording exceeded 64 MiB'),
        );
        return;
      }
      _wipePcm();
      final label =
          'audio_note_${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.wav';
      if (mounted) {
        Navigator.of(context)
            .pop(SyncV2RecordedAudio(label: label, bytes: resultBytes));
      }
    } catch (_) {
      _recording = false;
      _timer?.cancel();
      unawaited(_subscription?.cancel());
      _subscription = null;
      await _cancelBackend();
      _wipePcm();
      if (_isCurrent(operation)) {
        setState(
          () => _error = _text('録音を保存できませんでした', 'Could not finish recording'),
        );
      }
    } finally {
      _stopping = false;
      if (_isCurrent(operation)) setState(() => _busy = false);
    }
  }

  Future<void> _discardRecording({String? error}) async {
    if (_discarding) return;
    _discarding = true;
    _operation++;
    _timer?.cancel();
    final subscription = _subscription;
    _subscription = null;
    final shouldCancel = _recording || _starting || _stopping;
    _recording = false;
    _starting = false;
    _stopping = false;
    _wipePcm();
    unawaited(subscription?.cancel());
    if (shouldCancel) {
      await _cancelBackend();
    }
    if (mounted && !_disposed) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
    _discarding = false;
  }

  Future<void> _cancelBackend() async {
    try {
      await _backend.cancel();
    } catch (_) {
      // The in-memory PCM has already been erased.
    }
  }

  Future<void> _failRecording() => _discardRecording(
    error: _text(
      '録音に失敗しました。もう一度お試しください。',
      'Recording failed. Please try again.',
    ),
  );

  Future<void> _cancelAndClose() async {
    await _discardRecording();
    if (mounted) Navigator.of(context).pop();
  }

  String _text(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;

  @override
  Widget build(BuildContext context) {
    final recording = _recording;
    return AlertDialog(
      title: Text(_text('音声メモを録音', 'Record audio memo')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              recording
                  ? Icons.fiber_manual_record_rounded
                  : Icons.mic_none_rounded,
              size: 52,
              color: recording
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _formatDuration(_elapsed),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _cancelAndClose,
          child: Text(_text('キャンセル', 'Cancel')),
        ),
        if (recording)
          FilledButton.icon(
            onPressed: _busy ? null : _stopAndReturn,
            icon: const Icon(Icons.stop_rounded),
            label: Text(_text('停止して添付', 'Stop and attach')),
          )
        else
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.mic_rounded),
            label: Text(_text('録音開始', 'Start recording')),
          ),
      ],
    );
  }
}

Uint8List _wavFromPcm(List<int> pcm) {
  final bytes = Uint8List(_wavHeaderBytes + pcm.length);
  final data = ByteData.view(bytes.buffer);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, _sampleRate, Endian.little);
  data.setUint32(28, _sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcm.length, Endian.little);
  bytes.setRange(_wavHeaderBytes, bytes.length, pcm);
  return bytes;
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
