part of 'home_page.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const appLockToggleKey = Key('app-lock-toggle');
  static const appLockRelockImmediateKey = Key('app-lock-relock-immediate');
  static const appLockRelock30SecondsKey = Key('app-lock-relock-30-seconds');
  static const appLockRelock2MinutesKey = Key('app-lock-relock-2-minutes');
  static const appLockRelock10MinutesKey = Key('app-lock-relock-10-minutes');
  static const privateVaultLockOnAppLockKey = Key(
    'private-vault-lock-on-app-lock',
  );
  static const appLockAuthenticateKey = Key('app-lock-authenticate');
  static const appLockLockNowKey = Key('app-lock-lock-now');
  static const lightThemeKey = Key('theme-light-option');
  static const systemThemeKey = Key('theme-system-option');
  static const darkThemeKey = Key('theme-dark-option');
  static const localeDropdownKey = Key('locale-dropdown');
  static const fontDropdownKey = Key('font-dropdown');
  static const localeSystemKey = Key('locale-system-option');
  static const createDemoNotesKey = Key('create-demo-notes-button');
  static const deleteDemoNotesKey = Key('delete-demo-notes-button');
  static const localeJapaneseKey = Key('locale-japanese-option');
  static const localeEnglishKey = Key('locale-english-option');
  static const localeChineseKey = Key('locale-chinese-option');
  static const localeKoreanKey = Key('locale-korean-option');
  static const localeSpanishKey = Key('locale-spanish-option');
  static const localeGermanKey = Key('locale-german-option');
  static const memoQuickDefaultKey = Key('memo-default-quick-option');
  static const memoRichDefaultKey = Key('memo-default-rich-option');
  static const memoStandardListKey = Key('memo-standard-list-option');
  static const memoCompactListKey = Key('memo-compact-list-option');
  static const memoAutoLocationKey = Key('memo-auto-location-toggle');
  static const memoSpotlightIndexKey = Key('memo-spotlight-index-toggle');
  static const konjyoColorThemeKey = Key('color-theme-konjyo-option');
  static const moegiColorThemeKey = Key('color-theme-moegi-option');
  static const yamabukiColorThemeKey = Key('color-theme-yamabuki-option');
  static const syncOffKey = Key('sync-off-option');
  static const syncICloudKey = Key('sync-icloud-option');
  static const syncGoogleDriveKey = Key('sync-google-drive-option');
  static const syncConnectKey = Key('sync-connect-button');
  static const syncDisconnectKey = Key('sync-disconnect-button');
  static const syncNowKey = Key('sync-now-button');
  static const syncRefreshRemoteKey = Key('sync-refresh-remote-button');
  static const syncUploadBundleKey = Key('sync-upload-bundle-button');
  static const syncDownloadBundleKey = Key('sync-download-bundle-button');
  static const syncApplyBundleKey = Key('sync-apply-bundle-button');
  static const syncExclusionTagAddKey = Key('sync-exclusion-tag-add-button');
  static const syncExclusionTagInputKey = Key('sync-exclusion-tag-input');
  static const diagnosticICloudStorageBreakdownKey = Key(
    'diagnostic-icloud-storage-breakdown-button',
  );
  static const diagnosticICloudPruneBundlesKey = Key(
    'diagnostic-icloud-prune-bundles-button',
  );
  static const privateVaultSetKey = Key('private-vault-set-key');
  static const privateVaultUnlockKey = Key('private-vault-unlock-key');
  static const privateVaultLockKey = Key('private-vault-lock-key');
  static const privateVaultResetKey = Key('private-vault-reset-key');
  static const privateProfileAddKey = Key('private-profile-add-key');
  static const privateProfileAdminModeKey = Key(
    'private-profile-admin-mode-key',
  );
  static const privateProfileNameInputKey = Key('private-profile-name-input');
  static const privateProfilePasswordInputKey = Key(
    'private-profile-password-input',
  );
  static const privateProfileConfirmInputKey = Key(
    'private-profile-confirm-input',
  );
  static const privateProfileSubmitKey = Key('private-profile-submit');
  static const privateProfileExitAdminModeKey = Key(
    'private-profile-exit-admin-mode',
  );
  static const privateProfileRenameInputKey = Key(
    'private-profile-rename-input',
  );
  static const privateProfileRenameSubmitKey = Key(
    'private-profile-rename-submit',
  );
  static const startTutorialKey = Key('start-highlight-tutorial');
  static final _appearanceSectionKey = GlobalKey();
  static final _privateProfilesSectionKey = GlobalKey();
  static final _appSecuritySectionKey = GlobalKey();
  static final _syncSectionKey = GlobalKey();
  static final _appearanceController = ExpansibleController();
  static final _privateProfilesController = ExpansibleController();
  static final _appSecurityController = ExpansibleController();
  static final _syncController = ExpansibleController();
  static final List<DateTime> _diagnosticModeTapTimes = <DateTime>[];

  Future<void> _handleVersionTap(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final now = DateTime.now();
    _diagnosticModeTapTimes.removeWhere(
      (tap) => now.difference(tap) > const Duration(seconds: 5),
    );
    _diagnosticModeTapTimes.add(now);
    if (_diagnosticModeTapTimes.length < 5) {
      return;
    }
    _diagnosticModeTapTimes.clear();
    final enabled = await ref
        .read(diagnosticLogControllerProvider.notifier)
        .toggleEnabled();
    if (!context.mounted) {
      return;
    }
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.localized(
              en: 'Diagnostic logging is disabled.',
              ja: '診断ログモードを無効化しました。',
              zh: '已停用诊断日志模式。',
              ko: '진단 로그 모드를 껐습니다.',
              es: 'Se desactivo el registro de diagnostico.',
              de: 'Diagnoseprotokollierung ist deaktiviert.',
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Diagnostic logging is enabled.',
            ja: '診断ログモードを有効化しました。',
            zh: '已启用诊断日志模式。',
            ko: '진단 로그 모드를 켰습니다.',
            es: 'Se activo el registro de diagnostico.',
            de: 'Diagnoseprotokollierung ist aktiviert.',
          ),
        ),
      ),
    );
  }

  Future<void> _switchIdentity(WidgetRef ref, String identityId) async {
    await ref.read(activeIdentityProvider.notifier).switchTo(identityId);
    if (identityId != 'private') {
      ref.read(privateVaultSessionControllerProvider.notifier).lock();
    }
  }

  Future<void> _showSetCoverKeyDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secret = await _showSecretSetupDialog(
      context,
      title: strings.setAlternateProfilePassword,
      label: strings.text('home.alternate.profile.password'),
      confirmLabel: strings.text('home.confirm.alternate.profile.password'),
      helperText: strings.text(
        'home.use.this.password.to.switch.to.a.different.everyday.prof',
      ),
    );
    if (secret == null) {
      return;
    }
    await ref
        .read(coverModeSecretControllerProvider.notifier)
        .configure(secret);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(strings.text('home.alternate.profile.password.saved')),
        ),
      );
    }
  }

  Future<void> _confirmResetCoverKey(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.resetAlternateProfilePassword),
        content: Text(
          strings.text(
            'home.this.removes.the.configured.password.for.the.alternate.p',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text('home.reset')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(coverModeSecretControllerProvider.notifier).clear();
    if (ref.read(activeIdentityProvider) == 'cover') {
      await _switchIdentity(ref, 'daily');
    }
  }

  Future<void> _showSpecialAccessKeyDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secret = await _showSingleSecretPrompt(
      context,
      title: strings.text('home.enter.special.access.key'),
      label: strings.accessKey,
      helperText: strings.specialAccessKeyHelp,
      actionLabel: strings.unlockMode,
    );
    if (secret == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (await ref
        .read(privateVaultSecretControllerProvider.notifier)
        .verify(secret)) {
      await _switchIdentity(ref, 'private');
      messenger.showSnackBar(
        SnackBar(showCloseIcon: true, content: Text(strings.privateModeActive)),
      );
      return;
    }
    if (await ref
        .read(coverModeSecretControllerProvider.notifier)
        .verify(secret)) {
      await _switchIdentity(ref, 'cover');
      messenger.showSnackBar(
        SnackBar(showCloseIcon: true, content: Text(strings.coverModeActive)),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text(strings.accessKeyNoMatch)),
    );
  }

  Future<void> _showAddPrivateProfileDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final draft = await showDialog<_PrivateProfileDraft>(
      context: context,
      builder: (_) => const _AddPrivateProfileDialog(),
    );
    if (draft == null) {
      return;
    }
    final error = await ref
        .read(privateMemoProfilesControllerProvider.notifier)
        .addProfile(name: draft.name, password: draft.password);
    if (error == null) {
      await ref
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword(draft.password);
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          error ?? (strings.text('home.private.profile.added.and.opened')),
        ),
      ),
    );
  }

  Future<void> _enterAdminMode(BuildContext context, WidgetRef ref) async {
    final strings = context.strings;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.text(
              'home.admin.mode.is.not.available.in.this.environment',
            ),
          ),
        ),
      );
      return;
    }
    final authenticated = await ref
        .read(deviceAuthControllerProvider.notifier)
        .authenticate(reason: 'Enter admin mode to manage private profiles');
    if (!authenticated || !context.mounted) {
      return;
    }
    ref.read(adminModeSessionControllerProvider.notifier).unlock();
    ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.text(
            'home.admin.mode.unlocked.profile.names.and.vault.ids.remain.h',
          ),
        ),
      ),
    );
  }

  Future<void> _showChangeCurrentProfilePasswordDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final unlockedVaultId = ref.read(unlockedPrivateProfileVaultIdProvider);
    if (unlockedVaultId == null ||
        !unlockedVaultId.startsWith(customPrivateVaultPrefix)) {
      return;
    }
    final profileId = unlockedVaultId.substring(
      customPrivateVaultPrefix.length,
    );
    final password = await _showSecretSetupDialog(
      context,
      title: strings.text('home.change.current.profile.password'),
      label: strings.text('home.new.password'),
      confirmLabel: strings.text('home.confirm.new.password'),
      helperText: strings.text(
        'home.update.the.password.used.to.unlock.this.profile',
      ),
    );
    if (password == null) {
      return;
    }
    await ref
        .read(privateMemoProfilesControllerProvider.notifier)
        .updateProfilePassword(id: profileId, password: password);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(strings.text('home.profile.password.updated')),
      ),
    );
  }

  Future<void> _showRenamePrivateProfileDialog(
    BuildContext context,
    WidgetRef ref,
    PrivateMemoProfile profile,
  ) async {
    final strings = context.strings;
    final nextName = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePrivateProfileDialog(initialName: profile.name),
    );
    if (nextName == null || nextName == profile.name) {
      return;
    }
    await ref
        .read(privateMemoProfilesControllerProvider.notifier)
        .renameProfile(id: profile.id, name: nextName);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(en: 'Profile renamed.', ja: 'プロファイル名を変更しました。'),
        ),
      ),
    );
  }

  void _enterPrivateProfileFromAdmin(
    BuildContext context,
    WidgetRef ref,
    PrivateMemoProfile profile,
  ) {
    final strings = context.strings;
    ref
        .read(searchFiltersControllerProvider.notifier)
        .setVault(profile.vaultId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Showing ${profile.name}. Admin mode remains active.',
            ja: '${profile.name} を表示しています。管理者モードは継続中です。',
          ),
        ),
      ),
    );
    logAudit(
      'admin_mode_enter_private_profile',
      data: {'vaultId': profile.vaultId},
    );
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = context.strings;
    try {
      final confirmed = await _confirmLargeMobileSyncIfNeeded(
        context,
        ref,
        includeUpload: true,
        includeDownload: true,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      await ref
          .read(syncTransferControllerProvider.notifier)
          .syncNow(allowLargeMobileTransfer: true);
      if (!context.mounted) {
        return;
      }
      final message = _cloudSyncSnackBarMessage(
        strings,
        ref.read(syncTransferControllerProvider),
        _CloudSyncSnackBarAction.syncNow,
        ref.read(syncProviderControllerProvider),
      );
      messenger.showSnackBar(
        SnackBar(showCloseIcon: true, content: Text(message)),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(showCloseIcon: true, content: Text('$error')),
      );
    }
  }

  Future<bool> _confirmLargeMobileSyncIfNeeded(
    BuildContext context,
    WidgetRef ref, {
    required bool includeUpload,
    required bool includeDownload,
    bool estimateAllLocalNotes = false,
  }) async {
    final warning = await ref
        .read(syncTransferControllerProvider.notifier)
        .largeMobileTransferWarning(
          includeUpload: includeUpload,
          includeDownload: includeDownload,
          estimateAllLocalNotes: estimateAllLocalNotes,
        );
    if (warning == null) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    return await _showLargeMobileSyncConfirmDialog(context, warning) ?? false;
  }

  void _openSettingsSection(
    BuildContext context,
    ExpansibleController controller,
    GlobalKey key,
  ) {
    controller.expand();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 360), () {
        if (context.mounted) {
          _scrollToSettingsSection(key);
        }
      }),
    );
  }

  void _scrollToSettingsSection(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) {
      return;
    }
    final scrollable = Scrollable.maybeOf(targetContext);
    final targetObject = targetContext.findRenderObject();
    final scrollObject = scrollable?.context.findRenderObject();
    if (scrollable == null ||
        targetObject is! RenderBox ||
        scrollObject is! RenderBox) {
      return;
    }
    final position = scrollable.position;
    final targetOffset = targetObject
        .localToGlobal(Offset.zero, ancestor: scrollObject)
        .dy;
    final nextOffset =
        position.pixels + targetOffset - position.viewportDimension * 0.04;
    final clampedOffset = nextOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    unawaited(
      position.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final activeIdentity = ref.watch(activeIdentityProvider);
    final activeThemeMode = ref.watch(effectiveThemeModeProvider);
    final activeColorTheme = ref.watch(effectiveAppColorThemeProvider);
    final activeColorThemeScope = ref.watch(activeColorThemeScopeProvider);
    final colorThemeSettingsScope = ref.watch(colorThemeSettingsScopeProvider);
    final defaultThemeMode = ref.watch(themeModeControllerProvider);
    final defaultColorTheme = ref.watch(appColorThemeControllerProvider);
    final profileThemeModes = ref.watch(profileThemeModeControllerProvider);
    final profileColorThemes = ref.watch(profileColorThemeControllerProvider);
    final defaultFontFamily = ref.watch(appFontFamilyControllerProvider);
    final profileFontFamilies = ref.watch(profileFontFamilyControllerProvider);
    final defaultLocaleSetting = ref.watch(appLocaleControllerProvider);
    final profileLocales = ref.watch(profileLocaleControllerProvider);
    final activeFontFamily = ref.watch(effectiveAppFontFamilyProvider);
    final activeLocaleSetting = ref.watch(effectiveAppLocaleProvider);
    final appLockEnabled = ref.watch(appLockSettingsControllerProvider);
    final appLockRelockDelay = ref.watch(appLockRelockDelayControllerProvider);
    final appSessionUnlocked = ref.watch(appSessionUnlockControllerProvider);
    final lastNoteEditorSettings = ref.watch(
      lastNoteEditorSettingsControllerProvider,
    );
    final spotlightNoteIndexEnabled = ref.watch(
      spotlightNoteIndexEnabledControllerProvider,
    );
    final showSpotlightAppLockWarning =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        spotlightNoteIndexEnabled &&
        appLockEnabled;
    final notesListDensity = ref.watch(notesListDensityControllerProvider);
    final attachmentPreviewFit = ref.watch(
      attachmentPreviewFitControllerProvider,
    );
    final videoPlaybackMutedByDefault = ref.watch(
      videoPlaybackMutedByDefaultControllerProvider,
    );
    final notesListSortField = ref.watch(notesListSortControllerProvider);
    final widgetQuickCaptureEnabled = ref.watch(
      widgetQuickCaptureSettingsControllerProvider,
    );
    final deviceAuthState = ref.watch(deviceAuthControllerProvider);
    final pinLockState = ref.watch(appPinLockControllerProvider);
    final canUseDeviceAuth = !kIsWeb && deviceAuthState.isAvailable;
    final usePinAppLock = kIsWeb || !canUseDeviceAuth;
    final privateVaultConfigured = ref.watch(
      privateVaultSecretControllerProvider,
    );
    final coverModeConfigured = ref.watch(coverModeSecretControllerProvider);
    final privateVaultUnlocked = ref.watch(
      privateVaultSessionControllerProvider,
    );
    final adminMode = ref.watch(adminModeSessionControllerProvider);
    final privateProfiles = ref.watch(privateMemoProfilesProvider);
    final unlockedPrivateProfileVaultId = ref.watch(
      unlockedPrivateProfileVaultIdProvider,
    );
    final activePrivateProfileLabel = ref.watch(
      activePrivateProfileLabelProvider,
    );
    final privateVaultLockOnAppLock = ref.watch(
      privateVaultLockOnAppLockControllerProvider,
    );
    final syncProvider = ref.watch(syncProviderControllerProvider);
    final syncAuthState = ref.watch(selectedSyncAuthStateProvider);
    final syncQueueSummary = ref.watch(syncQueueSummaryProvider);
    final syncHistory = ref.watch(syncHistoryProvider);
    final syncTransferState = ref.watch(syncTransferControllerProvider);
    final syncBundleFingerprint = ref.watch(syncBundleFingerprintProvider);
    final syncBundleState = ref.watch(syncBundleStateProvider);
    final syncConflictWarning = ref.watch(syncConflictWarningProvider);
    final syncExclusionTags = ref.watch(syncExclusionTagsControllerProvider);
    final inAppUpdateState = ref.watch(inAppUpdateControllerProvider);
    final packageInfo = ref.watch(packageInfoProvider);
    final currentReleaseNote = ref.watch(currentReleaseNoteProvider);
    final releaseNotes = ref.watch(releaseNotesProvider);
    final diagnosticLog = ref.watch(diagnosticLogControllerProvider);
    final auditLog = ref.watch(auditLogControllerProvider);
    final storageUsageSummary = ref.watch(storageUsageSummaryProvider);
    const showLegacyAccessSettings = bool.fromEnvironment(
      'HIMEMO_SHOW_LEGACY_ACCESS_SETTINGS',
    );
    const showLegacyPrivateVaultSettings = bool.fromEnvironment(
      'HIMEMO_SHOW_LEGACY_PRIVATE_VAULT_SETTINGS',
    );
    final flavorName =
        FlavorConfig.instance.variables['flavor'] as String? ?? 'development';
    final showFlavorInfo = flavorName != 'production';
    final displayName =
        FlavorConfig.instance.variables['displayName'] as String? ?? 'HiMemo';
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final visibleStorageVaultIds = {
      for (final vault in visibleVaults) vault.id,
    };
    final currentNotes = ref.watch(notesControllerProvider);
    final conflictedNotes = currentNotes
        .where((note) => note.syncState == NoteSyncState.conflict)
        .toList(growable: false);
    final noteCount = currentNotes
        .where(
          (note) =>
              note.deletedAt == null &&
              visibleStorageVaultIds.contains(note.vaultId) &&
              !isGeneratedSampleNote(note),
        )
        .length;
    final demoNoteCount = currentNotes
        .where((note) => note.deletedAt == null && isGeneratedSampleNote(note))
        .length;
    final currentModeLabel = activeIdentity == 'daily'
        ? (strings.text('home.normal.memo.mode'))
        : ref.watch(activeIdentityDataProvider).name;
    final currentProfileLabel = adminMode
        ? strings.adminModeActiveLabel
        : (activePrivateProfileLabel ??
              strings.localized(
                en: 'Normal notes',
                ja: '通常メモ',
                zh: '普通备忘录',
                ko: '일반 메모',
                es: 'Notas normales',
                de: 'Normale Notizen',
              ));
    final currentProfileIcon = adminMode
        ? Icons.admin_panel_settings_outlined
        : (activePrivateProfileLabel != null
              ? Icons.lock_open_outlined
              : Icons.lock_outline);
    final lockSummary = !appLockEnabled
        ? (strings.text(
            'home.off.turning.this.on.asks.for.a.password.or.device.authen',
          ))
        : (appSessionUnlocked
              ? (strings.text('home.on.this.session.is.unlocked'))
              : (strings.text('home.on.this.session.is.locked')));
    final syncSummary = syncProvider == SyncProvider.off
        ? (strings.text('home.device.only.storage'))
        : _syncAuthSummary(context, syncProvider, syncAuthState);
    final memoEditorModeLabel =
        lastNoteEditorSettings.mode == NoteEditorMode.quick
        ? strings.quickMemo
        : strings.richMemo;
    final memoListDensityLabel = notesListDensity == NotesListDensity.compact
        ? strings.text('home.compact.list')
        : strings.text('home.standard.list');
    final memoLocationLabel = lastNoteEditorSettings.captureLocation
        ? strings.text('home.enabled')
        : strings.text('home.disabled');
    final memoSettingsSummary = strings.localized(
      en: '$memoEditorModeLabel / $memoListDensityLabel / Location: $memoLocationLabel',
      ja: '$memoEditorModeLabel / $memoListDensityLabel / 現在地: $memoLocationLabel',
      zh: '$memoEditorModeLabel / $memoListDensityLabel / 位置：$memoLocationLabel',
      ko: '$memoEditorModeLabel / $memoListDensityLabel / 위치: $memoLocationLabel',
      es: '$memoEditorModeLabel / $memoListDensityLabel / Ubicación: $memoLocationLabel',
      de: '$memoEditorModeLabel / $memoListDensityLabel / Standort: $memoLocationLabel',
    );
    final effectiveFontFamily =
        _availableFontFamilies.contains(activeFontFamily)
        ? activeFontFamily
        : AppFontFamily.system;
    final appearanceSummary = strings.appearanceSummary(
      language: _localeSettingLabel(context, activeLocaleSetting),
      theme: _themeModeLabel(context, activeThemeMode),
      font: _fontFamilyLabel(context, effectiveFontFamily),
      color: _colorThemeLabel(context, activeColorTheme),
    );
    final colorThemeTargets = [
      _ColorThemeScopeOption(
        scope: defaultColorThemeScope,
        label: strings.text('home.normal.memo.mode'),
      ),
      if (unlockedPrivateProfileVaultId != null &&
          activeColorThemeScope != defaultColorThemeScope)
        _ColorThemeScopeOption(
          scope: activeColorThemeScope,
          label:
              activePrivateProfileLabel ?? strings.text('home.private.profile'),
        ),
    ];
    final resolvedColorThemeScope =
        colorThemeTargets.any(
          (target) => target.scope == colorThemeSettingsScope,
        )
        ? colorThemeSettingsScope
        : (colorThemeTargets.any(
                (target) => target.scope == activeColorThemeScope,
              )
              ? activeColorThemeScope
              : defaultColorThemeScope);
    final colorThemeTargetLabel = colorThemeTargets
        .firstWhere(
          (target) => target.scope == resolvedColorThemeScope,
          orElse: () => colorThemeTargets.first,
        )
        .label;
    final selectedColorTheme = resolvedColorThemeScope == defaultColorThemeScope
        ? defaultColorTheme
        : (profileColorThemes[resolvedColorThemeScope] ?? defaultColorTheme);
    final selectedThemeMode = resolvedColorThemeScope == defaultColorThemeScope
        ? defaultThemeMode
        : (profileThemeModes[resolvedColorThemeScope] ?? defaultThemeMode);
    final selectedFontFamily = resolvedColorThemeScope == defaultColorThemeScope
        ? defaultFontFamily
        : (profileFontFamilies[resolvedColorThemeScope] ?? defaultFontFamily);
    final selectedLocaleSetting =
        resolvedColorThemeScope == defaultColorThemeScope
        ? defaultLocaleSetting
        : (profileLocales[resolvedColorThemeScope] ?? defaultLocaleSetting);
    final aboutVersion = packageInfo.when(
      data: (info) => info.displayVersion,
      loading: strings.readingVersion,
      error: (_, _) => '1.0.0 (1)',
    );
    final aboutSummary = showFlavorInfo
        ? '$aboutVersion / $_appAuthor / $displayName'
        : '$aboutVersion / $_appAuthor';
    final appUpdatesSupported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final appUpdatesDescription = appUpdatesSupported
        ? strings.appUpdatesDesc
        : _appUpdatesUnavailableDescription(strings);
    final diagnosticLogSnapshot = diagnosticLog.asData?.value;
    final auditLogSnapshot = auditLog.asData?.value;
    final inAppUpdateSummary = switch (inAppUpdateState.stage) {
      InAppUpdateStage.checking => strings.updateStatusChecking,
      InAppUpdateStage.ready => strings.updateStatusAvailable,
      InAppUpdateStage.completed =>
        inAppUpdateState.status?.updateAvailable == true
            ? strings.updateStatusStarted
            : strings.updateStatusUpToDate,
      InAppUpdateStage.unsupported => appUpdatesDescription,
      InAppUpdateStage.error =>
        inAppUpdateState.message ?? strings.updateStatusUnsupported,
      _ =>
        inAppUpdateState.status?.updateAvailable == true
            ? strings.updateStatusAvailable
            : appUpdatesDescription,
    };

    return ListView(
      cacheExtent: 6000,
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsOverviewCard(
          items: [
            _SettingsOverviewItem(
              label: strings.localized(
                en: 'Profile',
                ja: 'プロファイル',
                zh: '配置文件',
                ko: '프로필',
                es: 'Perfil',
                de: 'Profil',
              ),
              value: currentProfileLabel,
              icon: currentProfileIcon,
              onTap: () => _openSettingsSection(
                context,
                _privateProfilesController,
                _privateProfilesSectionKey,
              ),
            ),
            _SettingsOverviewItem(
              label: strings.localized(
                en: 'App lock',
                ja: 'アプリ保護',
                zh: '应用锁',
                ko: '앱 잠금',
                es: 'Bloqueo de app',
                de: 'App-Sperre',
              ),
              value: appLockEnabled
                  ? (strings.text('home.enabled'))
                  : (strings.text('home.disabled')),
              icon: Icons.enhanced_encryption_outlined,
              onTap: () => _openSettingsSection(
                context,
                _appSecurityController,
                _appSecuritySectionKey,
              ),
            ),
            _SettingsOverviewItem(
              label: strings.syncLabel,
              value: syncProvider == SyncProvider.off
                  ? (strings.text('home.off'))
                  : (strings.text('home.configured')),
              icon: Icons.sync_outlined,
              onTap: () => _openSettingsSection(
                context,
                _syncController,
                _syncSectionKey,
              ),
            ),
            _SettingsOverviewItem(
              label: strings.text('home.theme'),
              value: _themeModeLabel(context, activeThemeMode),
              icon: Icons.palette_outlined,
              onTap: () => _openSettingsSection(
                context,
                _appearanceController,
                _appearanceSectionKey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildAppearanceSettingsGroup(
          context: context,
          ref: ref,
          strings: strings,
          localeSetting: selectedLocaleSetting,
          themeMode: selectedThemeMode,
          fontFamily: selectedFontFamily,
          colorTheme: selectedColorTheme,
          appearanceScope: resolvedColorThemeScope,
          appearanceScopeTargets: colorThemeTargets,
          appearanceScopeLabel: colorThemeTargetLabel,
          appearanceSummary: appearanceSummary,
          sectionKey: _appearanceSectionKey,
          controller: _appearanceController,
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.localized(
            en: 'Memo settings',
            ja: 'メモ設定',
            zh: '备忘录设置',
            ko: '메모 설정',
            es: 'Ajustes de notas',
            de: 'Notiz-Einstellungen',
          ),
          summary: memoSettingsSummary,
          icon: Icons.edit_note_outlined,
          semanticLabel: 'settings-memo',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(
                strings.localized(
                  en: 'Trash',
                  ja: 'ゴミ箱',
                  zh: '废纸篓',
                  ko: '휴지통',
                  es: 'Papelera',
                  de: 'Papierkorb',
                ),
              ),
              subtitle: Text(
                strings.localized(
                  en: 'Deleted notes are kept for 7 days before permanent deletion.',
                  ja: '削除したメモは7日間保持され、その後完全に削除されます。',
                  zh: '已删除的备忘录会保留 7 天，然后永久删除。',
                  ko: '삭제한 메모는 7일 동안 보관된 뒤 완전히 삭제됩니다.',
                  es: 'Las notas eliminadas se conservan 7 dias antes de borrarse definitivamente.',
                  de: 'Geloeschte Notizen bleiben 7 Tage erhalten und werden danach endgueltig geloescht.',
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go('/trash'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sell_outlined),
              title: Text(
                strings.localized(
                  en: 'Tags',
                  ja: '\u30bf\u30b0',
                  zh: '\u6807\u7b7e',
                  ko: '\ud0dc\uadf8',
                  es: 'Etiquetas',
                  de: 'Tags',
                ),
              ),
              subtitle: Text(
                strings.localized(
                  en: 'Review, rename, and delete memo tags.',
                  ja: '\u30e1\u30e2\u306e\u30bf\u30b0\u3092\u4e00\u89a7\u30fb\u30ea\u30cd\u30fc\u30e0\u30fb\u524a\u9664\u3057\u307e\u3059\u3002',
                  zh: '\u67e5\u770b\u3001\u91cd\u547d\u540d\u548c\u5220\u9664\u7b14\u8bb0\u6807\u7b7e\u3002',
                  ko: '\uba54\ubaa8 \ud0dc\uadf8\ub97c \ubcf4\uace0 \uc774\ub984\uc744 \ubc14\uafb8\uac70\ub098 \uc0ad\uc81c\ud569\ub2c8\ub2e4.',
                  es: 'Revisa, renombra y elimina etiquetas de notas.',
                  de: 'Notiz-Tags ansehen, umbenennen und loeschen.',
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go('/tags'),
            ),
            const SizedBox(height: 8),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
              SwitchListTile.adaptive(
                key: memoSpotlightIndexKey,
                value: spotlightNoteIndexEnabled,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  strings.localized(
                    en: 'Show standard notes in Spotlight',
                    ja: '標準メモをSpotlight検索に表示',
                    zh: '在 Spotlight 中显示标准笔记',
                    ko: '표준 메모를 Spotlight 검색에 표시',
                    es: 'Mostrar notas estandar en Spotlight',
                    de: 'Standardnotizen in Spotlight anzeigen',
                  ),
                ),
                subtitle: Text(
                  strings.localized(
                    en: 'When enabled, only normal Notes are indexed on this device. Turning it off removes HiMemo notes from Spotlight.',
                    ja: 'オンにすると、この端末の通常のノートだけを検索対象にします。オフにするとHiMemoのメモをSpotlightから削除します。',
                    zh: '开启后，仅在此设备上索引普通笔记。关闭后会从 Spotlight 中移除 HiMemo 笔记。',
                    ko: '켜면 이 기기의 일반 노트만 인덱싱합니다. 끄면 Spotlight에서 HiMemo 메모를 제거합니다.',
                    es: 'Al activarlo, solo se indexan las notas normales en este dispositivo. Al desactivarlo, se quitan las notas de HiMemo de Spotlight.',
                    de: 'Wenn aktiviert, werden nur normale Notizen auf diesem Geraet indexiert. Beim Deaktivieren entfernt HiMemo seine Notizen aus Spotlight.',
                  ),
                ),
                onChanged: (enabled) async {
                  await ref
                      .read(
                        spotlightNoteIndexEnabledControllerProvider.notifier,
                      )
                      .setEnabled(enabled);
                  if (enabled && appLockEnabled && context.mounted) {
                    await _showSpotlightAppLockWarningDialog(context, strings);
                  }
                },
              ),
              if (showSpotlightAppLockWarning) ...[
                _SettingsWarningBox(
                  text: _spotlightAppLockWarningText(strings),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
            ],
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'Default input',
                ja: '入力の既定',
                zh: '默认输入',
                ko: '기본 입력',
                es: 'Entrada predeterminada',
                de: 'Standardeingabe',
              ),
            ),
            _ThemeOptionTile(
              tileKey: memoQuickDefaultKey,
              title: strings.quickMemo,
              subtitle: strings.localized(
                en: 'Start new notes with the simple first-line memo editor.',
                ja: '新規メモを1行目タイトルのシンプル入力で開始します。',
                zh: '新建备忘录时使用首行作为标题的简单输入。',
                ko: '새 메모를 첫 줄 제목 방식의 간단 입력으로 시작합니다.',
                es: 'Inicia las notas nuevas con el editor simple de primera línea.',
                de: 'Neue Notizen starten mit dem einfachen Editor, bei dem die erste Zeile der Titel ist.',
              ),
              selected: lastNoteEditorSettings.mode == NoteEditorMode.quick,
              onTap: () => ref
                  .read(lastNoteEditorSettingsControllerProvider.notifier)
                  .remember(
                    mode: NoteEditorMode.quick,
                    vaultId: lastNoteEditorSettings.vaultId,
                    captureLocation: lastNoteEditorSettings.captureLocation,
                  ),
            ),
            _ThemeOptionTile(
              tileKey: memoRichDefaultKey,
              title: strings.richMemo,
              subtitle: strings.localized(
                en: 'Start new notes with block-style text and media editing.',
                ja: '新規メモを本文ブロックとメディアを扱える入力で開始します。',
                zh: '新建备忘录时使用支持文本块和媒体的编辑器。',
                ko: '새 메모를 텍스트 블록과 미디어 편집으로 시작합니다.',
                es: 'Inicia las notas nuevas con edición por bloques de texto y medios.',
                de: 'Neue Notizen starten mit blockbasierter Text- und Medienbearbeitung.',
              ),
              selected: lastNoteEditorSettings.mode == NoteEditorMode.rich,
              onTap: () => ref
                  .read(lastNoteEditorSettingsControllerProvider.notifier)
                  .remember(
                    mode: NoteEditorMode.rich,
                    vaultId: lastNoteEditorSettings.vaultId,
                    captureLocation: lastNoteEditorSettings.captureLocation,
                  ),
            ),
            const SizedBox(height: 8),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'List display',
                ja: '一覧表示',
                zh: '列表显示',
                ko: '목록 표시',
                es: 'Vista de lista',
                de: 'Listenansicht',
              ),
            ),
            _ThemeOptionTile(
              tileKey: memoStandardListKey,
              title: strings.text('home.standard.list'),
              subtitle: strings.localized(
                en: 'Show two-line previews and more context in the note list.',
                ja: 'ノート一覧に2行プレビューを表示し、内容を把握しやすくします。',
                zh: '在列表中显示两行预览，便于查看内容。',
                ko: '목록에 두 줄 미리보기를 표시해 내용을 더 쉽게 확인합니다.',
                es: 'Muestra vistas previas de dos líneas y más contexto en la lista.',
                de: 'Zeigt zweizeilige Vorschauen und mehr Kontext in der Notizliste.',
              ),
              selected: notesListDensity == NotesListDensity.standard,
              onTap: () => ref
                  .read(notesListDensityControllerProvider.notifier)
                  .setDensity(NotesListDensity.standard),
            ),
            _ThemeOptionTile(
              tileKey: memoCompactListKey,
              title: strings.text('home.compact.list'),
              subtitle: strings.localized(
                en: 'Fit more notes on screen with a denser one-line list.',
                ja: '1行中心の密な一覧にして、画面に多くのメモを表示します。',
                zh: '使用更紧凑的单行列表，在屏幕上显示更多备忘录。',
                ko: '한 줄 중심의 촘촘한 목록으로 더 많은 메모를 표시합니다.',
                es: 'Muestra más notas en pantalla con una lista densa de una línea.',
                de: 'Zeigt mehr Notizen auf dem Bildschirm mit einer dichteren einzeiligen Liste.',
              ),
              selected: notesListDensity == NotesListDensity.compact,
              onTap: () => ref
                  .read(notesListDensityControllerProvider.notifier)
                  .setDensity(NotesListDensity.compact),
            ),
            const SizedBox(height: 8),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'Note list attachment preview',
                ja: 'ノート一覧の添付プレビュー',
                zh: '笔记列表附件预览',
                ko: '노트 목록 첨부 미리보기',
                es: 'Vista previa de adjuntos en la lista',
                de: 'Anhangsvorschau in der Notizliste',
              ),
            ),
            _ThemeOptionTile(
              title: strings.localized(
                en: 'Show thumbnails',
                ja: 'サムネイルを表示',
                zh: '显示缩略图',
                ko: '썸네일 표시',
                es: 'Mostrar miniaturas',
                de: 'Miniaturen anzeigen',
              ),
              subtitle: strings.localized(
                en: 'Show photo and video thumbnails in the note list.',
                ja: 'ノート一覧に写真や動画のサムネイルを表示します。',
                zh: '在笔记列表中显示照片和视频缩略图。',
                ko: '노트 목록에 사진과 동영상 썸네일을 표시합니다.',
                es: 'Muestra miniaturas de fotos y videos en la lista de notas.',
                de: 'Zeigt Foto- und Videominiaturen in der Notizliste.',
              ),
              selected: attachmentPreviewFit == AttachmentPreviewFit.preview,
              onTap: () => ref
                  .read(attachmentPreviewFitControllerProvider.notifier)
                  .setFit(AttachmentPreviewFit.preview),
            ),
            _ThemeOptionTile(
              title: strings.localized(
                en: 'Show icons',
                ja: 'アイコンで表示',
                zh: '仅显示图标',
                ko: '아이콘만 표시',
                es: 'Solo iconos',
                de: 'Nur Symbole',
              ),
              subtitle: strings.localized(
                en: 'Do not show image thumbnails in the note list; use attachment type icons instead.',
                ja: 'ノート一覧では画像サムネイルを表示せず、添付種別のアイコンに置き換えます。',
                zh: '笔记列表中不显示图片缩略图，改用附件类型图标。',
                ko: '노트 목록에서 이미지 썸네일 대신 첨부 유형 아이콘을 표시합니다.',
                es: 'No muestra miniaturas en la lista de notas; usa iconos del tipo de adjunto.',
                de: 'Zeigt in der Notizliste keine Bildminiaturen, sondern Symbole fuer den Anhangstyp.',
              ),
              selected: attachmentPreviewFit == AttachmentPreviewFit.icon,
              onTap: () => ref
                  .read(attachmentPreviewFitControllerProvider.notifier)
                  .setFit(AttachmentPreviewFit.icon),
            ),
            const SizedBox(height: 8),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'Sort order',
                ja: '表示順',
                zh: '排序',
                ko: '정렬',
                es: 'Orden',
                de: 'Sortierung',
              ),
            ),
            _ThemeOptionTile(
              title: _notesListSortLabel(strings, NotesListSortField.updatedAt),
              subtitle: strings.localized(
                en: 'Show recently edited notes first.',
                ja: '最近変更したメモを上に表示します。',
                zh: '优先显示最近编辑的笔记。',
                ko: '최근 수정한 메모를 먼저 표시합니다.',
                es: 'Muestra primero las notas editadas recientemente.',
                de: 'Zeigt zuletzt bearbeitete Notizen zuerst.',
              ),
              selected: notesListSortField == NotesListSortField.updatedAt,
              onTap: () => ref
                  .read(notesListSortControllerProvider.notifier)
                  .setSortField(NotesListSortField.updatedAt),
            ),
            _ThemeOptionTile(
              title: _notesListSortLabel(strings, NotesListSortField.createdAt),
              subtitle: strings.localized(
                en: 'Keep the list ordered by when each note was created.',
                ja: 'メモを作成日時の新しい順に表示します。',
                zh: '按笔记创建时间排序。',
                ko: '메모 생성 시각 기준으로 표시합니다.',
                es: 'Ordena la lista por fecha de creación.',
                de: 'Sortiert die Liste nach Erstellungszeit.',
              ),
              selected: notesListSortField == NotesListSortField.createdAt,
              onTap: () => ref
                  .read(notesListSortControllerProvider.notifier)
                  .setSortField(NotesListSortField.createdAt),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: memoAutoLocationKey,
              value: lastNoteEditorSettings.captureLocation,
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.localized(
                  en: 'Add current location to new notes',
                  ja: '新規メモに現在地を自動付与',
                  zh: '为新建备忘录自动添加当前位置',
                  ko: '새 메모에 현재 위치 자동 추가',
                  es: 'Añadir ubicación actual a notas nuevas',
                  de: 'Aktuellen Standort zu neuen Notizen hinzufügen',
                ),
              ),
              subtitle: Text(
                strings.localized(
                  en: 'When enabled, new notes try to capture location metadata when the editor opens.',
                  ja: 'オンにすると、新規メモ作成画面を開いたときに位置情報を取得します。',
                  zh: '开启后，打开新建编辑器时会尝试获取位置元数据。',
                  ko: '켜면 새 메모 편집기를 열 때 위치 메타데이터를 가져옵니다.',
                  es: 'Al activarlo, las notas nuevas intentan capturar metadatos de ubicación al abrir el editor.',
                  de: 'Wenn aktiviert, erfassen neue Notizen beim Öffnen des Editors Standortmetadaten.',
                ),
              ),
              onChanged: (enabled) => ref
                  .read(lastNoteEditorSettingsControllerProvider.notifier)
                  .setCaptureLocation(enabled),
            ),
            const SizedBox(height: 8),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'Video playback',
                ja: '動画再生',
                zh: '视频播放',
                ko: '동영상 재생',
                es: 'Reproducción de video',
                de: 'Videowiedergabe',
              ),
            ),
            SwitchListTile.adaptive(
              value: videoPlaybackMutedByDefault,
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.localized(
                  en: 'Mute videos by default',
                  ja: '動画をデフォルトでミュート',
                  zh: '默认将视频静音',
                  ko: '동영상을 기본적으로 음소거',
                  es: 'Silenciar videos de forma predeterminada',
                  de: 'Videos standardmäßig stummschalten',
                ),
              ),
              subtitle: Text(
                strings.localized(
                  en: 'Newly opened videos start muted. Turn this off if you want videos to start with sound.',
                  ja: '新しく開く動画はミュートで開始します。音声ありで開始したい場合はオフにしてください。',
                  zh: '新打开的视频会以静音开始。如需默认播放声音，请关闭此项。',
                  ko: '새로 여는 동영상은 음소거로 시작합니다. 소리와 함께 시작하려면 끄세요.',
                  es: 'Los videos recién abiertos empiezan silenciados. Desactívalo si quieres que empiecen con sonido.',
                  de: 'Neu geöffnete Videos starten stumm. Deaktiviere dies, wenn Videos mit Ton starten sollen.',
                ),
              ),
              onChanged: (muted) => ref
                  .read(videoPlaybackMutedByDefaultControllerProvider.notifier)
                  .setMuted(muted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.privateProfilesSettingsTitle,
          summary: adminMode
              ? strings.privateProfilesSettingsAdminSummary
              : (activePrivateProfileLabel != null
                    ? strings.privateProfilesSettingsActiveSummary(
                        activePrivateProfileLabel,
                      )
                    : strings.privateProfilesSettingsDefaultSummary),
          icon: Icons.key_outlined,
          sectionKey: _privateProfilesSectionKey,
          controller: _privateProfilesController,
          children: [
            Text(
              strings.privateProfilesSettingsBody,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
            const SizedBox(height: 8),
            Text(
              strings.localized(
                en: 'Private profile passwords cannot be reset, unlocked, or recovered by support. Keep the password in a safe place.',
                ja: 'プライベートプロファイルのパスワード忘れ、ロック解除、データ復旧には対応できません。パスワードはご自身で安全に保管してください。',
                zh: '私密配置文件的密码无法由支持人员重置、解锁或恢复。请妥善保管密码。',
                ko: '개인 프로필 비밀번호는 지원을 통해 재설정, 잠금 해제 또는 복구할 수 없습니다. 비밀번호를 안전하게 보관하세요.',
                es: 'Soporte no puede restablecer, desbloquear ni recuperar contrasenas de perfiles privados. Guarda la contrasena en un lugar seguro.',
                de: 'Private-Profile-Passworter konnen vom Support nicht zuruckgesetzt, entsperrt oder wiederhergestellt werden. Bewahre das Passwort sicher auf.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _openExternalLink(context, Uri.parse(_helpUrl), strings),
                icon: const Icon(Icons.help_outline_rounded),
                label: Text(strings.privateProfileHelp),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  key: privateProfileAddKey,
                  onPressed: () => _showAddPrivateProfileDialog(context, ref),
                  child: Text(strings.addPrivateProfile),
                ),
                FilledButton.tonal(
                  key: privateProfileAdminModeKey,
                  onPressed: adminMode
                      ? null
                      : () => _enterAdminMode(context, ref),
                  child: Text(
                    adminMode
                        ? strings.adminModeActiveLabel
                        : strings.enterAdminModeLabel,
                  ),
                ),
                if (adminMode)
                  OutlinedButton(
                    key: privateProfileExitAdminModeKey,
                    onPressed: () => ref
                        .read(adminModeSessionControllerProvider.notifier)
                        .lock(),
                    child: Text(strings.exitAdminModeLabel),
                  ),
                if (unlockedPrivateProfileVaultId != null &&
                    unlockedPrivateProfileVaultId.startsWith(
                      customPrivateVaultPrefix,
                    ))
                  OutlinedButton(
                    onPressed: () =>
                        _showChangeCurrentProfilePasswordDialog(context, ref),
                    child: Text(
                      strings.text('home.change.current.profile.password.2'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _AdminModeAuditNotice(
              text: strings.localized(
                en: adminMode
                    ? 'Admin mode can view every profile. Use a profile row to focus that profile. Admin sign-ins and profile or note operations are recorded in Audit logs, so use it only when necessary.'
                    : 'Admin mode grants access to view every profile. Admin sign-ins are recorded in Audit logs; use normal private profile unlock for everyday work.',
                ja: adminMode
                    ? '管理者モードでは全プロファイルを閲覧できます。管理者ログインとプロファイル/ノート操作は監査ログに記録されるため、必要な時だけ使用してください。'
                    : '管理者モードでは全プロファイルの閲覧権限が付与されます。管理者ログインは監査ログに記録されるため、普段は通常のプライベートプロファイル解除を使ってください。',
                zh: adminMode
                    ? 'Admin mode can view every profile. Use a profile row to focus that profile. Admin sign-ins and profile or note operations are recorded in Audit logs, so use it only when necessary.'
                    : 'Admin mode grants access to view every profile. Admin sign-ins are recorded in Audit logs; use normal private profile unlock for everyday work.',
                ko: adminMode
                    ? 'Admin mode can view every profile. Use a profile row to focus that profile. Admin sign-ins and profile or note operations are recorded in Audit logs, so use it only when necessary.'
                    : 'Admin mode grants access to view every profile. Admin sign-ins are recorded in Audit logs; use normal private profile unlock for everyday work.',
                es: adminMode
                    ? 'Admin mode can view every profile. Use a profile row to focus that profile. Admin sign-ins and profile or note operations are recorded in Audit logs, so use it only when necessary.'
                    : 'Admin mode grants access to view every profile. Admin sign-ins are recorded in Audit logs; use normal private profile unlock for everyday work.',
                de: adminMode
                    ? 'Admin mode can view every profile. Use a profile row to focus that profile. Admin sign-ins and profile or note operations are recorded in Audit logs, so use it only when necessary.'
                    : 'Admin mode grants access to view every profile. Admin sign-ins are recorded in Audit logs; use normal private profile unlock for everyday work.',
              ),
            ),
            if (adminMode) ...[
              const SizedBox(height: 12),
              if (privateProfiles.isEmpty)
                Text(
                  strings.noPrivateProfilesMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                )
              else
                Column(
                  children: [
                    for (final profile in privateProfiles)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline),
                        title: Text(profile.name),
                        subtitle: Text(
                          strings.localized(
                            en: 'Private profile',
                            ja: 'プライベートプロファイル',
                          ),
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: strings.localized(
                                en: 'Open profile',
                                ja: 'プロファイルに入る',
                              ),
                              onPressed: () => _enterPrivateProfileFromAdmin(
                                context,
                                ref,
                                profile,
                              ),
                              icon: const Icon(Icons.login_outlined),
                            ),
                            IconButton(
                              tooltip: strings.localized(
                                en: 'Rename profile',
                                ja: 'プロファイル名を変更',
                              ),
                              onPressed: () => _showRenamePrivateProfileDialog(
                                context,
                                ref,
                                profile,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (kDebugMode && showLegacyAccessSettings)
          _SettingsGroup(
            title: strings.text('home.access.modes'),
            summary: strings.accessModeSummary(currentModeLabel),
            icon: Icons.vpn_key_outlined,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.text('home.current.mode')),
                subtitle: Text(
                  activeIdentity == 'daily'
                      ? (strings.text('home.normal.memo.mode'))
                      : ref.watch(activeIdentityDataProvider).name,
                ),
              ),
              Text(
                strings.text(
                  'home.the.app.stays.in.normal.memo.mode.by.default.enter.a.spe',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 12),
              if (syncProvider != SyncProvider.iCloud)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () =>
                          _showSpecialAccessKeyDialog(context, ref),
                      child: Text(
                        strings.text('home.enter.special.access.key'),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: activeIdentity == 'daily'
                          ? null
                          : () => _switchIdentity(ref, 'daily'),
                      child: Text(strings.text('home.return.to.normal.mode')),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _showSetCoverKeyDialog(context, ref),
                    child: Text(
                      coverModeConfigured
                          ? strings.changeAlternateProfilePassword
                          : strings.setAlternateProfilePassword,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: coverModeConfigured
                        ? () => _confirmResetCoverKey(context, ref)
                        : null,
                    child: Text(strings.resetAlternateProfilePassword),
                  ),
                ],
              ),
            ],
          ),
        if (kDebugMode && showLegacyAccessSettings) const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.app.security'),
          summary: lockSummary,
          icon: Icons.enhanced_encryption_outlined,
          sectionKey: _appSecuritySectionKey,
          controller: _appSecurityController,
          children: [
            SwitchListTile.adaptive(
              key: appLockToggleKey,
              value: appLockEnabled,
              contentPadding: EdgeInsets.zero,
              title: usePinAppLock
                  ? Text(strings.text('home.require.pin.on.launch'))
                  : Text(strings.text('home.require.device.auth.on.launch')),
              subtitle: Text(
                usePinAppLock
                    ? strings.localized(
                        en: 'Protect the app with a 4 digit PIN. ${strings.pinLockSummary(isConfigured: pinLockState.isConfigured, lastError: pinLockState.lastError)}',
                        ja: '4 桁の PIN でアプリを保護します。${strings.pinLockSummary(isConfigured: pinLockState.isConfigured, lastError: pinLockState.lastError)}',
                        zh: '使用 4 位數 PIN 保護應用程式。${strings.pinLockSummary(isConfigured: pinLockState.isConfigured, lastError: pinLockState.lastError)}',
                        ko: '4자리 PIN으로 앱을 보호합니다. ${strings.pinLockSummary(isConfigured: pinLockState.isConfigured, lastError: pinLockState.lastError)}',
                        es: 'Protege la app con un PIN de 4 dígitos. ${strings.pinLockSummary(isConfigured: pinLockState.isConfigured, lastError: pinLockState.lastError)}',
                        de: 'Schütze die App mit einer 4-stelligen PIN. ${strings.pinLockSummary(isConfigured: pinLockState.isConfigured, lastError: pinLockState.lastError)}',
                      )
                    : strings.deviceAuthProtectionSummary(
                        deviceAuthState.summary,
                      ),
              ),
              onChanged: (value) async {
                if (!value) {
                  await ref
                      .read(appLockSettingsControllerProvider.notifier)
                      .setEnabled(false);
                  ref
                      .read(appSessionUnlockControllerProvider.notifier)
                      .unlock();
                  return;
                }

                if (usePinAppLock) {
                  if (!pinLockState.isConfigured) {
                    final configured = await _showPinSetupDialog(
                      context,
                      title: strings.text('home.set.unlock.pin'),
                      confirmLabel: strings.text('home.save.pin'),
                    );
                    if (configured == null) {
                      return;
                    }
                    await ref
                        .read(appPinLockControllerProvider.notifier)
                        .configure(configured);
                  }
                } else {
                  final authenticated = await ref
                      .read(deviceAuthControllerProvider.notifier)
                      .authenticate(reason: strings.enableDeviceAuthReason);
                  if (!authenticated) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          showCloseIcon: true,
                          content: Text(
                            strings.text(
                              'home.device.authentication.was.not.completed.so.launch.protec',
                            ),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                }

                await ref
                    .read(appLockSettingsControllerProvider.notifier)
                    .setEnabled(true);
                if (spotlightNoteIndexEnabled && context.mounted) {
                  await _showSpotlightAppLockWarningDialog(context, strings);
                }
              },
            ),
            if (showSpotlightAppLockWarning) ...[
              _SettingsWarningBox(text: _spotlightAppLockWarningText(strings)),
              const SizedBox(height: 8),
            ],
            if (syncProvider == SyncProvider.iCloud)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  strings.text(
                    'home.when.icloud.sync.is.selected.this.key.is.shared.automati',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.session.status')),
              subtitle: Text(
                appSessionUnlocked
                    ? (strings.text('home.this.session.is.currently.unlocked'))
                    : (usePinAppLock
                          ? strings.localized(
                              en: 'This session stays locked until the correct PIN is entered.',
                              ja: '正しい PIN を入力するまで、このセッションはロックされます。',
                              zh: '輸入正確的 PIN 前，此工作階段會保持鎖定。',
                              ko: '올바른 PIN을 입력할 때까지 이 세션은 잠긴 상태로 유지됩니다.',
                              es: 'Esta sesión permanece bloqueada hasta introducir el PIN correcto.',
                              de: 'Diese Sitzung bleibt gesperrt, bis die richtige PIN eingegeben wurde.',
                            )
                          : (strings.text(
                              'home.this.session.stays.locked.until.device.authentication.su',
                            ))),
              ),
            ),
            if (usePinAppLock) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () async {
                        final pin = await _showPinSetupDialog(
                          context,
                          title: pinLockState.isConfigured
                              ? (strings.text('home.change.unlock.pin'))
                              : (strings.text('home.set.unlock.pin.2')),
                          confirmLabel: pinLockState.isConfigured
                              ? (strings.text('home.update.pin'))
                              : (strings.text('home.save.pin')),
                        );
                        if (pin == null) {
                          return;
                        }
                        await ref
                            .read(appPinLockControllerProvider.notifier)
                            .configure(pin);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              showCloseIcon: true,
                              content: Text(
                                pinLockState.isConfigured
                                    ? (strings.text('home.unlock.pin.updated'))
                                    : (strings.text(
                                        'home.unlock.pin.configured',
                                      )),
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        pinLockState.isConfigured
                            ? (strings.text('home.change.pin'))
                            : (strings.text('home.set.pin')),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: pinLockState.isConfigured
                          ? () async {
                              final shouldRemove = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    strings.text('home.remove.unlock.pin'),
                                  ),
                                  content: Text(
                                    kIsWeb
                                        ? strings.text(
                                            'home.remove.the.web.unlock.pin.for.this.browser.and.turn.off',
                                          )
                                        : strings.localized(
                                            en: 'Remove the unlock PIN from this device and turn off launch PIN protection?',
                                            ja: 'この端末の解除用 PIN を削除し、起動時の PIN 保護をオフにしますか？',
                                            zh: '要从此装置移除解锁 PIN，并关闭启动 PIN 保护吗？',
                                            ko: '이 기기의 잠금 해제 PIN을 제거하고 실행 시 PIN 보호를 끄시겠습니까?',
                                            es: '¿Eliminar el PIN de desbloqueo de este dispositivo y desactivar la protección al iniciar?',
                                            de: 'Entsperr-PIN von diesem Gerät entfernen und PIN-Schutz beim Start deaktivieren?',
                                          ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: Text(strings.cancel),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: Text(strings.text('home.remove')),
                                    ),
                                  ],
                                ),
                              );
                              if (shouldRemove != true) {
                                return;
                              }
                              await ref
                                  .read(appPinLockControllerProvider.notifier)
                                  .clear();
                              await ref
                                  .read(
                                    appLockSettingsControllerProvider.notifier,
                                  )
                                  .setEnabled(false);
                            }
                          : null,
                      child: Text(strings.text('home.remove.pin')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? strings.text(
                        'home.web.pin.is.a.browser.level.access.gate.it.does.not.repla',
                      )
                    : strings.localized(
                        en: 'This PIN is stored on this device and is used when OS device authentication is unavailable.',
                        ja: 'この PIN はこの端末に保存され、OS の端末認証が利用できない場合の解除に使われます。',
                        zh: '此 PIN 會儲存在本裝置，並在無法使用系統裝置認證時用於解鎖。',
                        ko: '이 PIN은 이 기기에 저장되며 OS 기기 인증을 사용할 수 없을 때 잠금 해제에 사용됩니다.',
                        es: 'Este PIN se guarda en este dispositivo y se usa cuando la autenticación del sistema no está disponible.',
                        de: 'Diese PIN wird auf diesem Gerät gespeichert und genutzt, wenn die Geräteauthentifizierung des Systems nicht verfügbar ist.',
                      ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (showLegacyAccessSettings) ...[
              SwitchListTile.adaptive(
                value: widgetQuickCaptureEnabled,
                contentPadding: EdgeInsets.zero,
                title: Text(strings.homeWidgetQuickCapture),
                subtitle: Text(
                  !kIsWeb &&
                          (defaultTargetPlatform == TargetPlatform.android ||
                              defaultTargetPlatform == TargetPlatform.iOS)
                      ? strings.homeWidgetQuickCaptureDesc
                      : strings.homeWidgetQuickCaptureMobileOnly,
                ),
                onChanged:
                    !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS)
                    ? (value) => ref
                          .read(
                            widgetQuickCaptureSettingsControllerProvider
                                .notifier,
                          )
                          .setEnabled(value)
                    : null,
              ),
              Text(
                strings.text(
                  'home.quick.widget.capture.only.writes.plain.text.into.notes.i',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Text(strings.text('home.re.lock.after.app.leaves.the.foreground')),
            const SizedBox(height: 8),
            _ThemeOptionTile(
              tileKey: appLockRelockImmediateKey,
              title: strings.text('home.immediately'),
              subtitle: strings.text(
                'home.lock.the.app.as.soon.as.it.moves.to.the.background',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.immediate,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.immediate),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock30SecondsKey,
              title: strings.text('home.after.30.seconds'),
              subtitle: strings.text(
                'home.allow.quick.app.switching.without.immediate.re.auth',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.seconds30,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.seconds30),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock2MinutesKey,
              title: strings.text('home.after.2.minutes'),
              subtitle: strings.text(
                'home.useful.when.capturing.photos.or.audio.between.notes',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.minutes2,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes2),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock10MinutesKey,
              title: strings.text('home.after.10.minutes'),
              subtitle: strings.text(
                'home.keep.the.app.open.during.longer.editing.sessions',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.minutes10,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes10),
            ),
            if (showLegacyPrivateVaultSettings)
              SwitchListTile.adaptive(
                key: privateVaultLockOnAppLockKey,
                value: privateVaultLockOnAppLock,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  strings.text('home.lock.legacy.private.area.when.app.locks'),
                ),
                subtitle: Text(
                  strings.text(
                    'home.normally.this.locks.whenever.the.app.locks',
                  ),
                ),
                onChanged: (value) => ref
                    .read(privateVaultLockOnAppLockControllerProvider.notifier)
                    .setEnabled(value),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!usePinAppLock)
                    FilledButton.tonal(
                      key: appLockAuthenticateKey,
                      onPressed: () => ref
                          .read(deviceAuthControllerProvider.notifier)
                          .authenticate(
                            reason: strings.unlockWithDeviceAuthReason,
                          ),
                      child: Text(strings.text('home.authenticate.now')),
                    ),
                  OutlinedButton(
                    key: appLockLockNowKey,
                    onPressed: appLockEnabled
                        ? () {
                            ref
                                .read(
                                  appSessionUnlockControllerProvider.notifier,
                                )
                                .lock();
                            ref
                                .read(
                                  privateVaultSessionControllerProvider
                                      .notifier,
                                )
                                .lock();
                            ref
                                .read(
                                  unlockedPrivateProfileVaultIdProvider
                                      .notifier,
                                )
                                .lock();
                            ref
                                .read(
                                  adminModeSessionControllerProvider.notifier,
                                )
                                .lock();
                          }
                        : null,
                    child: Text(strings.text('home.lock.session.now')),
                  ),
                  if (!kIsWeb)
                    OutlinedButton(
                      onPressed: () => ref
                          .read(deviceAuthControllerProvider.notifier)
                          .refresh(),
                      child: Text(strings.text('home.refresh.availability')),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.external.quick.memo'),
          summary: widgetQuickCaptureEnabled
              ? (strings.text(
                  'home.widget.quick.writes.are.allowed.while.the.app.is.locked',
                ))
              : (strings.text('home.widget.quick.writes.are.off')),
          icon: Icons.quickreply_outlined,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.text('home.allow.widget.writes.while.locked'),
              ),
              subtitle: Text(
                strings.text(
                  'home.only.the.submitted.text.is.saved.existing.notes.and.lock',
                ),
              ),
              value: widgetQuickCaptureEnabled,
              onChanged: (value) => ref
                  .read(widgetQuickCaptureSettingsControllerProvider.notifier)
                  .setEnabled(value),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.write.target')),
              subtitle: Text(strings.notes),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (kDebugMode && showLegacyPrivateVaultSettings)
          _SettingsGroup(
            title: strings.text('home.private.vault'),
            summary: privateVaultConfigured
                ? (privateVaultUnlocked
                      ? (strings.text('home.configured.and.currently.unlocked'))
                      : (strings.text('home.configured.and.locked')))
                : (strings.text('home.no.private.vault.key.has.been.set.yet')),
            icon: Icons.shield_outlined,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.text('home.status')),
                subtitle: Text(
                  privateVaultConfigured
                      ? (privateVaultUnlocked
                            ? (strings.text(
                                'home.configured.and.unlocked.for.this.session',
                              ))
                            : (strings.text(
                                'home.configured.and.locked.a.separate.key.is.required',
                              )))
                      : (strings.text(
                          'home.not.configured.yet.set.a.separate.key.for.the.private.va',
                        )),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!privateVaultConfigured)
                    FilledButton(
                      key: privateVaultSetKey,
                      onPressed: () => _showSetPrivateKeyDialog(context, ref),
                      child: Text(strings.text('home.set.private.key')),
                    ),
                  if (privateVaultConfigured && !privateVaultUnlocked)
                    FilledButton(
                      key: privateVaultUnlockKey,
                      onPressed: () =>
                          _showUnlockPrivateVaultDialog(context, ref),
                      child: Text(strings.text('home.unlock.private.vault')),
                    ),
                  if (privateVaultUnlocked)
                    FilledButton.tonal(
                      key: privateVaultLockKey,
                      onPressed: () => ref
                          .read(privateVaultSessionControllerProvider.notifier)
                          .lock(),
                      child: Text(strings.text('home.lock.private.vault')),
                    ),
                  if (privateVaultConfigured)
                    OutlinedButton(
                      key: privateVaultResetKey,
                      onPressed: () => _confirmResetPrivateKey(context, ref),
                      child: Text(strings.text('home.reset.private.key')),
                    ),
                ],
              ),
            ],
          ),
        if (kDebugMode && showLegacyPrivateVaultSettings)
          const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.backup.and.sync'),
          summary: syncSummary,
          icon: Icons.sync_outlined,
          sectionKey: _syncSectionKey,
          controller: _syncController,
          children: [
            if (syncConflictWarning != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                child: Text(
                  _localizedSyncTransferMessage(
                    strings,
                    syncConflictWarning,
                    syncProvider,
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'Remote backup',
                ja: 'リモートバックアップ',
                zh: '远程备份',
                ko: '원격 백업',
                es: 'Copia remota',
                de: 'Remote-Backup',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.selected.target')),
              subtitle: Text(
                _syncSubtitle(context, syncProvider, syncAuthState),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_syncStatusTitle(context, syncProvider)),
              subtitle: Text(
                _syncAuthSummary(context, syncProvider, syncAuthState),
              ),
            ),
            _SyncExclusionTagsTile(
              tags: syncExclusionTags,
              onAdd: () => _addSyncExclusionTag(context, ref),
              onRemove: (tag) => ref
                  .read(syncExclusionTagsControllerProvider.notifier)
                  .removeTag(tag),
            ),
            if (syncProvider != SyncProvider.off)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    key: syncNowKey,
                    onPressed:
                        syncTransferState.isBusy ||
                            !syncAuthState.isAuthenticated
                        ? null
                        : () => _syncNow(context, ref),
                    icon: syncTransferState.stage == SyncTransferStage.busy
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(
                      syncTransferState.stage == SyncTransferStage.busy
                          ? _syncProgressLabel(strings, syncTransferState)
                          : strings.localized(
                              en: 'Sync',
                              ja: '同期',
                              zh: '同步',
                              ko: '동기화',
                              es: 'Sincronizar',
                              de: 'Synchronisieren',
                            ),
                    ),
                  ),
                  if (syncTransferState.isCoolingDown)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            strings.localized(
                              en: 'Retry is paused after repeated failures.',
                              ja: '\u5931\u6557\u304c\u7d9a\u3044\u305f\u305f\u3081\u518d\u8a66\u884c\u3092\u4e00\u6642\u505c\u6b62\u3057\u3066\u3044\u307e\u3059\u3002',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          OutlinedButton.icon(
                            onPressed: !syncAuthState.isAuthenticated
                                ? null
                                : () async {
                                    ref
                                        .read(
                                          syncTransferControllerProvider
                                              .notifier,
                                        )
                                        .clearRetryCooldown();
                                    await _syncNow(context, ref);
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(
                              strings.localized(
                                en: 'Retry now',
                                ja: '\u4eca\u3059\u3050\u518d\u8a66\u884c',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (syncTransferState.stage == SyncTransferStage.busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: _syncProgressValueForState(
                                syncTransferState,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _syncProgressDescription(
                                strings,
                                syncTransferState,
                                syncProvider,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: Text(strings.syncDetailsTitle),
                  subtitle: Text(strings.syncDetailsSummary),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.localized(
                          en: 'Sync progress',
                          ja: '同期の進捗',
                          zh: '同步进度',
                          ko: '동기화 진행률',
                          es: 'Progreso de sincronizacion',
                          de: 'Synchronisierungsfortschritt',
                        ),
                      ),
                      subtitle: Text(
                        _syncProgressDescription(
                          strings,
                          syncTransferState,
                          syncProvider,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.pending.sync.queue')),
                      subtitle: Text(
                        syncQueueSummary.when(
                          data: (summary) {
                            if (!summary.hasPendingChanges) {
                              return strings.text(
                                'home.no.pending.device.changes',
                              );
                            }
                            final timestamp = summary.lastQueuedAt;
                            final stampText = timestamp == null
                                ? (strings.text('home.queue.ready'))
                                : strings.lastQueuedAt(
                                    _formatDateTime(timestamp, strings),
                                  );
                            return strings.pendingSyncSummary(
                              total: summary.totalChanges,
                              upserts: summary.upserts,
                              deletes: summary.deletes,
                              stamp: stampText,
                            );
                          },
                          loading: () =>
                              strings.text('home.checking.pending.changes'),
                          error: (_, _) => strings.text(
                            'home.unable.to.inspect.the.local.sync.queue',
                          ),
                        ),
                      ),
                    ),
                    if (conflictedNotes.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.report_problem_outlined),
                        title: Text(
                          strings.localized(
                            en: 'Conflicts to resolve',
                            ja: '\u89e3\u6c7a\u304c\u5fc5\u8981\u306a\u7af6\u5408',
                          ),
                        ),
                        subtitle: Text(
                          strings.localized(
                            en: '${conflictedNotes.length} notes need review before sync can settle.',
                            ja: '${conflictedNotes.length} \u4ef6\u306e\u30e1\u30e2\u306e\u78ba\u8a8d\u304c\u5fc5\u8981\u3067\u3059\u3002',
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () => _showSyncConflictListDialog(
                            context,
                            ref,
                            conflictedNotes,
                          ),
                          child: Text(
                            strings.localized(en: 'Review', ja: '\u78ba\u8a8d'),
                          ),
                        ),
                        onTap: () => _showSyncConflictListDialog(
                          context,
                          ref,
                          conflictedNotes,
                        ),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.remote.bundle')),
                      subtitle: Text(
                        _remoteBundleSummary(
                          strings,
                          syncProvider,
                          syncTransferState,
                          syncBundleState.asData?.value,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.help_outline_rounded),
                      title: Text(strings.syncHelp),
                      subtitle: Text(strings.syncHelpDesc),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => _openExternalLink(
                        context,
                        Uri.parse(_helpUrl),
                        strings,
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.text('home.cloud.recovery.key.fingerprint'),
                      ),
                      subtitle: Text(
                        syncBundleFingerprint.when(
                          data: (value) => value,
                          loading: () =>
                              strings.text('home.preparing.cloud.recovery.key'),
                          error: (_, _) => strings.text(
                            'home.unable.to.read.the.cloud.recovery.key.fingerprint',
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final backupCode = await ref
                                    .read(syncBundleKeyServiceProvider)
                                    .exportBackupCode();
                                await Clipboard.setData(
                                  ClipboardData(text: backupCode),
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text(
                                      strings.text(
                                        'home.cloud.recovery.key.copied.to.clipboard',
                                      ),
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text('$error'),
                                  ),
                                );
                              }
                            },
                            child: Text(strings.text('home.copy.recovery.key')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final backupCode = await ref
                                    .read(syncBundleKeyServiceProvider)
                                    .exportBackupCode();
                                if (!context.mounted) {
                                  return;
                                }
                                await _showSyncKeyQrDialog(
                                  context,
                                  backupCode: backupCode,
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text('$error'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.qr_code_2_rounded),
                            label: Text(
                              strings.localized(
                                en: 'Show QR',
                                ja: 'QRを表示',
                                zh: '显示 QR',
                                ko: 'QR 표시',
                                es: 'Mostrar QR',
                                de: 'QR anzeigen',
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              final backupCode = await _showSyncKeyImportDialog(
                                context,
                              );
                              if (!context.mounted || backupCode == null) {
                                return;
                              }
                              await _handleSyncKeyImport(
                                context,
                                ref,
                                backupCode,
                              );
                            },
                            child: Text(
                              strings.text('home.import.recovery.key'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final backupCode =
                                  await _showSyncKeyQrScannerDialog(context);
                              if (!context.mounted || backupCode == null) {
                                return;
                              }
                              await _handleSyncKeyImport(
                                context,
                                ref,
                                backupCode,
                              );
                            },
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: Text(
                              strings.localized(
                                en: 'Scan QR',
                                ja: 'QRを読み取り',
                                zh: '扫描 QR',
                                ko: 'QR 스캔',
                                es: 'Escanear QR',
                                de: 'QR scannen',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.last.sync.activity')),
                      subtitle: Text(
                        syncBundleState.when(
                          data: (value) {
                            final entries = <String>[];
                            if (value.lastUploadedAt != null) {
                              entries.add(
                                strings.lastUploadAt(
                                  _formatDateTime(
                                    value.lastUploadedAt!,
                                    strings,
                                  ),
                                ),
                              );
                            }
                            if (value.lastAppliedAt != null) {
                              entries.add(
                                strings.lastApplyAt(
                                  _formatDateTime(
                                    value.lastAppliedAt!,
                                    strings,
                                  ),
                                ),
                              );
                            }
                            if (value.lastRemoteModifiedAt != null) {
                              entries.add(
                                strings.remoteBundleAt(
                                  _formatDateTime(
                                    value.lastRemoteModifiedAt!,
                                    strings,
                                  ),
                                ),
                              );
                            }
                            if (entries.isEmpty) {
                              return strings.text(
                                'home.no.sync.activity.has.been.recorded.on.this.device.yet',
                              );
                            }
                            return entries.join('\n');
                          },
                          loading: () =>
                              strings.text('home.reading.sync.activity'),
                          error: (_, _) => strings.text(
                            'home.unable.to.read.local.sync.activity',
                          ),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_rounded),
                      title: Text(
                        strings.localized(
                          en: 'Sync history',
                          ja: '\u540c\u671f\u5c65\u6b74',
                        ),
                      ),
                      subtitle: Text(
                        syncHistory.when(
                          data: (entries) => entries.isEmpty
                              ? strings.localized(
                                  en: 'No sync history has been recorded yet.',
                                  ja: '\u307e\u3060\u540c\u671f\u5c65\u6b74\u306f\u3042\u308a\u307e\u305b\u3093\u3002',
                                )
                              : _syncHistoryEntrySummary(
                                  strings,
                                  entries.first,
                                  syncProvider,
                                ),
                          loading: () => strings.localized(
                            en: 'Reading sync history...',
                            ja: '\u540c\u671f\u5c65\u6b74\u3092\u8aad\u307f\u8fbc\u3093\u3067\u3044\u307e\u3059\u2026',
                          ),
                          error: (_, _) => strings.localized(
                            en: 'Unable to read sync history.',
                            ja: '\u540c\u671f\u5c65\u6b74\u3092\u8aad\u307f\u8fbc\u3081\u307e\u305b\u3093\u3002',
                          ),
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: syncHistory.asData?.value == null
                            ? null
                            : () => _showSyncHistoryDialog(
                                context,
                                syncHistory.asData!.value,
                              ),
                        child: Text(
                          strings.localized(en: 'Show', ja: '\u8868\u793a'),
                        ),
                      ),
                      onTap: syncHistory.asData?.value == null
                          ? null
                          : () => _showSyncHistoryDialog(
                              context,
                              syncHistory.asData!.value,
                            ),
                    ),
                    if (syncTransferState.localBundle != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.text('home.local.bundle.cache')),
                        subtitle: Text(
                          strings.localBundleStoredAt(
                            syncTransferState.localBundle!.reference,
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (syncProvider != SyncProvider.off)
                            OutlinedButton(
                              key: syncRefreshRemoteKey,
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final confirmed =
                                            await _confirmLargeMobileSyncIfNeeded(
                                              context,
                                              ref,
                                              includeUpload: false,
                                              includeDownload: true,
                                            );
                                        if (!confirmed || !context.mounted) {
                                          return;
                                        }
                                        await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .refreshRemoteStatus();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final message =
                                            _cloudSyncSnackBarMessage(
                                              strings,
                                              ref.read(
                                                syncTransferControllerProvider,
                                              ),
                                              _CloudSyncSnackBarAction
                                                  .refreshRemote,
                                              syncProvider,
                                            );
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text(message),
                                          ),
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.refresh.remote')),
                            ),
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated)
                            OutlinedButton(
                              key: syncUploadBundleKey,
                              onPressed:
                                  syncTransferState.isBusy ||
                                      syncConflictWarning != null
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final confirmed =
                                            await _confirmLargeMobileSyncIfNeeded(
                                              context,
                                              ref,
                                              includeUpload: true,
                                              includeDownload: false,
                                            );
                                        if (!confirmed || !context.mounted) {
                                          return;
                                        }
                                        await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .uploadCurrentBundle(
                                              allowLargeMobileTransfer: true,
                                            );
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final message =
                                            _cloudSyncSnackBarMessage(
                                              strings,
                                              ref.read(
                                                syncTransferControllerProvider,
                                              ),
                                              _CloudSyncSnackBarAction.upload,
                                              syncProvider,
                                            );
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text(message),
                                          ),
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.upload.bundle')),
                            ),
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.cloud_upload_outlined),
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final shouldReupload =
                                          await showDialog<bool>(
                                            context: context,
                                            builder: (context) {
                                              return AlertDialog(
                                                title: Text(
                                                  strings.localized(
                                                    en: 'Re-upload all notes',
                                                    ja: '全メモを再アップロード',
                                                    zh: '重新上传全部备忘',
                                                    ko: '모든 메모 다시 업로드',
                                                    es: 'Volver a subir todas las notas',
                                                    de: 'Alle Notizen erneut hochladen',
                                                  ),
                                                ),
                                                content: Text(
                                                  strings.localized(
                                                    en: 'This queues all notes on this device and uploads a new encrypted bundle to the selected sync target. Use this after changing sync targets or repairing attachments on this device. It may overwrite the remote bundle.',
                                                    ja: 'この端末の全メモを同期キューに入れ、選択中の同期先へ新しい暗号化バンドルをアップロードします。同期先の切り替え後や、この端末で添付を修復した後に使用してください。リモートのバンドルは上書きされる場合があります。',
                                                    zh: '这会将本机全部备忘加入同步队列，并向选定同步目标上传新的加密包。请在切换同步目标或在本机修复附件后使用。远程包可能会被覆盖。',
                                                    ko: '이 기기의 모든 메모를 동기화 대기열에 넣고 선택한 동기화 대상으로 새 암호화 번들을 업로드합니다. 동기화 대상을 변경했거나 이 기기에서 첨부 파일을 복구한 뒤 사용하세요. 원격 번들을 덮어쓸 수 있습니다.',
                                                    es: 'Esto pone todas las notas de este dispositivo en la cola de sincronizacion y sube un nuevo paquete cifrado al destino seleccionado. Usalo tras cambiar de destino o reparar adjuntos en este dispositivo. Puede sobrescribir el paquete remoto.',
                                                    de: 'Dadurch werden alle Notizen dieses Gerats in die Synchronisierungswarteschlange gestellt und als neues verschlusseltes Paket zum ausgewahlten Ziel hochgeladen. Nutze dies nach Zielwechseln oder reparierten Anhangen. Das Remote-Paket kann uberschrieben werden.',
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(false),
                                                    child: Text(strings.cancel),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(true),
                                                    child: Text(
                                                      strings.localized(
                                                        en: 'Re-upload',
                                                        ja: '再アップロード',
                                                        zh: '重新上传',
                                                        ko: '다시 업로드',
                                                        es: 'Volver a subir',
                                                        de: 'Erneut hochladen',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ) ??
                                          false;
                                      if (!shouldReupload) {
                                        return;
                                      }
                                      if (!context.mounted) {
                                        return;
                                      }
                                      try {
                                        final confirmed =
                                            await _confirmLargeMobileSyncIfNeeded(
                                              context,
                                              ref,
                                              includeUpload: true,
                                              includeDownload: false,
                                              estimateAllLocalNotes: true,
                                            );
                                        if (!confirmed || !context.mounted) {
                                          return;
                                        }
                                        await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .reuploadAllCurrentNotes(
                                              allowLargeMobileTransfer: true,
                                            );
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final message =
                                            _cloudSyncSnackBarMessage(
                                              strings,
                                              ref.read(
                                                syncTransferControllerProvider,
                                              ),
                                              _CloudSyncSnackBarAction.upload,
                                              syncProvider,
                                            );
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text(message),
                                          ),
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              label: Text(
                                strings.localized(
                                  en: 'Re-upload all notes',
                                  ja: '全メモを再アップロード',
                                  zh: '重新上传全部备忘',
                                  ko: '모든 메모 다시 업로드',
                                  es: 'Volver a subir todas las notas',
                                  de: 'Alle Notizen erneut hochladen',
                                ),
                              ),
                            ),
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated &&
                              syncConflictWarning != null)
                            FilledButton.tonal(
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final shouldForce =
                                          await showDialog<bool>(
                                            context: context,
                                            builder: (context) {
                                              return AlertDialog(
                                                title: Text(
                                                  strings.text(
                                                    'home.force.upload.2',
                                                  ),
                                                ),
                                                content: Text(
                                                  strings.text(
                                                    'home.a.newer.remote.bundle.was.found.while.this.device.still',
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(false),
                                                    child: Text(strings.cancel),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(true),
                                                    child: Text(
                                                      strings.text(
                                                        'home.force.upload',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ) ??
                                          false;
                                      if (!shouldForce) {
                                        return;
                                      }
                                      if (!context.mounted) {
                                        return;
                                      }
                                      final confirmed =
                                          await _confirmLargeMobileSyncIfNeeded(
                                            context,
                                            ref,
                                            includeUpload: true,
                                            includeDownload: false,
                                          );
                                      if (!confirmed || !context.mounted) {
                                        return;
                                      }
                                      await ref
                                          .read(
                                            syncTransferControllerProvider
                                                .notifier,
                                          )
                                          .uploadCurrentBundle(
                                            force: true,
                                            allowLargeMobileTransfer: true,
                                          );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      final message = _cloudSyncSnackBarMessage(
                                        strings,
                                        ref.read(
                                          syncTransferControllerProvider,
                                        ),
                                        _CloudSyncSnackBarAction.upload,
                                        syncProvider,
                                      );
                                      messenger.showSnackBar(
                                        SnackBar(
                                          showCloseIcon: true,
                                          content: Text(message),
                                        ),
                                      );
                                    },
                              child: Text(strings.text('home.force.upload')),
                            ),
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated)
                            OutlinedButton(
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final history = await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .listRemoteBundleHistory();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        if (history.isEmpty) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              showCloseIcon: true,
                                              content: Text(
                                                strings.text(
                                                  'home.no.remote.bundle.history.is.available',
                                                ),
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        await _showBundleHistoryDialog(
                                          context,
                                          history,
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.bundle.history')),
                            ),
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated)
                            OutlinedButton(
                              key: syncDownloadBundleKey,
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .downloadLatestBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final message =
                                            _cloudSyncSnackBarMessage(
                                              strings,
                                              ref.read(
                                                syncTransferControllerProvider,
                                              ),
                                              _CloudSyncSnackBarAction.download,
                                              syncProvider,
                                            );
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text(message),
                                          ),
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.download.bundle')),
                            ),
                          if (syncTransferState.localBundle != null)
                            OutlinedButton(
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final preview = await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .previewDownloadedBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        await _showBundlePreviewDialog(
                                          context,
                                          preview,
                                          confirmLabel: strings.close,
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.review.bundle')),
                            ),
                          if (syncTransferState.localBundle != null)
                            OutlinedButton(
                              key: syncApplyBundleKey,
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final preview = await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .previewDownloadedBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final shouldApply =
                                            await _showBundlePreviewDialog(
                                              context,
                                              preview,
                                              confirmLabel: strings.text(
                                                'home.apply.bundle',
                                              ),
                                            ) ??
                                            false;
                                        if (!shouldApply) {
                                          return;
                                        }
                                        await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .applyDownloadedBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final message =
                                            _cloudSyncSnackBarMessage(
                                              strings,
                                              ref.read(
                                                syncTransferControllerProvider,
                                              ),
                                              _CloudSyncSnackBarAction.apply,
                                              syncProvider,
                                            );
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text(message),
                                          ),
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.apply.bundle')),
                            ),
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated)
                            OutlinedButton(
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final count = await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .downloadDeferredAttachments();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text(
                                              count == 0
                                                  ? strings.text(
                                                      'home.no.deferred.attachments',
                                                    )
                                                  : strings.text(
                                                      'home.deferred.attachments.downloaded',
                                                    ),
                                            ),
                                          ),
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(
                                strings.text(
                                  'home.download.deferred.attachments',
                                ),
                              ),
                            ),
                          OutlinedButton(
                            onPressed: () async {
                              final syncEngine = ref.read(syncEngineProvider);
                              final pendingChanges = await syncEngine
                                  .loadPendingChanges();
                              final pendingIds = pendingChanges
                                  .map((change) => change.noteId)
                                  .toSet();
                              final notes = await ref
                                  .read(notesControllerProvider.notifier)
                                  .notesForSyncSnapshot(
                                    pendingNoteIds: pendingIds,
                                  );
                              final snapshot = await syncEngine.prepareSnapshot(
                                notes,
                                pendingChanges: pendingChanges,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              await showDialog<void>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: Text(
                                      strings.text(
                                        'home.prepared.sync.snapshot',
                                      ),
                                    ),
                                    content: Text(
                                      strings.syncSnapshotSummary(
                                        notes: snapshot.notes.length,
                                        attachments:
                                            snapshot.attachments.length,
                                        pending: snapshot.summary.totalChanges,
                                        deviceId: snapshot.deviceId,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: Text(strings.close),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            child: Text(strings.text('home.inspect.snapshot')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _ThemeOptionTile(
              tileKey: syncOffKey,
              title: strings.text('home.off'),
              subtitle: strings.text('home.keep.data.on.this.device.only'),
              selected: syncProvider == SyncProvider.off,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.off),
            ),
            if (isICloudSyncSupported)
              _ThemeOptionTile(
                tileKey: syncICloudKey,
                title: 'iCloud',
                subtitle: strings.text(
                  'home.use.this.device.s.icloud.as.the.sync.target.no.himemo.lo',
                ),
                selected: syncProvider == SyncProvider.iCloud,
                onTap: () => ref
                    .read(syncProviderControllerProvider.notifier)
                    .setProvider(SyncProvider.iCloud),
              ),
            _ThemeOptionTile(
              tileKey: syncGoogleDriveKey,
              title: 'Google Drive',
              subtitle: strings.text('home.google.drive.app.data.sync.target'),
              selected: syncProvider == SyncProvider.googleDrive,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.googleDrive),
            ),
            if (kIsWeb &&
                syncProvider == SyncProvider.googleDrive &&
                !syncAuthState.isAuthenticated)
              const _GoogleDriveWebSignInPanel(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (syncProvider != SyncProvider.off &&
                    !(kIsWeb && syncProvider == SyncProvider.googleDrive))
                  FilledButton(
                    key: syncConnectKey,
                    onPressed: syncAuthState.stage == SyncAuthStage.busy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref
                                  .read(syncAuthControllerProvider.notifier)
                                  .connectSelected();
                              if (!context.mounted) {
                                return;
                              }
                              final message = ref
                                  .read(
                                    syncAuthControllerProvider,
                                  )[syncProvider]
                                  ?.message;
                              final localizedMessage =
                                  _cloudSyncAuthSnackBarMessage(
                                    strings,
                                    message,
                                  );
                              if (localizedMessage != null &&
                                  localizedMessage.isNotEmpty) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text(localizedMessage),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text('$error'),
                                ),
                              );
                            }
                          },
                    child: Text(
                      syncAuthState.isAuthenticated
                          ? _syncReconnectLabel(context, syncProvider)
                          : _syncConnectLabel(context, syncProvider),
                    ),
                  ),
                if (syncProvider != SyncProvider.off &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncDisconnectKey,
                    onPressed: () => ref
                        .read(syncAuthControllerProvider.notifier)
                        .disconnectSelected(),
                    child: Text(_syncDisconnectLabel(context, syncProvider)),
                  ),
              ],
            ),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'File backup',
                ja: 'ファイルバックアップ',
                zh: '文件备份',
                ko: '파일 백업',
                es: 'Copia en archivo',
                de: 'Datei-Backup',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: noteCount == 0
                        ? null
                        : () => _exportLocalArchive(
                            context,
                            ref,
                            vaultIds: visibleStorageVaultIds,
                          ),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      strings.localized(
                        en: 'File export',
                        ja: 'ファイルエクスポート',
                        zh: '文件导出',
                        ko: '파일 내보내기',
                        es: 'Exportar archivo',
                        de: 'Datei exportieren',
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _importLocalArchive(context, ref),
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      strings.localized(
                        en: 'File import',
                        ja: 'ファイルインポート',
                        zh: '文件导入',
                        ko: '파일 가져오기',
                        es: 'Importar archivo',
                        de: 'Datei importieren',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.storage'),
          summary: strings.noteCountSummary(noteCount),
          icon: Icons.storage_outlined,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.saved.notes.on.this.device')),
              subtitle: Text(strings.entriesCount(noteCount)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.localized(
                  en: 'Storage size',
                  ja: '保存サイズ',
                  zh: '存储大小',
                  ko: '저장 크기',
                  es: 'Tamaño guardado',
                  de: 'Speichergröße',
                ),
              ),
              subtitle: Text(
                storageUsageSummary.when(
                  data: (summary) => strings.localized(
                    en: '${strings.byteCount(summary.totalBytes)} total / notes ${strings.byteCount(summary.notePayloadBytes)} / attachments ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    ja: '合計 ${strings.byteCount(summary.totalBytes)} / ノート ${strings.byteCount(summary.notePayloadBytes)} / 添付 ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    zh: '合计 ${strings.byteCount(summary.totalBytes)} / 笔记 ${strings.byteCount(summary.notePayloadBytes)} / 附件 ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    ko: '합계 ${strings.byteCount(summary.totalBytes)} / 노트 ${strings.byteCount(summary.notePayloadBytes)} / 첨부 ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    es: '${strings.byteCount(summary.totalBytes)} en total / notas ${strings.byteCount(summary.notePayloadBytes)} / adjuntos ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    de: '${strings.byteCount(summary.totalBytes)} gesamt / Notizen ${strings.byteCount(summary.notePayloadBytes)} / Anhänge ${strings.byteCount(summary.attachmentPayloadBytes)}',
                  ),
                  loading: () => strings.localized(
                    en: 'Calculating...',
                    ja: '計算中...',
                    zh: '正在计算...',
                    ko: '계산 중...',
                    es: 'Calculando...',
                    de: 'Wird berechnet...',
                  ),
                  error: (_, _) => strings.localized(
                    en: 'Unable to calculate storage size.',
                    ja: '保存サイズを計算できませんでした。',
                    zh: '无法计算存储大小。',
                    ko: '저장 크기를 계산할 수 없습니다.',
                    es: 'No se pudo calcular el tamaño guardado.',
                    de: 'Speichergröße konnte nicht berechnet werden.',
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: createDemoNotesKey,
                    onPressed: () async {
                      final createdCount = await ref
                          .read(notesControllerProvider.notifier)
                          .createDemoNotes();
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          showCloseIcon: true,
                          content: Text(
                            createdCount == 0
                                ? strings.noDemoNotesToCreate
                                : strings.demoNotesCreated(createdCount),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: Text(strings.createDemoNotes),
                  ),
                  OutlinedButton.icon(
                    key: deleteDemoNotesKey,
                    onPressed: demoNoteCount == 0
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) {
                                return AlertDialog(
                                  title: Text(strings.deleteDemoNotesTitle),
                                  content: Text(
                                    strings.deleteDemoNotesBody(demoNoteCount),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(
                                        dialogContext,
                                      ).pop(false),
                                      child: Text(strings.text('home.cancel')),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                      child: Text(strings.delete),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirmed != true) {
                              return;
                            }
                            final deletedCount = await ref
                                .read(notesControllerProvider.notifier)
                                .deleteDemoNotes();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(
                                  strings.demoNotesDeleted(deletedCount),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(strings.deleteDemoNotes),
                  ),
                  OutlinedButton.icon(
                    onPressed: noteCount == 0
                        ? null
                        : () async {
                            final confirmed = await _confirmStorageReset(
                              context,
                              noteCount,
                            );
                            if (confirmed != true) {
                              return;
                            }
                            final deletedCount = await ref
                                .read(notesControllerProvider.notifier)
                                .resetLocalStorage();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(
                                  strings.localized(
                                    en: 'Initialized local storage. Deleted $deletedCount notes.',
                                    ja: '\u30b9\u30c8\u30ec\u30fc\u30b8\u3092\u521d\u671f\u5316\u3057\u307e\u3057\u305f\u3002$deletedCount \u4ef6\u306e\u30ce\u30fc\u30c8\u3092\u524a\u9664\u3057\u307e\u3057\u305f\u3002',
                                    zh: '\u5df2\u521d\u59cb\u5316\u672c\u5730\u5b58\u50a8\u3002\u5220\u9664\u4e86 $deletedCount \u6761\u7b14\u8bb0\u3002',
                                    ko: '\ub85c\uceec \uc800\uc7a5\uc18c\ub97c \ucd08\uae30\ud654\ud588\uc2b5\ub2c8\ub2e4. \uba54\ubaa8 $deletedCount\uac1c\ub97c \uc0ad\uc81c\ud588\uc2b5\ub2c8\ub2e4.',
                                    es: 'Se inicializo el almacenamiento local. Se eliminaron $deletedCount notas.',
                                    de: 'Lokaler Speicher initialisiert. $deletedCount Notizen wurden geloescht.',
                                  ),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(
                      strings.localized(
                        en: 'Initialize storage',
                        ja: '\u30b9\u30c8\u30ec\u30fc\u30b8\u3092\u521d\u671f\u5316',
                        zh: '\u521d\u59cb\u5316\u5b58\u50a8',
                        ko: '\uc800\uc7a5\uc18c \ucd08\uae30\ud654',
                        es: 'Inicializar almacenamiento',
                        de: 'Speicher initialisieren',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.about,
          summary: aboutSummary,
          icon: Icons.info_outlined,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(strings.appVersion),
              subtitle: Text(
                packageInfo.when(
                  data: (info) =>
                      _versionWithBuildDate(strings, info.displayVersion),
                  loading: strings.readingVersion,
                  error: (_, _) => _versionWithBuildDate(strings, '1.0.0 (1)'),
                ),
              ),
              onTap: () => _handleVersionTap(context, ref, strings),
            ),
            ListTile(
              key: startTutorialKey,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tips_and_updates_outlined),
              title: Text(
                strings.localized(
                  en: 'Start guided tour',
                  ja: '使い方ガイドを開始',
                  zh: '开始使用指南',
                  ko: '사용 가이드 시작',
                  es: 'Iniciar guia',
                  de: 'Gefuehrte Tour starten',
                ),
              ),
              subtitle: Text(
                strings.localized(
                  en: 'Highlight the main controls and where to find them.',
                  ja: '主要な操作ボタンと場所をハイライトで確認します。',
                  zh: '高亮显示主要控件及其位置。',
                  ko: '주요 조작 버튼과 위치를 하이라이트로 확인합니다.',
                  es: 'Resalta los controles principales y donde encontrarlos.',
                  de: 'Hebt die wichtigsten Bedienelemente und ihre Position hervor.',
                ),
              ),
              onTap: () {
                ref.read(appTutorialControllerProvider.notifier).start();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.new_releases_outlined),
              title: Text(
                strings.localized(
                  en: 'Update history',
                  ja: '\u66f4\u65b0\u5c65\u6b74',
                  zh: '\u66f4\u65b0\u5386\u53f2',
                  ko: '\uc5c5\ub370\uc774\ud2b8 \uae30\ub85d',
                  es: 'Historial de novedades',
                  de: 'Versionsverlauf',
                ),
              ),
              subtitle: Text(
                releaseNotes.when(
                  data: (releases) {
                    final current = currentReleaseNote.asData?.value;
                    if (current != null) {
                      return current.localizedSummary(strings.locale);
                    }
                    if (releases.isNotEmpty) {
                      return strings.localized(
                        en: '${releases.length} release notes are available.',
                        ja: '${releases.length}\u4ef6\u306e\u66f4\u65b0\u5c65\u6b74\u304c\u3042\u308a\u307e\u3059\u3002',
                        zh: '\u53ef\u67e5\u770b ${releases.length} \u6761\u66f4\u65b0\u8bf4\u660e\u3002',
                        ko: '${releases.length}\uac1c\uc758 \uc5c5\ub370\uc774\ud2b8 \uae30\ub85d\uc774 \uc788\uc2b5\ub2c8\ub2e4.',
                        es: 'Hay ${releases.length} notas de version disponibles.',
                        de: '${releases.length} Versionshinweise sind verfuegbar.',
                      );
                    }
                    return strings.localized(
                      en: 'No release notes are available.',
                      ja: '\u66f4\u65b0\u5c65\u6b74\u306f\u307e\u3060\u3042\u308a\u307e\u305b\u3093\u3002',
                      zh: '\u5c1a\u65e0\u66f4\u65b0\u8bf4\u660e\u3002',
                      ko: '\uc5c5\ub370\uc774\ud2b8 \uae30\ub85d\uc774 \uc544\uc9c1 \uc5c6\uc2b5\ub2c8\ub2e4.',
                      es: 'No hay notas de version disponibles.',
                      de: 'Es sind keine Versionshinweise verfuegbar.',
                    );
                  },
                  loading: () => strings.localized(
                    en: 'Reading release notes...',
                    ja: '\u66f4\u65b0\u5c65\u6b74\u3092\u8aad\u307f\u8fbc\u307f\u4e2d...',
                    zh: '\u6b63\u5728\u8bfb\u53d6\u66f4\u65b0\u8bf4\u660e...',
                    ko: '\uc5c5\ub370\uc774\ud2b8 \uae30\ub85d\uc744 \uc77d\ub294 \uc911...',
                    es: 'Leyendo novedades...',
                    de: 'Versionshinweise werden gelesen...',
                  ),
                  error: (_, _) => strings.localized(
                    en: 'Release notes could not be loaded.',
                    ja: '\u66f4\u65b0\u5c65\u6b74\u3092\u8aad\u307f\u8fbc\u3081\u307e\u305b\u3093\u3067\u3057\u305f\u3002',
                    zh: '\u65e0\u6cd5\u8bfb\u53d6\u66f4\u65b0\u8bf4\u660e\u3002',
                    ko: '\uc5c5\ub370\uc774\ud2b8 \uae30\ub85d\uc744 \uc77d\uc744 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.',
                    es: 'No se pudieron cargar las novedades.',
                    de: 'Versionshinweise konnten nicht geladen werden.',
                  ),
                ),
              ),
              onTap: releaseNotes.asData?.value.isEmpty ?? true
                  ? null
                  : () => _showReleaseNotesHistoryDialog(
                      context,
                      releaseNotes.asData!.value,
                      currentReleaseNote.asData?.value?.version,
                    ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update_alt_outlined),
              title: Text(strings.appUpdates),
              subtitle: Text(
                inAppUpdateState.status == null
                    ? appUpdatesDescription
                    : [
                        inAppUpdateSummary,
                        if (inAppUpdateState.status?.availableVersionCode !=
                            null)
                          strings.updateVersionLabel(
                            inAppUpdateState.status?.availableVersionCode,
                          ),
                        if (inAppUpdateState.status?.updatePriority != null)
                          strings.updatePriorityLabel(
                            inAppUpdateState.status?.updatePriority,
                          ),
                        if (inAppUpdateState.status?.installStatus ==
                            InstallStatus.downloaded)
                          strings.updateFlexibleReady,
                      ].join('\n'),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: inAppUpdateState.isBusy
                      ? null
                      : () async {
                          if (!appUpdatesSupported) {
                            await _openStoreListingOrExplain(context, strings);
                            return;
                          }
                          await ref
                              .read(inAppUpdateControllerProvider.notifier)
                              .check();
                          if (!context.mounted) {
                            return;
                          }
                          final message = ref
                              .read(inAppUpdateControllerProvider)
                              .message;
                          if (message != null && message.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(message),
                              ),
                            );
                          }
                        },
                  child: Text(strings.checkForUpdates),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openStoreReviewOrExplain(context, strings),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: Text(strings.writeStoreReview),
                ),
                if (inAppUpdateState.status?.updateAvailable == true &&
                    inAppUpdateState.status?.installStatus !=
                        InstallStatus.downloaded)
                  FilledButton(
                    onPressed: inAppUpdateState.isBusy
                        ? null
                        : () async {
                            await ref
                                .read(inAppUpdateControllerProvider.notifier)
                                .startPreferredUpdate();
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(inAppUpdateControllerProvider)
                                .message;
                            if (message != null && message.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text(message),
                                ),
                              );
                            }
                          },
                    child: Text(strings.startUpdate),
                  ),
                if (inAppUpdateState.status?.installStatus ==
                    InstallStatus.downloaded)
                  FilledButton.tonal(
                    onPressed: inAppUpdateState.isBusy
                        ? null
                        : () async {
                            await ref
                                .read(inAppUpdateControllerProvider.notifier)
                                .completeFlexibleUpdate();
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(inAppUpdateControllerProvider)
                                .message;
                            if (message != null && message.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text(message),
                                ),
                              );
                            }
                          },
                    child: Text(strings.completeUpdateInstall),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(strings.termsOfUse),
              subtitle: Text(strings.termsOfUseDesc),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () =>
                  _openExternalLink(context, Uri.parse(_termsUrl), strings),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(strings.privacyPolicy),
              subtitle: Text(strings.privacyPolicyDesc),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () =>
                  _openExternalLink(context, Uri.parse(_privacyUrl), strings),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const _SettingsListIcon(icon: Icons.email_outlined),
              title: Text(strings.contact),
              subtitle: Text(strings.contactDesc),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () =>
                  _openExternalLink(context, Uri.parse(_contactUrl), strings),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const _SettingsListIcon(
                icon: Icons.help_outline_outlined,
              ),
              title: Text(strings.help),
              subtitle: Text(strings.helpDesc),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () =>
                  _openExternalLink(context, Uri.parse(_helpUrl), strings),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_outlined),
              title: Text(strings.ossLicenses),
              subtitle: Text(strings.ossLicensesDesc),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () {
                final info = packageInfo.asData?.value;
                showLicensePage(
                  context: context,
                  applicationName: info?.appName ?? 'HiMemo',
                  applicationVersion: info?.displayVersion ?? '1.0.0 (1)',
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(strings.appAuthor),
              subtitle: const Text(_appAuthor),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () =>
                  _openExternalLink(context, Uri.parse(_appAuthorUrl), strings),
            ),
            if (showFlavorInfo)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.developer_mode_outlined),
                title: Text(displayName),
                subtitle: Text(strings.currentFlavor(flavorName)),
              ),
          ],
        ),
        if (adminMode) ...[
          const SizedBox(height: 16),
          _buildAuditLogSettingsGroup(
            context: context,
            ref: ref,
            strings: strings,
            snapshot: auditLogSnapshot,
          ),
        ],
        if (diagnosticLogSnapshot?.enabled == true) ...[
          const SizedBox(height: 16),
          _buildDiagnosticLogSettingsGroup(
            context: context,
            ref: ref,
            strings: strings,
            snapshot: diagnosticLogSnapshot!,
          ),
        ],
      ],
    );
  }

  Widget _buildDiagnosticLogSettingsGroup({
    required BuildContext context,
    required WidgetRef ref,
    required AppStrings strings,
    required DiagnosticLogSnapshot snapshot,
  }) {
    final entries = snapshot.entries;
    final preview = entries.isEmpty
        ? strings.localized(
            en: 'No diagnostic log entries yet.',
            ja: '診断ログはまだありません。',
            zh: '还没有诊断日志。',
            ko: '아직 진단 로그가 없습니다.',
            es: 'Aun no hay registros de diagnostico.',
            de: 'Noch keine Diagnoseprotokolleintraege.',
          )
        : entries.reversed.take(120).join('\n');
    return _SettingsGroup(
      title: strings.localized(
        en: 'Diagnostic logs',
        ja: '診断ログ',
        zh: '诊断日志',
        ko: '진단 로그',
        es: 'Registros de diagnostico',
        de: 'Diagnoseprotokolle',
      ),
      summary: strings.localized(
        en: '${entries.length} entries. Sync, attachment display, and network checks are recorded.',
        ja: '${entries.length}件。同期ステップとCloudKit呼び出しを記録します。',
        zh: '${entries.length} 条。记录同步步骤和 CloudKit 调用。',
        ko: '${entries.length}개 항목. 동기화 단계와 CloudKit 호출을 기록합니다.',
        es: '${entries.length} entradas. Se registran pasos de sincronizacion y llamadas CloudKit.',
        de: '${entries.length} Eintraege. Synchronisierungsschritte und CloudKit-Aufrufe werden protokolliert.',
      ),
      icon: Icons.storage_outlined,
      children: [
        Text(
          strings.localized(
            en: 'Hidden diagnostic mode is active. Logs may include device IDs, remote bundle IDs, attachment labels, file references, connection types, timestamps, counts, sizes, and error messages, but not note bodies or attachment bytes.',
            ja: '隠し診断モードが有効です。ログには端末ID、リモートバンドルID、時刻、件数、サイズ、エラー文言が含まれる場合がありますが、メモ本文や添付データは含めません。',
            zh: '隐藏诊断模式已启用。日志可能包含设备 ID、远程包 ID、时间、数量、大小和错误信息，但不包含笔记正文或附件数据。',
            ko: '숨겨진 진단 모드가 켜져 있습니다. 로그에는 기기 ID, 원격 번들 ID, 시각, 개수, 크기, 오류 메시지가 포함될 수 있지만 메모 본문이나 첨부 데이터는 포함하지 않습니다.',
            es: 'El modo de diagnostico oculto esta activo. Los registros pueden incluir IDs de dispositivo, IDs de paquetes remotos, horas, conteos, tamanos y errores, pero no texto de notas ni datos adjuntos.',
            de: 'Der versteckte Diagnosemodus ist aktiv. Protokolle koennen Geraete-IDs, Remote-Paket-IDs, Zeiten, Zaehler, Groessen und Fehlermeldungen enthalten, aber keine Notiztexte oder Anhangsdaten.',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                preview,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(diagnosticLogControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                strings.localized(
                  en: 'Refresh',
                  ja: '更新',
                  zh: '刷新',
                  ko: '새로고침',
                  es: 'Actualizar',
                  de: 'Aktualisieren',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _downloadDiagnosticLog(context, ref, strings),
              icon: const Icon(Icons.download_outlined),
              label: Text(
                strings.localized(
                  en: 'Download',
                  ja: 'ダウンロード',
                  zh: '下载',
                  ko: '다운로드',
                  es: 'Descargar',
                  de: 'Herunterladen',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(diagnosticLogControllerProvider.notifier)
                    .clear();
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    showCloseIcon: true,
                    content: Text(
                      strings.localized(
                        en: 'Diagnostic logs were cleared.',
                        ja: '診断ログを消去しました。',
                        zh: '已清除诊断日志。',
                        ko: '진단 로그를 지웠습니다.',
                        es: 'Se borraron los registros de diagnostico.',
                        de: 'Diagnoseprotokolle wurden geloescht.',
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(
                strings.localized(
                  en: 'Clear',
                  ja: '消去',
                  zh: '清除',
                  ko: '지우기',
                  es: 'Borrar',
                  de: 'Loeschen',
                ),
              ),
            ),
            OutlinedButton.icon(
              key: diagnosticICloudStorageBreakdownKey,
              onPressed: () =>
                  _showICloudStorageBreakdown(context, ref, strings),
              icon: const Icon(Icons.cloud_queue_rounded),
              label: Text(
                strings.localized(
                  en: 'iCloud usage',
                  ja: 'iCloud 使用量',
                  zh: 'iCloud 使用量',
                  ko: 'iCloud 사용량',
                  es: 'Uso de iCloud',
                  de: 'iCloud-Nutzung',
                ),
              ),
            ),
            OutlinedButton.icon(
              key: diagnosticICloudPruneBundlesKey,
              onPressed: () =>
                  _confirmCompactICloudStorage(context, ref, strings),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(
                strings.localized(
                  en: 'Clean old iCloud bundles',
                  ja: 'iCloud 同期データを整理',
                  zh: '清理旧 iCloud 包',
                  ko: '이전 iCloud 번들 정리',
                  es: 'Limpiar paquetes iCloud antiguos',
                  de: 'Alte iCloud-Pakete bereinigen',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => ref
                  .read(diagnosticLogControllerProvider.notifier)
                  .setEnabled(false),
              icon: const Icon(Icons.visibility_off_outlined),
              label: Text(
                strings.localized(
                  en: 'Disable',
                  ja: '無効化',
                  zh: '停用',
                  ko: '끄기',
                  es: 'Desactivar',
                  de: 'Deaktivieren',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuditLogSettingsGroup({
    required BuildContext context,
    required WidgetRef ref,
    required AppStrings strings,
    required AuditLogSnapshot? snapshot,
  }) {
    final entries = snapshot?.entries ?? const <String>[];
    final previewEntries = entries.reversed.take(120).toList(growable: false);
    final emptyMessage = strings.localized(
      en: 'No audit log entries yet.',
      ja: '監査ログはまだありません。',
      zh: 'No audit log entries yet.',
      ko: 'No audit log entries yet.',
      es: 'No audit log entries yet.',
      de: 'No audit log entries yet.',
    );
    return _SettingsGroup(
      title: strings.localized(
        en: 'Audit logs',
        ja: '監査ログ',
        zh: 'Audit logs',
        ko: 'Audit logs',
        es: 'Audit logs',
        de: 'Audit logs',
      ),
      summary: strings.localized(
        en: '${entries.length} entries. Admin access, profile access, and note operations are recorded on this device.',
        ja: '${entries.length}件。管理者アクセス、プロファイル利用、ノート操作をこの端末に記録します。',
        zh: '${entries.length} entries. Admin access, profile access, and note operations are recorded on this device.',
        ko: '${entries.length} entries. Admin access, profile access, and note operations are recorded on this device.',
        es: '${entries.length} entries. Admin access, profile access, and note operations are recorded on this device.',
        de: '${entries.length} entries. Admin access, profile access, and note operations are recorded on this device.',
      ),
      icon: Icons.admin_panel_settings_outlined,
      children: [
        Text(
          strings.localized(
            en: 'Stored locally, up to the latest 2,000 entries. Older entries are removed automatically. Logs include event type, profile or vault ID, note ID, revision, attachment counts, and timestamps, but not note bodies or attachment bytes.',
            ja: 'この端末に最新2,000件まで保存します。上限を超えた古い記録は自動的に削除されます。記録には操作種別、プロファイル/保管庫ID、ノートID、リビジョン、添付数、時刻が含まれますが、ノート本文や添付データは含みません。',
            zh: 'Stored locally, up to the latest 2,000 entries. Older entries are removed automatically. Logs include event type, profile or vault ID, note ID, revision, attachment counts, and timestamps, but not note bodies or attachment bytes.',
            ko: 'Stored locally, up to the latest 2,000 entries. Older entries are removed automatically. Logs include event type, profile or vault ID, note ID, revision, attachment counts, and timestamps, but not note bodies or attachment bytes.',
            es: 'Stored locally, up to the latest 2,000 entries. Older entries are removed automatically. Logs include event type, profile or vault ID, note ID, revision, attachment counts, and timestamps, but not note bodies or attachment bytes.',
            de: 'Stored locally, up to the latest 2,000 entries. Older entries are removed automatically. Logs include event type, profile or vault ID, note ID, revision, attachment counts, and timestamps, but not note bodies or attachment bytes.',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _AuditLogPreview(
                entries: previewEntries,
                emptyMessage: emptyMessage,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(auditLogControllerProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                strings.localized(
                  en: 'Refresh',
                  ja: '更新',
                  zh: 'Refresh',
                  ko: 'Refresh',
                  es: 'Refresh',
                  de: 'Refresh',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _downloadAuditLog(context, ref, strings),
              icon: const Icon(Icons.download_outlined),
              label: Text(
                strings.localized(
                  en: 'Download',
                  ja: 'ダウンロード',
                  zh: 'Download',
                  ko: 'Download',
                  es: 'Download',
                  de: 'Download',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showICloudStorageBreakdown(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    try {
      final breakdown = await ref
          .read(syncTransferControllerProvider.notifier)
          .fetchICloudStorageBreakdown();
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            strings.localized(
              en: 'iCloud storage usage',
              ja: 'iCloud ストレージ使用量',
              zh: 'iCloud 存储使用量',
              ko: 'iCloud 저장 공간 사용량',
              es: 'Uso de almacenamiento de iCloud',
              de: 'iCloud-Speichernutzung',
            ),
          ),
          content: SelectableText(
            strings.localized(
              en: 'Total: ${strings.byteCount(breakdown.totalBytes)}\nSync bundles: ${breakdown.bundleCount} / ${strings.byteCount(breakdown.bundleBytes)}\nAttachments: ${breakdown.attachmentCount} / ${strings.byteCount(breakdown.attachmentBytes)}',
              ja: '合計: ${strings.byteCount(breakdown.totalBytes)}\n同期バンドル: ${breakdown.bundleCount} 件 / ${strings.byteCount(breakdown.bundleBytes)}\n添付オブジェクト: ${breakdown.attachmentCount} 件 / ${strings.byteCount(breakdown.attachmentBytes)}',
              zh: '总计：${strings.byteCount(breakdown.totalBytes)}\n同步包：${breakdown.bundleCount} / ${strings.byteCount(breakdown.bundleBytes)}\n附件：${breakdown.attachmentCount} / ${strings.byteCount(breakdown.attachmentBytes)}',
              ko: '합계: ${strings.byteCount(breakdown.totalBytes)}\n동기화 번들: ${breakdown.bundleCount}개 / ${strings.byteCount(breakdown.bundleBytes)}\n첨부 파일: ${breakdown.attachmentCount}개 / ${strings.byteCount(breakdown.attachmentBytes)}',
              es: 'Total: ${strings.byteCount(breakdown.totalBytes)}\nPaquetes de sincronizacion: ${breakdown.bundleCount} / ${strings.byteCount(breakdown.bundleBytes)}\nAdjuntos: ${breakdown.attachmentCount} / ${strings.byteCount(breakdown.attachmentBytes)}',
              de: 'Gesamt: ${strings.byteCount(breakdown.totalBytes)}\nSync-Pakete: ${breakdown.bundleCount} / ${strings.byteCount(breakdown.bundleBytes)}\nAnhaenge: ${breakdown.attachmentCount} / ${strings.byteCount(breakdown.attachmentBytes)}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.close),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(showCloseIcon: true, content: Text('$error')));
    }
  }

  Future<void> _confirmCompactICloudStorage(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          strings.localized(
            en: 'Clean old iCloud sync bundles?',
            ja: 'iCloud 同期データを整理しますか？',
            zh: '清理旧的 iCloud 同步包？',
            ko: '이전 iCloud 동기화 번들을 정리할까요?',
            es: '¿Limpiar paquetes antiguos de iCloud?',
            de: 'Alte iCloud-Sync-Pakete bereinigen?',
          ),
        ),
        content: Text(
          strings.localized(
            en: 'This uploads the current state as a fresh full snapshot, keeps that latest iCloud bundle, and deletes older bundles plus attachment objects no longer referenced by the latest snapshot.',
            ja: '現在の状態を新しいフルスナップショットとしてアップロードし、その最新 iCloud バンドルだけを残します。古いバンドルと、最新スナップショットから参照されない添付オブジェクトも削除します。',
            zh: '这会保留最新的 iCloud 同步包并删除旧的包快照。此命令不会删除附件对象。',
            ko: '최신 iCloud 동기화 번들 1개를 남기고 이전 번들 스냅샷을 삭제합니다. 이 명령은 첨부 파일 객체를 삭제하지 않습니다.',
            es: 'Sube el estado actual como una instantanea completa, conserva el paquete mas reciente y elimina paquetes antiguos y adjuntos sin referencia.',
            de: 'Laedt den aktuellen Stand als vollstaendigen Snapshot hoch, behaelt das neueste Paket und loescht alte Pakete sowie nicht referenzierte Anhaenge.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.text('home.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final result = await ref
          .read(syncTransferControllerProvider.notifier)
          .compactICloudStorage();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.localized(
              en: 'Deleted ${result.deletedBundleCount} old bundles and ${result.deletedAttachmentCount} unreferenced attachments (${strings.byteCount(result.deletedBytes)}).',
              ja: '古いバンドル ${result.deletedBundleCount} 件と未参照の添付 ${result.deletedAttachmentCount} 件（${strings.byteCount(result.deletedBytes)}）を削除しました。',
              zh: '已删除 ${result.deletedBundleCount} 个旧 iCloud 包（${strings.byteCount(result.deletedBundleBytes)}）。',
              ko: '이전 iCloud 번들 ${result.deletedBundleCount}개(${strings.byteCount(result.deletedBundleBytes)})를 삭제했습니다.',
              es: 'Se eliminaron ${result.deletedBundleCount} paquetes antiguos y ${result.deletedAttachmentCount} adjuntos sin referencia (${strings.byteCount(result.deletedBytes)}).',
              de: '${result.deletedBundleCount} alte Pakete und ${result.deletedAttachmentCount} nicht referenzierte Anhaenge geloescht (${strings.byteCount(result.deletedBytes)}).',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(showCloseIcon: true, content: Text('$error')));
    }
  }

  Future<void> _downloadDiagnosticLog(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final text = await ref
        .read(diagnosticLogControllerProvider.notifier)
        .exportText();
    final bytes = Uint8List.fromList(utf8.encode(text));
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final fileName = 'himemo-diagnostic-log-$timestamp.txt';
    final savedPath = await FilePicker.saveFile(
      dialogTitle: strings.localized(
        en: 'Download diagnostic log',
        ja: '診断ログをダウンロード',
        zh: '下载诊断日志',
        ko: '진단 로그 다운로드',
        es: 'Descargar registro de diagnostico',
        de: 'Diagnoseprotokoll herunterladen',
      ),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: bytes,
    );
    if (!context.mounted) {
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.localized(
              en: 'Diagnostic log download was started.',
              ja: '診断ログのダウンロードを開始しました。',
              zh: '已开始下载诊断日志。',
              ko: '진단 로그 다운로드를 시작했습니다.',
              es: 'Se inicio la descarga del registro de diagnostico.',
              de: 'Download des Diagnoseprotokolls wurde gestartet.',
            ),
          ),
        ),
      );
      return;
    }
    if (savedPath == null || savedPath.isEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: fileName, mimeType: 'text/plain'),
          ],
          text: 'HiMemo diagnostic log',
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Diagnostic log was downloaded.',
            ja: '診断ログをダウンロードしました。',
            zh: '已下载诊断日志。',
            ko: '진단 로그를 다운로드했습니다.',
            es: 'Se descargo el registro de diagnostico.',
            de: 'Diagnoseprotokoll wurde heruntergeladen.',
          ),
        ),
      ),
    );
  }

  Future<void> _downloadAuditLog(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final text = await ref
        .read(auditLogControllerProvider.notifier)
        .exportText();
    final bytes = Uint8List.fromList(utf8.encode(text));
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final fileName = 'himemo-audit-log-$timestamp.txt';
    final savedPath = await FilePicker.saveFile(
      dialogTitle: strings.localized(
        en: 'Download audit log',
        ja: '監査ログをダウンロード',
        zh: 'Download audit log',
        ko: 'Download audit log',
        es: 'Download audit log',
        de: 'Download audit log',
      ),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: bytes,
    );
    if (!context.mounted) {
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.localized(
              en: 'Audit log download was started.',
              ja: '監査ログのダウンロードを開始しました。',
              zh: 'Audit log download was started.',
              ko: 'Audit log download was started.',
              es: 'Audit log download was started.',
              de: 'Audit log download was started.',
            ),
          ),
        ),
      );
      return;
    }
    if (savedPath == null || savedPath.isEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, name: fileName, mimeType: 'text/plain'),
          ],
          text: 'HiMemo audit log',
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Audit log was downloaded.',
            ja: '監査ログをダウンロードしました。',
            zh: 'Audit log was downloaded.',
            ko: 'Audit log was downloaded.',
            es: 'Audit log was downloaded.',
            de: 'Audit log was downloaded.',
          ),
        ),
      ),
    );
  }

  Widget _buildAppearanceSettingsGroup({
    required BuildContext context,
    required WidgetRef ref,
    required AppStrings strings,
    required AppLocaleSetting localeSetting,
    required ThemeMode themeMode,
    required AppFontFamily fontFamily,
    required AppColorTheme colorTheme,
    required String appearanceScope,
    required List<_ColorThemeScopeOption> appearanceScopeTargets,
    required String appearanceScopeLabel,
    required String appearanceSummary,
    required Key sectionKey,
    required ExpansibleController controller,
  }) {
    final effectiveFontFamily = _availableFontFamilies.contains(fontFamily)
        ? fontFamily
        : AppFontFamily.system;
    return _SettingsGroup(
      title: strings.appearanceWithControls,
      summary: appearanceSummary,
      icon: Icons.palette_outlined,
      sectionKey: sectionKey,
      controller: controller,
      semanticLabel: 'settings-appearance',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            strings.language,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        DropdownButtonFormField<AppLocaleSetting>(
          key: SettingsScreen.localeDropdownKey,
          initialValue: localeSetting,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: strings.languageSystemDesc,
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.translate_rounded),
          ),
          items: [
            DropdownMenuItem(
              key: SettingsScreen.localeSystemKey,
              value: AppLocaleSetting.system,
              child: Text(strings.languageSystemOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeJapaneseKey,
              value: AppLocaleSetting.japanese,
              child: Text(strings.languageJapaneseOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeEnglishKey,
              value: AppLocaleSetting.english,
              child: Text(strings.languageEnglishOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeChineseKey,
              value: AppLocaleSetting.chinese,
              child: Text(strings.languageChineseOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeKoreanKey,
              value: AppLocaleSetting.korean,
              child: Text(strings.languageKoreanOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeSpanishKey,
              value: AppLocaleSetting.spanish,
              child: Text(strings.languageSpanishOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeGermanKey,
              value: AppLocaleSetting.german,
              child: Text(strings.languageGermanOption),
            ),
          ],
          onChanged: (value) {
            if (value == null || value == localeSetting) {
              return;
            }
            _setLocaleForScope(ref, appearanceScope, value);
          },
        ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            strings.appFont,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        DropdownButtonFormField<AppFontFamily>(
          key: SettingsScreen.fontDropdownKey,
          initialValue: effectiveFontFamily,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: strings.appFontDesc,
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.text_fields_rounded),
          ),
          items: _availableFontFamilies
              .map(
                (font) => DropdownMenuItem(
                  value: font,
                  child: Text(_fontFamilyLabel(context, font)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null || value == effectiveFontFamily) {
              return;
            }
            _setFontForScope(ref, appearanceScope, value);
          },
        ),
        const Divider(height: 24),
        _ThemeOptionTile(
          tileKey: lightThemeKey,
          title: strings.themeLight,
          subtitle: strings.lightDesc,
          selected: themeMode == ThemeMode.light,
          onTap: () =>
              _setThemeModeForScope(ref, appearanceScope, ThemeMode.light),
        ),
        _ThemeOptionTile(
          tileKey: systemThemeKey,
          title: strings.themeSystem,
          subtitle: strings.systemDesc,
          selected: themeMode == ThemeMode.system,
          onTap: () =>
              _setThemeModeForScope(ref, appearanceScope, ThemeMode.system),
        ),
        _ThemeOptionTile(
          tileKey: darkThemeKey,
          title: strings.themeDark,
          subtitle: strings.darkDesc,
          selected: themeMode == ThemeMode.dark,
          onTap: () =>
              _setThemeModeForScope(ref, appearanceScope, ThemeMode.dark),
        ),
        const Divider(height: 24),
        if (appearanceScopeTargets.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: appearanceScope,
            isExpanded: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: strings.localized(
                en: 'Settings target',
                ja: '設定先',
                zh: '设置目标',
                ko: '설정 대상',
                es: 'Destino de ajustes',
                de: 'Einstellungsziel',
              ),
              prefixIcon: const Icon(Icons.palette_outlined),
            ),
            items: [
              for (final target in appearanceScopeTargets)
                DropdownMenuItem(
                  value: target.scope,
                  child: Text(target.label),
                ),
            ],
            onChanged: (value) {
              if (value == null || value == appearanceScope) {
                return;
              }
              ref.read(colorThemeSettingsScopeProvider.notifier).select(value);
            },
          ),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${strings.accentColor} ($appearanceScopeLabel)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                strings.accentColorJapanesePaletteDesc,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ],
          ),
        ),
        _ColorThemePicker(
          current: colorTheme,
          basicThemes: const [
            AppColorTheme.konjyo,
            AppColorTheme.moegi,
            AppColorTheme.yamabuki,
            AppColorTheme.kurenai,
            AppColorTheme.sakura,
          ],
          extendedThemes: const [
            AppColorTheme.konjyo,
            AppColorTheme.ai,
            AppColorTheme.ruri,
            AppColorTheme.hanada,
            AppColorTheme.chigusa,
            AppColorTheme.asagi,
            AppColorTheme.sora,
            AppColorTheme.tokiwa,
            AppColorTheme.seiheki,
            AppColorTheme.wakatake,
            AppColorTheme.moegi,
            AppColorTheme.byakuroku,
            AppColorTheme.rikyucha,
            AppColorTheme.kurumi,
            AppColorTheme.yamabuki,
            AppColorTheme.nanohana,
            AppColorTheme.enji,
            AppColorTheme.akane,
            AppColorTheme.kurenai,
            AppColorTheme.haizakura,
            AppColorTheme.sakura,
            AppColorTheme.sumi,
            AppColorTheme.ginnezumi,
            AppColorTheme.shironeri,
            AppColorTheme.gofun,
            AppColorTheme.kikyo,
            AppColorTheme.edomurasaki,
            AppColorTheme.sumire,
            AppColorTheme.fuji,
            AppColorTheme.shion,
          ],
          titleFor: (theme) => _colorThemeLabel(context, theme),
          subtitleFor: (theme) => _colorThemeDescription(context, theme),
          sampleColorFor: _themeSampleColor,
          tileKeyFor: _colorThemeTileKey,
          onSelect: (theme) =>
              _setColorThemeForScope(ref, appearanceScope, theme),
        ),
      ],
    );
  }

  String _syncStatusTitle(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.icloud.availability');
    }
    return strings.text('home.authentication');
  }

  String _syncConnectLabel(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.check.icloud');
    }
    return strings.text('home.connect');
  }

  String _syncReconnectLabel(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.check.again');
    }
    return strings.text('home.reconnect');
  }

  String _syncDisconnectLabel(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.stop.using.icloud');
    }
    return strings.text('home.disconnect');
  }

  String _syncSubtitle(
    BuildContext context,
    SyncProvider provider,
    SyncAuthState authState,
  ) {
    final strings = context.strings;
    switch (provider) {
      case SyncProvider.off:
        return strings.text('home.sync.is.disabled');
      case SyncProvider.iCloud:
        return strings.text(
          'home.icloud.selected.the.app.checks.this.device.s.icloud.avai',
        );
      case SyncProvider.googleDrive:
        if (authState.isAuthenticated) {
          return strings.localized(
            en: 'Google Drive app-data sync is connected and ready.',
            ja: 'Google Drive のアプリデータ同期は接続済みです。',
            zh: 'Google Drive 应用数据同步已连接并可使用。',
            ko: 'Google Drive 앱 데이터 동기화가 연결되어 사용할 수 있습니다.',
            es: 'La sincronizacion de datos de la app con Google Drive esta conectada y lista.',
            de: 'Die Google Drive App-Daten-Synchronisierung ist verbunden und bereit.',
          );
        }
        return strings.text(
          'home.google.drive.selected.authorize.access.to.drive.app.data',
        );
    }
  }

  String syncSubtitleLegacy(BuildContext context, SyncProvider provider) {
    return _syncSubtitle(
      context,
      provider,
      SyncAuthState(provider: provider, stage: SyncAuthStage.idle),
    );
  }

  String _syncAuthSummary(
    BuildContext context,
    SyncProvider provider,
    SyncAuthState authState,
  ) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      switch (authState.stage) {
        case SyncAuthStage.idle:
          return strings.text(
            'home.this.device.s.icloud.availability.has.not.been.checked.y',
          );
        case SyncAuthStage.busy:
          return strings.text(
            'home.checking.this.device.s.icloud.availability',
          );
        case SyncAuthStage.authenticated:
          return strings.text(
            'home.this.device.can.use.icloud.as.the.himemo.sync.target',
          );
        case SyncAuthStage.unsupported:
        case SyncAuthStage.error:
          return authState.message ??
              (strings.text(
                'home.icloud.sync.is.not.available.on.this.device',
              ));
      }
    }
    if (provider == SyncProvider.off) {
      return strings.text('home.no.cloud.account.is.connected');
    }

    switch (authState.stage) {
      case SyncAuthStage.idle:
        return strings.text('home.no.account.connected.yet');
      case SyncAuthStage.busy:
        return strings.text('home.waiting.for.authentication.to.complete');
      case SyncAuthStage.authenticated:
        final identity =
            authState.email ?? authState.displayName ?? authState.userId;
        final suffix = authState.message == null ? '' : ' ${authState.message}';
        return identity == null
            ? strings.syncConnected(suffix: suffix)
            : strings.syncConnected(identity: identity, suffix: suffix);
      case SyncAuthStage.unsupported:
      case SyncAuthStage.error:
        if (provider == SyncProvider.googleDrive &&
            _isGoogleDriveWebSignInUnavailable(authState.message)) {
          return strings.googleDriveWebSignInUnavailable;
        }
        return authState.message ??
            (strings.text('home.authentication.is.not.available'));
    }
  }

  bool _isGoogleDriveWebSignInUnavailable(String? message) {
    return message != null &&
        message.contains(
          'Google Drive sync on web requires the Google Sign-In SDK button flow',
        );
  }

  String syncAuthSummaryLegacy(
    BuildContext context,
    SyncProvider provider,
    SyncAuthState authState,
  ) {
    final strings = context.strings;
    if (provider == SyncProvider.off) {
      return strings.text('home.no.cloud.account.is.connected.2');
    }

    switch (authState.stage) {
      case SyncAuthStage.idle:
        return strings.text('home.no.account.connected.yet.2');
      case SyncAuthStage.busy:
        return strings.text('home.waiting.for.authentication.to.complete.2');
      case SyncAuthStage.authenticated:
        final identity =
            authState.email ?? authState.displayName ?? authState.userId;
        final suffix = authState.message == null ? '' : ' ${authState.message}';
        return identity == null
            ? strings.syncConnectedLegacy(suffix: suffix)
            : strings.syncConnectedLegacy(identity: identity, suffix: suffix);
      case SyncAuthStage.unsupported:
      case SyncAuthStage.error:
        return authState.message ??
            (strings.text('home.authentication.is.not.available.2'));
    }
  }

  Future<void> _showSetPrivateKeyDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secretController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(strings.setPrivateKey),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: secretController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: strings.privateKey,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: strings.confirmPrivateKey(strings.privateKey),
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final secret = secretController.text.trim();
                    final confirm = confirmController.text.trim();
                    if (secret.length < 4) {
                      setState(() {
                        errorText = strings.useAtLeast4Chars;
                      });
                      return;
                    }
                    if (secret != confirm) {
                      setState(() {
                        errorText = strings.keysDoNotMatch;
                      });
                      return;
                    }
                    await ref
                        .read(privateVaultSecretControllerProvider.notifier)
                        .configure(secret);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(strings.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showUnlockPrivateVaultDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secretController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(strings.unlockPrivateVault),
              content: TextField(
                controller: secretController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: strings.privateKey,
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final matched = await ref
                        .read(privateVaultSecretControllerProvider.notifier)
                        .verify(secretController.text.trim());
                    if (!matched) {
                      setState(() {
                        errorText = strings.privateKeyIncorrect;
                      });
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(strings.unlock),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmResetPrivateKey(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.resetPrivateKey),
          content: Text(strings.resetPrivateKeyBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.reset),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(privateVaultSecretControllerProvider.notifier).clear();
    }
  }

  Future<void> _addSyncExclusionTag(BuildContext context, WidgetRef ref) async {
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => const _SyncExclusionTagDialog(),
    );
    if (tag == null || tag.isEmpty) {
      return;
    }
    await ref.read(syncExclusionTagsControllerProvider.notifier).addTag(tag);
  }

  Future<bool?> _confirmStorageReset(BuildContext context, int noteCount) {
    final strings = context.strings;
    var agreed = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                strings.localized(
                  en: 'Initialize storage',
                  ja: '\u30b9\u30c8\u30ec\u30fc\u30b8\u3092\u521d\u671f\u5316',
                  zh: '\u521d\u59cb\u5316\u5b58\u50a8',
                  ko: '\uc800\uc7a5\uc18c \ucd08\uae30\ud654',
                  es: 'Inicializar almacenamiento',
                  de: 'Speicher initialisieren',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.localized(
                      en: 'This deletes all notes and attachments saved on this device. This action cannot be undone.',
                      ja: '\u3053\u306e\u7aef\u672b\u306b\u4fdd\u5b58\u3055\u308c\u3066\u3044\u308b\u3059\u3079\u3066\u306e\u30ce\u30fc\u30c8\u3068\u6dfb\u4ed8\u30d5\u30a1\u30a4\u30eb\u3092\u524a\u9664\u3057\u307e\u3059\u3002\u3053\u306e\u64cd\u4f5c\u306f\u5143\u306b\u623b\u305b\u307e\u305b\u3093\u3002',
                      zh: '\u8fd9\u5c06\u5220\u9664\u6b64\u8bbe\u5907\u4e0a\u4fdd\u5b58\u7684\u6240\u6709\u7b14\u8bb0\u548c\u9644\u4ef6\u3002\u6b64\u64cd\u4f5c\u65e0\u6cd5\u64a4\u9500\u3002',
                      ko: '\uc774 \uae30\uae30\uc5d0 \uc800\uc7a5\ub41c \ubaa8\ub4e0 \uba54\ubaa8\uc640 \ucca8\ubd80 \ud30c\uc77c\uc744 \uc0ad\uc81c\ud569\ub2c8\ub2e4. \uc774 \uc791\uc5c5\uc740 \ub418\ub3cc\ub9b4 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.',
                      es: 'Esto elimina todas las notas y adjuntos guardados en este dispositivo. Esta accion no se puede deshacer.',
                      de: 'Dies loescht alle Notizen und Anhaenge auf diesem Geraet. Diese Aktion kann nicht rueckgaengig gemacht werden.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.localized(
                      en: 'Notes to delete: $noteCount',
                      ja: '\u524a\u9664\u5bfe\u8c61\u306e\u30ce\u30fc\u30c8: $noteCount \u4ef6',
                      zh: '\u8981\u5220\u9664\u7684\u7b14\u8bb0\uff1a$noteCount',
                      ko: '\uc0ad\uc81c\ud560 \uba54\ubaa8: $noteCount\uac1c',
                      es: 'Notas a eliminar: $noteCount',
                      de: 'Zu loeschende Notizen: $noteCount',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: agreed,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      strings.localized(
                        en: 'I understand that the data will be deleted.',
                        ja: '\u30c7\u30fc\u30bf\u304c\u524a\u9664\u3055\u308c\u308b\u3053\u3068\u306b\u540c\u610f\u3057\u307e\u3059\u3002',
                        zh: '\u6211\u7406\u89e3\u5e76\u540c\u610f\u6570\u636e\u5c06\u88ab\u5220\u9664\u3002',
                        ko: '\ub370\uc774\ud130\uac00 \uc0ad\uc81c\ub428\uc744 \uc774\ud574\ud558\uace0 \ub3d9\uc758\ud569\ub2c8\ub2e4.',
                        es: 'Entiendo que los datos se eliminaran.',
                        de: 'Ich verstehe, dass die Daten geloescht werden.',
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        agreed = value ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: agreed
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: Text(strings.delete),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const _availableFontFamilies = <AppFontFamily>[
    ...iOSFriendlyAppFontFamilies,
  ];

  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    final strings = context.strings;
    return switch (mode) {
      ThemeMode.light => strings.themeLight,
      ThemeMode.system => strings.themeSystem,
      ThemeMode.dark => strings.themeDark,
    };
  }

  String _fontFamilyLabel(BuildContext context, AppFontFamily fontFamily) {
    final strings = context.strings;
    return switch (fontFamily) {
      AppFontFamily.system => strings.fontSystem,
      AppFontFamily.gothic => strings.fontGothic,
      AppFontFamily.uiGothic => strings.fontUiGothic,
      AppFontFamily.kakuGothic => strings.fontKakuGothic,
      AppFontFamily.mincho => strings.fontMincho,
      AppFontFamily.uiMincho => strings.fontUiMincho,
      AppFontFamily.rounded => strings.fontRounded,
      AppFontFamily.zenRounded => strings.fontZenRounded,
      AppFontFamily.casual => strings.fontCasual,
      AppFontFamily.monospace => strings.fontMonospace,
    };
  }

  String _localeSettingLabel(BuildContext context, AppLocaleSetting setting) {
    final strings = context.strings;
    return switch (setting) {
      AppLocaleSetting.system => strings.languageSystemOption,
      AppLocaleSetting.japanese => strings.languageJapaneseOption,
      AppLocaleSetting.english => strings.languageEnglishOption,
      AppLocaleSetting.chinese => strings.languageChineseOption,
      AppLocaleSetting.korean => strings.languageKoreanOption,
      AppLocaleSetting.spanish => strings.languageSpanishOption,
      AppLocaleSetting.german => strings.languageGermanOption,
    };
  }

  String _colorThemeLabel(BuildContext context, AppColorTheme theme) {
    final strings = context.strings;
    return switch (theme) {
      AppColorTheme.konjyo => strings.colorKonjyo,
      AppColorTheme.moegi => strings.colorMoegi,
      AppColorTheme.yamabuki => strings.colorYamabuki,
      AppColorTheme.ginnezumi => strings.colorGinnezumi,
      AppColorTheme.seiheki => strings.colorSeiheki,
      AppColorTheme.kurenai => strings.colorKurenai,
      AppColorTheme.sakura => strings.colorSakura,
      AppColorTheme.fuji => strings.colorFuji,
      AppColorTheme.ai => strings.colorAi,
      AppColorTheme.kurumi => strings.colorKurumi,
      AppColorTheme.chigusa => strings.colorChigusa,
      AppColorTheme.sumire => strings.colorSumire,
      AppColorTheme.sumi => strings.colorSumi,
      AppColorTheme.shironeri => strings.colorShironeri,
      AppColorTheme.gofun => strings.colorGofun,
      AppColorTheme.enji => strings.colorEnji,
      AppColorTheme.hanada => strings.colorHanada,
      AppColorTheme.sora => strings.colorSora,
      AppColorTheme.ruri => strings.colorRuri,
      AppColorTheme.asagi => strings.colorAsagi,
      AppColorTheme.wakatake => strings.colorWakatake,
      AppColorTheme.tokiwa => strings.colorTokiwa,
      AppColorTheme.byakuroku => strings.colorByakuroku,
      AppColorTheme.nanohana => strings.colorNanohana,
      AppColorTheme.haizakura => strings.colorHaizakura,
      AppColorTheme.akane => strings.colorAkane,
      AppColorTheme.kikyo => strings.colorKikyo,
      AppColorTheme.edomurasaki => strings.colorEdomurasaki,
      AppColorTheme.shion => strings.colorShion,
      AppColorTheme.rikyucha => strings.colorRikyucha,
    };
  }

  String _colorThemeDescription(BuildContext context, AppColorTheme theme) {
    final strings = context.strings;
    return switch (theme) {
      AppColorTheme.konjyo => strings.colorKonjyoDesc,
      AppColorTheme.moegi => strings.colorMoegiDesc,
      AppColorTheme.yamabuki => strings.colorYamabukiDesc,
      AppColorTheme.ginnezumi => strings.colorGinnezumiDesc,
      AppColorTheme.seiheki => strings.colorSeihekiDesc,
      AppColorTheme.kurenai => strings.colorKurenaiDesc,
      AppColorTheme.sakura => strings.colorSakuraDesc,
      AppColorTheme.fuji => strings.colorFujiDesc,
      AppColorTheme.ai => strings.colorAiDesc,
      AppColorTheme.kurumi => strings.colorKurumiDesc,
      AppColorTheme.chigusa => strings.colorChigusaDesc,
      AppColorTheme.sumire => strings.colorSumireDesc,
      AppColorTheme.sumi => strings.colorSumiDesc,
      AppColorTheme.shironeri => strings.colorShironeriDesc,
      AppColorTheme.gofun => strings.colorGofunDesc,
      AppColorTheme.enji => strings.colorEnjiDesc,
      AppColorTheme.hanada => strings.colorHanadaDesc,
      AppColorTheme.sora => strings.colorSoraDesc,
      AppColorTheme.ruri => strings.colorRuriDesc,
      AppColorTheme.asagi => strings.colorAsagiDesc,
      AppColorTheme.wakatake => strings.colorWakatakeDesc,
      AppColorTheme.tokiwa => strings.colorTokiwaDesc,
      AppColorTheme.byakuroku => strings.colorByakurokuDesc,
      AppColorTheme.nanohana => strings.colorNanohanaDesc,
      AppColorTheme.haizakura => strings.colorHaizakuraDesc,
      AppColorTheme.akane => strings.colorAkaneDesc,
      AppColorTheme.kikyo => strings.colorKikyoDesc,
      AppColorTheme.edomurasaki => strings.colorEdomurasakiDesc,
      AppColorTheme.shion => strings.colorShionDesc,
      AppColorTheme.rikyucha => strings.colorRikyuchaDesc,
    };
  }

  Future<void> _setColorThemeForScope(
    WidgetRef ref,
    String scope,
    AppColorTheme theme,
  ) {
    if (scope == defaultColorThemeScope) {
      return ref.read(appColorThemeControllerProvider.notifier).setTheme(theme);
    }
    return ref
        .read(profileColorThemeControllerProvider.notifier)
        .setTheme(scope, theme);
  }

  Future<void> _setThemeModeForScope(
    WidgetRef ref,
    String scope,
    ThemeMode mode,
  ) {
    if (scope == defaultColorThemeScope) {
      return ref.read(themeModeControllerProvider.notifier).setMode(mode);
    }
    return ref
        .read(profileThemeModeControllerProvider.notifier)
        .setMode(scope, mode);
  }

  Future<void> _setLocaleForScope(
    WidgetRef ref,
    String scope,
    AppLocaleSetting locale,
  ) {
    if (scope == defaultColorThemeScope) {
      return ref.read(appLocaleControllerProvider.notifier).setLocale(locale);
    }
    return ref
        .read(profileLocaleControllerProvider.notifier)
        .setLocale(scope, locale);
  }

  Future<void> _setFontForScope(
    WidgetRef ref,
    String scope,
    AppFontFamily font,
  ) {
    if (scope == defaultColorThemeScope) {
      return ref.read(appFontFamilyControllerProvider.notifier).setFont(font);
    }
    return ref
        .read(profileFontFamilyControllerProvider.notifier)
        .setFont(scope, font);
  }

  Color _themeSampleColor(AppColorTheme theme) {
    return switch (theme) {
      AppColorTheme.konjyo => const Color(0xFF113285),
      AppColorTheme.moegi => const Color(0xFF7BA23F),
      AppColorTheme.yamabuki => const Color(0xFFFFB11B),
      AppColorTheme.ginnezumi => const Color(0xFF91989F),
      AppColorTheme.seiheki => const Color(0xFF268785),
      AppColorTheme.kurenai => const Color(0xFFCB1B45),
      AppColorTheme.sakura => const Color(0xFFFEDFE1),
      AppColorTheme.fuji => const Color(0xFF8B81C3),
      AppColorTheme.ai => const Color(0xFF0F4C81),
      AppColorTheme.kurumi => const Color(0xFF947A6D),
      AppColorTheme.chigusa => const Color(0xFF3A8FB7),
      AppColorTheme.sumire => const Color(0xFF66327C),
      AppColorTheme.sumi => const Color(0xFF1C1C1C),
      AppColorTheme.shironeri => const Color(0xFFF3F3F2),
      AppColorTheme.gofun => const Color(0xFFFFFBF0),
      AppColorTheme.enji => const Color(0xFF9F353A),
      AppColorTheme.hanada => const Color(0xFF006284),
      AppColorTheme.sora => const Color(0xFF58B2DC),
      AppColorTheme.ruri => const Color(0xFF005CAF),
      AppColorTheme.asagi => const Color(0xFF33A6B8),
      AppColorTheme.wakatake => const Color(0xFF5DAC81),
      AppColorTheme.tokiwa => const Color(0xFF1B813E),
      AppColorTheme.byakuroku => const Color(0xFFA8D8B9),
      AppColorTheme.nanohana => const Color(0xFFFFEC47),
      AppColorTheme.haizakura => const Color(0xFFD7C4BB),
      AppColorTheme.akane => const Color(0xFFB7282E),
      AppColorTheme.kikyo => const Color(0xFF6A4C9C),
      AppColorTheme.edomurasaki => const Color(0xFF77428D),
      AppColorTheme.shion => const Color(0xFF8F77B5),
      AppColorTheme.rikyucha => const Color(0xFF897D55),
    };
  }

  Key? _colorThemeTileKey(AppColorTheme theme) {
    return switch (theme) {
      AppColorTheme.konjyo => SettingsScreen.konjyoColorThemeKey,
      AppColorTheme.moegi => SettingsScreen.moegiColorThemeKey,
      AppColorTheme.yamabuki => SettingsScreen.yamabukiColorThemeKey,
      _ => null,
    };
  }

  String _notesListSortLabel(AppStrings strings, NotesListSortField sortField) {
    return switch (sortField) {
      NotesListSortField.updatedAt => strings.localized(
        en: 'Updated first',
        ja: '更新順',
        zh: '按更新时间',
        ko: '수정순',
        es: 'Actualizadas primero',
        de: 'Zuletzt bearbeitet',
      ),
      NotesListSortField.createdAt => strings.localized(
        en: 'Created first',
        ja: '作成順',
        zh: '按创建时间',
        ko: '생성순',
        es: 'Creadas primero',
        de: 'Zuletzt erstellt',
      ),
    };
  }
}

class _SyncExclusionTagsTile extends StatelessWidget {
  const _SyncExclusionTagsTile({
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync_disabled_rounded),
            title: Text(
              strings.localized(
                en: 'Excluded sync tags',
                ja: '\u540c\u671f\u5bfe\u8c61\u5916\u30bf\u30b0',
                zh: '\u6392\u9664\u540c\u6b65\u6807\u7b7e',
                ko: '\ub3d9\uae30\ud654 \uc81c\uc678 \ud0dc\uadf8',
                es: 'Etiquetas excluidas de sincronizacion',
                de: 'Vom Sync ausgeschlossene Tags',
              ),
            ),
            subtitle: Text(
              strings.localized(
                en: 'Notes with these tags stay on this device and are not written to the cloud bundle.',
                ja: '\u3053\u308c\u3089\u306e\u30bf\u30b0\u304c\u4ed8\u3044\u305f\u30e1\u30e2\u306f\u3053\u306e\u7aef\u672b\u306b\u6b8b\u308a\u3001\u30af\u30e9\u30a6\u30c9\u30d0\u30f3\u30c9\u30eb\u306b\u66f8\u304d\u51fa\u3055\u308c\u307e\u305b\u3093\u3002',
                zh: '\u5e26\u6709\u8fd9\u4e9b\u6807\u7b7e\u7684\u7b14\u8bb0\u4f1a\u7559\u5728\u6b64\u8bbe\u5907\uff0c\u4e0d\u5199\u5165\u4e91\u7aef\u5305\u3002',
                ko: '\uc774 \ud0dc\uadf8\uac00 \uc788\ub294 \uba54\ubaa8\ub294 \uc774 \uae30\uae30\uc5d0 \ub0a8\uace0 \ud074\ub77c\uc6b0\ub4dc \ubc88\ub4e4\uc5d0 \uae30\ub85d\ub418\uc9c0 \uc54a\uc2b5\ub2c8\ub2e4.',
                es: 'Las notas con estas etiquetas se quedan en este dispositivo y no se escriben en el paquete de nube.',
                de: 'Notizen mit diesen Tags bleiben auf diesem Geraet und werden nicht in das Cloud-Bundle geschrieben.',
              ),
            ),
            trailing: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                strings.localized(
                  en: 'Add',
                  ja: '\u8ffd\u52a0',
                  zh: '\u6dfb\u52a0',
                  ko: '\ucd94\uac00',
                  es: 'Agregar',
                  de: 'Hinzufuegen',
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                InputChip(
                  avatar: isSystemSyncExclusionTag(tag)
                      ? const Icon(Icons.lock_outline_rounded, size: 18)
                      : null,
                  label: Text(_displayNoteTagWithHash(context, tag)),
                  tooltip: isSystemSyncExclusionTag(tag)
                      ? strings.localized(
                          en: 'Built-in tag. It cannot be removed.',
                          ja: '\u521d\u671f\u767b\u9332\u306e\u30b7\u30b9\u30c6\u30e0\u30bf\u30b0\u306e\u305f\u3081\u524a\u9664\u3067\u304d\u307e\u305b\u3093\u3002',
                          zh: '\u5185\u7f6e\u6807\u7b7e\uff0c\u65e0\u6cd5\u5220\u9664\u3002',
                          ko: '\uae30\ubcf8 \uc2dc\uc2a4\ud15c \ud0dc\uadf8\uc774\ubbc0\ub85c \uc0ad\uc81c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.',
                          es: 'Etiqueta integrada. No se puede eliminar.',
                          de: 'Integrierter Tag. Er kann nicht entfernt werden.',
                        )
                      : null,
                  onPressed: isSystemSyncExclusionTag(tag) ? null : () {},
                  onDeleted: isSystemSyncExclusionTag(tag)
                      ? null
                      : () => onRemove(tag),
                  deleteIcon: const Icon(Icons.close_rounded),
                  backgroundColor: isSystemSyncExclusionTag(tag)
                      ? theme.colorScheme.secondaryContainer
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncExclusionTagDialog extends StatefulWidget {
  const _SyncExclusionTagDialog();

  @override
  State<_SyncExclusionTagDialog> createState() =>
      _SyncExclusionTagDialogState();
}

class _SyncExclusionTagDialogState extends State<_SyncExclusionTagDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(
        strings.localized(
          en: 'Add excluded sync tag',
          ja: '\u540c\u671f\u5bfe\u8c61\u5916\u30bf\u30b0\u3092\u8ffd\u52a0',
          zh: '\u6dfb\u52a0\u6392\u9664\u540c\u6b65\u6807\u7b7e',
          ko: '\ub3d9\uae30\ud654 \uc81c\uc678 \ud0dc\uadf8 \ucd94\uac00',
          es: 'Agregar etiqueta excluida de sincronizacion',
          de: 'Ausgeschlossenen Sync-Tag hinzufuegen',
        ),
      ),
      content: TextField(
        key: SettingsScreen.syncExclusionTagInputKey,
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: strings.localized(
            en: 'Tag',
            ja: '\u30bf\u30b0',
            zh: '\u6807\u7b7e',
            ko: '\ud0dc\uadf8',
            es: 'Etiqueta',
            de: 'Tag',
          ),
          prefixText: '#',
          errorText: _errorText,
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(strings),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: SettingsScreen.syncExclusionTagAddKey,
          onPressed: () => _submit(strings),
          child: Text(
            strings.localized(
              en: 'Add',
              ja: '\u8ffd\u52a0',
              zh: '\u6dfb\u52a0',
              ko: '\ucd94\uac00',
              es: 'Agregar',
              de: 'Hinzufuegen',
            ),
          ),
        ),
      ],
    );
  }

  void _submit(AppStrings strings) {
    final normalized = normalizeNoteTag(_controller.text);
    if (normalized.isEmpty) {
      setState(() {
        _errorText = strings.localized(
          en: 'Enter a tag name.',
          ja: '\u30bf\u30b0\u540d\u3092\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
          zh: '\u8bf7\u8f93\u5165\u6807\u7b7e\u540d\u79f0\u3002',
          ko: '\ud0dc\uadf8 \uc774\ub984\uc744 \uc785\ub825\ud558\uc138\uc694.',
          es: 'Introduce un nombre de etiqueta.',
          de: 'Gib einen Tag-Namen ein.',
        );
      });
      return;
    }
    Navigator.of(context).pop(normalized);
  }
}
