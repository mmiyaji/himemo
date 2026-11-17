import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:himemo/features/sync/presentation/sync_v2_responsive_navigation.dart';

void main() {
  testWidgets('wide layout shows every section and add action', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    final selected = <SyncV2NavigationSection>[];
    var adds = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1000,
              height: 700,
              child: Row(
                children: [
                  SizedBox(
                    width: 256,
                    child: SyncV2ResponsiveNavigation(
                      wide: true,
                      section: SyncV2NavigationSection.notes,
                      onSectionSelected: selected.add,
                      onAddNote: () => adds++,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    for (final label in ['ノート', 'カレンダー', '記録', 'ゴミ箱', 'タグ管理', '設定']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('ゴミ箱'));
    await tester.tap(find.text('ノートを追加'));
    expect(selected, [SyncV2NavigationSection.trash]);
    expect(adds, 1);
    await tester.tap(find.byTooltip('サイドバーを折りたたむ'));
    await tester.pumpAndSettle();
    expect(find.text('ノートを追加'), findsNothing);
    expect(find.byTooltip('ノートを追加'), findsOneWidget);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('compact layout keeps primary navigation and add callback', (
    tester,
  ) async {
    final selected = <SyncV2NavigationSection>[];
    var adds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SizedBox(
            width: 390,
            child: SyncV2ResponsiveNavigation(
              wide: false,
              section: SyncV2NavigationSection.calendar,
              onSectionSelected: selected.add,
              onAddNote: () => adds++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('ノート'), findsOneWidget);
    expect(find.text('カレンダー'), findsOneWidget);
    expect(find.text('記録'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('ゴミ箱'), findsNothing);
    await tester.tap(find.byTooltip('ノートを追加'));
    await tester.tap(find.text('記録'));
    expect(adds, 1);
    expect(selected, [SyncV2NavigationSection.insights]);
  });

  testWidgets('disabled state blocks navigation and add callbacks', (
    tester,
  ) async {
    final selected = <SyncV2NavigationSection>[];
    var adds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SyncV2ResponsiveNavigation(
            wide: false,
            section: SyncV2NavigationSection.notes,
            enabled: false,
            canOpenSettings: false,
            onSectionSelected: selected.add,
            onAddNote: () => adds++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('設定'));
    await tester.tap(find.text('カレンダー'));
    await tester.tap(find.byTooltip('ノートを追加'));
    expect(selected, isEmpty);
    expect(adds, 0);
  });

  testWidgets('settings can be gated separately', (tester) async {
    final selected = <SyncV2NavigationSection>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SyncV2ResponsiveNavigation(
            wide: false,
            section: SyncV2NavigationSection.notes,
            canOpenSettings: false,
            onSectionSelected: selected.add,
            onAddNote: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('設定'));
    expect(selected, isEmpty);
  });
}
