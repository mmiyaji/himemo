import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  group('mobile simulator smoke', () {
    late FlutterDriver driver;

    setUpAll(() async {
      driver = await FlutterDriver.connect();
    });

    tearDownAll(() async {
      await driver.close();
    });

    test(
      'can create a note on the emulator',
      () async {
        await driver.waitFor(
          find.byValueKey('driver-smoke-ready'),
          timeout: const Duration(seconds: 60),
        );
        final addButton = find.byValueKey('add-note-button');
        final noteInput = find.byValueKey('note-content-input');
        final saveButton = find.byValueKey('save-note-button');
        await driver.waitFor(addButton, timeout: const Duration(seconds: 60));
        await driver.tap(addButton);
        await driver.waitFor(noteInput, timeout: const Duration(seconds: 30));
        await driver.tap(noteInput);
        await driver.enterText(
          'Simulator quick note\nCreated from Android smoke test.',
        );
        await driver.waitFor(saveButton, timeout: const Duration(seconds: 15));
        await driver.tap(saveButton);
        await driver.waitFor(
          find.byValueKey('driver-smoke-latest-title'),
          timeout: const Duration(seconds: 30),
        );
        expect(
          await driver.getText(find.byValueKey('driver-smoke-latest-title')),
          'Simulator quick note',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
