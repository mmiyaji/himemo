import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/presentation/sync_v2_web_media_viewer.dart';

void main() {
  testWidgets('clears late media bytes after the viewer is closed', (
    tester,
  ) async {
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: SyncV2WebMediaViewer(
          label: 'audio.wav',
          video: false,
          isActive: () => true,
          loadBytes: () => pending.future,
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final bytes = Uint8List.fromList([1, 2, 3]);
    pending.complete(bytes);
    await tester.pump();
    expect(bytes, [0, 0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports an unavailable media source and clears its bytes', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await tester.pumpWidget(
      MaterialApp(
        home: SyncV2WebMediaViewer(
          label: 'clip.mp4',
          video: true,
          isActive: () => true,
          loadBytes: () async => bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to play this file. Download it to open it.'),
      findsOneWidget,
    );
    expect(bytes, [0, 0, 0]);
  });
}
