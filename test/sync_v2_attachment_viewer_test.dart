import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/presentation/sync_v2_attachment_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannelSyncV2AttachmentViewer.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const viewer = MethodChannelSyncV2AttachmentViewer();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'open sends the bytes and label and waits for native dismissal',
    () async {
      final nativeClose = Completer<void>();
      final nativeCalled = Completer<void>();
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        nativeCalled.complete();
        return nativeClose.future;
      });

      final bytes = Uint8List.fromList([0, 1, 2, 255]);
      var completed = false;
      final opening = viewer.open(bytes: bytes, label: '共有写真.jpg').then((_) {
        completed = true;
      });
      await nativeCalled.future;

      expect(received?.method, 'open');
      final arguments = received!.arguments as Map<Object?, Object?>;
      expect(arguments.keys, containsAll(['bytes', 'label']));
      expect(arguments, hasLength(2));
      expect(arguments['bytes'], bytes);
      expect(arguments['label'], '共有写真.jpg');
      expect(completed, isFalse);

      nativeClose.complete();
      await opening;
      expect(completed, isTrue);
    },
  );

  test(
    'rejects empty and oversized byte buffers before native invocation',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });

      await expectLater(
        viewer.open(bytes: Uint8List(0), label: 'empty'),
        throwsA(
          isA<SyncV2AttachmentViewerException>().having(
            (failure) => failure.code,
            'code',
            'invalid',
          ),
        ),
      );
      await expectLater(
        viewer.open(bytes: Uint8List(64 * 1024 * 1024 + 1), label: 'too large'),
        throwsA(
          isA<SyncV2AttachmentViewerException>().having(
            (failure) => failure.code,
            'code',
            'invalid',
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test(
    'maps arbitrary platform failures without exposing native details',
    () async {
      const privateMessage = 'private file path: /Users/alice/secret.jpg';
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'native_internal_error',
          message: privateMessage,
          details: {'path': privateMessage},
        );
      });

      await expectLater(
        viewer.open(bytes: Uint8List.fromList([1]), label: 'photo'),
        throwsA(
          isA<SyncV2AttachmentViewerException>()
              .having((failure) => failure.code, 'code', 'unavailable')
              .having(
                (failure) => failure.toString(),
                'safe string representation',
                isNot(contains(privateMessage)),
              ),
        ),
      );
    },
  );

  test('preserves native cancellation code', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'cancelled',
        message: 'native cancellation detail',
      );
    });

    await expectLater(
      viewer.open(bytes: Uint8List.fromList([1]), label: 'photo'),
      throwsA(
        isA<SyncV2AttachmentViewerException>().having(
          (failure) => failure.code,
          'code',
          'cancelled',
        ),
      ),
    );
  });

  test('maps a missing open plugin to unavailable', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException('platform is not present');
    });

    await expectLater(
      viewer.open(bytes: Uint8List.fromList([1]), label: 'photo'),
      throwsA(
        isA<SyncV2AttachmentViewerException>().having(
          (failure) => failure.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });

  test('close tolerates a missing plugin', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException();
    });

    await expectLater(viewer.close(), completes);
  });
}
