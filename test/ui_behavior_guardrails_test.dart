import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _homePresentationSource() => [
  'lib/features/home/presentation/home_page.dart',
  'lib/features/home/presentation/home_settings_screen.dart',
  'lib/features/home/presentation/home_settings_components.dart',
  'lib/features/home/presentation/home_private_profile_settings.dart',
  'lib/features/home/presentation/home_note_content.dart',
  'lib/features/home/presentation/home_sync_support.dart',
  'lib/features/home/presentation/home_media_viewers.dart',
  'lib/features/home/presentation/home_trash_widgets.dart',
  'lib/features/home/presentation/home_sidebar.dart',
  'lib/features/home/presentation/home_note_lists.dart',
  'lib/features/home/presentation/home_note_detail.dart',
  'lib/features/home/presentation/home_calendar_screen.dart',
  'lib/features/home/presentation/home_insights_screen.dart',
  'lib/features/home/presentation/home_notes_screen.dart',
  'lib/features/home/presentation/home_trash_screen.dart',
  'lib/features/home/presentation/home_google_drive_panel.dart',
].map((path) => File(path).readAsStringSync()).join('\n');

void main() {
  test('web video playback stays enabled through the native video element', () {
    final webVideoElement = File(
      'lib/features/home/presentation/web_video_element_view_web.dart',
    ).readAsStringSync();
    final homePage = _homePresentationSource();

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
    final homePage = _homePresentationSource();

    expect(homePage, contains('void _ensureTrailingRichParagraph'));
    expect(homePage, contains('_ensureTrailingRichParagraph(drafts);'));
    expect(homePage, contains('_ensureTrailingRichParagraph(_richBlocks);'));
  });

  test('mobile note editor keeps keyboard footer compact', () {
    final homePage = _homePresentationSource();

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
    expect(homePage, contains('height: _attachmentActionBusy ? 56 : 0'));
  });

  test('notes search field keeps an inline clear action', () {
    final homePage = _homePresentationSource();

    expect(homePage, contains("Key('notes-search-clear-button')"));
    expect(homePage, contains('Icons.clear_rounded'));
    expect(homePage, contains('void _clearSearchQuery()'));
    expect(homePage, contains('_searchController.clear();'));
  });

  test('note detail search stays collapsible and highlights list searches', () {
    final homePage = _homePresentationSource();

    expect(homePage, contains("Key('note-detail-search-button')"));
    expect(homePage, contains("Key('note-detail-search-input')"));
    expect(homePage, contains('note-detail-search-previous-button'));
    expect(homePage, contains('note-detail-search-next-button'));
    expect(homePage, contains('TextInputAction.search'));
    expect(homePage, contains('onSubmitted: (_)'));
    expect(homePage, contains('_jumpDetailSearch'));
    expect(homePage, contains('matchStart'));
    expect(homePage, contains('_noteSearchActiveHighlightStyle'));
    expect(homePage, contains('_noteDetailSearchTargetsForText'));
    expect(homePage, contains('key: _detailTitleKey'));
    expect(homePage, contains('text: note.title'));
    expect(
      homePage,
      contains('_detailSearchVisible = _detailSearchQuery.isNotEmpty;'),
    );
    expect(homePage, contains('_pendingInitialSearchJumpNoteId'));
    expect(homePage, contains('_scheduleInitialDetailSearchJump'));
    expect(homePage, contains('_scheduleDetailSearchTargetVisibilityCheck'));
    expect(homePage, contains('_detailSearchScrollPolicy'));
    expect(homePage, contains('alignment: movingDown ? 0.78 : 0.12'));
    expect(homePage, contains('ScrollPositionAlignmentPolicy.explicit'));
    expect(homePage, contains('position.ensureVisible'));
    expect(homePage, contains('_detailSearchScrollPosition(targetContext)'));
    expect(homePage, contains('_fallbackDetailSearchScroll'));
    expect(
      homePage,
      contains('ScrollPositionAlignmentPolicy.keepVisibleAtEnd'),
    );
    expect(
      homePage,
      contains('ScrollPositionAlignmentPolicy.keepVisibleAtStart'),
    );
    expect(homePage, contains('duration: Duration.zero'));
    expect(homePage, contains('_FloatingNoteSearchNavigator'));
    expect(homePage, contains('_detailSearchNavigatorPinned'));
    expect(homePage, contains('note-detail-search-floating-previous-button'));
    expect(homePage, contains('note-detail-search-floating-next-button'));
    expect(
      homePage,
      contains(
        'final listSearchQuery = ref.watch(searchQueryProvider).trim();',
      ),
    );
    expect(homePage, contains('highlightQuery: highlightQuery'));
    expect(homePage, contains('class _HighlightedInlineText'));
    expect(homePage, contains('List<TextSpan> _highlightTextSpans'));
    expect(homePage, contains("Key('note-detail-delete-button')"));
    expect(homePage, isNot(contains('_NoteDetailAction.delete')));
    expect(homePage, contains("Key('editor-delete-note-button')"));
  });

  test('app lock background privacy cover prevents delayed relock flashes', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();
    final appStrings = File('lib/l10n/app_strings.dart').readAsStringSync();
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
    expect(appShell, contains('strings.unlockWithPinInstruction'));
    expect(appShell, contains('strings.noUnlockMethodConfigured'));
    expect(appShell, contains('strings.authenticating'));
    expect(appShell, contains('strings.localizedPinLockError'));
    expect(appShell, contains('strings.unlockWithDeviceAuthReason'));
    expect(appStrings, contains('String get unlockWithPinInstruction'));
    expect(appStrings, contains('String get noUnlockMethodConfigured'));
    expect(appStrings, contains('String get authenticating'));
    expect(appStrings, contains('String localizedPinLockError'));
    expect(appStrings, contains('String get privateVaultLockedMessage'));
  });

  test('recent daily trend chart starts at the latest day', () {
    final homePage = _homePresentationSource();

    expect(homePage, contains('class _InsightBarChartState'));
    expect(homePage, contains('_scrollController.position.maxScrollExtent'));
    expect(homePage, contains('controller: _scrollController'));
  });

  test('mobile create note action is a centered pen navigation button', () {
    final homePage = _homePresentationSource();
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
    expect(homePage, contains('String bottomNavLabel(String label)'));
    expect(homePage, contains("return '';"));
    expect(homePage, contains('label: bottomNavLabel(strings.notes)'));
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

  test('private profile access action uses Material icons', () {
    final homePage = _homePresentationSource();

    expect(homePage, contains('class _PrivateProfileAccessIcon'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.locked'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.unlocked'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.admin'));
    expect(homePage, contains('Icons.lock_outline'));
    expect(homePage, contains('Icons.lock_open_outlined'));
    expect(homePage, contains('Icons.admin_panel_settings_outlined'));
    expect(homePage, isNot(contains('assets/settings/private-lock.svg')));
    expect(homePage, isNot(contains('assets/settings/private-unlock.svg')));
    expect(homePage, isNot(contains('assets/settings/private-admin.svg')));
    expect(homePage, contains('profileAccessPillLabel'));
    expect(homePage, contains('privateProfileActive || adminMode'));
    expect(homePage, contains('_PrivateProfileAccessIconKind.admin'));
  });

  test('support links use distinct Material list icons', () {
    final homePage = _homePresentationSource();

    expect(homePage, contains('class _SettingsListIcon'));
    expect(homePage, contains('icon: Icons.email_outlined'));
    expect(homePage, contains('icon: Icons.help_outline_outlined'));
    expect(homePage, isNot(contains("assets/settings/contact.svg")));
    expect(homePage, isNot(contains("assets/settings/help.svg")));
  });

  test('admin mode and note operations are covered by audit logs', () {
    final auditLog = File('lib/app/audit_log.dart').readAsStringSync();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final homePage = _homePresentationSource();

    expect(auditLog, contains('class AuditLogService'));
    expect(auditLog, contains('HiMemo audit log'));
    expect(auditLog, contains('static const _maxEntries = 2000'));
    expect(
      auditLog,
      contains('_entries.sublist(_entries.length - _maxEntries)'),
    );
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
    expect(homePage, contains('up to the latest 2,000 entries'));
    expect(homePage, contains('最新2,000件まで保存'));
    expect(
      homePage,
      isNot(contains('recorded separately from diagnostic logs')),
    );
  });

  test('tablet create note action lives at the bottom of the sidebar', () {
    final homePage = _homePresentationSource();

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
    final homePage = _homePresentationSource();

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
    final homePage = _homePresentationSource();
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
    expect(appDelegate, contains('body ?? ""'));
    expect(appDelegate, contains('attributeSet.alternateNames'));
    expect(appDelegate, contains('searchTerms'));
    expect(homeProviders, contains("logDiagnostic('spotlight'"));
    expect(homeProviders, contains('replace all requested'));
    expect(app, contains('spotlightNoteOpenRequestControllerProvider'));
    expect(app, contains('shouldDeferSpotlightOpen'));
    expect(app, contains('appSessionUnlockControllerProvider'));
    expect(app, contains('openSpotlightNoteRequest(pendingSpotlightNoteId)'));
  });

  test('Spotlight indexing warns when app lock is also enabled', () {
    final homePage = _homePresentationSource();

    expect(homePage, contains('showSpotlightAppLockWarning'));
    expect(homePage, contains('spotlightNoteIndexEnabled &&'));
    expect(homePage, contains('appLockEnabled'));
    expect(homePage, contains('_SettingsWarningBox'));
    expect(homePage, contains('_spotlightAppLockWarningText'));
    expect(homePage, contains('_showSpotlightAppLockWarningDialog'));
    expect(homePage, contains('enabled && appLockEnabled'));
    expect(homePage, contains('spotlightNoteIndexEnabled && context.mounted'));
    expect(
      homePage,
      contains('App lock does not hide notes from iOS Spotlight.'),
    );
  });

  test('AI tag suggestions keep an iOS bridge and local fallback', () {
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final homePage = _homePresentationSource();
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
    expect(appDelegate, contains('canImport(FoundationModels)'));
    expect(appDelegate, contains('LanguageModelSession'));
    expect(appDelegate, contains('SystemLanguageModel.default'));
    expect(appDelegate, contains('usedAppleIntelligence'));
    expect(appDelegate, contains('suggestTagsWithFoundationModels'));
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
    final homePage = _homePresentationSource();

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
    final homePage = _homePresentationSource();
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
    final homePage = _homePresentationSource();

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

  test('note editor guards slow attachment saves and video playback', () {
    final homePage = _homePresentationSource();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final videoFactory = File(
      'lib/features/home/presentation/video_player_controller_factory_io.dart',
    ).readAsStringSync();

    expect(homePage, contains('late final String _newNoteId'));
    expect(homePage, contains('id: widget.note?.id ?? _newNoteId'));
    expect(
      homePage,
      contains(
        'if (!_canSave || _saveBusy || _saved || _attachmentActionBusy)',
      ),
    );
    expect(homePage, contains('int _pendingAttachmentPlaceholderCount = 0'));
    expect(homePage, contains('class _AttachmentProcessingPlaceholder'));
    expect(homePage, contains('Preparing attachment'));
    expect(homePage, contains('pendingAttachmentCount'));
    expect(homePage, contains('createLocalVideoController(tempFilePath)'));
    expect(homePage, contains('timeout(const Duration(seconds: 15))'));
    expect(videoFactory, contains('VideoPlayerController.file'));
    expect(homeProviders, contains('_pickIOSPhotoLibraryMedia'));
    expect(
      homeProviders,
      contains('defaultTargetPlatform == TargetPlatform.iOS'),
    );
    expect(homeProviders, contains('picker.pickMultiImage'));
    expect(homeProviders, contains('picker.pickMultiVideo'));
    expect(homeProviders, contains('_deferredVideoPreviewThresholdBytes'));
    expect(homeProviders, contains('video preview deferred for large file'));
    expect(homeProviders, contains('attachment import build completed'));
    final attachmentStore = File(
      'lib/features/security/data/encrypted_attachment_store.dart',
    ).readAsStringSync();
    expect(attachmentStore, contains('_backgroundEncryptionThresholdBytes'));
    expect(attachmentStore, contains('_backgroundDecryptionThresholdChars'));
    expect(attachmentStore, contains('_attachmentBinaryMagic'));
    expect(attachmentStore, contains('_encryptAttachmentPayloadBinary'));
    expect(attachmentStore, contains('_decryptAttachmentPayloadBinary'));
    expect(attachmentStore, contains('file.writeAsBytes(encrypted'));
    expect(attachmentStore, contains('TransferableTypedData'));
    expect(attachmentStore, contains('Isolate.run'));
    expect(attachmentStore, contains('_decryptAttachmentBytesFromStorage'));
    expect(attachmentStore, contains('_decryptAttachmentPayload'));
    expect(attachmentStore, contains('estimateStoredAttachmentPayloadBytes'));
    expect(homePage, contains('_decodeRemoteAttachmentBytes'));
  });

  test('attachment diagnostics include image byte signatures', () {
    final homePage = _homePresentationSource();
    final syncEngine = File(
      'lib/features/sync/data/sync_engine.dart',
    ).readAsStringSync();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();

    expect(homePage, contains('_attachmentByteDiagnosticData'));
    expect(homePage, contains('_logVideoPlaybackDiagnostic'));
    expect(homePage, contains('_videoByteDiagnosticData'));
    expect(homePage, contains('byteSignature'));
    expect(homePage, contains('detectedImageFormat'));
    expect(homePage, contains('detectedVideoBrand'));
    expect(homePage, contains("return 'heic';"));
    expect(homePage, contains("return 'jpeg';"));
    expect(homePage, contains('video playback load requested'));
    expect(homePage, contains('video playback materialized file unavailable'));
    expect(homePage, contains('video playback load failed'));
    expect(homePage, contains('video controller initialized'));
    expect(syncEngine, contains('class SyncAttachmentMissingException'));
    expect(syncEngine, contains('sync.error.local_attachment_missing'));
    expect(homeProviders, contains('SyncAttachmentMissingException'));
    expect(
      homeProviders,
      contains('upload blocked by missing local attachment'),
    );
  });

  test('cloud sync heavy work does not run on the UI isolate', () {
    final syncEngine = File(
      'lib/features/sync/data/sync_engine.dart',
    ).readAsStringSync();
    final secureBundleStore = File(
      'lib/features/sync/data/secure_sync_bundle_store.dart',
    ).readAsStringSync();
    final attachmentStore = File(
      'lib/features/security/data/encrypted_attachment_store.dart',
    ).readAsStringSync();
    final homeProviders = File(
      'lib/features/home/presentation/home_providers.dart',
    ).readAsStringSync();
    final homePage = _homePresentationSource();

    expect(syncEngine, contains('dart:isolate'));
    expect(syncEngine, contains('TransferableTypedData.fromList'));
    expect(syncEngine, contains('Isolate.run'));
    expect(syncEngine, contains('_base64EncodedLength'));
    expect(syncEngine, contains('SyncSnapshotPreparationProgress'));
    expect(syncEngine, contains('estimateStoredAttachmentPayloadBytes'));
    expect(secureBundleStore, contains('dart:isolate'));
    expect(secureBundleStore, contains('_encryptSyncBundleJson'));
    expect(secureBundleStore, contains('_decryptSyncBundleJson'));
    expect(secureBundleStore, contains('Isolate.run'));
    expect(attachmentStore, contains('_decryptAttachmentBytesFromStorage'));
    expect(attachmentStore, contains('_decryptAttachmentPayload'));
    expect(attachmentStore, contains('TransferableTypedData.fromList'));
    expect(homeProviders, contains('Future<void> _yieldToUi()'));
    expect(homeProviders, contains('await _yieldToUi();'));
    expect(homeProviders, contains('_encodeLocalZipArchive'));
    expect(homeProviders, contains('_decodeLocalZipArchive'));
    expect(
      homeProviders,
      contains('_encodeLocalZipArchivePayloadInBackground'),
    );
    expect(
      homeProviders,
      contains('_decodeLocalZipArchivePayloadInBackground'),
    );
    expect(homeProviders, contains('onProgress: (progress) async'));
    expect(homePage, contains('includeUpload: false'));
    expect(homePage, contains('includeDownload: true'));
    expect(homeProviders, contains('detail'));
    expect(homeProviders, contains('completedItems'));
    expect(homeProviders, contains('totalItems'));
    expect(homeProviders, contains('_setProgressDetail'));
    expect(homeProviders, contains('_measureSyncStep'));
    expect(homeProviders, contains('Checking cloud status'));
    expect(homeProviders, contains('_remoteStatusCacheTtl'));
    expect(homeProviders, contains('_fetchLatestRemoteStatusWithCache'));
    expect(homeProviders, contains('remote status cache hit'));
    expect(
      homeProviders,
      contains(r'Requesting latest $providerName metadata'),
    );
    expect(homeProviders, contains('Using recent cloud status'));
    expect(homeProviders, contains('Reading sync history'));
    expect(homeProviders, contains('Checking transfer size'));
    expect(homeProviders, contains('Checking local changes'));
    expect(homeProviders, contains('elapsedMs'));
    expect(homeProviders, contains('_decodeSyncAttachmentBytes'));
    expect(homeProviders, contains('Uploading attachment'));
    expect(homeProviders, contains('Applying attachment'));
    expect(homeProviders, contains('syncAttachmentObjectHashesInNoteJson'));
    final syncAttachmentRefs = File(
      'lib/features/sync/data/sync_attachment_refs.dart',
    ).readAsStringSync();
    expect(syncAttachmentRefs, contains('syncAttachmentObjectRefPrefix'));
    expect(syncAttachmentRefs, contains('syncAttachmentObjectContentHash'));
    expect(syncAttachmentRefs, contains("rawBlock['attachment']"));
    expect(syncEngine, contains('isSyncAttachmentObjectRef'));
    expect(
      homeProviders,
      isNot(contains('math.min(3, pendingUploads.length)')),
    );
    expect(homePage, contains('class _HeaderSyncIndicator'));
    expect(homePage, contains('class _HeaderSyncIndicatorState'));
    expect(homePage, contains('AnimationController'));
    expect(homePage, contains('RotationTransition'));
    expect(homePage, contains('ReverseAnimation(_rotationController)'));
    expect(homePage, contains('Tap to show sync progress'));
    expect(homePage, contains('_showHeaderSyncProgressDialog'));
    expect(homePage, contains('showDialog<void>'));
    expect(homePage, contains('LinearProgressIndicator'));
    expect(homePage, contains('syncTransferControllerProvider'));
    expect(homePage, contains('_syncProgressValueForState'));
    expect(homePage, contains('_syncProgressItemProgressText'));
  });

  test('automatic cloud sync does not loop while idle', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();

    expect(appShell, contains('automatic sync idle without reschedule'));
    expect(
      appShell,
      contains(
        'static const _automaticCloudSyncRemoteMinInterval = Duration(minutes: 10);',
      ),
    );
    expect(appShell, contains('allowCachedRemoteStatus: !hasPendingChanges'));
    expect(appShell, contains('if (remainingPendingChanges)'));
    expect(appShell, contains('_cloudSyncScheduledForLocalChanges = false;'));
    expect(appShell, contains('_cloudSyncRescheduleRequested = false;'));
    expect(appShell, contains('_cloudSyncRescheduleDelay = null;'));
    expect(
      appShell,
      isNot(
        contains(
          "else {\n"
          "          _cloudSyncRescheduleRequested = true;\n"
          "          _cloudSyncRescheduleDelay = _automaticCloudSyncRetryDelay(\n"
          "            hasPendingChanges: false,\n"
          "          );\n"
          "        }",
        ),
      ),
    );
  });
}
