import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/data/home_repository.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/domain/note_tags.dart';
import 'package:himemo/features/home/domain/vault_models.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('app strings fall back to English for unsupported locales', () {
    final strings = AppStrings(const Locale('fr'));

    expect(strings.createDemoNotes, 'Create demo notes');
    expect(strings.deleteDemoNotesBody(3), contains('3 demo notes'));
    expect(strings.noteDayLabel(DateTime(2026, 5, 3)), 'May 3, 2026 (Sun)');
    expect(strings.languageSystemOption, 'Follow system');
    expect(
      strings.appearanceWithControls,
      'Appearance (language, font, and color)',
    );
    expect(
      strings.appearanceSummary(
        language: 'English',
        theme: 'Light',
        font: 'System default',
        color: '桜 (Sakura)',
      ),
      contains('Font: System default'),
    );
    expect(strings.colorKonjyo, '紺青 (Konjyo)');
    expect(strings.colorKurenai, '紅 (Kurenai)');
    expect(strings.colorSakura, '桜 (Sakura)');
    expect(strings.colorFuji, '藤 (Fuji)');
    expect(strings.extendedThemes, 'Extended themes');
    expect(strings.extendedThemesWithCount(30), 'Extended themes (30 total)');
    expect(strings.colorAi, '藍 (Ai)');
    expect(strings.colorAsagi, '浅葱 (Asagi)');
    expect(strings.colorShironeri, '白練 (Shironeri)');
    expect(strings.themeCategoryNeutral, 'White, black, and neutral');
    expect(strings.onboardingColorThemeBody(30), contains('30+'));
  });

  test('app strings localize home UI labels to Japanese', () {
    final strings = AppStrings(const Locale('ja'));

    expect(strings.emptyNotesTitle, '一致するノートはありません');
    expect(strings.previousImage, '前の画像');
    expect(strings.videoPreviewUnavailableWeb, 'Web では動画プレビューを利用できません。');
    expect(strings.languageSystemOption, 'システムに合わせる (System)');
    expect(strings.languageJapaneseOption, '日本語 (Japanese)');
    expect(strings.appearanceWithControls, '表示（言語・フォント・カラー）');
    expect(
      strings.appearanceSummary(
        language: '日本語 (Japanese)',
        theme: 'ライト',
        font: 'システム標準',
        color: '桜 (Sakura)',
      ),
      contains(strings.fontSystem),
    );
    expect(strings.colorKonjyo, '紺青 (Konjyo)');
    expect(strings.colorKurenai, '紅 (Kurenai)');
    expect(strings.colorSakura, '桜 (Sakura)');
    expect(strings.colorFuji, '藤 (Fuji)');
    expect(strings.extendedThemes, '拡張テーマ');
    expect(strings.extendedThemesWithCount(30), '拡張テーマ（全30種）');
    expect(strings.colorAi, '藍 (Ai)');
    expect(strings.colorAsagi, '浅葱 (Asagi)');
    expect(strings.colorShironeri, '白練 (Shironeri)');
    expect(strings.themeCategoryNeutral, '白・黒・無彩色');
    expect(strings.onboardingColorThemeBody(30), contains('全30色以上'));
  });

  test('traditional color themes include 30 or more choices', () {
    expect(AppColorTheme.values.length, greaterThanOrEqualTo(30));
  });

  test('note attachments preserve media duration metadata', () {
    const attachment = NoteAttachment(
      type: AttachmentType.audio,
      label: 'memo.m4a',
      durationMs: 65000,
    );

    expect(NoteAttachment.fromJson(attachment.toJson()).durationMs, 65000);
  });

  test('widget quick capture stores first line only as title', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = MemoryHomeRepository();
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(11));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repository),
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    await container
        .read(notesControllerProvider.notifier)
        .createWidgetQuickCapture('Title line\nBody line');

    final note = container.read(notesControllerProvider).single;
    expect(note.title, 'Title line');
    expect(note.body, 'Body line');
    expect(note.blocks.single.text, 'Body line');
  });

  test('app strings support Chinese and Korean locales', () {
    final zh = AppStrings(const Locale('zh'));
    final ko = AppStrings(const Locale('ko'));

    expect(AppStrings.supportedLocales, contains(const Locale('zh')));
    expect(AppStrings.supportedLocales, contains(const Locale('ko')));
    expect(zh.notes, '笔记');
    expect(zh.languageSystemOption, '跟随系统 (System)');
    expect(zh.languageChineseOption, '中文 (Chinese)');
    expect(zh.emptyNotesTitle, '没有匹配的笔记');
    expect(zh.quickMemo, '快速备忘录');
    expect(zh.addMedia, '添加媒体');
    expect(zh.appUpdates, '应用更新');
    expect(zh.text('home.save.to.private.profile'), '保存到私密档案');
    expect(zh.noteDayLabel(DateTime(2026, 5, 3)), '2026/05/03(周日)');
    expect(
      zh.webPinProtectionSummary(zh.pinLockSummary(isConfigured: false)),
      '使用 4 位 PIN 保护此浏览器会话。此浏览器尚未设置解锁 PIN。',
    );
    expect(
      zh.remoteBundleSummary(
        modifiedAt: '2026/05/03 22:00',
        sizeLabel: '12 KB',
        noteCount: '3',
        attachmentCount: '2',
      ),
      '最新包：2026/05/03 22:00，12 KB，笔记 3 条，附件 2 个。',
    );
    expect(ko.notes, '노트');
    expect(ko.languageSystemOption, '시스템 따르기 (System)');
    expect(ko.languageKoreanOption, '한국어 (Korean)');
    expect(ko.emptyNotesTitle, '일치하는 노트가 없습니다');
    expect(ko.quickMemo, '빠른 메모');
    expect(ko.addMedia, '미디어 추가');
    expect(ko.appUpdates, '앱 업데이트');
    expect(ko.text('home.save.to.private.profile'), '비공개 프로필에 저장');
    expect(ko.noteDayLabel(DateTime(2026, 5, 3)), '2026/05/03(일)');
    expect(
      ko.webPinProtectionSummary(ko.pinLockSummary(isConfigured: true)),
      '이 브라우저 세션을 4자리 PIN으로 보호합니다. 이 브라우저 세션에는 웹 전용 잠금 해제 PIN이 설정되어 있습니다.',
    );
    expect(
      ko.remoteBundleSummary(
        modifiedAt: '2026/05/03 22:00',
        sizeLabel: '12 KB',
        noteCount: '3',
        attachmentCount: '2',
      ),
      '최신 번들: 2026/05/03 22:00, 12 KB, 노트 3개, 첨부 2개.',
    );
  });

  testWidgets('insights do not show a best day when there are no notes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: InsightsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Best day'), findsOneWidget);
    expect(find.text('-'), findsWidgets);
    expect(find.textContaining(RegExp(r'\d+/\d+')), findsNothing);
  });

  test('note location metadata is serialized with notes', () {
    final note = NoteEntry(
      id: 'location-note',
      vaultId: 'everyday',
      title: 'Location',
      body: '',
      createdAt: DateTime(2026, 5, 6, 10, 0),
      location: NoteLocation(
        latitude: 35.681236,
        longitude: 139.767125,
        accuracyMeters: 12,
        address: 'Tokyo Station',
        capturedAt: DateTime(2026, 5, 6, 10, 1),
      ),
    );

    final restored = NoteEntry.fromJson(note.toJson());

    expect(restored.location?.latitude, 35.681236);
    expect(restored.location?.longitude, 139.767125);
    expect(restored.location?.address, 'Tokyo Station');
  });

  test('app strings support Spanish and German locales', () {
    final es = AppStrings(const Locale('es'));
    final de = AppStrings(const Locale('de'));

    expect(AppStrings.supportedLocales, contains(const Locale('es')));
    expect(AppStrings.supportedLocales, contains(const Locale('de')));
    expect(es.notes, 'Notas');
    expect(es.settings, 'Ajustes');
    expect(es.languageSystemOption, 'Seguir sistema (System)');
    expect(es.languageSpanishOption, 'Español (Spanish)');
    expect(es.emptyNotesTitle, 'No hay notas coincidentes');
    expect(es.noteDayLabel(DateTime(2026, 5, 3)), 'mayo 3, 2026 (dom)');
    expect(es.themeSystem, 'Sistema');
    expect(es.accentColor, 'Color de acento');
    expect(es.privateProfilesSettingsTitle, 'Perfiles privados');
    expect(es.quickMemo, 'Memo rápido');
    expect(es.createNote, 'Crear nota');
    expect(es.recordAudio, 'Grabar audio');
    expect(es.audioPlaybackFailed, 'No se pudo reproducir este audio.');
    expect(
      es.text('home.remote.bundle.storage.is.not.configured.yet'),
      'El almacenamiento del paquete remoto aún no está configurado.',
    );
    expect(de.notes, 'Notizen');
    expect(de.settings, 'Einstellungen');
    expect(de.languageSystemOption, 'System folgen (System)');
    expect(de.languageGermanOption, 'Deutsch (German)');
    expect(de.emptyNotesTitle, 'Keine passenden Notizen');
    expect(de.noteDayLabel(DateTime(2026, 5, 3)), 'Mai 3, 2026 (So)');
    expect(de.themeSystem, 'System');
    expect(de.accentColor, 'Akzentfarbe');
    expect(de.privateProfilesSettingsTitle, 'Private Profile');
    expect(de.quickMemo, 'Schnellnotiz');
    expect(de.createNote, 'Notiz erstellen');
    expect(de.recordAudio, 'Audio aufnehmen');
    expect(
      de.audioPlaybackFailed,
      'Dieses Audio konnte nicht abgespielt werden.',
    );
    expect(
      de.text('home.remote.bundle.storage.is.not.configured.yet'),
      'Der Remote-Bundle-Speicher ist noch nicht eingerichtet.',
    );
  });

  test('localized AppStrings entries include Spanish and German values', () {
    final source = File('lib/l10n/app_strings.dart').readAsStringSync();
    final missing = <String>[];
    for (final match in RegExp(
      r'localized\(([\s\S]*?)\);',
    ).allMatches(source)) {
      final block = match.group(0)!;
      if (block.contains('required String en')) {
        continue;
      }
      if (!block.contains('es:') || !block.contains('de:')) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        missing.add('line $line');
      }
    }

    expect(missing, isEmpty);
  });

  test('generated app localizations support configured locales', () async {
    expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('ja')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('zh')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('ko')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('es')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('de')));

    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final es = await AppLocalizations.delegate.load(const Locale('es'));
    final de = await AppLocalizations.delegate.load(const Locale('de'));

    expect(en.noMatchingNotes, 'No matching notes');
    expect(ja.noMatchingNotes, '一致するノートはありません');
    expect(zh.notes, '笔记');
    expect(ko.saveToPrivateProfile, '비공개 프로필에 저장');
    expect(es.notes, 'Notas');
    expect(de.saveToPrivateProfile, 'In privatem Profil speichern');
  });

  test('iCloud sync is ignored on unsupported platforms', () async {
    SharedPreferences.setMockInitialValues({
      'settings.sync_provider': 'iCloud',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(isICloudSyncSupported, isFalse);
    expect(container.read(syncProviderControllerProvider), SyncProvider.off);

    await pumpEventQueue();
    expect(container.read(syncProviderControllerProvider), SyncProvider.off);

    await container
        .read(syncProviderControllerProvider.notifier)
        .setProvider(SyncProvider.iCloud);
    expect(container.read(syncProviderControllerProvider), SyncProvider.off);
  });

  test('stale iCloud Sign in with Apple errors are not restored', () async {
    SharedPreferences.setMockInitialValues({
      'sync.auth_accounts.v1': jsonEncode({
        'iCloud': {
          'provider': 'iCloud',
          'stage': 'error',
          'message':
              'SignInWithAppleAuthorizationException(AuthorizationErrorCode.unknown, The operation couldn\'t be completed. (com.apple.AuthenticationServices.AuthorizationError error 1000.))',
        },
      }),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await pumpEventQueue();

    expect(
      container.read(syncAuthControllerProvider)[SyncProvider.iCloud]?.stage,
      SyncAuthStage.idle,
    );
  });

  test('iCloud connect does not require an Apple sign-in plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final state = await DefaultSyncAuthGateway().connect(SyncProvider.iCloud);

    expect(state.stage, SyncAuthStage.authenticated);
    expect(state.displayName, 'iCloud');
  });

  test('Google Drive auth config normalizes blank client IDs', () {
    const empty = GoogleDriveAuthConfig(clientId: '  ', serverClientId: '');
    const configured = GoogleDriveAuthConfig(
      clientId: 'ios-client.apps.googleusercontent.com',
      serverClientId: 'web-client.apps.googleusercontent.com',
    );

    expect(empty.normalizedClientId, isNull);
    expect(empty.normalizedServerClientId, isNull);
    expect(
      configured.normalizedClientId,
      'ios-client.apps.googleusercontent.com',
    );
    expect(
      configured.normalizedServerClientId,
      'web-client.apps.googleusercontent.com',
    );
  });

  test('effective color theme follows unlocked private profile', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(appColorThemeControllerProvider.notifier)
        .setTheme(AppColorTheme.konjyo);
    await container
        .read(profileColorThemeControllerProvider.notifier)
        .setTheme('private_profile:p1', AppColorTheme.fuji);

    expect(
      container.read(effectiveAppColorThemeProvider),
      AppColorTheme.konjyo,
    );

    container
        .read(unlockedPrivateProfileVaultIdProvider.notifier)
        .unlock('private_profile:p1');

    expect(container.read(effectiveAppColorThemeProvider), AppColorTheme.fuji);
  });

  test('color theme settings target resets to active profile scope', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(colorThemeSettingsScopeProvider),
      defaultColorThemeScope,
    );

    container
        .read(colorThemeSettingsScopeProvider.notifier)
        .select('private_profile:p1');
    expect(
      container.read(colorThemeSettingsScopeProvider),
      'private_profile:p1',
    );

    container
        .read(unlockedPrivateProfileVaultIdProvider.notifier)
        .unlock('private_profile:p2');
    expect(
      container.read(colorThemeSettingsScopeProvider),
      'private_profile:p2',
    );
  });

  test('providers expose private profiles only after unlock', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(3));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    expect(container.read(identitiesProvider).length, 3);
    expect(container.read(visibleVaultsProvider).length, 1);

    final addError = await container
        .read(privateMemoProfilesControllerProvider.notifier)
        .addProfile(name: 'Cover profile', password: 'cover-pass-123');
    expect(addError, isNull);
    expect(container.read(privateMemoProfilesProvider).length, 1);
    expect(container.read(visibleVaultsProvider).length, 1);

    final unlocked = await container
        .read(privateProfileUnlockControllerProvider.notifier)
        .unlockWithPassword('cover-pass-123');
    expect(unlocked, isNotNull);

    expect(container.read(visibleVaultsProvider).length, 2);
    expect(
      container
          .read(visibleVaultsProvider)
          .any((vault) => vault.id == unlocked!.vaultId),
      isTrue,
    );
  });

  test('private profile notes remain visible immediately after save', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(13));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    final addError = await container
        .read(privateMemoProfilesControllerProvider.notifier)
        .addProfile(name: 'Private journal', password: 'journal-pass-123');
    expect(addError, isNull);

    final unlocked = await container
        .read(privateProfileUnlockControllerProvider.notifier)
        .unlockWithPassword('journal-pass-123');
    expect(unlocked, isNotNull);

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'private-after-save',
            vaultId: unlocked!.vaultId,
            title: 'Private saved note',
            body: 'This should remain visible.',
            createdAt: DateTime(2026, 4, 20, 12, 0),
          ),
        );

    expect(
      container.read(visibleNotesProvider).map((note) => note.id),
      contains('private-after-save'),
    );
    expect(
      container.read(notesForVaultProvider(unlocked.vaultId)).single.id,
      'private-after-save',
    );
  });

  test('seeded demo notes are dated within a week of first launch', () {
    final launchDate = DateTime(2026, 4, 29, 15, 30);
    final notes = SeededHomeRepository(seedBaseDate: launchDate).seededNotes;
    final launchDay = DateTime(2026, 4, 29);
    final earliestDemoDay = launchDay.subtract(const Duration(days: 7));

    expect(notes, isNotEmpty);
    for (final note in notes) {
      final noteDay = DateTime(
        note.createdAt.year,
        note.createdAt.month,
        note.createdAt.day,
      );
      expect(noteDay.isBefore(earliestDemoDay), isFalse);
      expect(noteDay.isAfter(launchDay), isFalse);
      expect(note.createdAt.isAfter(launchDate), isFalse);
      expect(note.updatedAt?.isAfter(launchDate) ?? false, isFalse);
    }
    expect(
      notes.any(
        (note) =>
            note.createdAt.year == launchDay.year &&
            note.createdAt.month == launchDay.month &&
            note.createdAt.day == launchDay.day,
      ),
      isTrue,
    );
  });

  test(
    'demo notes are only created on request and are not restored automatically after deletion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(14));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteDatabaseProvider.overrideWithValue(database),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: database,
              directoryProvider: () async => Directory.systemTemp,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(database.close);

      await container.read(notesControllerProvider.notifier).restoreCompleted;
      expect(container.read(notesControllerProvider), isEmpty);

      final createdCount = await container
          .read(notesControllerProvider.notifier)
          .createDemoNotes();
      final initialSeedCount = container
          .read(notesControllerProvider)
          .where((note) => note.id.startsWith('seed-'))
          .length;
      expect(initialSeedCount, greaterThan(0));
      expect(createdCount, initialSeedCount);

      final deletedCount = await container
          .read(notesControllerProvider.notifier)
          .deleteDemoNotes();
      expect(deletedCount, initialSeedCount);
      expect(
        container
            .read(notesControllerProvider)
            .where((note) => note.id.startsWith('seed-')),
        isEmpty,
      );

      final secondContainer = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteDatabaseProvider.overrideWithValue(database),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: database,
              directoryProvider: () async => Directory.systemTemp,
            ),
          ),
        ],
      );
      addTearDown(secondContainer.dispose);
      await secondContainer
          .read(notesControllerProvider.notifier)
          .restoreCompleted;
      expect(
        secondContainer
            .read(notesControllerProvider)
            .where((note) => note.id.startsWith('seed-')),
        isEmpty,
      );
    },
  );

  test('notes are sorted by memo date after the date is edited', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(42));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    final controller = container.read(notesControllerProvider.notifier);
    await controller.restoreCompleted;
    await controller.upsert(
      NoteEntry(
        id: 'older',
        vaultId: 'everyday',
        title: 'Older',
        body: '',
        createdAt: DateTime(2026, 5, 1, 10, 0),
        updatedAt: DateTime(2026, 5, 1, 10, 0),
      ),
    );
    await controller.upsert(
      NoteEntry(
        id: 'newer',
        vaultId: 'everyday',
        title: 'Newer',
        body: '',
        createdAt: DateTime(2026, 5, 3, 10, 0),
        updatedAt: DateTime(2026, 5, 3, 10, 0),
      ),
    );
    await controller.upsert(
      container
          .read(notesControllerProvider)
          .firstWhere((note) => note.id == 'older')
          .copyWith(
            createdAt: DateTime(2026, 5, 4, 9, 0),
            updatedAt: DateTime(2026, 5, 5, 12, 0),
          ),
    );

    expect(container.read(notesControllerProvider).map((note) => note.id), [
      'older',
      'newer',
    ]);
  });

  test('private notes are sorted before normal notes', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(43));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final profileDataKeyService = ProfileDataKeyService(
      secureStore: secureStore,
      encryptionService: encryptionService,
      normalMasterKeyService: masterKeyService,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        profileDataKeyServiceProvider.overrideWithValue(profileDataKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            profileDataKeyService: profileDataKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    final controller = container.read(notesControllerProvider.notifier);
    await controller.restoreCompleted;
    await profileDataKeyService.configureProfile(
      vaultId: legacyPrivateVaultId,
      password: 'private-pass',
    );
    await controller.upsert(
      NoteEntry(
        id: 'normal-newer',
        vaultId: 'everyday',
        title: 'Normal newer',
        body: '',
        createdAt: DateTime(2026, 5, 5, 10, 0),
      ),
    );
    await controller.upsert(
      NoteEntry(
        id: 'private-older',
        vaultId: legacyPrivateVaultId,
        title: 'Private older',
        body: '',
        createdAt: DateTime(2026, 5, 1, 10, 0),
      ),
    );

    expect(container.read(notesControllerProvider).map((note) => note.id), [
      'private-older',
      'normal-newer',
    ]);
  });

  test('privacy screen activates for legacy private vault session', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(privacyScreenActiveProvider), isFalse);
    container.read(privateVaultSessionControllerProvider.notifier).unlock();
    expect(container.read(privacyScreenActiveProvider), isTrue);
    container.read(privateVaultSessionControllerProvider.notifier).lock();
    expect(container.read(privacyScreenActiveProvider), isFalse);
  });

  test('onboarding completion is not reverted by restore race', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(appLaunchControllerProvider),
      AppLaunchSurface.onboarding,
    );
    await container
        .read(appLaunchControllerProvider.notifier)
        .completeOnboarding();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appLaunchControllerProvider), AppLaunchSurface.ready);
  });

  test('app lock policy providers expose secure defaults', () {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(4));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    expect(
      container.read(appLockRelockDelayControllerProvider),
      AppLockRelockDelay.immediate,
    );
    expect(container.read(privateVaultLockOnAppLockControllerProvider), isTrue);
  });

  testWidgets('app renders HiMemo shell', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(5));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteDatabaseProvider.overrideWithValue(database),
          encryptedNoteStoreProvider.overrideWithValue(
            EncryptedNoteStore(
              encryptionService: encryptionService,
              masterKeyService: masterKeyService,
              database: database,
              directoryProvider: () async => Directory.systemTemp,
            ),
          ),
        ],
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    addTearDown(database.close);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('HiMemo'), findsOneWidget);
    expect(find.text('Notes'), findsAtLeastNWidgets(1));
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('mobile tab switch closes open note detail sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(16));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 200));
    await container.read(notesControllerProvider.notifier).createDemoNotes();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(
      find.byKey(const Key('note-tile-seed-2026-04-12-groceries')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('edit-note-button')), findsOneWidget);

    await tester.tap(find.byKey(AppShell.settingsNavKey));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('edit-note-button')), findsNothing);
    expect(container.read(selectedNoteIdProvider), isNull);
  });

  test('note entry defaults sync metadata safely', () {
    final note = NoteEntry(
      id: 'sample',
      vaultId: 'everyday',
      title: 'Sample',
      body: 'Body',
      createdAt: DateTime(2026, 4, 12, 13, 0),
    );

    expect(note.updatedAt, isNull);
    expect(note.revision, 1);
    expect(note.deletedAt, isNull);
    expect(note.deviceId, isNull);
    expect(note.contentHash, isNull);
    expect(note.syncState, NoteSyncState.localOnly);
    expect(note.blocks, isEmpty);
    expect(note.editorMode, NoteEditorMode.rich);
  });

  test('search filters can narrow notes by tags', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(6));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'tag-1',
            vaultId: 'everyday',
            title: 'Project alpha',
            body: 'First body',
            tags: const ['Work', 'Alpha'],
            createdAt: DateTime(2026, 4, 20, 10, 0),
          ),
        );
    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'tag-2',
            vaultId: 'everyday',
            title: 'Personal errands',
            body: 'Second body',
            tags: const ['Home'],
            createdAt: DateTime(2026, 4, 20, 11, 0),
          ),
        );

    container.read(searchFiltersControllerProvider.notifier).addTag('alpha');

    final visible = container.read(visibleNotesProvider);
    expect(visible.map((note) => note.id), ['tag-1']);
    expect(container.read(visibleTagSuggestionsProvider), contains('Alpha'));
    expect(dedupeNoteTags([' Alpha ', '#alpha', 'HOME']), ['Alpha', 'HOME']);
  });
}

class MemoryHomeRepository implements HomeRepository {
  @override
  List<UnlockIdentity> get identities => const [
    UnlockIdentity(
      id: 'daily',
      name: 'Notes',
      tagline: '',
      lockLabel: 'Standard access',
      visibleVaultIds: ['everyday'],
      accentHex: 0xFF6B8798,
      warning: '',
    ),
  ];

  @override
  List<NoteEntry> get seededNotes => const [];

  @override
  List<VaultBucket> get vaults => const [
    VaultBucket(id: 'everyday', name: 'Notes', description: ''),
  ];
}
