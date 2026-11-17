import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/presentation/sync_v2_auto_tag_rules.dart';

void main() {
  SyncV2WorkspaceNote entry({
    String profile = 'v2-profile',
    String title = 'Invoice to pay',
    bool ready = true,
    bool conflict = false,
    List<String> tags = const [],
  }) {
    final note = NoteEntry(
      id: 'note-$profile-${title.hashCode}',
      vaultId: profile,
      title: title,
      body: '',
      createdAt: DateTime.utc(2025),
      tags: tags,
    );
    final versions = [
      SyncV2NoteVersion(
        change: SyncV2Change(
          id: 'change-1',
          profileId: profile,
          noteId: note.id,
          operation: SyncV2Operation.upsert,
          parentIds: const {},
          payloadDigest: 'digest',
        ),
        payloadAvailable: ready,
        body: ready ? {'type': 'note'} : null,
      ),
      if (conflict)
        SyncV2NoteVersion(
          change: SyncV2Change(
            id: 'change-2',
            profileId: profile,
            noteId: note.id,
            operation: SyncV2Operation.upsert,
            parentIds: const {},
            payloadDigest: 'digest-2',
          ),
          payloadAvailable: true,
          body: const {'type': 'note'},
        ),
    ];
    return SyncV2WorkspaceNote(
      note,
      SyncV2NoteSnapshot(versions: versions, pendingIds: const {}),
      const [],
    );
  }

  final invoiceRule = AutoTagRule(
    id: 'r1',
    tag: 'Finance',
    keywords: const ['invoice'],
  );

  test(
    'plans matching V2 notes and skips locked, unavailable and conflict notes',
    () {
      final complete = entry();
      final unavailable = entry(title: 'Invoice pending load', ready: false);
      final conflict = entry(title: 'Invoice conflict', conflict: true);
      final otherProfile = entry(profile: 'another-profile');

      final result = planSyncV2AutoTagEdits(
        notes: [complete, unavailable, conflict, otherProfile],
        rules: [invoiceRule],
        selectedProfileId: 'v2-profile',
        locked: false,
      );

      expect(result.keys, [complete]);
      expect(result[complete], ['Finance']);
      expect(
        planSyncV2AutoTagEdits(
          notes: [complete],
          rules: [invoiceRule],
          selectedProfileId: 'v2-profile',
          locked: true,
        ),
        isEmpty,
      );
    },
  );

  test('does not duplicate existing tags or apply disabled rules', () {
    final existing = entry(tags: const ['finance']);
    final result = planSyncV2AutoTagEdits(
      notes: [existing],
      rules: [invoiceRule],
      selectedProfileId: 'v2-profile',
      locked: false,
    );
    expect(result, isEmpty);
    expect(
      planSyncV2AutoTagEdits(
        notes: [entry()],
        rules: [invoiceRule.copyWith(enabled: false)],
        selectedProfileId: 'v2-profile',
        locked: false,
      ),
      isEmpty,
    );
  });

  testWidgets('English editor returns normalized, validated fields', (
    tester,
  ) async {
    SyncV2AutoTagRuleDraft? saved;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSyncV2AutoTagRuleEditor(
                context,
                onSave: (value) async => saved = value,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Create auto-tag rule'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sync-v2-auto-tag-name')),
      '  #Finance  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sync-v2-auto-tag-keywords')),
      'invoice, Invoice, payment',
    );
    await tester.tap(find.byKey(const ValueKey('sync-v2-auto-tag-save')));
    await tester.pumpAndSettle();
    expect(saved?.tag, 'Finance');
    expect(saved?.keywords, ['invoice', 'payment']);
    expect(saved?.matchTitle, isTrue);
    expect(saved?.matchBody, isTrue);
    expect(saved?.matchAttachments, isTrue);
  });

  testWidgets('Japanese editor validates reserved tag and asks for a target', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSyncV2AutoTagRuleEditor(
                context,
                onSave: (_) async => saves++,
              ),
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(find.text('自動タグルールを作成'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sync-v2-auto-tag-name')),
      'sync:excluded',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sync-v2-auto-tag-keywords')),
      'invoice',
    );
    await tester.tap(find.byKey(const ValueKey('sync-v2-auto-tag-save')));
    await tester.pumpAndSettle();
    expect(find.text('このタグ名はアプリが使用しています。'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('rules panel fits a narrow mobile width in English', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: SyncV2AutoTagRulesPanel(
              rules: [invoiceRule],
              onAdd: () {},
              onToggle: (_, _) {},
              onEdit: (_) {},
              onDelete: (_) {},
              onApply: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto-tag rules'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
