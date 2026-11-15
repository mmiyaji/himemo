import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:himemo/features/sync/data/sync_v2_pairing_code.dart';
import 'package:himemo/features/sync/presentation/sync_v2_pairing_dialogs.dart';

class _FakeScannerPlatform extends MobileScannerPlatform {
  final _barcodes = StreamController<BarcodeCapture?>.broadcast(sync: true);
  final _torch = StreamController<TorchState>.broadcast(sync: true);
  final _zoom = StreamController<double>.broadcast(sync: true);
  Completer<MobileScannerViewAttributes>? delayedStart;
  int failStarts = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool _streamsClosed = false;

  static const view = MobileScannerViewAttributes(
    cameraDirection: CameraFacing.back,
    currentTorchMode: TorchState.off,
    size: Size(640, 480),
    initialDeviceOrientation: DeviceOrientation.portraitUp,
  );

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;
  @override
  Stream<TorchState> get torchStateStream => _torch.stream;
  @override
  Stream<double> get zoomScaleStateStream => _zoom.stream;

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) {
    startCalls++;
    final delayed = delayedStart;
    if (delayed != null) return delayed.future;
    if (failStarts > 0) {
      failStarts--;
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
        errorDetails: MobileScannerErrorDetails(
          message: 'native camera error should stay hidden',
        ),
      );
    }
    return Future.value(view);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await closeStreams();
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<Set<CameraLensType>> getSupportedLenses({
    CameraFacing? facing,
  }) async => {CameraLensType.normal};

  void emit(String raw, {BarcodeFormat format = BarcodeFormat.qrCode}) {
    _barcodes.add(
      BarcodeCapture(
        barcodes: [Barcode(rawValue: raw, format: format)],
        size: const Size(640, 480),
      ),
    );
  }

  Future<void> closeStreams() async {
    if (_streamsClosed) return;
    _streamsClosed = true;
    await _barcodes.close();
    await _torch.close();
    await _zoom.close();
  }
}

String _syncCode() => base64Url.encode(
  utf8.encode(
    jsonEncode({
      'format': 'himemo.sync.v2.recovery',
      'version': 1,
      'account': 'test-account',
      'generation': 'test-generation',
      'key': base64Url.encode(List<int>.filled(32, 1)),
    }),
  ),
);

String _adminCode() =>
    'himemo-admin-v2:${base64Url.encode(utf8.encode(jsonEncode({'generation': 'test-generation', 'key': base64Encode(List<int>.filled(32, 2))})))}';

Future<void> _showQr(
  WidgetTester tester, {
  required String code,
  required bool administrator,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SyncV2PairingQrDialog(
                code: code,
                administrator: administrator,
              ),
            ),
            child: const Text('Show QR'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show QR'));
  await tester.pumpAndSettle();
}

Future<void> _openScanner(
  WidgetTester tester, {
  required _FakeScannerPlatform platform,
  required ValueChanged<String?> onResult,
  bool administrator = false,
}) async {
  final previous = MobileScannerPlatform.instance;
  MobileScannerPlatform.instance = platform;
  addTearDown(() async {
    MobileScannerPlatform.instance = previous;
    await platform.closeStreams();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              unawaited(
                showDialog<String>(
                  context: context,
                  builder: (_) =>
                      SyncV2PairingScannerDialog(administrator: administrator),
                ).then(onResult),
              );
            },
            child: const Text('Open scanner'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open scanner'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('SYNC QR explains normal-only access and uses safe QR styling', (
    tester,
  ) async {
    final code = _syncCode();
    await _showQr(tester, code: code, administrator: false);

    expect(find.text('Sync pairing QR'), findsOneWidget);
    expect(find.textContaining('normal notes'), findsOneWidget);
    expect(find.textContaining('private profile access'), findsOneWidget);
    expect(find.textContaining('photo or copy'), findsOneWidget);
    expect(find.textContaining('does not expire'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text(code), findsNothing);

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.size, lessThanOrEqualTo(320));
    expect(qr.backgroundColor, Colors.white);
    expect(qr.eyeStyle.color, Colors.black);
    expect(qr.dataModuleStyle.color, Colors.black);
  });

  testWidgets('ADMIN QR explains private access and no-expiry reuse', (
    tester,
  ) async {
    final code = _adminCode();
    await _showQr(tester, code: code, administrator: true);

    expect(find.text('Admin pairing QR'), findsOneWidget);
    expect(find.textContaining('every private profile'), findsOneWidget);
    expect(find.textContaining('photo or copy'), findsOneWidget);
    expect(find.textContaining('does not expire'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text(code), findsNothing);
  });

  testWidgets('pairing QR fits a small screen and closes cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _showQr(tester, code: _syncCode(), administrator: false);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);

    final box = tester.getSize(
      find.byKey(const ValueKey('sync-v2-pairing-qr-image')),
    );
    expect(box.width, lessThanOrEqualTo(320));
    expect(box.height, box.width);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Sync pairing QR'), findsNothing);
    expect(find.text('Show QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanner rejects the wrong role and returns a valid code once', (
    tester,
  ) async {
    final platform = _FakeScannerPlatform();
    final syncCode = _syncCode();
    final wrongRoleQr = SyncV2PairingCode.encodeQr(
      _adminCode(),
      administrator: true,
    );
    String? result;
    var resultCount = 0;
    await _openScanner(
      tester,
      platform: platform,
      onResult: (value) {
        result = value;
        resultCount++;
      },
    );
    expect(platform.startCalls, 1);

    platform.emit(wrongRoleQr);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not match the selected access level'),
      findsOneWidget,
    );
    expect(find.text(wrongRoleQr), findsNothing);
    expect(result, isNull);
    expect(find.text('Scan sync pairing QR'), findsOneWidget);

    final syncQr = SyncV2PairingCode.encodeQr(syncCode, administrator: false);
    platform.emit(syncQr);
    platform.emit(syncQr);
    await tester.pumpAndSettle();
    expect(result, syncCode);
    expect(resultCount, 1);
    expect(platform.stopCalls, 1);
    expect(platform.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive scanner ignores late capture and resumes scanning', (
    tester,
  ) async {
    final platform = _FakeScannerPlatform();
    final syncCode = _syncCode();
    final syncQr = SyncV2PairingCode.encodeQr(syncCode, administrator: false);
    String? result;
    await _openScanner(
      tester,
      platform: platform,
      onResult: (value) => result = value,
    );
    expect(platform.startCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(platform.stopCalls, 1);
    expect(find.text('Camera paused'), findsOneWidget);
    platform.emit(syncQr);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Scan sync pairing QR'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.startCalls, 2);
    platform.emit(syncQr);
    await tester.pumpAndSettle();
    expect(result, syncCode);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(platform.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission failure uses sanitized text and can retry', (
    tester,
  ) async {
    final platform = _FakeScannerPlatform()..failStarts = 1;
    String? result;
    await _openScanner(
      tester,
      platform: platform,
      onResult: (value) => result = value,
    );
    expect(find.textContaining('Camera unavailable'), findsOneWidget);
    expect(find.text('native camera error should stay hidden'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.startCalls, 1);
    expect(find.textContaining('Camera unavailable'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(platform.startCalls, 2);
    expect(find.text('Camera unavailable'), findsNothing);
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(platform.disposeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing while permission start is pending disposes after it settles',
    (tester) async {
      final platform = _FakeScannerPlatform()
        ..delayedStart = Completer<MobileScannerViewAttributes>();
      final delayedStart = platform.delayedStart!;
      String? result;
      await _openScanner(
        tester,
        platform: platform,
        onResult: (value) => result = value,
      );
      expect(platform.startCalls, 1);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(platform.stopCalls, 0);
      expect(platform.disposeCalls, 0);

      delayedStart.complete(_FakeScannerPlatform.view);
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(platform.stopCalls, 1);
      expect(platform.disposeCalls, 1);
      expect(find.text('Scan sync pairing QR'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
