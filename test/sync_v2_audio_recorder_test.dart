import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/presentation/sync_v2_audio_recorder.dart';

void main() {
  testWidgets('returns bounded WAV bytes and disposes the recorder', (
    tester,
  ) async {
    final backend = _FakeBackend();
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final resultFuture = showDialog<SyncV2RecordedAudio>(
      context: hostContext,
      builder: (_) => SyncV2AudioRecorderDialog(createBackend: () => backend),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording'));
    await tester.pump();
    backend.controller.add(Uint8List.fromList([1, 2, 3, 4]));
    await tester.pump();
    expect(backend.started, isTrue);
    expect(find.text('Stop and attach'), findsOneWidget);
    await tester.tap(find.text('Stop and attach'));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(backend.stopped, isTrue);
    expect(find.text('The recording was empty'), findsNothing);
    expect(find.text('Could not finish recording'), findsNothing);
    final audio = await tester.runAsync(
      () => resultFuture.timeout(const Duration(seconds: 3)),
    );
    expect(audio, isNotNull);
    final recorded = audio!;
    expect(recorded.label, startsWith('audio_note_'));
    expect(recorded.label, endsWith('.wav'));
    expect(recorded.bytes.length, 48);
    expect(String.fromCharCodes(recorded.bytes.take(4)), 'RIFF');
    expect(recorded.bytes.sublist(44), [1, 2, 3, 4]);
    expect(backend.stopped, isTrue);
    expect(backend.disposed, isTrue);
  });

  testWidgets('cancels and wipes recording when app backgrounds', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              SyncV2AudioRecorderDialog(createBackend: () => backend),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording'));
    await tester.pump();
    backend.controller.add(Uint8List.fromList([9, 8, 7]));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(backend.cancelled, isTrue);
    expect(find.text('Start recording'), findsOneWidget);
    expect(find.text('Stop and attach'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('does not start recording without microphone permission', (
    tester,
  ) async {
    final backend = _FakeBackend()..permission = false;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              SyncV2AudioRecorderDialog(createBackend: () => backend),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone permission was denied'), findsOneWidget);
    expect(backend.started, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('failed stop cancels recording and leaves dialog usable', (
    tester,
  ) async {
    final backend = _FakeBackend()..failStop = true;
    await _openRecorder(tester, backend);
    await tester.tap(find.text('Start recording'));
    await tester.pump();
    backend.controller.add(Uint8List.fromList([5, 4]));
    await tester.pump();
    await tester.tap(find.text('Stop and attach'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(backend.cancelled, isTrue);
    expect(find.text('Could not finish recording'), findsOneWidget);
    expect(find.text('Start recording'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('late stream start is cancelled after backgrounding', (
    tester,
  ) async {
    final backend = _FakeBackend()
      ..delayedStart = Completer<Stream<Uint8List>>();
    await _openRecorder(tester, backend);
    await tester.tap(find.text('Start recording'));
    await tester.pump();
    await tester.pump();
    expect(backend.started, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(backend.cancelled, isTrue);
    backend.delayedStart!.complete(backend.controller.stream);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(backend.cancelCount, greaterThanOrEqualTo(2));
    expect(find.text('Start recording'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('late stream start is cancelled after start timeout', (
    tester,
  ) async {
    final backend = _FakeBackend()
      ..delayedStart = Completer<Stream<Uint8List>>();
    await _openRecorder(tester, backend);
    await tester.tap(find.text('Start recording'));
    await tester.pump();
    await tester.pump();
    expect(backend.started, isTrue);

    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(backend.cancelled, isTrue);
    expect(find.text('Could not start recording'), findsOneWidget);

    backend.delayedStart!.complete(backend.controller.stream);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(backend.cancelCount, greaterThanOrEqualTo(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}

Future<void> _openRecorder(WidgetTester tester, _FakeBackend backend) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          hostContext = context;
          return const Scaffold();
        },
      ),
    ),
  );
  unawaited(
    showDialog<void>(
      context: hostContext,
      builder: (_) => SyncV2AudioRecorderDialog(createBackend: () => backend),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeBackend implements SyncV2AudioRecorderBackend {
  final StreamController<Uint8List> controller =
      StreamController<Uint8List>.broadcast();
  bool permission = true;
  bool started = false;
  bool stopped = false;
  bool cancelled = false;
  bool disposed = false;
  bool failStop = false;
  Completer<Stream<Uint8List>>? delayedStart;
  int cancelCount = 0;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> startPcmStream() async {
    started = true;
    if (delayedStart case final pending?) return pending.future;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (failStop) throw StateError('stop failed');
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    cancelCount++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!controller.isClosed) await controller.close();
  }
}
