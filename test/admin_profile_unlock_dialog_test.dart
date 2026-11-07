import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('identifies target and retries without losing it', (
    tester,
  ) async {
    final calls = <String>[];
    final harness = await _showDialog(
      tester,
      profileName: '旅行メモ',
      createdAt: DateTime.utc(2025, 1, 2, 3, 4),
      onUnlock: (password) async {
        calls.add(password);
        return calls.length == 2;
      },
    );
    await tester.pump();

    expect(find.text('対象プロファイル'), findsOneWidget);
    expect(find.text('旅行メモ'), findsOneWidget);
    expect(find.textContaining('2025/01/02 12:04 JST'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.enterText(
      find.byKey(const Key('admin-profile-unlock-password-input')),
      ' wrong ',
    );
    await tester.tap(find.byKey(const Key('admin-profile-unlock-submit')));
    await tester.pumpAndSettle();
    expect(calls, [' wrong ']);
    expect(find.text('旅行メモ'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('admin-profile-unlock-password-input')),
      ' right ',
    );
    await tester.tap(find.byKey(const Key('admin-profile-unlock-submit')));
    await tester.pumpAndSettle();
    expect(calls, [' wrong ', ' right ']);
    expect(await harness.result, isTrue);
  });

  testWidgets('does not overflow with a long name on a small viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _showDialog(
      tester,
      profileName: '非常に長いプロファイル名を持つ対象プロファイルの確認用テキスト',
      isLegacy: true,
      onUnlock: (_) async => true,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('admin-profile-unlock-legacy')),
      findsOneWidget,
    );
  });
}

class _DialogHarness {
  late Future<bool?> result;
}

Future<_DialogHarness> _showDialog(
  WidgetTester tester, {
  required String profileName,
  required Future<bool> Function(String) onUnlock,
  DateTime? createdAt,
  bool isLegacy = false,
}) async {
  final harness = _DialogHarness();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () {
            harness.result = showDialog<bool>(
              context: context,
              builder: (_) => AdminProfileUnlockDialog(
                profileName: profileName,
                createdAt: createdAt,
                isLegacy: isLegacy,
                onUnlock: onUnlock,
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  return harness;
}
