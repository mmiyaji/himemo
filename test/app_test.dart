import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('providers expose separate profiles', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(identitiesProvider).length, 3);
    expect(container.read(visibleVaultsProvider).length, 1);

    container.read(activeIdentityProvider.notifier).switchTo('private');
    expect(container.read(visibleVaultsProvider).length, 1);

    container.read(privateVaultSessionControllerProvider.notifier).unlock();

    expect(container.read(visibleVaultsProvider).length, 2);
    expect(container.read(visibleNotesProvider).length, 4);
  });

  test('app lock policy providers expose secure defaults', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(appLockRelockDelayControllerProvider),
      AppLockRelockDelay.immediate,
    );
    expect(container.read(privateVaultLockOnAppLockControllerProvider), isTrue);
  });

  testWidgets('app renders HiMemo shell', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
    });

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      const ProviderScope(child: HiMemoApp(flavor: AppFlavor.development)),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('HiMemo'), findsOneWidget);
    expect(find.text('Daily View'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
