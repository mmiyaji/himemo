import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  test(
    'production iOS startup renders onboarding and registers native channels',
    () async {
      final driver = await FlutterDriver.connect();
      try {
        await driver.waitFor(
          find.byValueKey('onboarding-next-button'),
          timeout: const Duration(seconds: 90),
        );
        expect(
          await driver.requestData('check-native-channels'),
          startsWith('native-channels-ready:'),
        );
        final directory = Directory('build/ios-launch-smoke')
          ..createSync(recursive: true);
        await File('${directory.path}/onboarding.png')
            .writeAsBytes(await driver.screenshot());
      } finally {
        await driver.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
