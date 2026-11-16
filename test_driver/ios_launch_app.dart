import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:himemo/main_production.dart' as production;

Future<void> main() async {
  enableFlutterDriverExtension(
    handler: (_) async {
      // These channels used to depend on AppDelegate.window at app launch.
      const network = MethodChannel('org.ruhenheim.himemo/network');
      const privacy = MethodChannel('org.ruhenheim.himemo/privacy');
      const viewer = MethodChannel(
        'org.ruhenheim.himemo/sync_v2_attachment_viewer',
      );
      final kind = await network.invokeMethod<String>('currentConnectionKind');
      await privacy.invokeMethod<void>('setProtected', {'enabled': true});
      await privacy.invokeMethod<void>('setProtected', {'enabled': false});
      final image = await rootBundle.load('assets/app-icon.png');
      final bytes = Uint8List.fromList(
        image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes),
      );
      var openCompleted = false;
      final open = viewer
          .invokeMethod<void>('open', {
            'bytes': bytes,
            'label': 'startup-smoke.png',
          })
          .then<PlatformException?>(
            (_) {
              openCompleted = true;
              return null;
            },
            onError: (Object error) {
              openCompleted = true;
              if (error is PlatformException) return error;
              throw error;
            },
          );
      await Future<void>.delayed(const Duration(seconds: 2));
      if (openCompleted) {
        final error = await open;
        throw StateError(
          'Quick Look open completed before smoke close: ${error?.code ?? "success"}',
        );
      }
      await viewer.invokeMethod<void>('close');
      final openError = await open;
      if (openError?.code != 'cancelled') {
        throw StateError('Quick Look close did not cancel the open request.');
      }
      return 'native-channels-ready:$kind:attachment-preview-ready';
    },
  );
  await production.main();
}
