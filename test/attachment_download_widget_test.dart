import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows Japanese download guidance, progress, and closes with downloaded attachment',
    (tester) async {
      final downloadCompleter = Completer<NoteAttachment>();
      final downloaded = _remoteAttachment().copyWith(
        filePath: '/local/portrait.jpg',
      );
      final fake = _FakeSyncTransferController(
        onDownload: (_) => downloadCompleter.future,
      );
      final harness = await _pumpDownloadDialog(
        tester,
        fake: fake,
        attachment: _remoteAttachment(),
        size: const Size(280, 600),
      );

      expect(find.text('portrait.jpg'), findsOneWidget);
      expect(find.textContaining('まだこの端末に保存'), findsOneWidget);
      final downloadButton = find.byType(FilledButton).last;
      expect(downloadButton, findsOneWidget);

      await tester.tap(downloadButton);
      await tester.pump();
      expect(fake.calls, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // The busy state disables the action, so a second tap cannot start a
      // duplicate transfer.
      await tester.tap(downloadButton);
      expect(fake.calls, 1);

      downloadCompleter.complete(downloaded);
      await tester.pumpAndSettle();
      expect(await harness.result, downloaded);
      expect(find.byType(RemoteAttachmentDownloadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hides raw decryption failures and retries successfully', (
    tester,
  ) async {
    final downloaded = _remoteAttachment().copyWith(
      filePath: '/local/report.pdf',
    );
    var calls = 0;
    final fake = _FakeSyncTransferController(
      onDownload: (attachment) {
        calls += 1;
        if (calls == 1) {
          return Future<NoteAttachment>.error(
            const HimemoDecryptionException('SECRET_KEY_MATERIAL'),
          );
        }
        return Future<NoteAttachment>.value(downloaded);
      },
    );
    final harness = await _pumpDownloadDialog(
      tester,
      fake: fake,
      attachment: _remoteAttachment(label: 'report.pdf'),
    );

    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    expect(find.text('SECRET_KEY_MATERIAL'), findsNothing);
    expect(find.textContaining('復号'), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);

    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(fake.calls, 2);
    expect(await harness.result, downloaded);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prevents back and cancel while a download is busy', (
    tester,
  ) async {
    final downloadCompleter = Completer<NoteAttachment>();
    final fake = _FakeSyncTransferController(
      onDownload: (_) => downloadCompleter.future,
    );
    await _pumpDownloadDialog(
      tester,
      fake: fake,
      attachment: _remoteAttachment(),
    );

    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(RemoteAttachmentDownloadDialog), findsOneWidget);
    expect(find.text('キャンセル'), findsOneWidget);
    expect(tester.takeException(), isNull);

    downloadCompleter.complete(_remoteAttachment(filePath: '/local/photo.jpg'));
    await tester.pumpAndSettle();
  });
}

NoteAttachment _remoteAttachment({
  String label = 'portrait.jpg',
  String? filePath,
}) {
  return NoteAttachment(
    type: AttachmentType.photo,
    label: label,
    filePath: filePath ?? 'sync-attachment-object://0123456789abcdef',
  );
}

class _FakeSyncTransferController extends SyncTransferController {
  _FakeSyncTransferController({required this.onDownload});

  final Future<NoteAttachment> Function(NoteAttachment attachment) onDownload;
  int calls = 0;

  @override
  SyncTransferState build() => const SyncTransferState.idle();

  @override
  Future<NoteAttachment> downloadAttachment(NoteAttachment attachment) {
    calls += 1;
    return onDownload(attachment);
  }
}

class _DialogHarness {
  Future<NoteAttachment?>? result;
}

Future<_DialogHarness> _pumpDownloadDialog(
  WidgetTester tester, {
  required _FakeSyncTransferController fake,
  required NoteAttachment attachment,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = _DialogHarness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [syncTransferControllerProvider.overrideWith(() => fake)],
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
            builder: (context) => FilledButton(
              onPressed: () {
                harness.result = showDialog<NoteAttachment>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      RemoteAttachmentDownloadDialog(attachment: attachment),
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('開く'));
  await tester.pump();
  expect(find.byType(RemoteAttachmentDownloadDialog), findsOneWidget);
  return harness;
}
