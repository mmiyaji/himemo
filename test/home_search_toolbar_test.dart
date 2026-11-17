import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/home/presentation/home_search_toolbar.dart';

void main() {
  testWidgets('search toolbar forwards query, clear, density, and details', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final queries = <String>[];
    final densities = <NotesListDensity>[];
    var clearCalls = 0;
    var detailsCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeSearchToolbar(
            controller: controller,
            density: NotesListDensity.standard,
            searchLabel: 'Search',
            searchHint: 'Search notes',
            clearLabel: 'Clear search',
            layoutLabel: 'List layout',
            standardLabel: 'Standard',
            compactLabel: 'Compact',
            detailsLabel: 'Filters',
            detailsKey: const ValueKey('toolbar-details'),
            densityKey: const ValueKey('toolbar-density'),
            filterCount: 0,
            onQueryChanged: queries.add,
            onClear: () {
              clearCalls++;
              controller.clear();
            },
            onDensityChanged: densities.add,
            onDetailsPressed: () => detailsCalls++,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'memo');
    expect(queries, ['memo']);
    await tester.pump();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(clearCalls, 1);
    expect(controller.text, isEmpty);

    await tester.tap(find.byKey(const ValueKey('toolbar-details')));
    expect(detailsCalls, 1);
    await tester.tap(find.byKey(const ValueKey('toolbar-density')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text('Compact').last,
            matching: find.byWidgetPredicate(
              (widget) => widget is CheckedPopupMenuItem,
            ),
          )
          .first,
    );
    expect(densities, [NotesListDensity.compact]);
  });
}
