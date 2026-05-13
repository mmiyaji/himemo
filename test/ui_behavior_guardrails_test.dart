import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web video playback stays enabled through the native video element', () {
    final webVideoElement = File(
      'lib/features/home/presentation/web_video_element_view_web.dart',
    ).readAsStringSync();
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(webVideoElement, contains('html.VideoElement'));
    expect(webVideoElement, contains('..controls = true'));
    expect(webVideoElement, contains('..muted = muted'));
    expect(webVideoElement, contains('HtmlElementView'));
    expect(
      homePage,
      isNot(
        contains('VideoPlayerController.networkUrl(Uri.parse(webObjectUrl))'),
      ),
    );
  });

  test(
    'UI behavior guardrails cover repeated mobile and media regressions',
    () {
      final guardrails = File(
        'docs/ui-behavior-guardrails.md',
      ).readAsStringSync();

      expect(
        guardrails,
        contains('Do not disable video thumbnail generation on Web'),
      );
      expect(guardrails, contains('Videos must remain playable on Web'));
      expect(guardrails, contains('full-screen modal sheet'));
      expect(guardrails, contains('app header behind it'));
      expect(guardrails, contains('Automated checks should cover these rules'));
    },
  );

  test('rich editor restores a text block after trailing attachments', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(homePage, contains('void _ensureTrailingRichParagraph'));
    expect(homePage, contains('_ensureTrailingRichParagraph(drafts);'));
    expect(homePage, contains('_ensureTrailingRichParagraph(_richBlocks);'));
  });

  test('mobile note editor keeps keyboard footer compact', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(
      homePage,
      contains(
        'final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;',
      ),
    );
    expect(
      homePage,
      contains(
        '? 16.0\n        : (_editorMode == NoteEditorMode.rich ? 16.0 : 96.0);',
      ),
    );
    expect(homePage, contains('bottom: !keyboardVisible'));
    expect(homePage, contains('height: _attachmentImportBusy ? 56 : 0'));
  });

  test('app lock background privacy cover prevents delayed relock flashes', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();
    final androidMainActivity = File(
      'android/app/src/main/kotlin/org/ruhenheim/himemo/MainActivity.kt',
    ).readAsStringSync();

    expect(appShell, contains('_activateAppLockPrivacyCoverIfEnabled'));
    expect(appShell, contains('_lifecyclePrivacyCoverVisible'));
    expect(appShell, contains('_AppPrivacyCover'));
    expect(
      appShell,
      contains('privacyScreenActive || _lifecyclePrivacyProtectionEnabled'),
    );
    expect(appShell, contains("'showCover': showCover"));
    expect(androidMainActivity, contains('override fun onPause()'));
    expect(androidMainActivity, contains('setPrivacyOverlayVisible(true)'));
    expect(androidMainActivity, contains('buildPrivacyOverlay'));
  });

  test('recent daily trend chart starts at the latest day', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(homePage, contains('class _InsightBarChartState'));
    expect(homePage, contains('_scrollController.position.maxScrollExtent'));
    expect(homePage, contains('controller: _scrollController'));
  });

  test('mobile create note action is a centered pen navigation button', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final createNoteIcon = File(
      'assets/actions/create-note.svg',
    ).readAsStringSync();

    expect(homePage, contains('class _CreateNoteNavButton'));
    expect(homePage, contains('class _CreateNoteIcon'));
    expect(homePage, contains('class _CreateNoteIconColorMapper'));
    expect(homePage, contains('key: AppShell.addNoteKey'));
    expect(homePage, contains('assets/actions/create-note.svg'));
    expect(homePage, contains('colorMapper: _CreateNoteIconColorMapper'));
    expect(homePage, contains('static const _verticalOffset = 12.0'));
    expect(homePage, contains('static const _tapSize = 68.0'));
    expect(homePage, contains('static const _buttonSize = 56.0'));
    expect(homePage, contains('static const _iconSize = 44.0'));
    expect(
      homePage,
      isNot(contains('offset: const Offset(0, _verticalOffset)')),
    );
    expect(homePage, contains('_CreateNoteIcon(size: _iconSize)'));
    expect(homePage, contains('width: _buttonSize'));
    expect(homePage, contains('height: _buttonSize'));
    expect(homePage, contains('height: _tapSize + _verticalOffset'));
    expect(homePage, contains('alignment: Alignment.bottomCenter'));
    expect(homePage, contains('shape: BoxShape.circle'));
    expect(homePage, contains('enabled: false'));
    expect(
      homePage,
      contains('static const _compactBottomNavLabelBreakpoint = 380.0'),
    );
    expect(homePage, contains('LayoutBuilder('));
    expect(
      homePage,
      contains('constraints.maxWidth < _compactBottomNavLabelBreakpoint'),
    );
    expect(homePage, contains("hideBottomNavLabels ? '' : label"));
    expect(homePage, contains('NavigationDestinationLabelBehavior.alwaysHide'));
    expect(homePage, contains('NavigationDestinationLabelBehavior.alwaysShow'));
    expect(homePage, contains('if (index == 2)'));
    expect(homePage, contains('Positioned('));
    expect(homePage, contains('bottom: 4'));
    expect(homePage, contains('icon: SizedBox.shrink()'));
    expect(homePage, contains('child: _CreateNoteNavButton('));
    expect(homePage, contains('showNoteEditorSheet(context, ref);'));
    expect(createNoteIcon, contains('<svg'));
    expect(createNoteIcon, contains('#FFF7F4'));
    expect(createNoteIcon, contains('#9F5261'));
  });

  test('tablet create note action lives at the bottom of the sidebar', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(homePage, contains('class _SidebarCreateNoteButton'));
    expect(
      homePage,
      contains('onAddNote: () => showNoteEditorSheet(context, ref)'),
    );
    expect(homePage, contains('key: AppShell.addNoteKey'));
    expect(homePage, contains('floatingActionButton: null'));
    expect(homePage, contains('FilledButton.icon'));
    expect(homePage, contains('strings.addNote'));
  });

  test('iOS Spotlight indexing is opt-in and clears when disabled', () {
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final app = File('lib/app/app.dart').readAsStringSync();

    expect(homeProviders, contains('SpotlightNoteIndexEnabledController'));
    expect(
      homeProviders,
      contains('settings.ios_spotlight_standard_notes_enabled'),
    );
    expect(homeProviders, contains('replaceAllStandardNotes'));
    expect(homeProviders, contains("note.vaultId == 'everyday'"));
    expect(homeProviders, contains('bridge.clearNotes();'));
    expect(homePage, contains('memoSpotlightIndexKey'));
    expect(homePage, contains('TargetPlatform.iOS'));
    expect(appDelegate, contains('import CoreSpotlight'));
    expect(appDelegate, contains('spotlightDomainIdentifier'));
    expect(appDelegate, contains('CSSearchableItemActionType'));
    expect(app, contains('spotlightNoteOpenRequestControllerProvider'));
  });

  test('quick capture bypasses app lock auto prompts while active', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();

    expect(appShell, contains('bool get _isQuickCaptureActive'));
    expect(
      appShell,
      contains('ref.read(widgetQuickCaptureRequestControllerProvider) != null'),
    );
    expect(
      appShell,
      contains(
        'ref.watch(widgetQuickCaptureRequestControllerProvider) != null',
      ),
    );
    expect(appShell, contains('if (_isQuickCaptureActive)'));
  });

  test('note list day dividers follow the active sort field', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(homePage, contains('DateTime _noteListMoment'));
    expect(
      homePage,
      contains(
        'NotesListSortField.updatedAt => note.updatedAt ?? note.createdAt',
      ),
    );
    expect(
      homePage,
      contains('_MobileDayRow(_noteListMoment(notes[i], sortField))'),
    );
    expect(
      homePage,
      contains('_SplitNoteDayRow(_noteListMoment(notes[i], sortField))'),
    );
  });

  test('diagnostic mode exposes iCloud storage maintenance actions', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final iCloudTransport = File(
      'lib/features/sync/data/icloud_sync_transport.dart',
    ).readAsStringSync();
    final networkConnection = File(
      'lib/app/network_connection.dart',
    ).readAsStringSync();

    expect(homePage, contains('diagnosticICloudStorageBreakdownKey'));
    expect(homePage, contains('diagnosticICloudPruneBundlesKey'));
    expect(homePage, contains("'attachment'"));
    expect(homePage, contains('image decode failed'));
    expect(networkConnection, contains("'network'"));
    expect(networkConnection, contains('connection kind read'));
    expect(iCloudTransport, contains('fetchStorageBreakdown'));
    expect(iCloudTransport, contains('pruneObsoleteData'));
  });

  test('native attachment sharing keeps materialized files readable', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(homePage, contains('_markSharedAttachmentForCleanup'));
    expect(homePage, contains('markMaterializedFileForCleanup'));
    expect(
      homePage,
      contains('const _sharedAttachmentCleanupDelay = Duration(hours: 24);'),
    );
    expect(homePage, contains('mimeType: _mimeTypeForAttachment(attachment)'));
    expect(
      homePage,
      isNot(
        contains(
          'finally {\n      await attachmentStore.deleteMaterializedFile(tempFilePath);',
        ),
      ),
    );
  });

  test('attachment diagnostics include image byte signatures', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(homePage, contains('_attachmentByteDiagnosticData'));
    expect(homePage, contains('byteSignature'));
    expect(homePage, contains('detectedImageFormat'));
    expect(homePage, contains("return 'heic';"));
    expect(homePage, contains("return 'jpeg';"));
  });
}
