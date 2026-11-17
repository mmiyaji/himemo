import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/presentation/sync_v2_rich_blocks_editor.dart';

Widget _host({
  required List<NoteBlock> blocks,
  required ValueChanged<List<NoteBlock>> onChanged,
  bool enabled = true,
}) => MaterialApp(
  home: Scaffold(
    body: SyncV2RichBlocksEditor(
      blocks: blocks,
      onChanged: onChanged,
      enabled: enabled,
    ),
  ),
);

void main() {
  testWidgets('editing retains attachment data and stable paragraph state', (
    tester,
  ) async {
    const attachment = NoteAttachment(
      type: AttachmentType.photo,
      label: 'photo',
      filePath: 'v2attachment:photo-id',
      previewBytesBase64: 'YWJj',
      durationMs: 12,
      localPayloadSizeBytes: 42,
      localPayloadModifiedAtMillis: 123,
      syncAttachmentContentHash: 'hash',
    );
    const blocks = [
      NoteBlock(type: NoteBlockType.paragraph, text: 'before'),
      NoteBlock(type: NoteBlockType.photo, attachment: attachment),
      NoteBlock(type: NoteBlockType.paragraph, text: 'after'),
    ];
    List<NoteBlock>? result;
    await tester.pumpWidget(
      _host(blocks: blocks, onChanged: (v) => result = v),
    );

    await tester.tap(find.byKey(const ValueKey('sync-v2-rich-move-up-2')));
    await tester.pump();
    expect(result!.map((block) => block.type), [
      NoteBlockType.paragraph,
      NoteBlockType.paragraph,
      NoteBlockType.photo,
    ]);
    expect(result![2].attachment, attachment);

    await tester.enterText(
      find.byKey(const ValueKey('sync-v2-rich-paragraph-2')),
      'edited after move',
    );
    expect(result![0].text, 'before');
    expect(result![1].text, 'edited after move');
    expect(result![2].attachment, attachment);
  });

  testWidgets('paragraphs can be inserted and removed while retaining one', (
    tester,
  ) async {
    List<NoteBlock>? result;
    await tester.pumpWidget(
      _host(
        blocks: const [NoteBlock(type: NoteBlockType.paragraph, text: 'one')],
        onChanged: (v) => result = v,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('sync-v2-add-paragraph')));
    await tester.pump();
    expect(result, hasLength(2));
    expect(result![0].text, 'one');
    expect(result![1].text, '');
    await tester.showKeyboard(
      find.byKey(const ValueKey('sync-v2-rich-paragraph-new-1')),
    );

    await tester.tap(
      find.byKey(const ValueKey('sync-v2-rich-remove-paragraph-new-1')),
    );
    await tester.pump();
    expect(result, hasLength(1));
    expect(result!.single.text, 'one');
    expect(tester.takeException(), isNull);

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('sync-v2-rich-remove-paragraph-0')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'pending files insert at selection without losing selected text',
    (tester) async {
      final key = GlobalKey<SyncV2RichBlocksEditorState>();
      List<NoteBlock>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncV2RichBlocksEditor(
              key: key,
              blocks: const [
                NoteBlock(type: NoteBlockType.paragraph, text: 'abcdef'),
              ],
              onChanged: (blocks) => result = blocks,
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('sync-v2-body')),
      );
      field.controller!.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 2,
      );
      await tester.showKeyboard(find.byKey(const Key('sync-v2-body')));
      final target = key.currentState!.captureInsertionTarget()!;
      expect(
        key.currentState!.insertPendingAttachments(target, const [
          SyncV2PendingBlock(
            draftId: 'pending-a',
            label: 'a.txt',
            type: AttachmentType.file,
          ),
          SyncV2PendingBlock(
            draftId: 'pending-b',
            label: 'b.txt',
            type: AttachmentType.file,
          ),
        ]),
        isTrue,
      );
      await tester.pump();
      expect(result, hasLength(4));
      expect(result![0].text, 'ab');
      expect(result![1].attachment!.filePath, 'v2pending:pending-a');
      expect(result![2].attachment!.filePath, 'v2pending:pending-b');
      expect(result![3].text, 'cdef');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending insertion rejects a paragraph edited after picker opens',
    (tester) async {
      final key = GlobalKey<SyncV2RichBlocksEditorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncV2RichBlocksEditor(
              key: key,
              blocks: const [
                NoteBlock(type: NoteBlockType.paragraph, text: 'original'),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.showKeyboard(find.byKey(const Key('sync-v2-body')));
      final target = key.currentState!.captureInsertionTarget()!;
      await tester.enterText(find.byKey(const Key('sync-v2-body')), 'changed');
      expect(
        key.currentState!.insertPendingAttachments(target, const [
          SyncV2PendingBlock(
            draftId: 'stale',
            label: 'stale.txt',
            type: AttachmentType.file,
          ),
        ]),
        isFalse,
      );
      expect(find.text('stale.txt'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled editor exposes no structural actions', (tester) async {
    await tester.pumpWidget(
      _host(
        blocks: const [NoteBlock(type: NoteBlockType.paragraph, text: 'one')],
        onChanged: (_) {},
        enabled: false,
      ),
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('sync-v2-add-paragraph')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('sync-v2-rich-insert-paragraph-0')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('attachment deletion after a move can be undone in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const attachment = NoteAttachment(
      type: AttachmentType.photo,
      label: 'photo',
      filePath: 'v2attachment:photo-id',
    );
    final original = const [
      NoteBlock(type: NoteBlockType.paragraph, text: 'first'),
      NoteBlock(type: NoteBlockType.paragraph, text: 'second'),
      NoteBlock(type: NoteBlockType.photo, attachment: attachment),
    ];
    List<NoteBlock>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncV2RichBlocksEditor(
            blocks: original,
            removableAttachmentIds: const {'photo-id'},
            onChanged: (blocks) => result = blocks,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('sync-v2-rich-move-up-2')));
    await tester.pump();
    expect(result!.map((block) => block.type), [
      NoteBlockType.paragraph,
      NoteBlockType.photo,
      NoteBlockType.paragraph,
    ]);
    await tester.tap(
      find.byKey(const ValueKey('sync-v2-rich-remove-attachment-2')),
    );
    await tester.pump();
    expect(result!.map((block) => block.text), ['first', 'second']);
    expect(find.text('Undo'), findsOneWidget);

    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();
    expect(result, [original[0], original[2], original[1]]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate and unlinked attachment rows cannot be removed', (
    tester,
  ) async {
    const linked = NoteAttachment(
      type: AttachmentType.photo,
      label: 'linked',
      filePath: 'v2attachment:shared-id',
    );
    const unlinked = NoteAttachment(
      type: AttachmentType.file,
      label: 'unlinked',
      filePath: 'legacy/path',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncV2RichBlocksEditor(
            blocks: const [
              NoteBlock(type: NoteBlockType.photo, attachment: linked),
              NoteBlock(type: NoteBlockType.photo, attachment: linked),
              NoteBlock(type: NoteBlockType.file, attachment: unlinked),
            ],
            removableAttachmentIds: const {'shared-id'},
            onChanged: (_) {},
          ),
        ),
      ),
    );

    for (final id in ['0', '1', '2']) {
      expect(
        tester
            .widget<IconButton>(
              find.byKey(ValueKey('sync-v2-rich-remove-attachment-$id')),
            )
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('quick mode keeps a single editable paragraph', (tester) async {
    List<NoteBlock>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncV2RichBlocksEditor(
            blocks: const [
              NoteBlock(type: NoteBlockType.paragraph, text: 'quick body'),
            ],
            onChanged: (blocks) => result = blocks,
            allowStructureChanges: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('sync-v2-add-paragraph')), findsNothing);
    expect(find.byKey(const ValueKey('sync-v2-rich-move-up-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('sync-v2-rich-remove-paragraph-0')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const Key('sync-v2-body')),
      'changed quick',
    );
    expect(result!.single.text, 'changed quick');
  });
}
