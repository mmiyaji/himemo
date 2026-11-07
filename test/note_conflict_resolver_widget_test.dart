import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/sync/data/sync_engine.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';

void main() {
  testWidgets(
    'conflict resolver blocks loading and resolution while exposing detailed differences',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final remoteCompleter = Completer<PreparedSyncNote?>();
      final resolutionCompleter = Completer<NoteConflictResolutionOutcome>();
      var resolutionCalls = 0;
      NoteConflictResolutionAction? selectedAction;
      final local = NoteEntry(
        id: 'conflict-note',
        vaultId: 'everyday',
        title: '端末のタイトル',
        body: '端末だけの本文です。\n二行目も異なります。',
        createdAt: DateTime(2026, 7, 18, 9),
        updatedAt: DateTime(2026, 7, 18, 10),
        tags: const ['端末', '共有'],
        isPinned: true,
        revision: 4,
        syncState: NoteSyncState.conflict,
      );
      final remote = PreparedSyncNote(
        action: PendingNoteChangeAction.upsert,
        note: NoteEntry(
          id: 'conflict-note',
          vaultId: 'everyday',
          title: 'リモートのタイトル',
          body: 'リモートだけの本文です。',
          createdAt: DateTime(2026, 7, 18, 9),
          updatedAt: DateTime(2026, 7, 18, 11),
          tags: const ['リモート', '共有'],
          revision: 5,
          syncState: NoteSyncState.synced,
        ),
      );

      await _pumpDialogLauncher(
        tester,
        dialog: NoteConflictResolverDialog(
          localNote: local,
          loadRemote: () => remoteCompleter.future,
          resolve: (action, remoteChange) {
            resolutionCalls += 1;
            selectedAction = action;
            expect(remoteChange, same(remote));
            return resolutionCompleter.future;
          },
        ),
      );

      await tester.tap(find.text('開く'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('リモートの最新版を読み込んでいます…'), findsOneWidget);
      expect(
        find.byKey(NoteConflictResolverDialog.cancelButtonKey),
        findsOneWidget,
      );

      remoteCompleter.complete(remote);
      await tester.pumpAndSettle();
      expect(find.text('概要'), findsOneWidget);
      expect(find.text('詳細差分'), findsOneWidget);

      await tester.tap(find.text('詳細差分'));
      await tester.pumpAndSettle();
      expect(find.text('タイトル'), findsOneWidget);
      expect(find.text('本文'), findsOneWidget);
      expect(find.text('タグ'), findsOneWidget);
      expect(find.text('端末のタイトル'), findsOneWidget);
      expect(find.text('リモートのタイトル'), findsOneWidget);
      expect(find.text('端末のみ'), findsWidgets);
      expect(find.text('リモートのみ'), findsWidgets);
      expect(tester.takeException(), isNull);

      final keepLocalOption = find.byKey(
        NoteConflictResolverDialog.keepLocalOptionKey,
      );
      await tester.ensureVisible(keepLocalOption);
      await tester.pumpAndSettle();
      await tester.tap(keepLocalOption);
      await tester.pump();
      await tester.tap(find.byKey(NoteConflictResolverDialog.resolveButtonKey));
      await tester.pump();

      expect(resolutionCalls, 1);
      expect(selectedAction, NoteConflictResolutionAction.keepLocal);
      expect(
        find.byKey(NoteConflictResolverDialog.busyOverlayKey),
        findsOneWidget,
      );
      final cancel = tester.widget<TextButton>(
        find.byKey(NoteConflictResolverDialog.cancelButtonKey),
      );
      expect(cancel.onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(NoteConflictResolverDialog), findsOneWidget);

      resolutionCompleter.complete(
        const NoteConflictResolutionOutcome.resolved(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NoteConflictResolverDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('remote deletion is explicit and merge is unavailable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final local = NoteEntry(
      id: 'remote-delete',
      vaultId: 'everyday',
      title: '残しておきたいメモ',
      body: '削除を採用しても、この内容はゴミ箱に残します。',
      createdAt: DateTime(2026, 7, 18, 9),
      updatedAt: DateTime(2026, 7, 18, 10),
      syncState: NoteSyncState.conflict,
    );
    final deletedAt = DateTime(2026, 7, 18, 11);
    final remoteDelete = PreparedSyncNote(
      action: PendingNoteChangeAction.delete,
      note: NoteEntry(
        id: 'remote-delete',
        vaultId: 'everyday',
        title: '',
        body: '',
        createdAt: local.createdAt,
        updatedAt: deletedAt,
        deletedAt: deletedAt,
        revision: 3,
      ),
    );

    await _pumpDialogLauncher(
      tester,
      dialog: NoteConflictResolverDialog(
        localNote: local,
        loadRemote: () async => remoteDelete,
        resolve: (_, _) async => const NoteConflictResolutionOutcome.resolved(),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    expect(find.text('リモートの削除を採用'), findsOneWidget);
    expect(find.text('この端末のメモを復元'), findsOneWidget);
    expect(find.byKey(NoteConflictResolverDialog.mergeOptionKey), findsNothing);

    await tester.tap(find.text('詳細差分'));
    await tester.pumpAndSettle();
    expect(find.textContaining('リモート側には本文ではなく削除記録'), findsOneWidget);
    expect(find.text('状態'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote loading can be cancelled without trapping navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final remoteCompleter = Completer<PreparedSyncNote?>();
    final local = NoteEntry(
      id: 'cancel-load',
      vaultId: 'everyday',
      title: '端末版',
      body: '端末本文',
      createdAt: DateTime(2026, 7, 18, 9),
      syncState: NoteSyncState.conflict,
    );
    await _pumpDialogLauncher(
      tester,
      dialog: NoteConflictResolverDialog(
        localNote: local,
        loadRemote: () => remoteCompleter.future,
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NoteConflictResolverDialog), findsNothing);

    remoteCompleter.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small high-text-scale layout shows structured differences without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final createdAt = DateTime(2026, 7, 18, 9);
      final local = NoteEntry(
        id: 'structured-diff',
        vaultId: 'everyday',
        title: '構造差分',
        body: '同じ本文',
        createdAt: createdAt,
        updatedAt: createdAt,
        blocks: const [NoteBlock(type: NoteBlockType.paragraph, text: '端末の段落')],
        syncState: NoteSyncState.conflict,
      );
      final remote = PreparedSyncNote(
        action: PendingNoteChangeAction.upsert,
        note: NoteEntry(
          id: 'structured-diff',
          vaultId: 'everyday',
          title: '構造差分',
          body: '同じ本文',
          createdAt: createdAt,
          updatedAt: createdAt,
          blocks: const [
            NoteBlock(type: NoteBlockType.paragraph, text: 'リモートの段落'),
          ],
          syncState: NoteSyncState.synced,
        ),
      );
      await _pumpDialogLauncher(
        tester,
        dialog: NoteConflictResolverDialog(
          localNote: local,
          loadRemote: () async => remote,
          resolve: (_, _) async =>
              const NoteConflictResolutionOutcome.resolved(),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('詳細差分'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('構成・書式'), findsOneWidget);
      expect(
        find.byKey(NoteConflictResolverDialog.mergeOptionKey),
        findsNothing,
      );
      expect(find.textContaining('自動マージしません'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('very long body differences are capped for responsive review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final createdAt = DateTime(2026, 7, 18, 9);
    final local = NoteEntry(
      id: 'long-diff',
      vaultId: 'everyday',
      title: '長文差分',
      body: List.generate(1200, (index) => '端末 $index').join('\n'),
      createdAt: createdAt,
      updatedAt: createdAt,
      editorMode: NoteEditorMode.quick,
      syncState: NoteSyncState.conflict,
    );
    final remote = PreparedSyncNote(
      action: PendingNoteChangeAction.upsert,
      note: NoteEntry(
        id: 'long-diff',
        vaultId: 'everyday',
        title: '長文差分',
        body: List.generate(1200, (index) => 'リモート $index').join('\n'),
        createdAt: createdAt,
        updatedAt: createdAt,
        editorMode: NoteEditorMode.quick,
        syncState: NoteSyncState.synced,
      ),
    );
    await _pumpDialogLauncher(
      tester,
      dialog: NoteConflictResolverDialog(
        localNote: local,
        loadRemote: () async => remote,
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細差分'));
    await tester.pumpAndSettle();

    expect(find.textContaining('行を省略（先頭と末尾を表示）'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a middle-only change remains visible in a very long body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final createdAt = DateTime(2026, 7, 18, 9);
    final localLines = List.generate(1200, (index) => '共通 $index');
    final remoteLines = [...localLines];
    localLines[600] = '端末 中央の変更';
    remoteLines[600] = 'リモート 中央の変更';
    final local = NoteEntry(
      id: 'middle-diff',
      vaultId: 'everyday',
      title: '中央差分',
      body: localLines.join('\n'),
      createdAt: createdAt,
      updatedAt: createdAt,
      editorMode: NoteEditorMode.quick,
      syncState: NoteSyncState.conflict,
    );
    final remote = PreparedSyncNote(
      action: PendingNoteChangeAction.upsert,
      note: NoteEntry(
        id: 'middle-diff',
        vaultId: 'everyday',
        title: '中央差分',
        body: remoteLines.join('\n'),
        createdAt: createdAt,
        updatedAt: createdAt,
        editorMode: NoteEditorMode.quick,
        syncState: NoteSyncState.synced,
      ),
    );
    await _pumpDialogLauncher(
      tester,
      dialog: NoteConflictResolverDialog(
        localNote: local,
        loadRemote: () async => remote,
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細差分'));
    await tester.pumpAndSettle();

    expect(find.text('端末 中央の変更'), findsOneWidget);
    expect(find.text('リモート 中央の変更'), findsOneWidget);
    expect(find.textContaining('共通する'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a central change remains visible in a huge single line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final createdAt = DateTime(2026, 7, 18, 9);
    final padding = List.filled(260000, 'あ').join();
    final localBody = [padding, '端末の中央変更', padding].join();
    final remoteBody = [padding, 'リモートの中央変更', padding].join();
    final local = NoteEntry(
      id: 'huge-line-diff',
      vaultId: 'everyday',
      title: '巨大行差分',
      body: localBody,
      createdAt: createdAt,
      updatedAt: createdAt,
      editorMode: NoteEditorMode.quick,
      syncState: NoteSyncState.conflict,
    );
    final remote = PreparedSyncNote(
      action: PendingNoteChangeAction.upsert,
      note: NoteEntry(
        id: 'huge-line-diff',
        vaultId: 'everyday',
        title: '巨大行差分',
        body: remoteBody,
        createdAt: createdAt,
        updatedAt: createdAt,
        editorMode: NoteEditorMode.quick,
        syncState: NoteSyncState.synced,
      ),
    );
    await _pumpDialogLauncher(
      tester,
      dialog: NoteConflictResolverDialog(
        localNote: local,
        loadRemote: () async => remote,
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細差分'));
    await tester.pumpAndSettle();

    expect(find.textContaining('端末の中央変更'), findsOneWidget);
    expect(find.textContaining('リモートの中央変更'), findsOneWidget);
    expect(find.textContaining('最初と最後の変更位置周辺'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long single line uses the bounded excerpt path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final createdAt = DateTime(2026, 7, 18, 9);
    final padding = List.filled(2000, 'あ').join();
    final local = NoteEntry(
      id: 'long-line-diff',
      vaultId: 'everyday',
      title: '長い単一行',
      body: [padding, '端末の境界変更', padding].join(),
      createdAt: createdAt,
      updatedAt: createdAt,
      editorMode: NoteEditorMode.quick,
      syncState: NoteSyncState.conflict,
    );
    final remote = PreparedSyncNote(
      action: PendingNoteChangeAction.upsert,
      note: NoteEntry(
        id: 'long-line-diff',
        vaultId: 'everyday',
        title: '長い単一行',
        body: [padding, 'リモートの境界変更', padding].join(),
        createdAt: createdAt,
        updatedAt: createdAt,
        editorMode: NoteEditorMode.quick,
        syncState: NoteSyncState.synced,
      ),
    );
    await _pumpDialogLauncher(
      tester,
      dialog: NoteConflictResolverDialog(
        localNote: local,
        loadRemote: () async => remote,
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細差分'));
    await tester.pumpAndSettle();

    expect(find.textContaining('端末の境界変更'), findsOneWidget);
    expect(find.textContaining('リモートの境界変更'), findsOneWidget);
    expect(find.textContaining('最初と最後の変更位置周辺'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large excerpt keeps source line order after its head budget', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String fixedLine(String prefix, int length) =>
        prefix + List.filled(length - prefix.length, 'x').join();

    final localLines = <String>[
      for (var index = 1; index <= 8; index++) fixedLine('端末$index:', 2000),
      fixedLine('端末9:', 1000),
      fixedLine('端末10:', 100),
      fixedLine('共通:', 20000),
    ];
    final remoteLines = <String>[
      for (var index = 1; index <= 8; index++) fixedLine('遠隔$index:', 2000),
      fixedLine('遠隔9:', 1000),
      fixedLine('遠隔10:', 100),
      localLines.last,
    ];
    final createdAt = DateTime(2026, 7, 18, 9);
    final local = NoteEntry(
      id: 'line-order-diff',
      vaultId: 'everyday',
      title: '行順差分',
      body: localLines.join('\n'),
      createdAt: createdAt,
      updatedAt: createdAt,
      editorMode: NoteEditorMode.quick,
      syncState: NoteSyncState.conflict,
    );
    final remote = PreparedSyncNote(
      action: PendingNoteChangeAction.upsert,
      note: NoteEntry(
        id: 'line-order-diff',
        vaultId: 'everyday',
        title: '行順差分',
        body: remoteLines.join('\n'),
        createdAt: createdAt,
        updatedAt: createdAt,
        editorMode: NoteEditorMode.quick,
        syncState: NoteSyncState.synced,
      ),
    );
    await _pumpDialogLauncher(
      tester,
      dialog: NoteConflictResolverDialog(
        localNote: local,
        loadRemote: () async => remote,
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('詳細差分'));
    await tester.pumpAndSettle();

    final displayedLines = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data ?? '')
        .toList(growable: false);
    final localNinth = displayedLines.indexWhere(
      (line) => line.startsWith('端末9:'),
    );
    final localTenth = displayedLines.indexWhere(
      (line) => line.startsWith('端末10:'),
    );
    final remoteNinth = displayedLines.indexWhere(
      (line) => line.startsWith('遠隔9:'),
    );
    final remoteTenth = displayedLines.indexWhere(
      (line) => line.startsWith('遠隔10:'),
    );
    expect(localNinth, isNonNegative);
    expect(localTenth, greaterThan(localNinth));
    expect(remoteNinth, isNonNegative);
    expect(remoteTenth, greaterThan(remoteNinth));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDialogLauncher(
  WidgetTester tester, {
  required Widget dialog,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showDialog<NoteConflictResolutionOutcome>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => dialog,
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
