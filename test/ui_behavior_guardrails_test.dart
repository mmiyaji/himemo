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
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appShell, contains('_activateAppLockPrivacyCoverIfEnabled'));
    expect(appShell, contains('_lifecyclePrivacyCoverVisible'));
    expect(appShell, contains('_AppPrivacyCover'));
    expect(appShell, contains('class _AppLockIcon'));
    expect(appShell, contains('Color(0xFFFDFCFF)'));
    expect(appShell, contains('assets/privacy-icon.png'));
    expect(appShell, contains('dimension: wide ? 136 : 128'));
    expect(appShell, contains('dimension: 152'));
    expect(appShell.contains('width: 104'), isFalse);
    expect(appShell.contains('height: 104'), isFalse);
    expect(appShell.contains('EdgeInsets.all(4)'), isFalse);
    expect(
      appShell,
      contains('privacyScreenActive || _lifecyclePrivacyProtectionEnabled'),
    );
    expect(appShell, contains("'showCover': showCover"));
    expect(androidMainActivity, contains('override fun onPause()'));
    expect(androidMainActivity, contains('override fun onStop()'));
    expect(androidMainActivity, contains('window.addFlags'));
    expect(
      androidMainActivity,
      contains('WindowManager.LayoutParams.FLAG_SECURE'),
    );
    expect(androidMainActivity, contains('setPrivacyOverlayVisible(true)'));
    expect(androidMainActivity, contains('PRIVACY_OVERLAY_COLOR'));
    expect(androidMainActivity, contains('buildPrivacyOverlay'));
    expect(appDelegate, contains('alpha: 1.0'));
    expect(appDelegate.contains('UIBlurEffect(style: .extraLight)'), isFalse);
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
    expect(homePage, contains("tooltip: ''"));
    expect(homePage, contains('tooltip: strings.notes'));
    expect(homePage, contains('tooltip: strings.calendar'));
    expect(homePage, contains('if (index == 2)'));
    expect(homePage, contains('Positioned('));
    expect(homePage, contains('static const _createNoteNavTopOffset = -4.0'));
    expect(homePage, contains('top: _createNoteNavTopOffset'));
    expect(homePage, contains('icon: SizedBox.shrink()'));
    expect(homePage, contains('child: _CreateNoteNavButton('));
    expect(homePage, contains('showNoteEditorSheet(context, ref);'));
    expect(createNoteIcon, contains('<svg'));
    expect(createNoteIcon, contains('#FFF7F4'));
    expect(createNoteIcon, contains('#9F5261'));
  });

  test('private profile access action uses unified Lucide SVG icons', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final privateLockIcon = File(
      'assets/settings/private-lock.svg',
    ).readAsStringSync();
    final privateUnlockIcon = File(
      'assets/settings/private-unlock.svg',
    ).readAsStringSync();
    final privateAdminIcon = File(
      'assets/settings/private-admin.svg',
    ).readAsStringSync();

    expect(homePage, contains('class _PrivateProfileAccessIcon'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.locked'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.unlocked'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.admin'));
    expect(homePage, contains('assets/settings/private-lock.svg'));
    expect(homePage, contains('assets/settings/private-unlock.svg'));
    expect(homePage, contains('assets/settings/private-admin.svg'));
    expect(homePage, contains('colorFilter: ColorFilter.mode'));
    expect(homePage, contains('profileAccessPillLabel'));
    expect(homePage, contains('privateProfileActive || adminMode'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.admin'));
    expect(privateLockIcon, contains('lucide-static'));
    expect(privateUnlockIcon, contains('lucide-static'));
    expect(privateAdminIcon, contains('lucide-static'));
    expect(privateLockIcon, contains('stroke-width="1.5"'));
    expect(privateUnlockIcon, contains('stroke-width="1.5"'));
    expect(privateAdminIcon, contains('stroke-width="1.5"'));
  });

  test('support links use distinct Lucide list icons', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final contactIcon = File('assets/settings/contact.svg').readAsStringSync();
    final helpIcon = File('assets/settings/help.svg').readAsStringSync();

    expect(homePage, contains('class _SettingsListIcon'));
    expect(homePage, contains('assets/settings/contact.svg'));
    expect(homePage, contains('assets/settings/help.svg'));
    expect(homePage, isNot(contains('Icons.contact_support_outlined')));
    expect(contactIcon, contains('lucide-static'));
    expect(contactIcon, contains('M2.992 16.342'));
    expect(contactIcon, contains('stroke-width="1.5"'));
    expect(helpIcon, contains('lucide-static'));
    expect(helpIcon, contains('M9.09 9'));
    expect(helpIcon, contains('stroke-width="1.5"'));
    expect(contactIcon, isNot(equals(helpIcon)));
  });

  test('admin mode and note operations are covered by audit logs', () {
    final auditLog = File('lib/app/audit_log.dart').readAsStringSync();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(auditLog, contains('class AuditLogService'));
    expect(auditLog, contains('HiMemo audit log'));
    expect(homeProviders, contains('AuditLogController'));
    expect(homeProviders, contains("'admin_mode_login'"));
    expect(homeProviders, contains("'profile_switch'"));
    expect(homeProviders, contains("'private_profile_unlock'"));
    expect(homeProviders, contains("created ? 'note_create' : 'note_update'"));
    expect(homeProviders, contains("logAudit(\n        'note_delete'"));
    expect(homePage, contains('_buildAuditLogSettingsGroup'));
    expect(homePage, contains('class _AuditLogPreviewLine'));
    expect(homePage, contains("entry.contains('admin_mode_login')"));
    expect(homePage, contains("entry.contains('admin_mode_logout')"));
    expect(homePage, contains('colorScheme.errorContainer'));
    expect(homePage, contains('colorScheme.primaryContainer'));
    expect(homePage, contains('_AdminModeAuditNotice'));
    expect(homePage, contains('Admin mode can view every profile'));
    expect(homePage, contains('管理者モードでは全プロファイル'));
    expect(homePage, contains('診断ログとは別に記録'));
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

  test('soft-deleted notes stay restorable from the trash screen', () {
    final appRouter = File('lib/app/app_router.dart').readAsStringSync();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(appRouter, contains("path: '/trash'"));
    expect(appRouter, contains('TrashScreen'));
    expect(
      homePage,
      contains('AppSection { notes, calendar, insights, trash, settings }'),
    );
    expect(homePage, contains("context.go('/trash')"));
    expect(homePage, contains('class TrashScreen'));
    expect(homePage, contains('class _TrashNoteTile'));
    expect(homePage, contains('deletePermanently(note.id)'));
    expect(homePage, contains('restoreFromTrash(note.id)'));
    expect(homePage, contains('NotesController.trashRetention'));
    expect(
      homeProviders,
      contains('static const trashRetention = Duration(days: 7)'),
    );
    expect(homeProviders, contains('Future<void> restoreFromTrash'));
    expect(homeProviders, contains('Future<void> deletePermanently'));
    expect(homeProviders, contains('Future<int> purgeTrashOlderThan'));
    expect(homeProviders, contains('final trashedNotesProvider'));
    expect(homeProviders, contains("'note_restore'"));
    expect(homeProviders, contains("'note_permanent_delete'"));
    expect(homeProviders, contains("'note_trash_purge'"));
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
    expect(homeProviders, contains('_spotlightSearchTerms'));
    expect(homeProviders, contains("'searchTerms'"));
    expect(homeProviders, contains('bridge.clearNotes();'));
    expect(homePage, contains('memoSpotlightIndexKey'));
    expect(homePage, contains('TargetPlatform.iOS'));
    expect(appDelegate, contains('import CoreSpotlight'));
    expect(appDelegate, contains('spotlightDomainIdentifier'));
    expect(appDelegate, contains('CSSearchableIndex.isIndexingAvailable()'));
    expect(appDelegate, contains('"indexedCount"'));
    expect(appDelegate, contains('CSSearchableItemActionType'));
    expect(appDelegate, contains('.userActivityDictionary'));
    expect(appDelegate, contains('handleSpotlightUserActivity'));
    expect(appDelegate, contains('attributeSet.textContent'));
    expect(appDelegate, contains('attributeSet.displayName'));
    expect(appDelegate, contains('attributeSet.alternateNames'));
    expect(appDelegate, contains('searchTerms'));
    expect(homeProviders, contains("logDiagnostic('spotlight'"));
    expect(homeProviders, contains('replace all requested'));
    expect(app, contains('spotlightNoteOpenRequestControllerProvider'));
  });

  test('AI tag suggestions keep an iOS bridge and local fallback', () {
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(homeProviders, contains('class TagSuggestionRequest'));
    expect(homeProviders, contains('tagSuggestionGatewayProvider'));
    expect(homeProviders, contains('suggestLocalNoteTags'));
    expect(homeProviders, contains('org.ruhenheim.himemo/intelligence'));
    expect(homeProviders, contains("'suggestTags'"));
    expect(homePage, contains('_tagSuggestionsBusy'));
    expect(homePage, contains('_applySuggestedTag'));
    expect(homePage, contains('visibleTagSuggestionsProvider'));
    expect(homePage, contains('Icons.auto_awesome_rounded'));
    expect(appDelegate, contains('intelligenceChannelName'));
    expect(appDelegate, contains('handleIntelligenceMethod'));
    expect(appDelegate, contains('apple_intelligence_unavailable'));
  });

  test('quick capture bypasses app lock auto prompts while active', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();
    final quickCaptureScreen = File(
      'lib/features/home/presentation/widget_quick_capture_screen.dart',
    ).readAsStringSync();

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
    expect(
      quickCaptureScreen.indexOf(
        'ref.read(widgetQuickCaptureRequestControllerProvider.notifier).clear();',
      ),
      lessThan(quickCaptureScreen.indexOf("router.go('/notes');")),
    );
  });

  test('quick capture native and dart paths ignore duplicate requests', () {
    final androidMainActivity = File(
      'android/app/src/main/kotlin/org/ruhenheim/himemo/MainActivity.kt',
    ).readAsStringSync();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();

    expect(androidMainActivity, contains('EXTRA_QUICK_CAPTURE_NONCE'));
    expect(
      androidMainActivity,
      contains('"nonce" to quickCaptureNonce(intent)'),
    );
    expect(
      androidMainActivity,
      contains('consumeQuickCaptureIntent(currentIntent)'),
    );
    expect(androidMainActivity, contains('consumeQuickCaptureIntent(intent)'));
    expect(androidMainActivity, contains('setAction(Intent.ACTION_MAIN)'));
    expect(homeProviders, contains('final Set<String> _seenNonces'));
    expect(homeProviders, contains('!_seenNonces.add(request.nonce)'));
    expect(homeProviders, contains('arguments[\'nonce\']'));
  });

  test('google drive bundle lookup excludes trash and tags new bundles', () {
    final googleDriveTransport = File(
      'lib/features/sync/data/google_drive_sync_transport.dart',
    ).readAsStringSync();

    expect(googleDriveTransport, contains("'kind': 'bundle'"));
    expect(googleDriveTransport, contains('trashed = false and'));
    expect(
      googleDriveTransport,
      contains("appProperties has { key='kind' and value='bundle' }"),
    );
  });

  test('iOS network kind lookup returns asynchronously', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('currentConnectionKind(result: result)'));
    expect(appDelegate, contains('private func currentConnectionKind(result:'));
    expect(appDelegate, contains('queue.asyncAfter(deadline: .now() + 0.8)'));
    expect(appDelegate, isNot(contains('DispatchSemaphore')));
    expect(appDelegate, isNot(contains('wait(timeout:')));
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
    final syncEngine = File(
      'lib/features/sync/data/sync_engine.dart',
    ).readAsStringSync();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();

    expect(homePage, contains('_attachmentByteDiagnosticData'));
    expect(homePage, contains('byteSignature'));
    expect(homePage, contains('detectedImageFormat'));
    expect(homePage, contains("return 'heic';"));
    expect(homePage, contains("return 'jpeg';"));
    expect(syncEngine, contains('class SyncAttachmentMissingException'));
    expect(syncEngine, contains('sync.error.local_attachment_missing'));
    expect(homeProviders, contains('SyncAttachmentMissingException'));
    expect(
      homeProviders,
      contains('upload blocked by missing local attachment'),
    );
  });
}
