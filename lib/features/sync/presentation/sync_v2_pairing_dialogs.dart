import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/sync_v2_pairing_code.dart';
import '../data/sync_v2_device_transfer.dart';

class SyncV2PairingQrDialog extends StatelessWidget {
  const SyncV2PairingQrDialog({
    super.key,
    required this.code,
    required this.administrator,
  }) : device = false;

  SyncV2PairingQrDialog.device({
    super.key,
    required SyncV2DeviceTransfer transfer,
  }) : code = transfer.toQr(),
       administrator = transfer.includesAdministrator,
       device = true;

  final String code;
  final bool administrator;
  final bool device;

  String _text(BuildContext context, String japanese, String english) =>
      Localizations.localeOf(context).languageCode == 'ja' ? japanese : english;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final contentWidth = math.min(360.0, math.max(80.0, screen.width - 128));
    final qrSize = math.min(
      320.0,
      math.max(40.0, math.min(contentWidth - 24, screen.height - 320)),
    );
    final qrData = device
        ? code
        : SyncV2PairingCode.encodeQr(code, administrator: administrator);

    return AlertDialog(
      title: Text(
        _text(
          context,
          device
              ? '端末追加 QR'
              : administrator
              ? '管理者用の参加 QR'
              : '同期用の参加 QR',
          device
              ? 'Add device QR'
              : administrator
              ? 'Admin pairing QR'
              : 'Sync pairing QR',
        ),
      ),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                device && !administrator
                    ? _text(
                        context,
                        'この QR は同期用の鍵を含みます。管理者権限は含みませんが、プロファイルのパスコードを知る人はそのプロファイルを開けます。有効期限はなく、再利用できます。',
                        'This QR contains sync keys without administrator access. Anyone who knows a profile passcode can still open that profile. It does not expire and can be reused.',
                      )
                    : administrator
                    ? _text(
                        context,
                        'この QR を知る人（撮影・コピーを含む）は、同じ iCloud アカウントの v2 同期で全私用プロファイルにアクセスできます。有効期限はなく、再利用できます。信頼できる相手にだけ共有してください。',
                        'Anyone with this QR, including a photo or copy, can access every private profile in v2 sync for the same iCloud account. It does not expire and can be reused. Share it only with trusted people.',
                      )
                    : _text(
                        context,
                        'この QR を知る人（撮影・コピーを含む）は、同じ iCloud アカウントの v2 同期に参加し、通常メモにアクセスできます。私用プロファイルにはアクセスできません。有効期限はなく、再利用できます。',
                        'Anyone with this QR, including a photo or copy, can join v2 sync for the same iCloud account and access normal notes. It does not grant private profile access. It does not expire and can be reused.',
                      ),
              ),
              const SizedBox(height: 16),
              Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      key: const ValueKey('sync-v2-pairing-qr-image'),
                      data: qrData,
                      size: qrSize,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                      errorStateBuilder: (context, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _text(
                              context,
                              'QR を表示できません。閉じて復元コードの手入力を利用してください。',
                              'Could not display this QR. Close it and enter the recovery code manually.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_text(context, '閉じる', 'Close')),
        ),
      ],
    );
  }
}

class SyncV2PairingScannerDialog extends StatefulWidget {
  const SyncV2PairingScannerDialog({super.key, required this.administrator})
    : device = false;
  const SyncV2PairingScannerDialog.device({super.key})
    : administrator = false,
      device = true;

  final bool administrator;
  final bool device;

  @override
  State<SyncV2PairingScannerDialog> createState() =>
      _SyncV2PairingScannerDialogState();
}

class _SyncV2PairingScannerDialogState extends State<SyncV2PairingScannerDialog>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  Future<void> _cameraQueue = Future<void>.value();
  bool _foreground = true;
  bool _completed = false;
  bool _cameraStartFailed = false;
  String? _scanError;

  String _text(String japanese, String english) =>
      Localizations.localeOf(context).languageCode == 'ja' ? japanese : english;

  String get _cameraFailure => _text(
    'カメラを利用できません。カメラの許可を確認して再試行してください。',
    'Camera unavailable. Check camera permission and try again.',
  );

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => _foreground = true);
      _syncCamera();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (mounted) setState(() => _foreground = false);
      _syncCamera();
    }
  }

  void _syncCamera() {
    _cameraQueue = _cameraQueue
        .then((_) async {
          if (!mounted) return;
          if (!_foreground || _completed) {
            if (_controller.value.isRunning) await _controller.stop();
            return;
          }
          if (_cameraStartFailed) return;
          if (_controller.value.isRunning) return;
          try {
            await _controller.start();
            if (_controller.value.error != null) {
              _cameraStartFailed = true;
            }
          } catch (_) {
            _cameraStartFailed = true;
            if (mounted && _foreground && !_completed) {
              setState(() => _scanError = _cameraFailure);
            }
          }
        })
        .catchError((Object _) {});
  }

  void _retryCamera() {
    if (!mounted || !_foreground || _completed) return;
    setState(() {
      _scanError = null;
      _cameraStartFailed = false;
    });
    _syncCamera();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (!mounted || !_foreground || _completed) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        final code = widget.device
            ? SyncV2DeviceTransfer.fromQr(raw).toQr()
            : SyncV2PairingCode.decodeQr(
                raw,
                administrator: widget.administrator,
              );
        _completed = true;
        _syncCamera();
        Navigator.of(context).pop(code);
        return;
      } on FormatException {
        if (mounted) {
          setState(
            () => _scanError = _text(
              'この QR コードは選択したアクセス権では使用できません。',
              'This QR code does not match the selected access level.',
            ),
          );
        }
      } catch (_) {
        if (mounted) setState(() => _scanError = _cameraFailure);
      }
    }
  }

  Widget _cameraFailureView(BuildContext context, MobileScannerException _) =>
      ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  _cameraFailure,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _retryCamera,
                  child: Text(_text('再試行', 'Retry')),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _cameraView(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Visibility(
        visible: _foreground && !_completed,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: MobileScanner(
          controller: _controller,
          onDetect: _handleDetect,
          errorBuilder: _cameraFailureView,
          placeholderBuilder: (_) => const ColoredBox(color: Colors.black),
        ),
      ),
      if (!_foreground)
        ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              _text('カメラを一時停止しました', 'Camera paused'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final previewSize = math.min(
      320.0,
      math.max(80.0, math.min(screen.width - 128, screen.height - 300)),
    );
    final title = _text(
      widget.device
          ? '端末追加 QR を読み取り'
          : widget.administrator
          ? '管理者用 QR を読み取り'
          : '同期用 QR を読み取り',
      widget.device
          ? 'Scan add device QR'
          : widget.administrator
          ? 'Scan admin pairing QR'
          : 'Scan sync pairing QR',
    );

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: math.min(360.0, math.max(80.0, screen.width - 128)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _text(
                  '表示中の QR をこの端末で読み取ってください。',
                  'Point this camera at the pairing QR shown on the other device.',
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: previewSize,
                  child: _cameraView(context),
                ),
              ),
              if (_scanError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _scanError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                Align(
                  alignment: AlignmentDirectional.center,
                  child: TextButton(
                    onPressed: _retryCamera,
                    child: Text(_text('再試行', 'Retry')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_text('キャンセル', 'Cancel')),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    try {
      await _cameraQueue;
    } catch (_) {}
    try {
      if (_controller.value.isRunning) await _controller.stop();
    } catch (_) {}
    try {
      await _controller.dispose();
    } catch (_) {}
  }
}
