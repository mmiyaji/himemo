@Tags(['legacy'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v2 prevents legacy provider changes and storage reset', () async {
    SharedPreferences.setMockInitialValues({
      'settings.sync_v2.enabled': true,
      'settings.sync_provider': 'off',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = container.read(syncProviderControllerProvider.notifier);
    await provider.setProvider(SyncProvider.googleDrive);
    expect(container.read(syncProviderControllerProvider), SyncProvider.off);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'settings.sync_provider',
      ),
      'off',
    );
    await expectLater(
      container.read(notesControllerProvider.notifier).resetLocalStorage(),
      throwsStateError,
    );
  });

  test('legacy provider can still be set when v2 is disabled', () async {
    SharedPreferences.setMockInitialValues({'settings.sync_v2.enabled': false});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(syncProviderControllerProvider.notifier)
        .setProvider(SyncProvider.off);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'settings.sync_provider',
      ),
      'off',
    );
  });
}
