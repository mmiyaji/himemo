import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:himemo/features/sync/presentation/sync_v2_original_editor.dart';

void main() {
  testWidgets('editor exposes writable fields and keeps owner-provided slots', (
    tester,
  ) async {
    final title = TextEditingController(text: 'A saved title');
    final body = TextEditingController(text: 'Saved body text');
    addTearDown(title.dispose);
    addTearDown(body.dispose);
    var closed = 0;
    var actionCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncV2OriginalEditor(
            titleController: title,
            bodyController: body,
            writable: true,
            editing: true,
            createdAt: DateTime(2026, 11, 16, 9, 5),
            onClose: () => closed++,
            attachments: const ListTile(
              key: ValueKey('attachment-slot'),
              title: Text('Attachment from parent'),
            ),
            actions: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('action-slot-button'),
                  onPressed: () => actionCalls++,
                  child: const Text('Save from parent'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final titleField = tester.widget<TextField>(
      find.byKey(const ValueKey('sync-v2-title')),
    );
    final bodyField = tester.widget<TextField>(
      find.byKey(const ValueKey('sync-v2-body')),
    );
    expect(titleField.controller, same(title));
    expect(bodyField.controller, same(body));
    expect(titleField.readOnly, isFalse);
    expect(bodyField.readOnly, isFalse);
    expect(find.text('Quick memo'), findsOneWidget);
    expect(find.text('Editing'), findsOneWidget);
    expect(find.text('Attachment from parent'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('action-slot-button')));
    await tester.tap(find.text('Notes'));
    expect(actionCalls, 1);
    expect(closed, 1);
  });

  testWidgets('changing draft/read-only state retains owner controller text', (
    tester,
  ) async {
    final title = TextEditingController(text: 'Draft title');
    final body = TextEditingController(text: 'Draft body');
    addTearDown(title.dispose);
    addTearDown(body.dispose);

    Widget editor({required bool writable, bool editing = false}) =>
        MaterialApp(
          home: Scaffold(
            body: SyncV2OriginalEditor(
              titleController: title,
              bodyController: body,
              writable: writable,
              editing: editing,
              onClose: () {},
              attachments: const SizedBox.shrink(),
              actions: const SizedBox.shrink(),
            ),
          ),
        );

    await tester.pumpWidget(editor(writable: true));
    await tester.pumpWidget(editor(writable: false));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sync-v2-title')))
          .readOnly,
      isTrue,
    );
    expect(title.text, 'Draft title');
    expect(body.text, 'Draft body');

    await tester.pumpWidget(editor(writable: true, editing: true));
    expect(title.text, 'Draft title');
    expect(body.text, 'Draft body');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('sync-v2-title')))
          .readOnly,
      isFalse,
    );
  });

  testWidgets(
    'small screen and large text scale stay scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final title = TextEditingController(
        text: 'A long title for a narrow screen',
      );
      final body = TextEditingController(
        text: List.filled(14, 'A paragraph of note body text.').join('\n'),
      );
      addTearDown(title.dispose);
      addTearDown(body.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: SyncV2OriginalEditor(
                  titleController: title,
                  bodyController: body,
                  writable: true,
                  wide: true,
                  onClose: () {},
                  attachments: const Wrap(
                    children: [
                      Chip(label: Text('Attached image')),
                      Chip(label: Text('Attached document')),
                    ],
                  ),
                  actions: const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(onPressed: null, child: Text('Save note')),
                      TextButton(onPressed: null, child: Text('Discard draft')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('sync-v2-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-v2-body')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide tablet layout remains constrained without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final title = TextEditingController(text: 'Tablet title');
    final body = TextEditingController(text: 'Tablet note body');
    addTearDown(title.dispose);
    addTearDown(body.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: Scaffold(
              body: SyncV2OriginalEditor(
                titleController: title,
                bodyController: body,
                writable: true,
                wide: true,
                onClose: () {},
                attachments: const SizedBox.shrink(),
                actions: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    final titleSize = tester.getSize(
      find.byKey(const ValueKey('sync-v2-title')),
    );
    expect(titleSize.width, lessThanOrEqualTo(1040));
    expect(tester.takeException(), isNull);
  });
}
