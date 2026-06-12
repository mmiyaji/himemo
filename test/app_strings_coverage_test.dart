import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/l10n/app_strings.dart';

typedef _StringCase = ({String name, String Function(AppStrings strings) read});

void main() {
  group('AppStrings coverage smoke', () {
    final cases = <_StringCase>[
      (name: 'notes', read: (strings) => strings.notes),
      (name: 'calendar', read: (strings) => strings.calendar),
      (name: 'insights', read: (strings) => strings.insights),
      (name: 'settings', read: (strings) => strings.settings),
      (name: 'addNote', read: (strings) => strings.addNote),
      (name: 'collapseSidebar', read: (strings) => strings.collapseSidebar),
      (name: 'expandSidebar', read: (strings) => strings.expandSidebar),
      (name: 'search', read: (strings) => strings.search),
      (name: 'today', read: (strings) => strings.today),
      (name: 'weekdayShort.mon', read: (strings) => strings.weekdayShort(1)),
      (name: 'weekdayShort.sun', read: (strings) => strings.weekdayShort(7)),
      (name: 'monthName.jan', read: (strings) => strings.monthName(1)),
      (name: 'monthName.dec', read: (strings) => strings.monthName(12)),
      (
        name: 'noteDayLabel',
        read: (strings) => strings.noteDayLabel(DateTime(2026, 6, 12)),
      ),
      (
        name: 'weekdayShortLabels',
        read: (strings) => strings.weekdayShortLabels.join(','),
      ),
      (
        name: 'viewingPrivateProfile',
        read: (strings) => strings.viewingPrivateProfile('Private'),
      ),
      (
        name: 'currentPrivateProfile.null',
        read: (strings) => strings.currentPrivateProfile(null),
      ),
      (
        name: 'currentPrivateProfile.label',
        read: (strings) => strings.currentPrivateProfile('Private'),
      ),
      (name: 'filteredByTag', read: (strings) => strings.filteredByTag('work')),
      (
        name: 'tagFilterApplied',
        read: (strings) => strings.tagFilterApplied('work'),
      ),
      (
        name: 'deleteNoteConfirmation',
        read: (strings) => strings.deleteNoteConfirmation('Title'),
      ),
      (
        name: 'moveNoteToTrashConfirmation',
        read: (strings) => strings.moveNoteToTrashConfirmation('Title'),
      ),
      (name: 'moveNoteToTrash', read: (strings) => strings.moveNoteToTrash),
      (name: 'deletePermanently', read: (strings) => strings.deletePermanently),
      (
        name: 'deletePermanentlyOptionDescription',
        read: (strings) => strings.deletePermanentlyOptionDescription,
      ),
      (
        name: 'movedNoteToTrash',
        read: (strings) => strings.movedNoteToTrash('Title'),
      ),
      (name: 'deleteNote', read: (strings) => strings.deleteNote),
      (name: 'noteDeleted', read: (strings) => strings.noteDeleted('Title')),
      (
        name: 'unableToShareAttachment',
        read: (strings) => strings.unableToShareAttachment,
      ),
      (
        name: 'unableToDecryptAttachment',
        read: (strings) => strings.unableToDecryptAttachment,
      ),
      (name: 'unableToLoadImage', read: (strings) => strings.unableToLoadImage),
      (
        name: 'unableToDecryptImage',
        read: (strings) => strings.unableToDecryptImage,
      ),
      (
        name: 'videoPreviewUnavailableWeb',
        read: (strings) => strings.videoPreviewUnavailableWeb,
      ),
      (name: 'unlockedNotes', read: (strings) => strings.unlockedNotes),
      (name: 'noteEditedAt', read: (strings) => strings.noteEditedAt('12:00')),
      (
        name: 'noteCreatedRevision',
        read: (strings) => strings.noteCreatedRevision('12:00', 3),
      ),
      (name: 'photoPlaceholder', read: (strings) => strings.photoPlaceholder),
      (name: 'tapToViewPhoto', read: (strings) => strings.tapToViewPhoto),
      (name: 'videoPlaceholder', read: (strings) => strings.videoPlaceholder),
      (name: 'tapToPlayVideo', read: (strings) => strings.tapToPlayVideo),
      (name: 'audioPlaceholder', read: (strings) => strings.audioPlaceholder),
      (name: 'tapToPlayAudio', read: (strings) => strings.tapToPlayAudio),
      (name: 'filePlaceholder', read: (strings) => strings.filePlaceholder),
      (name: 'tapToOpenFile', read: (strings) => strings.tapToOpenFile),
      (
        name: 'filePreviewUnavailable',
        read: (strings) => strings.filePreviewUnavailable,
      ),
      (name: 'closeImageViewer', read: (strings) => strings.closeImageViewer),
      (name: 'syncLabel', read: (strings) => strings.syncLabel),
      (
        name: 'enableDeviceAuthReason',
        read: (strings) => strings.enableDeviceAuthReason,
      ),
      (
        name: 'unlockWithDeviceAuthReason',
        read: (strings) => strings.unlockWithDeviceAuthReason,
      ),
      (name: 'notesCount', read: (strings) => strings.notesCount(3)),
      (
        name: 'notesCount.compact',
        read: (strings) => strings.notesCount(3, spacedEnglish: false),
      ),
      (name: 'entriesCount', read: (strings) => strings.entriesCount(2)),
      (
        name: 'noteCountSummary',
        read: (strings) => strings.noteCountSummary(5),
      ),
      (
        name: 'accessModeSummary',
        read: (strings) => strings.accessModeSummary('Admin'),
      ),
      (
        name: 'webPinProtectionSummary',
        read: (strings) => strings.webPinProtectionSummary('On'),
      ),
      (
        name: 'deviceAuthProtectionSummary',
        read: (strings) => strings.deviceAuthProtectionSummary('On'),
      ),
      (name: 'lastQueuedAt', read: (strings) => strings.lastQueuedAt('12:00')),
      (
        name: 'recoveryKeyImported',
        read: (strings) => strings.recoveryKeyImported('abc123'),
      ),
      (name: 'lastUploadAt', read: (strings) => strings.lastUploadAt('12:00')),
      (name: 'lastApplyAt', read: (strings) => strings.lastApplyAt('12:00')),
      (
        name: 'remoteBundleAt',
        read: (strings) => strings.remoteBundleAt('12:00'),
      ),
      (
        name: 'localBundleStoredAt',
        read: (strings) => strings.localBundleStoredAt('bundle-ref'),
      ),
      (name: 'appearance', read: (strings) => strings.appearance),
      (
        name: 'appearanceWithControls',
        read: (strings) => strings.appearanceWithControls,
      ),
      (name: 'language', read: (strings) => strings.language),
      (name: 'languageSystem', read: (strings) => strings.languageSystem),
      (
        name: 'languageSystemOption',
        read: (strings) => strings.languageSystemOption,
      ),
      (name: 'languageJapanese', read: (strings) => strings.languageJapanese),
      (name: 'languageEnglish', read: (strings) => strings.languageEnglish),
      (name: 'languageChinese', read: (strings) => strings.languageChinese),
      (name: 'languageKorean', read: (strings) => strings.languageKorean),
      (name: 'languageSpanish', read: (strings) => strings.languageSpanish),
      (name: 'languageGerman', read: (strings) => strings.languageGerman),
      (name: 'appFont', read: (strings) => strings.appFont),
      (name: 'fontSystem', read: (strings) => strings.fontSystem),
      (name: 'fontGothic', read: (strings) => strings.fontGothic),
      (name: 'fontMincho', read: (strings) => strings.fontMincho),
      (name: 'fontRounded', read: (strings) => strings.fontRounded),
      (name: 'fontMonospace', read: (strings) => strings.fontMonospace),
      (name: 'themeLight', read: (strings) => strings.themeLight),
      (name: 'themeSystem', read: (strings) => strings.themeSystem),
      (name: 'themeDark', read: (strings) => strings.themeDark),
      (name: 'accentColor', read: (strings) => strings.accentColor),
      (
        name: 'extendedThemesWithCount',
        read: (strings) => strings.extendedThemesWithCount(30),
      ),
      (name: 'about', read: (strings) => strings.about),
      (name: 'appVersion', read: (strings) => strings.appVersion),
      (name: 'appAuthor', read: (strings) => strings.appAuthor),
      (
        name: 'buildDateLabel',
        read: (strings) => strings.buildDateLabel('2026-06-12'),
      ),
      (name: 'appUpdates', read: (strings) => strings.appUpdates),
      (name: 'checkForUpdates', read: (strings) => strings.checkForUpdates),
      (name: 'startUpdate', read: (strings) => strings.startUpdate),
      (
        name: 'completeUpdateInstall',
        read: (strings) => strings.completeUpdateInstall,
      ),
      (name: 'ossLicenses', read: (strings) => strings.ossLicenses),
      (
        name: 'homeWidgetQuickCapture',
        read: (strings) => strings.homeWidgetQuickCapture,
      ),
      (
        name: 'homeWidgetQuickCaptureDesc',
        read: (strings) => strings.homeWidgetQuickCaptureDesc,
      ),
      (name: 'unlockHiMemo', read: (strings) => strings.unlockHiMemo),
      (name: 'unlockWithPin', read: (strings) => strings.unlockWithPin),
      (name: 'authenticate', read: (strings) => strings.authenticate),
      (
        name: 'disableUnlockForNow',
        read: (strings) => strings.disableUnlockForNow,
      ),
      (name: 'browserPinGate', read: (strings) => strings.browserPinGate),
      (name: 'deviceAuthGate', read: (strings) => strings.deviceAuthGate),
      (
        name: 'unlockWithPinInstruction',
        read: (strings) => strings.unlockWithPinInstruction,
      ),
      (name: 'authenticating', read: (strings) => strings.authenticating),
      (
        name: 'noUnlockMethodConfigured',
        read: (strings) => strings.noUnlockMethodConfigured,
      ),
      (
        name: 'privateVaultLockedMessage',
        read: (strings) => strings.privateVaultLockedMessage,
      ),
      (
        name: 'onboardingColorThemeBody',
        read: (strings) => strings.onboardingColorThemeBody(30),
      ),
      (name: 'termsOfUse', read: (strings) => strings.termsOfUse),
      (name: 'privacyPolicy', read: (strings) => strings.privacyPolicy),
      (name: 'contact', read: (strings) => strings.contact),
      (name: 'help', read: (strings) => strings.help),
      (name: 'syncHelp', read: (strings) => strings.syncHelp),
      (
        name: 'privateProfilesHiddenSummary',
        read: (strings) => strings.privateProfilesHiddenSummary(2),
      ),
      (name: 'skip', read: (strings) => strings.skip),
      (name: 'next', read: (strings) => strings.next),
      (name: 'finishSetup', read: (strings) => strings.finishSetup),
      (name: 'cancel', read: (strings) => strings.cancel),
      (name: 'save', read: (strings) => strings.save),
      (name: 'quickMemo', read: (strings) => strings.quickMemo),
      (name: 'richMemo', read: (strings) => strings.richMemo),
      (name: 'newNote', read: (strings) => strings.newNote),
      (name: 'editNote', read: (strings) => strings.editNote),
      (name: 'memoLabel', read: (strings) => strings.memoLabel),
      (name: 'createNote', read: (strings) => strings.createNote),
      (name: 'saveChanges', read: (strings) => strings.saveChanges),
      (name: 'attachments', read: (strings) => strings.attachments),
      (name: 'addMedia', read: (strings) => strings.addMedia),
      (name: 'captureMedia', read: (strings) => strings.captureMedia),
      (name: 'importFiles', read: (strings) => strings.importFiles),
      (name: 'pickPhoto', read: (strings) => strings.pickPhoto),
      (name: 'takePhoto', read: (strings) => strings.takePhoto),
      (name: 'recordAudio', read: (strings) => strings.recordAudio),
      (
        name: 'addCurrentLocation',
        read: (strings) => strings.addCurrentLocation,
      ),
      (
        name: 'currentLocationLabel',
        read: (strings) => strings.currentLocationLabel,
      ),
      (name: 'openMap', read: (strings) => strings.openMap),
      (name: 'copyMapLink', read: (strings) => strings.copyMapLink),
      (
        name: 'audioRecordingStartFailed',
        read: (strings) => strings.audioRecordingStartFailed('denied'),
      ),
      (
        name: 'attachmentRemoved',
        read: (strings) => strings.attachmentRemoved('photo.jpg'),
      ),
      (
        name: 'syncAppleIdUnsupported',
        read: (strings) => strings.syncAppleIdUnsupported,
      ),
      (
        name: 'syncAppleIdUnavailable',
        read: (strings) => strings.syncAppleIdUnavailable,
      ),
      (
        name: 'syncAppleIdConnected',
        read: (strings) => strings.syncAppleIdConnected,
      ),
      (
        name: 'syncApplePluginMissing',
        read: (strings) => strings.syncApplePluginMissing,
      ),
      (
        name: 'googleDriveWebSignInTitle',
        read: (strings) => strings.googleDriveWebSignInTitle,
      ),
      (name: 'syncDetailsTitle', read: (strings) => strings.syncDetailsTitle),
      (name: 'close', read: (strings) => strings.close),
      (name: 'sendMemo', read: (strings) => strings.sendMemo),
      (name: 'sendQuickMemo', read: (strings) => strings.sendQuickMemo),
      (name: 'quickMemoSaved', read: (strings) => strings.quickMemoSaved),
    ];

    test('public labels resolve across supported locales', () {
      for (final locale in AppStrings.supportedLocales) {
        final strings = AppStrings(locale);
        expect(strings.localized(en: 'en', ja: 'ja'), isNotEmpty);
        for (final entry in cases) {
          final value = entry.read(strings);
          expect(
            value.trim(),
            isNotEmpty,
            reason: '${entry.name} returned an empty value for $locale',
          );
          expect(
            value,
            isNot(contains(RegExp(r'\{[^}]+\}'))),
            reason: '${entry.name} left a placeholder unresolved for $locale',
          );
        }
      }
    });

    test('locale flags and delegate behavior are stable', () async {
      expect(AppStrings(const Locale('ja')).isJapanese, isTrue);
      expect(AppStrings(const Locale('zh')).isChinese, isTrue);
      expect(AppStrings(const Locale('ko')).isKorean, isTrue);
      expect(AppStrings(const Locale('es')).isSpanish, isTrue);
      expect(AppStrings(const Locale('de')).isGerman, isTrue);
      expect(AppStrings.delegate.isSupported(const Locale('fr')), isFalse);
      expect(
        (await AppStrings.delegate.load(const Locale('en'))).notes,
        isNotEmpty,
      );
      expect(AppStrings.delegate.shouldReload(AppStrings.delegate), isFalse);
    });
  });
}
