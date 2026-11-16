import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:himemo/features/sync/presentation/sync_v2_attachment_image.dart';

Uint8List _pixel() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

Widget _host({
  required Future<Uint8List> Function(bool Function()) loadBytes,
  bool Function()? isActive,
  String label = 'Photo attachment',
  bool thumbnail = true,
  VoidCallback? onTap,
  VoidCallback? onUnsupported,
  double? size,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SyncV2AttachmentImage(
        key: const ValueKey('photo-session-profile-ref'),
        loadBytes: loadBytes,
        isActive: isActive ?? () => true,
        label: label,
        thumbnail: thumbnail,
        onTap: onTap,
        onUnsupported: onUnsupported,
        size: size,
      ),
    ),
  ),
);

void main() {
  testWidgets('loads valid in-memory image once across parent rebuilds', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var loads = 0;
    Widget host() => _host(
      loadBytes: (isCurrent) async {
        loads++;
        expect(isCurrent(), isTrue);
        return _pixel();
      },
    );

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(loads, 1);
    expect(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
      findsOneWidget,
    );

    await tester.pumpWidget(host());
    await tester.pump();
    expect(loads, 1);
  });

  testWidgets('pending bytes are zeroed when widget is disposed', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final pending = Completer<Uint8List>();
    var requestIsCurrent = false;
    await tester.pumpWidget(
      _host(
        loadBytes: (isCurrent) {
          requestIsCurrent = isCurrent();
          return pending.future;
        },
      ),
    );
    await tester.pump();
    expect(requestIsCurrent, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    final bytes = _pixel();
    pending.complete(bytes);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(bytes.every((value) => value == 0), isTrue);
    expect(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
      findsNothing,
    );
  });

  testWidgets('inactive lifecycle zeroes bytes and evicts the cached image', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final bytes = _pixel();
    var active = true;
    await tester.pumpWidget(
      _host(loadBytes: (_) async => bytes, isActive: () => active),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
    );
    final key = await image.image.obtainKey(ImageConfiguration.empty);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(bytes.every((value) => value == 0), isTrue);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
    active = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
      findsNothing,
    );
    expect(find.text('Image is locked'), findsOneWidget);
  });

  testWidgets('failed load shows generic retry and never exposes exception', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var attempts = 0;
    final goodBytes = _pixel();
    await tester.pumpWidget(
      _host(
        loadBytes: (_) async {
          attempts++;
          if (attempts == 1) {
            throw StateError('private attachment path must stay hidden');
          }
          return goodBytes;
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Could not display image'), findsOneWidget);
    expect(find.textContaining('private attachment path'), findsNothing);

    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(attempts, 2);
    expect(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
      findsOneWidget,
    );
  });

  testWidgets('decode failure offers retry and native fallback action', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var attempts = 0;
    var fallbackCalls = 0;
    final invalidBytes = Uint8List.fromList([1, 2, 3]);
    await tester.pumpWidget(
      _host(
        loadBytes: (_) async {
          attempts++;
          return attempts == 1 ? invalidBytes : _pixel();
        },
        onUnsupported: () => fallbackCalls++,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byTooltip('Could not display image'), findsOneWidget);
    expect(invalidBytes.every((value) => value == 0), isTrue);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Open another way'));
    expect(fallbackCalls, 1);
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(attempts, 2);
    expect(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
      findsOneWidget,
    );
  });

  testWidgets('late inactive result is zeroed and not installed', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final pending = Completer<Uint8List>();
    var active = true;
    await tester.pumpWidget(
      _host(loadBytes: (_) => pending.future, isActive: () => active),
    );
    await tester.pump();
    active = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final bytes = _pixel();
    pending.complete(bytes);
    await tester.pump();
    expect(bytes.every((value) => value == 0), isTrue);
    expect(
      find.byKey(const ValueKey('sync-v2-attachment-image-data')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('full image view stays bounded at small width and text scale', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: Scaffold(
              body: Center(
                child: SyncV2AttachmentImage(
                  loadBytes: (_) async => _pixel(),
                  isActive: () => true,
                  label: 'A photo attachment',
                  thumbnail: false,
                  size: 280,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
