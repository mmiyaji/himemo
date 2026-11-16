import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncV2AttachmentViewerException implements Exception {
  const SyncV2AttachmentViewerException(this.code);
  final String code;
}

abstract interface class SyncV2AttachmentViewer {
  Future<void> open({required Uint8List bytes, required String label});
  Future<void> close();
}

final syncV2AttachmentViewerProvider = Provider<SyncV2AttachmentViewer>(
  (ref) => const MethodChannelSyncV2AttachmentViewer(),
);

/// Native Quick Look owns protected temporary files until dismissal.
/// Input bytes remain owned by the caller and must be cleared afterwards.
class MethodChannelSyncV2AttachmentViewer implements SyncV2AttachmentViewer {
  const MethodChannelSyncV2AttachmentViewer();
  static const channel = MethodChannel(
    'org.ruhenheim.himemo/sync_v2_attachment_viewer',
  );

  @override
  Future<void> open({required Uint8List bytes, required String label}) async {
    if (bytes.isEmpty ||
        bytes.length > 64 * 1024 * 1024 ||
        label.length > 4096) {
      throw const SyncV2AttachmentViewerException('invalid');
    }
    try {
      await channel.invokeMethod<void>('open', {
        'bytes': bytes,
        'label': label,
      });
    } on MissingPluginException {
      throw const SyncV2AttachmentViewerException('unavailable');
    } on PlatformException catch (failure) {
      throw SyncV2AttachmentViewerException(
        const {'cancelled', 'busy', 'unsupported'}.contains(failure.code)
            ? failure.code
            : 'unavailable',
      );
    }
  }

  @override
  Future<void> close() async {
    try {
      await channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // No native preview can be alive when the channel is unavailable.
    } on PlatformException {
      // Native lifecycle handling also closes previews and retries cleanup.
    }
  }
}
