import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:himemo/features/sync/presentation/sync_v2_search_controls.dart';

void main() {
  testWidgets(
    'applies filters and display options together; reset preserves display options',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SyncV2SearchControlsResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showSyncV2SearchFiltersDialog(
                    context,
                    initialFilters: const SearchFilters(pinnedOnly: true),
                    availableTags: const [],
                    availableYears: const [],
                    hasArchivedNotes: false,
                    initialDensity: NotesListDensity.standard,
                    initialSort: NotesListSortField.createdAt,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(DropdownButtonFormField<NotesListDensity>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compact').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.filters.isDefault, isTrue);
      expect(result!.density, NotesListDensity.compact);
      expect(result!.sort, NotesListSortField.createdAt);
    },
  );

  testWidgets('cancel returns no result and Japanese labels are shown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SyncV2SearchControlsResult? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('en'), Locale('ja')],
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showSyncV2SearchFiltersDialog(
                  context,
                  initialFilters: const SearchFilters(),
                  availableTags: const [],
                  availableYears: const [],
                  hasArchivedNotes: false,
                  initialDensity: NotesListDensity.standard,
                  initialSort: NotesListSortField.updatedAt,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('一覧表示'), findsOneWidget);
    expect(find.text('密度'), findsOneWidget);
    expect(find.text('並び順'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
