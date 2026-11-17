import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_read_only_pane.dart';

void main() {
  testWidgets('renders supplied note data and approved attachment widgets', (
    tester,
  ) async {
    final note = SyncV2NotePreviewData(
      title: '合成メモ',
      body: '表示確認用の本文です。',
      createdAt: DateTime(2026, 7, 2, 8, 15),
      updatedAt: DateTime(2026, 7, 3, 9, 20),
      tags: const ['仕事', '確認'],
      location: const NoteLocation(
        latitude: 35.68124,
        longitude: 139.76712,
        address: '東京駅',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 800,
            child: SyncV2NoteReadOnlyPane(
              note: note,
              attachmentWidgets: const [
                Text('承認済み添付プレビュー', key: Key('approved-attachment')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('合成メモ'), findsOneWidget);
    expect(find.text('表示確認用の本文です。'), findsOneWidget);
    expect(find.text('仕事'), findsOneWidget);
    expect(find.text('確認'), findsOneWidget);
    expect(find.text('東京駅'), findsOneWidget);
    expect(find.text('35.68124, 139.76712'), findsOneWidget);
    expect(find.byKey(const Key('approved-attachment')), findsOneWidget);
    expect(find.textContaining('2026/7/2 08:15'), findsOneWidget);
    expect(find.textContaining('2026/7/3 09:20'), findsNWidgets(2));
  });

  testWidgets('forwards each visible action to its parent callback', (
    tester,
  ) async {
    var editCalls = 0;
    var copyCalls = 0;
    var shareCalls = 0;
    var deleteCalls = 0;
    var pinCalls = 0;
    final note = SyncV2NotePreviewData(
      title: '操作テスト',
      body: '',
      createdAt: DateTime(2026, 7, 2),
      isPinned: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: SyncV2NoteReadOnlyPane(
              note: note,
              onEdit: () => editCalls++,
              onCopy: () => copyCalls++,
              onShare: () => shareCalls++,
              onDelete: () => deleteCalls++,
              onTogglePinned: () => pinCalls++,
            ),
          ),
        ),
      ),
    );

    for (final tooltip in ['編集', 'テキストをコピー', '共有', '削除', 'ピン留めを解除']) {
      await tester.tap(find.byTooltip(tooltip));
    }

    expect(editCalls, 1);
    expect(copyCalls, 1);
    expect(shareCalls, 1);
    expect(deleteCalls, 1);
    expect(pinCalls, 1);
  });

  testWidgets('renders ordered body blocks instead of fallback content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 800,
            child: SyncV2NoteReadOnlyPane(
              note: SyncV2NotePreviewData(
                title: '順序テスト',
                body: 'fallback本文',
                createdAt: DateTime(2026, 7, 2),
                location: const NoteLocation(
                  latitude: 35.68124,
                  longitude: 139.76712,
                  address: 'ブロック外の位置情報',
                ),
              ),
              attachmentWidgets: const [Text('fallback添付')],
              contentWidgets: const [
                Text('本文ブロック1', key: Key('paragraph-1')),
                Text('添付ブロック', key: Key('attachment-block')),
                Text('本文ブロック2', key: Key('paragraph-2')),
              ],
            ),
          ),
        ),
      ),
    );

    final first = tester.getTopLeft(find.byKey(const Key('paragraph-1'))).dy;
    final attachment = tester
        .getTopLeft(find.byKey(const Key('attachment-block')))
        .dy;
    final second = tester.getTopLeft(find.byKey(const Key('paragraph-2'))).dy;
    final location = tester.getTopLeft(find.text('ブロック外の位置情報')).dy;
    expect(first, lessThan(attachment));
    expect(attachment, lessThan(second));
    expect(second, lessThan(location));
    expect(find.text('fallback本文'), findsNothing);
    expect(find.text('fallback添付'), findsNothing);
  });

  testWidgets('omits actions without parent callbacks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 600,
            child: SyncV2NoteReadOnlyPane(
              note: SyncV2NotePreviewData(
                title: '読み取り専用',
                body: '閲覧のみ',
                createdAt: DateTime(2026, 7, 2),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('編集'), findsNothing);
    expect(find.byTooltip('テキストをコピー'), findsNothing);
    expect(find.byTooltip('共有'), findsNothing);
    expect(find.byTooltip('削除'), findsNothing);
    expect(find.byTooltip('このノートを固定'), findsNothing);
  });
}
