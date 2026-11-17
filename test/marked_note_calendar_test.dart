import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/marked_note_calendar.dart';
import 'package:himemo/l10n/app_strings.dart';

void main() {
  testWidgets(
    'calendar marks supplied decrypted notes and handles navigation',
    (tester) async {
      DateTime? selected;
      var previous = 0;
      var next = 0;
      var today = 0;
      final note = NoteEntry(
        id: 'v2-note',
        vaultId: 'v2-profile',
        title: 'private title',
        body: 'private body',
        createdAt: DateTime(2026, 11, 13, 12, 34),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: MarkedNoteCalendar.fromNotes(
              visibleMonth: DateTime(2026, 11),
              selectedDay: DateTime(2026, 11, 1),
              notes: [note],
              onPreviousMonth: () => previous++,
              onNextMonth: () => next++,
              onTodaySelected: () => today++,
              onDateSelected: (day) => selected = day,
            ),
          ),
        ),
      );
      expect(find.text('2026/11'), findsOneWidget);
      expect(find.text('private title'), findsNothing);
      final date = find
          .ancestor(of: find.text('13'), matching: find.byType(InkWell))
          .first;
      final mark = tester.widget<AnimatedContainer>(
        find.descendant(of: date, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (mark.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      final empty = find
          .ancestor(of: find.text('14'), matching: find.byType(InkWell))
          .first;
      final emptyMark = tester.widget<AnimatedContainer>(
        find.descendant(of: empty, matching: find.byType(AnimatedContainer)),
      );
      expect(
        (emptyMark.decoration! as BoxDecoration).color,
        Colors.transparent,
      );
      await tester.tap(find.text('13'));
      expect(selected, DateTime(2026, 11, 13));
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.tap(find.text('今日'));
      expect([previous, next, today], [1, 1, 1]);
    },
  );
}
