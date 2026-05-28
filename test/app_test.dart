import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/app/app_router.dart';
import 'package:himemo/app/network_connection.dart';
import 'package:himemo/features/home/data/home_repository.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/domain/note_tags.dart';
import 'package:himemo/features/home/domain/vault_models.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/secure_sync_bundle_store.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/icloud_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_engine.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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
    expect(strings.appearanceWithControls, '表示（言語・フォント・色）');
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

  test('tag filter snackbar message is localized', () {
    final strings = AppStrings(const Locale('ja'));

    expect(
      strings.tagFilterApplied('\u4ed5\u4e8b'),
      '#\u4ed5\u4e8b \u306e\u30bf\u30b0\u3067\u7d5e\u308a\u8fbc\u307f\u307e\u3057\u305f',
    );
  });

  test('release notes parse localized user-facing items', () {
    final release = releaseNoteFromJson({
      'version': '1.2.3',
      'date': '2026-05-16',
      'importance': 'normal',
      'title': {'en': 'Updated', 'ja': '更新しました'},
      'summary': {'en': 'Summary', 'ja': '概要'},
      'items': [
        {
          'type': 'fix',
          'title': {'en': 'Fixed sync', 'ja': '同期を修正'},
          'body': {'en': 'Sync is clearer.', 'ja': '同期が分かりやすくなりました。'},
        },
      ],
    });

    expect(release?.version, '1.2.3');
    expect(release?.localizedTitle(const Locale('ja')), '更新しました');
    expect(release?.items.single.type, ReleaseNoteItemType.fix);
    expect(
      release?.items.single.localizedBody(const Locale('ja')),
      '同期が分かりやすくなりました。',
    );
  });

  test('current pubspec version has release notes', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versionMatch = RegExp(
      r'^version:\s*([0-9A-Za-z.+-]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(versionMatch, isNotNull);
    final currentVersion = versionMatch!.group(1)!.split('+').first;

    final releaseNotes =
        jsonDecode(
              File(
                'assets/release_notes/release_notes.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final releases = releaseNotes['releases'] as List<dynamic>;
    final currentRelease = releases
        .cast<Map<String, dynamic>>()
        .where((release) => release['version'] == currentVersion)
        .singleOrNull;

    expect(
      currentRelease,
      isNotNull,
      reason:
          'When pubspec.yaml version is changed, add or update the matching '
          'entry in assets/release_notes/release_notes.json.',
    );
    expect(currentRelease!['title'], isA<Map>());
    expect(currentRelease['summary'], isA<Map>());
    expect(
      currentRelease['items'],
      isA<List>().having((items) => items, 'items', isNotEmpty),
    );
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

  test(
    'widget quick capture is enabled by default but respects opt out',
    () async {
      SharedPreferences.setMockInitialValues({});
      final firstContainer = ProviderContainer();

      expect(
        firstContainer.read(widgetQuickCaptureSettingsControllerProvider),
        isTrue,
      );
      await pumpEventQueue();
      expect(
        firstContainer.read(widgetQuickCaptureSettingsControllerProvider),
        isTrue,
      );
      await firstContainer
          .read(widgetQuickCaptureSettingsControllerProvider.notifier)
          .setEnabled(false);
      expect(
        firstContainer.read(widgetQuickCaptureSettingsControllerProvider),
        isFalse,
      );
      firstContainer.dispose();
    },
  );

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
      '使用 4 位 PIN 保护此浏览器会话。尚未设置解锁 PIN。',
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
      '이 브라우저 세션을 4자리 PIN으로 보호합니다. 이 앱의 잠금 해제 PIN이 설정되어 있습니다.',
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

    expect(find.text('Build a record first'), findsOneWidget);
    expect(find.text('Best day'), findsNothing);
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

  test('last note editor location capture setting is restored', () async {
    SharedPreferences.setMockInitialValues({
      'notes.last_editor_mode': NoteEditorMode.quick.name,
      'notes.last_vault_id': 'everyday',
      'notes.last_capture_location': true,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(lastNoteEditorSettingsControllerProvider.notifier)
        .ensureRestored();

    final settings = container.read(lastNoteEditorSettingsControllerProvider);
    expect(settings.mode, NoteEditorMode.quick);
    expect(settings.vaultId, 'everyday');
    expect(settings.captureLocation, isTrue);
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

  test('fake Google Drive transport stores bundles in memory', () async {
    final transport = InMemoryGoogleDriveSyncTransport(
      uploadDelay: Duration.zero,
    );

    final uploaded = await transport.uploadBundle(
      encodedPayload: 'encrypted-payload',
      deviceId: 'test-device',
      noteCount: 2,
      attachmentCount: 1,
    );

    expect(uploaded.deviceId, 'test-device');
    expect(
      (await transport.fetchLatestBundleStatus())?.fileId,
      uploaded.fileId,
    );
    expect(
      await transport.listBundleHistory(),
      hasLength(greaterThanOrEqualTo(1)),
    );
    expect(
      (await transport.downloadLatestBundle())?.encodedPayload,
      'encrypted-payload',
    );

    await transport.uploadAttachmentObject(
      contentHash: 'hash-a',
      encodedPayload: 'attachment-payload',
      type: 'photo',
      label: 'photo.jpg',
      sizeBytes: 10,
    );
    expect(
      await transport.listAttachmentObjectContentHashes(),
      contains('hash-a'),
    );
    expect(
      await transport.downloadAttachmentObject('hash-a'),
      'attachment-payload',
    );
  });

  test('fake iCloud transport stores bundles and prunes old data', () async {
    final transport = InMemoryICloudSyncTransport();

    final status = await transport.checkAccountStatus();
    expect(status.isAvailable, isTrue);

    final first = await transport.uploadBundle(
      encodedPayload: 'first-encrypted-payload',
      deviceId: 'test-device',
      noteCount: 1,
      attachmentCount: 1,
    );
    final second = await transport.uploadBundle(
      encodedPayload: 'second-encrypted-payload',
      deviceId: 'test-device',
      noteCount: 2,
      attachmentCount: 2,
    );

    expect((await transport.fetchLatestBundleStatus())?.fileId, second.fileId);
    expect(
      (await transport.downloadBundleByRecordName(
        first.fileId,
      ))?.encodedPayload,
      'first-encrypted-payload',
    );

    await transport.uploadAttachmentObject(
      contentHash: 'keep-hash',
      encodedPayload: 'kept-attachment-payload',
      type: 'photo',
      label: 'photo.jpg',
      sizeBytes: 10,
    );
    await transport.uploadAttachmentObject(
      contentHash: 'delete-hash',
      encodedPayload: 'obsolete-attachment-payload',
      type: 'file',
      label: 'old.bin',
      sizeBytes: 20,
    );

    final beforePrune = await transport.fetchStorageBreakdown();
    expect(beforePrune.bundleCount, 2);
    expect(beforePrune.attachmentCount, 2);

    final pruned = await transport.pruneObsoleteData(
      referencedAttachmentHashes: {'keep-hash'},
    );
    expect(pruned.deletedBundleCount, 1);
    expect(pruned.deletedAttachmentCount, 1);
    expect(await transport.downloadAttachmentObject('keep-hash'), isNotNull);
    expect(await transport.downloadAttachmentObject('delete-hash'), isNull);
  });

  test(
    'fake iCloud sync keeps large video and multi-file attachments as objects',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-fake-icloud-large-attachments-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(67));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );
      final noteStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        database: noteDatabase,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final attachmentStore = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final fakeTransport = InMemoryICloudSyncTransport();
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          iCloudSynchronizableKeyValueStoreProvider.overrideWithValue(
            secureStore,
          ),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteStoreProvider.overrideWithValue(noteStore),
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
          secureSyncBundleStoreProvider.overrideWith(
            (ref) => SecureSyncBundleStore(
              encryptionService: encryptionService,
              syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
              legacyMasterKeyService: masterKeyService,
              directoryProvider: () async => tempDirectory,
              sharedPreferencesProvider: SharedPreferences.getInstance,
            ),
          ),
          iCloudSyncTransportProvider.overrideWithValue(fakeTransport),
        ],
      );
      final observedTransferStates = <SyncTransferState>[];
      final transferSubscription = container.listen<SyncTransferState>(
        syncTransferControllerProvider,
        (_, next) => observedTransferStates.add(next),
      );
      addTearDown(transferSubscription.close);
      addTearDown(container.dispose);
      addTearDown(noteDatabase.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      await container
          .read(syncProviderControllerProvider.notifier)
          .setProvider(SyncProvider.iCloud);
      await container
          .read(syncAuthControllerProvider.notifier)
          .connect(SyncProvider.iCloud);
      expect(
        container
            .read(syncAuthControllerProvider)[SyncProvider.iCloud]
            ?.isAuthenticated,
        isTrue,
      );

      final videoSource = await _writePayloadFile(
        tempDirectory,
        'simulator-icloud-large-video.mp4',
        sizeBytes: 8 * 1024 * 1024,
        byte: 0x41,
      );
      final attachmentSources = [
        (
          file: videoSource,
          type: AttachmentType.video,
          label: 'simulator-icloud-large-video.mp4',
          mimeType: 'video/mp4',
        ),
        for (var index = 0; index < 3; index++)
          (
            file: await _writePayloadFile(
              tempDirectory,
              'simulator-icloud-document-$index.bin',
              sizeBytes: 384 * 1024,
              byte: 0x60 + index,
            ),
            type: AttachmentType.file,
            label: 'simulator-icloud-document-$index.bin',
            mimeType: 'application/octet-stream',
          ),
      ];
      final attachments = <NoteAttachment>[];
      for (final source in attachmentSources) {
        final storedPath = await attachmentStore.storeAttachment(
          XFile(
            source.file.path,
            name: source.label,
            mimeType: source.mimeType,
          ),
          type: source.type,
        );
        expect(storedPath, isNotNull);
        attachments.add(
          NoteAttachment(
            type: source.type,
            label: source.label,
            filePath: storedPath,
          ),
        );
      }

      await container.read(notesControllerProvider.notifier).restoreCompleted;
      await container
          .read(notesControllerProvider.notifier)
          .upsert(
            NoteEntry(
              id: 'fake-icloud-large-attachment-note',
              vaultId: 'everyday',
              title: 'Fake iCloud large attachment note',
              body: 'Exercises an iCloud large video plus multiple files.',
              createdAt: DateTime.utc(2026, 5, 18, 10),
              updatedAt: DateTime.utc(2026, 5, 18, 10, 1),
              attachments: attachments,
            ),
          );

      final estimatedUploadBytes = await container
          .read(syncTransferControllerProvider.notifier)
          .estimatePendingUploadBytes();
      expect(estimatedUploadBytes, greaterThan(9 * 1024 * 1024));

      final stopwatch = Stopwatch()..start();
      await container
          .read(syncTransferControllerProvider.notifier)
          .uploadCurrentBundle(force: true);
      stopwatch.stop();

      final transferState = container.read(syncTransferControllerProvider);
      expect(transferState.stage, SyncTransferStage.success);
      final remoteStatus = await fakeTransport.fetchLatestBundleStatus();
      expect(remoteStatus?.noteCount, 1);
      expect(remoteStatus?.attachmentCount, attachments.length);
      expect(
        remoteStatus?.sizeBytes,
        lessThan(1024 * 1024),
        reason:
            'iCloud bundles should contain attachment object refs, '
            'not inline video/file bytes.',
      );
      final storage = await fakeTransport.fetchStorageBreakdown();
      expect(storage.attachmentCount, attachments.length);
      expect(storage.attachmentBytes, greaterThan(9 * 1024 * 1024));
      expect(
        observedTransferStates.any(
          (state) =>
              state.progress == SyncTransferProgress.uploadingBundle &&
              state.totalItems == attachments.length,
        ),
        isTrue,
        reason:
            'The UI needs item counts while multiple iCloud attachment '
            'objects are uploaded.',
      );
      debugPrint(
        'Fake iCloud large attachment upload completed in '
        '${stopwatch.elapsedMilliseconds} ms; estimated payload '
        '$estimatedUploadBytes bytes; remote bundle ${remoteStatus?.sizeBytes} '
        'bytes; attachment objects ${attachments.length}.',
      );
    },
  );

  test(
    'fake Google Drive sync sequence uploads and downloads bundle',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-fake-drive-sync-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(32));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );
      final noteStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        database: noteDatabase,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final fakeTransport = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
      );
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteStoreProvider.overrideWithValue(noteStore),
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          secureSyncBundleStoreProvider.overrideWith(
            (ref) => SecureSyncBundleStore(
              encryptionService: encryptionService,
              syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
              legacyMasterKeyService: masterKeyService,
              directoryProvider: () async => tempDirectory,
              sharedPreferencesProvider: SharedPreferences.getInstance,
            ),
          ),
          googleDriveSyncTransportProvider.overrideWithValue(fakeTransport),
          syncAuthGatewayProvider.overrideWithValue(
            FakeGoogleDriveSyncAuthGateway(fallback: DefaultSyncAuthGateway()),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(noteDatabase.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      await container
          .read(syncProviderControllerProvider.notifier)
          .setProvider(SyncProvider.googleDrive);
      await container
          .read(syncAuthControllerProvider.notifier)
          .connect(SyncProvider.googleDrive);
      expect(
        container
            .read(syncAuthControllerProvider)[SyncProvider.googleDrive]
            ?.isAuthenticated,
        isTrue,
      );

      final notesController = container.read(notesControllerProvider.notifier);
      await notesController.restoreCompleted;
      await notesController.upsert(
        NoteEntry(
          id: 'fake-drive-sequence-note',
          vaultId: 'everyday',
          title: 'Fake Drive sequence',
          body: 'Uploaded through the in-memory Google Drive simulator.',
          createdAt: DateTime.utc(2026, 5, 16, 10),
          updatedAt: DateTime.utc(2026, 5, 16, 10, 1),
        ),
      );

      final historyBefore = await fakeTransport.listBundleHistory();
      final syncController = container.read(
        syncTransferControllerProvider.notifier,
      );
      await syncController.uploadCurrentBundle(force: true);
      final afterUpload = container.read(syncTransferControllerProvider);
      expect(
        afterUpload.stage,
        SyncTransferStage.success,
        reason: afterUpload.message,
      );
      expect((await fakeTransport.fetchLatestBundleStatus())?.noteCount, 1);
      expect(
        await fakeTransport.listBundleHistory(),
        hasLength(historyBefore.length + 1),
      );

      await syncController.downloadLatestBundle();
      expect(
        container.read(syncTransferControllerProvider).stage,
        SyncTransferStage.success,
      );
      await syncController.applyDownloadedBundle();
      expect(
        container.read(syncTransferControllerProvider).stage,
        SyncTransferStage.success,
      );
      expect(
        container
            .read(notesControllerProvider)
            .any((note) => note.id == 'fake-drive-sequence-note'),
        isTrue,
      );
    },
  );

  test(
    'fake Google Drive sync keeps trashed notes hidden from stale remote upserts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fakeTransport = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
      );
      final firstDevice = await _createGoogleDriveSyncHarness(
        fakeTransport,
        tempPrefix: 'himemo-fake-drive-trash-first-',
        randomSeed: 91,
      );
      final secondDevice = await _createGoogleDriveSyncHarness(
        fakeTransport,
        tempPrefix: 'himemo-fake-drive-trash-second-',
        randomSeed: 92,
      );
      final firstNotes = firstDevice.container.read(
        notesControllerProvider.notifier,
      );
      final secondNotes = secondDevice.container.read(
        notesControllerProvider.notifier,
      );
      final firstSync = firstDevice.container.read(
        syncTransferControllerProvider.notifier,
      );
      final secondSync = secondDevice.container.read(
        syncTransferControllerProvider.notifier,
      );
      final createdAt = DateTime.utc(2026, 5, 19, 7);

      await firstNotes.upsert(
        NoteEntry(
          id: 'sim-trash-race',
          vaultId: 'everyday',
          title: 'Shared note',
          body: 'Initial shared body.',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      await firstSync.uploadCurrentBundle(force: true);
      expect(
        firstDevice.container.read(syncTransferControllerProvider).stage,
        SyncTransferStage.success,
      );

      await secondSync.downloadLatestBundle();
      await secondSync.applyDownloadedBundle();
      expect(
        secondDevice.container
            .read(visibleNotesProvider)
            .any((note) => note.id == 'sim-trash-race'),
        isTrue,
      );

      await firstNotes.delete('sim-trash-race');
      expect(
        firstDevice.container
            .read(trashedNotesProvider)
            .any((note) => note.id == 'sim-trash-race'),
        isTrue,
      );

      await secondNotes.upsert(
        NoteEntry(
          id: 'sim-trash-race',
          vaultId: 'everyday',
          title: 'Shared note edited remotely',
          body:
              'A stale device edited the note after another device deleted it.',
          createdAt: createdAt,
          updatedAt: DateTime.now().add(const Duration(hours: 1)),
          revision: 5,
        ),
      );
      await secondSync.uploadCurrentBundle(force: true);

      await firstSync.downloadLatestBundle();
      await firstSync.applyDownloadedBundle();
      final firstState = firstDevice.container.read(notesControllerProvider);
      final note = firstState.singleWhere(
        (entry) => entry.id == 'sim-trash-race',
      );
      expect(note.deletedAt, isNotNull);
      expect(note.syncState, NoteSyncState.pendingDelete);
      expect(
        firstDevice.container
            .read(visibleNotesProvider)
            .any((entry) => entry.id == 'sim-trash-race'),
        isFalse,
      );
      expect(
        firstDevice.container
            .read(trashedNotesProvider)
            .any((entry) => entry.id == 'sim-trash-race'),
        isTrue,
      );
    },
  );

  test('missing local attachment can be restored to remote reference', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-remote-ref-repair-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(33));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    final noteStore = EncryptedNoteStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      database: noteDatabase,
      directoryProvider: () async => tempDirectory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteStoreProvider.overrideWithValue(noteStore),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(noteDatabase.close);
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final notesController = container.read(notesControllerProvider.notifier);
    await notesController.restoreCompleted;
    final missingPath =
        '${tempDirectory.path}${Platform.pathSeparator}missing-video.mov.enc';
    await notesController.upsert(
      NoteEntry(
        id: 'missing-video-note',
        vaultId: 'everyday',
        title: 'Missing video',
        body: '',
        createdAt: DateTime.utc(2026, 5, 19, 10),
        attachments: [
          NoteAttachment(
            type: AttachmentType.video,
            label: 'IMG_5470.mov',
            filePath: missingPath,
          ),
        ],
      ),
    );

    const remoteRef =
        'sync-attachment-object://513e1430ad6bd63eba1ec515317dac8dec689c74d8dd409012b448093cb64cfa';
    final restored = await notesController
        .restoreMissingAttachmentRemoteReference(
          noteId: 'missing-video-note',
          index: 0,
          remoteAttachment: const NoteAttachment(
            type: AttachmentType.video,
            label: 'IMG_5470.mov',
            filePath: remoteRef,
            previewBytesBase64: 'preview',
            durationMs: 12000,
          ),
        );

    final note = container.read(notesControllerProvider).single;
    expect(restored, isTrue);
    expect(note.attachments.single.filePath, remoteRef);
    expect(note.attachments.single.previewBytesBase64, 'preview');
    expect(note.attachments.single.durationMs, 12000);
    expect(note.syncState, NoteSyncState.pendingUpload);
  });

  test('synced snapshot stores attachment reuse metadata locally', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-attachment-reuse-metadata-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(34));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    final noteStore = EncryptedNoteStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      database: noteDatabase,
      directoryProvider: () async => tempDirectory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteStoreProvider.overrideWithValue(noteStore),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(noteDatabase.close);
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final notesController = container.read(notesControllerProvider.notifier);
    await notesController.restoreCompleted;
    final localPath =
        '${tempDirectory.path}${Platform.pathSeparator}video.mov.enc';
    await notesController.upsert(
      NoteEntry(
        id: 'reuse-metadata-note',
        vaultId: 'everyday',
        title: 'Video',
        body: 'Local video note',
        createdAt: DateTime.utc(2026, 5, 19, 11),
        attachments: [
          NoteAttachment(
            type: AttachmentType.video,
            label: 'video.mov',
            filePath: localPath,
          ),
        ],
      ),
    );
    final queued = container.read(notesControllerProvider).single;
    const contentHash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    await notesController.markSnapshotChangesSynced(
      {queued.id: queued.contentHash},
      preparedNotes: [
        PreparedSyncNote(
          note: queued.copyWith(
            attachments: const [
              NoteAttachment(
                type: AttachmentType.video,
                label: 'video.mov',
                filePath: 'sync-attachment-object://$contentHash',
                localPayloadSizeBytes: 12345,
                localPayloadModifiedAtMillis: 1779178800000,
                syncAttachmentContentHash: contentHash,
              ),
            ],
          ),
          action: PendingNoteChangeAction.upsert,
        ),
      ],
    );

    final synced = container.read(notesControllerProvider).single;
    expect(synced.syncState, NoteSyncState.synced);
    expect(synced.attachments.single.filePath, localPath);
    expect(synced.attachments.single.localPayloadSizeBytes, 12345);
    expect(
      synced.attachments.single.localPayloadModifiedAtMillis,
      1779178800000,
    );
    expect(synced.attachments.single.syncAttachmentContentHash, contentHash);
  });

  test(
    'fake Google Drive sync keeps large video and multi-file attachments as objects',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-fake-drive-large-attachments-',
      );
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(64));
      final masterKeyService = MasterKeyService(
        secureStore: secureStore,
        keyFactory: encryptionService.generateKeyBytes,
      );
      final noteDatabase = EncryptedNoteDatabase(
        executor: NativeDatabase.memory(),
      );
      final noteStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        database: noteDatabase,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final attachmentStore = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: masterKeyService,
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
      final fakeTransport = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
      );
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(secureStore),
          encryptionServiceProvider.overrideWithValue(encryptionService),
          masterKeyServiceProvider.overrideWithValue(masterKeyService),
          encryptedNoteStoreProvider.overrideWithValue(noteStore),
          encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
          encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
          secureSyncBundleStoreProvider.overrideWith(
            (ref) => SecureSyncBundleStore(
              encryptionService: encryptionService,
              syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
              legacyMasterKeyService: masterKeyService,
              directoryProvider: () async => tempDirectory,
              sharedPreferencesProvider: SharedPreferences.getInstance,
            ),
          ),
          googleDriveSyncTransportProvider.overrideWithValue(fakeTransport),
          syncAuthGatewayProvider.overrideWithValue(
            FakeGoogleDriveSyncAuthGateway(fallback: DefaultSyncAuthGateway()),
          ),
        ],
      );
      final observedTransferStates = <SyncTransferState>[];
      final transferSubscription = container.listen<SyncTransferState>(
        syncTransferControllerProvider,
        (_, next) => observedTransferStates.add(next),
      );
      addTearDown(transferSubscription.close);
      addTearDown(container.dispose);
      addTearDown(noteDatabase.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      await container
          .read(syncProviderControllerProvider.notifier)
          .setProvider(SyncProvider.googleDrive);
      await container
          .read(syncAuthControllerProvider.notifier)
          .connect(SyncProvider.googleDrive);
      final attachmentHashesBeforeUpload = await fakeTransport
          .listAttachmentObjectContentHashes();

      final videoSource = await _writePayloadFile(
        tempDirectory,
        'simulator-large-video.mp4',
        sizeBytes: 12 * 1024 * 1024,
        byte: 0x41,
      );
      final attachmentSources = [
        (
          file: videoSource,
          type: AttachmentType.video,
          label: 'simulator-large-video.mp4',
          mimeType: 'video/mp4',
        ),
        for (var index = 0; index < 4; index++)
          (
            file: await _writePayloadFile(
              tempDirectory,
              'simulator-document-$index.bin',
              sizeBytes: 512 * 1024,
              byte: 0x50 + index,
            ),
            type: AttachmentType.file,
            label: 'simulator-document-$index.bin',
            mimeType: 'application/octet-stream',
          ),
      ];
      final attachments = <NoteAttachment>[];
      for (final source in attachmentSources) {
        final storedPath = await attachmentStore.storeAttachment(
          XFile(
            source.file.path,
            name: source.label,
            mimeType: source.mimeType,
          ),
          type: source.type,
        );
        expect(storedPath, isNotNull);
        attachments.add(
          NoteAttachment(
            type: source.type,
            label: source.label,
            filePath: storedPath,
          ),
        );
      }

      await container.read(notesControllerProvider.notifier).restoreCompleted;
      await container
          .read(notesControllerProvider.notifier)
          .upsert(
            NoteEntry(
              id: 'fake-drive-large-attachment-note',
              vaultId: 'everyday',
              title: 'Fake Drive large attachment note',
              body: 'Exercises a large video plus multiple file attachments.',
              createdAt: DateTime.utc(2026, 5, 16, 11),
              updatedAt: DateTime.utc(2026, 5, 16, 11, 1),
              attachments: attachments,
            ),
          );

      final estimatedUploadBytes = await container
          .read(syncTransferControllerProvider.notifier)
          .estimatePendingUploadBytes();
      expect(estimatedUploadBytes, greaterThan(14 * 1024 * 1024));

      final stopwatch = Stopwatch()..start();
      await container
          .read(syncTransferControllerProvider.notifier)
          .uploadCurrentBundle(force: true);
      stopwatch.stop();

      final transferState = container.read(syncTransferControllerProvider);
      expect(transferState.stage, SyncTransferStage.success);
      final remoteStatus = await fakeTransport.fetchLatestBundleStatus();
      expect(remoteStatus?.noteCount, 1);
      expect(remoteStatus?.attachmentCount, attachments.length);
      final attachmentHashesAfterUpload = await fakeTransport
          .listAttachmentObjectContentHashes();
      expect(
        attachmentHashesAfterUpload.length -
            attachmentHashesBeforeUpload.length,
        attachments.length,
      );
      expect(
        remoteStatus?.sizeBytes,
        lessThan(1024 * 1024),
        reason:
            'Google Drive bundles should contain attachment object refs, '
            'not inline video/file bytes.',
      );
      expect(
        observedTransferStates.any(
          (state) =>
              state.progress == SyncTransferProgress.uploadingBundle &&
              state.totalItems == attachments.length,
        ),
        isTrue,
        reason:
            'The UI needs item counts while multiple attachment objects '
            'are uploaded.',
      );
      debugPrint(
        'Fake Google Drive large attachment upload completed in '
        '${stopwatch.elapsedMilliseconds} ms; estimated payload '
        '$estimatedUploadBytes bytes; remote bundle ${remoteStatus?.sizeBytes} '
        'bytes; attachment objects ${attachments.length}.',
      );
    },
  );

  test(
    'Google Drive attachment upload failure keeps local attachment pending',
    () async {
      SharedPreferences.setMockInitialValues({});
      final failingTransport = _FailingAttachmentUploadTransport();
      final harness = await _createGoogleDriveSyncHarness(
        failingTransport,
        tempPrefix: 'himemo-fake-drive-attachment-upload-failure-',
      );
      final source = await _writePayloadFile(
        harness.tempDirectory,
        'must-stay-local-video.mp4',
        sizeBytes: 256 * 1024,
        byte: 0x31,
      );
      final storedPath = await harness.attachmentStore.storeAttachment(
        XFile(source.path, name: 'must-stay-local-video.mp4'),
        type: AttachmentType.video,
      );
      expect(storedPath, isNotNull);

      await harness.container
          .read(notesControllerProvider.notifier)
          .upsert(
            NoteEntry(
              id: 'attachment-upload-failure-note',
              vaultId: 'everyday',
              title: 'Attachment upload failure',
              body: 'The local attachment must not be replaced on failure.',
              createdAt: DateTime.utc(2026, 5, 16, 12),
              updatedAt: DateTime.utc(2026, 5, 16, 12, 1),
              attachments: [
                NoteAttachment(
                  type: AttachmentType.video,
                  label: 'must-stay-local-video.mp4',
                  filePath: storedPath,
                ),
              ],
            ),
          );

      await harness.container
          .read(syncTransferControllerProvider.notifier)
          .uploadCurrentBundle(force: true);

      final transferState = harness.container.read(
        syncTransferControllerProvider,
      );
      expect(transferState.stage, SyncTransferStage.error);
      expect(failingTransport.attachmentUploadCalls, 1);
      expect(failingTransport.bundleUploadCalls, 0);
      final note = harness.container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'attachment-upload-failure-note');
      expect(note.syncState, NoteSyncState.pendingUpload);
      expect(note.attachments.single.filePath, storedPath);
      expect(
        await harness.attachmentStore.readAttachment(
          storedPath!,
          type: AttachmentType.video,
        ),
        hasLength(256 * 1024),
      );
      expect(
        (await harness.container.read(syncEngineProvider).summarizeQueue())
            .totalChanges,
        1,
      );

      await harness.container
          .read(syncTransferControllerProvider.notifier)
          .uploadCurrentBundle(force: true);

      final retryState = harness.container.read(syncTransferControllerProvider);
      expect(retryState.stage, SyncTransferStage.error);
      expect(retryState.isCoolingDown, isTrue);
      expect(failingTransport.attachmentUploadCalls, 2);
    },
  );

  test(
    'Google Drive bundle upload failure keeps local attachment pending',
    () async {
      SharedPreferences.setMockInitialValues({});
      final failingTransport = _FailingBundleUploadTransport();
      final harness = await _createGoogleDriveSyncHarness(
        failingTransport,
        tempPrefix: 'himemo-fake-drive-bundle-upload-failure-',
      );
      final source = await _writePayloadFile(
        harness.tempDirectory,
        'must-stay-local-file.bin',
        sizeBytes: 128 * 1024,
        byte: 0x32,
      );
      final storedPath = await harness.attachmentStore.storeAttachment(
        XFile(source.path, name: 'must-stay-local-file.bin'),
        type: AttachmentType.file,
      );
      expect(storedPath, isNotNull);

      await harness.container
          .read(notesControllerProvider.notifier)
          .upsert(
            NoteEntry(
              id: 'bundle-upload-failure-note',
              vaultId: 'everyday',
              title: 'Bundle upload failure',
              body: 'The local attachment must survive bundle upload failure.',
              createdAt: DateTime.utc(2026, 5, 16, 13),
              updatedAt: DateTime.utc(2026, 5, 16, 13, 1),
              attachments: [
                NoteAttachment(
                  type: AttachmentType.file,
                  label: 'must-stay-local-file.bin',
                  filePath: storedPath,
                ),
              ],
            ),
          );

      await harness.container
          .read(syncTransferControllerProvider.notifier)
          .uploadCurrentBundle(force: true);

      final transferState = harness.container.read(
        syncTransferControllerProvider,
      );
      expect(transferState.stage, SyncTransferStage.error);
      expect(failingTransport.attachmentUploadCalls, 1);
      expect(failingTransport.bundleUploadCalls, 1);
      final note = harness.container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'bundle-upload-failure-note');
      expect(note.syncState, NoteSyncState.pendingUpload);
      expect(note.attachments.single.filePath, storedPath);
      expect(
        await harness.attachmentStore.readAttachment(
          storedPath!,
          type: AttachmentType.file,
        ),
        hasLength(128 * 1024),
      );
      expect(
        (await harness.container.read(syncEngineProvider).summarizeQueue())
            .totalChanges,
        1,
      );
    },
  );

  test('large Google Drive downloads warn on mobile data', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-fake-drive-large-download-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(65));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final noteDatabase = EncryptedNoteDatabase(
      executor: NativeDatabase.memory(),
    );
    final noteStore = EncryptedNoteStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      database: noteDatabase,
      directoryProvider: () async => tempDirectory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final fakeTransport = InMemoryGoogleDriveSyncTransport(
      uploadDelay: Duration.zero,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteStoreProvider.overrideWithValue(noteStore),
        encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
        googleDriveSyncTransportProvider.overrideWithValue(fakeTransport),
        networkConnectionServiceProvider.overrideWithValue(
          const _FakeNetworkConnectionService(NetworkConnectionKind.mobile),
        ),
        syncAuthGatewayProvider.overrideWithValue(
          FakeGoogleDriveSyncAuthGateway(fallback: DefaultSyncAuthGateway()),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(noteDatabase.close);
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    await container
        .read(syncProviderControllerProvider.notifier)
        .setProvider(SyncProvider.googleDrive);
    await container
        .read(syncAuthControllerProvider.notifier)
        .connect(SyncProvider.googleDrive);
    await fakeTransport.uploadBundle(
      encodedPayload: ''.padRight(51 * 1024 * 1024, 'x'),
      deviceId: 'remote-large-device',
      noteCount: 1,
      attachmentCount: 8,
    );
    await container
        .read(syncTransferControllerProvider.notifier)
        .refreshRemoteStatus();

    final warning = await container
        .read(syncTransferControllerProvider.notifier)
        .largeMobileTransferWarning(includeUpload: false);

    expect(warning?.direction, LargeSyncTransferDirection.download);
    expect(warning?.bytes, greaterThanOrEqualTo(50 * 1024 * 1024));
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
    final unlockedVaultId = unlocked!.vaultId;
    expect(
      container.read(searchFiltersControllerProvider).vaultId,
      unlockedVaultId,
    );

    expect(container.read(visibleVaultsProvider).length, 2);
    expect(
      container
          .read(visibleVaultsProvider)
          .any((vault) => vault.id == unlockedVaultId),
      isTrue,
    );
    expect(container.read(visibleVaultsProvider).map((vault) => vault.id), [
      unlockedVaultId,
      'everyday',
    ]);
    container.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
    expect(container.read(searchFiltersControllerProvider).vaultId, isNull);
  });

  test('private profiles can be renamed and focused from admin mode', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(17));
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
        .addProfile(name: 'Work archive', password: 'work-pass-123');
    expect(addError, isNull);

    final profile = container.read(privateMemoProfilesProvider).single;
    await container
        .read(privateMemoProfilesControllerProvider.notifier)
        .renameProfile(id: profile.id, name: 'Client archive');

    expect(
      container.read(privateMemoProfilesProvider).single.name,
      'Client archive',
    );
    container.read(adminModeSessionControllerProvider.notifier).unlock();
    container
        .read(searchFiltersControllerProvider.notifier)
        .setVault(container.read(privateMemoProfilesProvider).single.vaultId);

    expect(container.read(adminModeSessionControllerProvider), isTrue);
    expect(
      container.read(searchFiltersControllerProvider).vaultId,
      container.read(privateMemoProfilesProvider).single.vaultId,
    );
  });

  test(
    'private profile deletion is admin-only and removes local notes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(19));
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
          .addProfile(name: 'Old profile', password: 'old-pass-123');
      expect(addError, isNull);
      final profile = container.read(privateMemoProfilesProvider).single;
      final unlocked = await container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('old-pass-123');
      expect(unlocked?.vaultId, profile.vaultId);

      final notesController = container.read(notesControllerProvider.notifier);
      await notesController.restoreCompleted;
      await notesController.upsert(
        NoteEntry(
          id: 'old-private-note',
          vaultId: profile.vaultId,
          title: 'Old private note',
          body: 'This belongs to the old profile.',
          createdAt: DateTime.utc(2026, 5, 25, 1),
        ),
      );
      expect((await database.loadAll()).map((entry) => entry.note.id), [
        'old-private-note',
      ]);

      final blocked = await container
          .read(privateMemoProfilesControllerProvider.notifier)
          .deleteProfile(profile.id);
      expect(blocked, isFalse);
      expect(container.read(privateMemoProfilesProvider), hasLength(1));
      expect(await database.loadAll(), hasLength(1));

      container.read(adminModeSessionControllerProvider.notifier).unlock();
      final deleted = await container
          .read(privateMemoProfilesControllerProvider.notifier)
          .deleteProfile(profile.id);
      expect(deleted, isTrue);
      expect(container.read(privateMemoProfilesProvider), isEmpty);
      expect(await database.loadAll(), isEmpty);
      expect(await database.loadPendingChanges(), isEmpty);
      expect(container.read(searchFiltersControllerProvider).vaultId, isNull);
    },
  );

  test(
    'private profile unlock skips duplicate metadata without data key',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(23));
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
          .addProfile(name: 'Local private', password: 'same-pass-123');
      expect(addError, isNull);
      final localProfile = container.read(privateMemoProfilesProvider).single;
      final notesController = container.read(notesControllerProvider.notifier);
      await notesController.restoreCompleted;
      await notesController.upsert(
        NoteEntry(
          id: 'local-private-note',
          vaultId: localProfile.vaultId,
          title: 'Local private note',
          body: 'Must remain reachable after duplicate metadata import.',
          createdAt: DateTime.utc(2026, 5, 25, 8),
        ),
      );
      container.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();

      final salt = encryptionService.generateSalt();
      final verifier = await encryptionService.deriveSecretVerifier(
        secret: 'same-pass-123',
        salt: salt,
      );
      final imported = await container
          .read(privateMemoProfileStoreProvider)
          .importSyncPayload({
            'version': 1,
            'profiles': [
              {
                'id': 'profile_broken_remote',
                'name': 'Broken remote',
                'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
              },
            ],
            'verifiers': [
              {
                'profileId': 'profile_broken_remote',
                'salt': base64Encode(salt),
                'verifier': verifier,
              },
            ],
            'dataKeys': const [],
          });
      expect(imported, greaterThanOrEqualTo(2));
      await container
          .read(privateMemoProfilesControllerProvider.notifier)
          .refresh();
      expect(container.read(privateMemoProfilesProvider), hasLength(2));

      final unlocked = await container
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword('same-pass-123');
      expect(unlocked?.vaultId, localProfile.vaultId);
      expect(
        container.read(notesForVaultProvider(localProfile.vaultId)).single.id,
        'local-private-note',
      );
    },
  );

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

  test('sync upload keeps locked private profile changes encrypted', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'himemo-locked-private-sync-',
    );
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(113));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final attachmentStore = EncryptedAttachmentStore(
      encryptionService: encryptionService,
      masterKeyService: masterKeyService,
      directoryProvider: () async => tempDirectory,
      sharedPreferencesProvider: SharedPreferences.getInstance,
    );
    final fakeTransport = InMemoryGoogleDriveSyncTransport(
      uploadDelay: Duration.zero,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryptionService),
        masterKeyServiceProvider.overrideWithValue(masterKeyService),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
        encryptedNoteStoreProvider.overrideWith(
          (ref) => EncryptedNoteStore(
            encryptionService: encryptionService,
            masterKeyService: masterKeyService,
            profileDataKeyService: ref.watch(profileDataKeyServiceProvider),
            database: database,
            directoryProvider: () async => tempDirectory,
            sharedPreferencesProvider: SharedPreferences.getInstance,
          ),
        ),
        secureSyncBundleStoreProvider.overrideWith(
          (ref) => SecureSyncBundleStore(
            encryptionService: encryptionService,
            syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
            legacyMasterKeyService: masterKeyService,
            directoryProvider: () async => tempDirectory,
            sharedPreferencesProvider: SharedPreferences.getInstance,
          ),
        ),
        googleDriveSyncTransportProvider.overrideWithValue(fakeTransport),
        syncAuthGatewayProvider.overrideWithValue(
          FakeGoogleDriveSyncAuthGateway(fallback: DefaultSyncAuthGateway()),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    await container
        .read(syncProviderControllerProvider.notifier)
        .setProvider(SyncProvider.googleDrive);
    await container
        .read(syncAuthControllerProvider.notifier)
        .connect(SyncProvider.googleDrive);
    final addError = await container
        .read(privateMemoProfilesControllerProvider.notifier)
        .addProfile(name: 'Private sync', password: 'sync-pass-123');
    expect(addError, isNull);
    final unlocked = await container
        .read(privateProfileUnlockControllerProvider.notifier)
        .unlockWithPassword('sync-pass-123');
    expect(unlocked, isNotNull);

    final controller = container.read(notesControllerProvider.notifier);
    await controller.restoreCompleted;
    await controller.upsert(
      NoteEntry(
        id: 'locked-private-delete',
        vaultId: unlocked!.vaultId,
        title: 'Private pending delete',
        body: 'Must not upload while locked.',
        createdAt: DateTime.utc(2026, 5, 24, 10),
      ),
    );
    final snapshot = (await database.loadAll()).singleWhere(
      (entry) => entry.note.id == 'locked-private-delete',
    );
    final deletedAt = DateTime.utc(2026, 5, 24, 11);
    await database.upsertOne(
      note: snapshot.note,
      attachments: snapshot.attachments,
      pendingChange: PendingNoteChangeRecord(
        noteId: 'locked-private-delete',
        vaultId: unlocked.vaultId,
        revision: 2,
        action: PendingNoteChangeAction.delete,
        queuedAt: deletedAt,
        deletedAt: deletedAt,
      ),
    );
    container.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();

    await container
        .read(syncTransferControllerProvider.notifier)
        .uploadCurrentBundle(force: true);

    final remoteStatus = await fakeTransport.fetchLatestBundleStatus();
    expect(remoteStatus?.noteCount, 1);
    final remoteBundle = await fakeTransport.downloadLatestBundle();
    expect(remoteBundle, isNotNull);
    final localBundle = await container
        .read(secureSyncBundleStoreProvider)
        .writeEncryptedBundlePayload(
          remoteBundle!.encodedPayload,
          noteCount: remoteBundle.status.noteCount ?? 0,
          attachmentCount: remoteBundle.status.attachmentCount ?? 0,
          fileNameOverride: 'locked_private_sync_bundle.enc',
        );
    final decoded = await container
        .read(secureSyncBundleStoreProvider)
        .readBundleJson(localBundle.reference);
    expect(decoded?['notes'], isEmpty);
    expect(decoded?['encryptedPrivateNotes'], hasLength(1));
    final pendingChanges = await database.loadPendingChanges();
    expect(pendingChanges, isEmpty);
    expect(
      container.read(syncTransferControllerProvider).message,
      'sync.info.upload_success',
    );

    await database.deleteNoteById('locked-private-delete');
    expect(
      (await database.loadAll()).where(
        (entry) => entry.note.id == 'locked-private-delete',
      ),
      isEmpty,
    );
    final syncController = container.read(
      syncTransferControllerProvider.notifier,
    );
    await syncController.downloadLatestBundle();
    await syncController.applyDownloadedBundle();
    final restored = (await database.loadAll()).singleWhere(
      (entry) => entry.note.id == 'locked-private-delete',
    );
    expect(restored.note.deletedAt?.isAtSameMomentAs(deletedAt), isTrue);
    expect(await database.loadPendingChanges(), isEmpty);
  });

  test('Spotlight indexing sends note body and rich text terms', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final calls = <MethodCall>[];
    const channel = MethodChannel('org.ruhenheim.himemo/spotlight');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return <String, Object?>{'ok': true};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final bridge = SpotlightNoteIndexBridge((_) {});
    await bridge.replaceAllStandardNotes([
      NoteEntry(
        id: 'spotlight-body',
        vaultId: 'everyday',
        title: 'Spotlight title',
        body: 'Body keyword alpha',
        createdAt: DateTime(2026, 5, 16, 12),
        blocks: const [
          NoteBlock(type: NoteBlockType.paragraph, text: 'Rich block beta'),
          NoteBlock(
            type: NoteBlockType.file,
            attachment: NoteAttachment(
              type: AttachmentType.file,
              label: 'Attachment gamma.pdf',
            ),
          ),
        ],
        tags: const ['delta'],
      ),
    ]);

    final replaceCall = calls.firstWhere(
      (call) => call.method == 'replaceAllNotes',
    );
    final arguments = Map<String, Object?>.from(
      replaceCall.arguments as Map<Object?, Object?>,
    );
    final items = arguments['items']! as List<Object?>;
    final item = Map<String, Object?>.from(
      items.single! as Map<Object?, Object?>,
    );
    expect(item['body'], contains('Body keyword alpha'));
    expect(item['body'], contains('Rich block beta'));
    expect(item['body'], contains('Attachment gamma.pdf'));
    expect(item['searchTerms'], contains('alpha'));
    expect(item['searchTerms'], contains('beta'));
    expect(item['searchTerms'], contains('gamma'));
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

  test('seeded demo photo attachments use seasonal JPEG previews', () {
    final notes = SeededHomeRepository(
      seedBaseDate: DateTime(2026, 4, 29),
    ).seededNotes;
    final photoAttachments = notes
        .expand((note) => note.attachments)
        .where((attachment) => attachment.type == AttachmentType.photo)
        .toList();

    expect(
      photoAttachments.map((attachment) => attachment.label),
      containsAll([
        'spring-sakura.jpg',
        'summer-fireworks.jpg',
        'autumn-maple.jpg',
        'winter-snow.jpg',
      ]),
    );
    String titleForPhoto(String label) => notes
        .singleWhere(
          (note) => note.attachments.any(
            (attachment) =>
                attachment.type == AttachmentType.photo &&
                attachment.label == label,
          ),
        )
        .title;

    expect(titleForPhoto('spring-sakura.jpg'), '朝の桜');
    expect(titleForPhoto('summer-fireworks.jpg'), '夏の花火');
    expect(titleForPhoto('autumn-maple.jpg'), 'ライトアップの紅葉');
    expect(titleForPhoto('winter-snow.jpg'), '雪をまとった枝');

    final everydayPhotoLabels = notes
        .where((note) => note.vaultId == 'everyday')
        .expand((note) => note.attachments)
        .where((attachment) => attachment.type == AttachmentType.photo)
        .map((attachment) => attachment.label)
        .toSet();
    expect(
      everydayPhotoLabels,
      containsAll([
        'spring-sakura.jpg',
        'summer-fireworks.jpg',
        'autumn-maple.jpg',
        'winter-snow.jpg',
      ]),
    );
    final everydayVideoAttachments = notes
        .where((note) => note.vaultId == 'everyday')
        .expand((note) => note.attachments)
        .where((attachment) => attachment.type == AttachmentType.video);
    expect(everydayVideoAttachments, isEmpty);

    for (final attachment in photoAttachments) {
      final bytes = base64Decode(attachment.previewBytesBase64!);
      expect(bytes, hasLength(greaterThan(1024)));
      expect(bytes[0], 0xff);
      expect(bytes[1], 0xd8);
    }
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

  test('private notes do not override chronological sorting', () async {
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
        updatedAt: DateTime(2026, 5, 5, 10, 0),
      ),
    );
    await controller.upsert(
      NoteEntry(
        id: 'private-older',
        vaultId: legacyPrivateVaultId,
        title: 'Private older',
        body: '',
        createdAt: DateTime(2026, 5, 1, 10, 0),
        updatedAt: DateTime(2026, 5, 1, 10, 0),
      ),
    );

    expect(container.read(notesControllerProvider).map((note) => note.id), [
      'normal-newer',
      'private-older',
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

  test('onboarding completion marks current release notes as seen', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        packageInfoProvider.overrideWith(
          (ref) async => const AppPackageDetails(
            appName: 'HiMemo',
            version: '9.8.7',
            buildNumber: '654',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(appLaunchControllerProvider.notifier)
        .completeOnboarding();
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString('release_notes.last_seen'), '9.8.7+654');
  });

  test('app tutorial controller walks through highlight steps', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(appTutorialControllerProvider.notifier);

    expect(container.read(appTutorialControllerProvider), isNull);

    controller.start();
    expect(
      container.read(appTutorialControllerProvider)?.step,
      AppTutorialStep.privateProfile,
    );

    controller.next();
    expect(
      container.read(appTutorialControllerProvider)?.step,
      AppTutorialStep.addNote,
    );

    controller.previous();
    expect(
      container.read(appTutorialControllerProvider)?.step,
      AppTutorialStep.privateProfile,
    );

    controller.close();
    expect(container.read(appTutorialControllerProvider), isNull);
  });

  test('app tutorial controller starts purpose-based courses', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(appTutorialControllerProvider.notifier);

    expect(AppTutorialCourse.values.length, greaterThanOrEqualTo(13));

    controller.start(AppTutorialCourse.mainScreen);
    var state = container.read(appTutorialControllerProvider);
    expect(state?.course, AppTutorialCourse.mainScreen);
    expect(state?.steps, [
      AppTutorialStep.search,
      AppTutorialStep.filters,
      AppTutorialStep.notesList,
      AppTutorialStep.privateProfile,
      AppTutorialStep.syncStatus,
      AppTutorialStep.navigation,
    ]);

    controller.start(AppTutorialCourse.organize);
    state = container.read(appTutorialControllerProvider);
    expect(state?.course, AppTutorialCourse.organize);
    expect(state?.step, AppTutorialStep.tags);
    expect(state?.stepCount, 3);

    controller.next();
    state = container.read(appTutorialControllerProvider);
    expect(state?.step, AppTutorialStep.trash);

    controller.start(AppTutorialCourse.find);
    state = container.read(appTutorialControllerProvider);
    expect(state?.step, AppTutorialStep.search);
    expect(state?.steps, [
      AppTutorialStep.search,
      AppTutorialStep.filters,
      AppTutorialStep.tags,
    ]);

    controller.start(AppTutorialCourse.privateMemo);
    state = container.read(appTutorialControllerProvider);
    expect(state?.step, AppTutorialStep.privateMemo);

    controller.start(AppTutorialCourse.trashRecovery);
    state = container.read(appTutorialControllerProvider);
    expect(state?.steps, [
      AppTutorialStep.trashRecovery,
      AppTutorialStep.trash,
      AppTutorialStep.navigation,
    ]);
  });

  test('app tutorial completion is persisted by course', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      appTutorialCompletionControllerProvider.notifier,
    );
    await controller.markComplete(AppTutorialCourse.sync);

    expect(
      container.read(appTutorialCompletionControllerProvider),
      contains(AppTutorialCourse.sync),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('tutorials.completed_courses.v1'),
      contains(AppTutorialCourse.sync.name),
    );
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

  test(
    'device auth controller serializes concurrent unlock attempts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = _FakeDeviceAuthGateway();
      final container = ProviderContainer(
        overrides: [deviceAuthGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      final controller = container.read(deviceAuthControllerProvider.notifier);
      final firstAttempt = controller.authenticate(reason: 'Unlock HiMemo');
      final secondAttempt = controller.authenticate(reason: 'Unlock HiMemo');

      expect(
        container.read(deviceAuthControllerProvider).isAuthenticating,
        isTrue,
      );
      expect(gateway.authenticateCalls, 1);

      gateway.completeAuthentication(true);

      expect(await firstAttempt, isTrue);
      expect(await secondAttempt, isTrue);
      expect(gateway.authenticateCalls, 1);
      expect(
        container.read(deviceAuthControllerProvider).isAuthenticating,
        isFalse,
      );
      expect(container.read(appSessionUnlockControllerProvider), isTrue);
    },
  );

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

  testWidgets('private profile create dialog can be cancelled safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(23));
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
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    addTearDown(database.close);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Private profiles'));
    await tester.tap(find.text('Private profiles'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(SettingsScreen.privateProfileAddKey, skipOffstage: false),
    );
    await tester.tap(find.byKey(SettingsScreen.privateProfileAddKey));
    await tester.pumpAndSettle();
    expect(
      find.byKey(SettingsScreen.privateProfileNameInputKey),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(find.byKey(SettingsScreen.privateProfileNameInputKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile unlock dialog links to private profile creation', (
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
    final encryptionService = EncryptionService(random: Random(37));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packageInfoProvider.overrideWith(
            (ref) async => const AppPackageDetails(
              appName: 'HiMemo',
              version: '0.0.0',
              buildNumber: '0',
            ),
          ),
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

    await tester.tap(find.byKey(AppShell.privateProfileAccessKey));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('private-profile-unlock-password-input')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('private-profile-unlock-create-profile')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(SettingsScreen.privateProfileNameInputKey),
      findsOneWidget,
    );
    expect(find.text('Add private profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile access action is compact and tutorial targets fit', (
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
    final encryptionService = EncryptionService(random: Random(41));
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
    await tester.pumpAndSettle();

    final mobileProfileRect = tester.getRect(
      find.byKey(AppShell.privateProfileAccessKey),
    );
    expect(mobileProfileRect.width, 40);
    expect(mobileProfileRect.right, greaterThan(410));

    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpAndSettle();

    container
        .read(appTutorialControllerProvider.notifier)
        .start(AppTutorialCourse.basics);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    Rect cardRect() => tester.getRect(find.byKey(AppShell.tutorialCardKey));
    Rect padded(Rect rect) => rect.inflate(8);
    expect(
      cardRect().overlaps(
        padded(tester.getRect(find.byKey(AppShell.privateProfileAccessKey))),
      ),
      isFalse,
    );

    container.read(appTutorialControllerProvider.notifier).next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final addNoteRect = tester.getRect(find.byKey(AppShell.addNoteKey));
    expect(addNoteRect.left, lessThan(260));
    expect(cardRect().overlaps(padded(addNoteRect)), isFalse);

    container.read(appTutorialControllerProvider.notifier).next();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final syncRect = tester.getRect(find.byKey(AppShell.syncIndicatorKey));
    expect(syncRect.right, greaterThan(900));
    expect(cardRect().overlaps(padded(syncRect)), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tutorial advances across tabs and marks completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
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

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const HiMemoApp(flavor: AppFlavor.development),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go('/tags');
    container
        .read(appTutorialControllerProvider.notifier)
        .start(AppTutorialCourse.organize);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.routeInformationProvider.value.uri.path, '/tags');
    expect(find.byKey(AppShell.tutorialCardKey), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/trash');
    expect(
      container.read(appTutorialControllerProvider)?.step,
      AppTutorialStep.trash,
    );

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/calendar');
    expect(
      container.read(appTutorialControllerProvider)?.step,
      AppTutorialStep.calendarInsights,
    );

    final doneButton = find.text('Done').hitTestable();
    expect(doneButton, findsOneWidget);
    await tester.tap(doneButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/tutorials');
    expect(container.read(appTutorialControllerProvider), isNull);
    expect(
      container.read(appTutorialCompletionControllerProvider),
      contains(AppTutorialCourse.organize),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('maintenance tutorial can finish on mobile trash screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(43));
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
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go('/settings');
    container
        .read(appTutorialControllerProvider.notifier)
        .start(AppTutorialCourse.maintenance);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.byKey(AppShell.tutorialCardKey), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/notes');
    expect(find.byKey(AppShell.tutorialCardKey), findsOneWidget);

    await tester.tap(find.byKey(AppShell.tutorialNextKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/trash');
    expect(
      container.read(appTutorialControllerProvider)?.step,
      AppTutorialStep.trash,
    );
    expect(find.byKey(TrashScreen.trashContentKey), findsOneWidget);
    expect(find.byKey(AppShell.tutorialCardKey), findsOneWidget);

    final doneButton = find.text('Done').hitTestable();
    expect(doneButton, findsOneWidget);
    await tester.tap(doneButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/tutorials');
    expect(container.read(appTutorialControllerProvider), isNull);
    expect(
      container.read(appTutorialCompletionControllerProvider),
      contains(AppTutorialCourse.maintenance),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('all tutorial courses can advance on mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String routeForStep(AppTutorialStep step) => switch (step) {
      AppTutorialStep.privateProfile ||
      AppTutorialStep.addNote ||
      AppTutorialStep.search ||
      AppTutorialStep.filters ||
      AppTutorialStep.notesList ||
      AppTutorialStep.attachments ||
      AppTutorialStep.privateMemo ||
      AppTutorialStep.syncTroubleshooting ||
      AppTutorialStep.syncStatus ||
      AppTutorialStep.navigation => '/notes',
      AppTutorialStep.settings => '/settings',
      AppTutorialStep.tags => '/tags',
      AppTutorialStep.trash || AppTutorialStep.trashRecovery => '/trash',
      AppTutorialStep.calendarInsights => '/calendar',
    };

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(44));
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
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    for (final course in AppTutorialCourse.values) {
      container.read(appTutorialControllerProvider.notifier).start(course);
      final firstStep = container.read(appTutorialControllerProvider)!.step;
      router.go(routeForStep(firstStep));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      while (container.read(appTutorialControllerProvider) != null) {
        final state = container.read(appTutorialControllerProvider)!;
        expect(
          find.byKey(AppShell.tutorialCardKey),
          findsOneWidget,
          reason: '${course.name} stopped on ${state.step.name}',
        );

        final nextButton = find.byKey(AppShell.tutorialNextKey).hitTestable();
        expect(
          nextButton,
          findsOneWidget,
          reason: '${course.name} next button hidden on ${state.step.name}',
        );
        await tester.tap(nextButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      expect(router.routeInformationProvider.value.uri.path, '/tutorials');
      expect(
        container.read(appTutorialCompletionControllerProvider),
        contains(course),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('audit log settings are shown only in admin mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(41));
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
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audit logs'), findsNothing);

    container.read(adminModeSessionControllerProvider.notifier).unlock();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Audit logs'), 300);

    expect(find.text('Audit logs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('release notes history dialog opens from settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'app.onboarding_completed': true,
      'app.onboarding_completed_version': 2,
      'settings.locale': 'english',
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(31));
    final masterKeyService = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryptionService.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());

    configureFlavor(AppFlavor.development);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          releaseNotesProvider.overrideWith((ref) async {
            return [
              ReleaseNote(
                version: '1.0.0',
                date: DateTime(2026, 5, 16),
                importance: 'normal',
                title: const {'en': 'HiMemo was updated'},
                summary: const {'en': 'Release note summary.'},
                items: const [
                  ReleaseNoteItem(
                    type: ReleaseNoteItemType.improvement,
                    title: {'en': 'Improved history'},
                    body: {'en': 'The update history opens from settings.'},
                  ),
                ],
              ),
            ];
          }),
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
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    addTearDown(database.close);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('About'), 200);
    await tester.ensureVisible(find.text('About'));
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Update history'), 200);
    await tester.ensureVisible(find.text('Update history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update history'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('1.0.0 - HiMemo was updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    final homeRepository = SeededHomeRepository(
      seedBaseDate: DateTime(2026, 4, 12, 23, 30),
      useEnglishSeedData: true,
    );
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(homeRepository),
        notesControllerProvider.overrideWithValue(
          homeRepository.seededNotes
              .where((note) => note.vaultId == 'everyday')
              .toList(growable: false),
        ),
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
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(
      find.byKey(const Key('note-tile-seed-2026-04-12-groceries')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('edit-note-button')), findsOneWidget);

    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();

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
    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'tag-3',
            vaultId: 'everyday',
            title: 'Shared project',
            body: 'Third body',
            tags: const ['Alpha', 'Home'],
            createdAt: DateTime(2026, 4, 20, 12, 0),
          ),
        );

    container.read(searchFiltersControllerProvider.notifier).addTag('alpha');

    final visible = container.read(visibleNotesProvider);
    expect(visible.map((note) => note.id), ['tag-3', 'tag-1']);
    expect(container.read(visibleNoteIndexByIdProvider), {
      'tag-3': 0,
      'tag-1': 1,
    });
    expect(container.read(visibleTagSuggestionsProvider), contains('Alpha'));

    container.read(searchFiltersControllerProvider.notifier).setTags([
      'alpha',
      'home',
    ]);
    expect(container.read(visibleNotesProvider).map((note) => note.id), [
      'tag-3',
      'tag-2',
      'tag-1',
    ]);
    container
        .read(searchFiltersControllerProvider.notifier)
        .setRequireAllTags(true);
    expect(container.read(visibleNotesProvider).map((note) => note.id), [
      'tag-3',
    ]);

    container.read(searchFiltersControllerProvider.notifier).reset();
    container.read(searchQueryProvider.notifier).setQuery('second body');
    expect(container.read(visibleNotesProvider).map((note) => note.id), [
      'tag-2',
    ]);
    expect(dedupeNoteTags([' Alpha ', '#alpha', 'HOME']), ['Alpha', 'HOME']);
  });

  test(
    'local tag suggestions prefer visible known tags and avoid duplicates',
    () {
      final suggestions = suggestLocalNoteTags(
        const TagSuggestionRequest(
          title: 'Project Alpha review',
          body: 'Discussed client onboarding and release checklist.',
          existingTags: ['Work'],
          knownTags: ['Alpha', 'Work', 'Client', 'Release'],
          attachmentLabels: ['alpha-outline.pdf'],
        ),
      );

      expect(suggestions.take(3), containsAllInOrder(['Alpha', 'Release']));
      expect(suggestions, isNot(contains('Work')));
    },
  );

  test(
    'local tag suggestions boost frequently used known tags above ad-hoc tokens',
    () {
      final suggestions = suggestLocalNoteTags(
        const TagSuggestionRequest(
          title: 'planning long_term_strategy and review',
          body: 'planning planning long_term_strategy long_term_strategy',
          existingTags: <String>[],
          knownTags: ['planning'],
          attachmentLabels: <String>[],
          knownTagCounts: {'planning': 8},
        ),
      );

      // Known/used tag must rank ahead of an ad-hoc compound token like
      // long_term_strategy that appears more times in the text.
      expect(suggestions.first, 'planning');
      final planningIndex = suggestions.indexOf('planning');
      final compoundIndex = suggestions.indexOf('long_term_strategy');
      expect(planningIndex, lessThan(compoundIndex));
    },
  );

  test('auto tag rules add matching tags without duplicates', () {
    final rule = AutoTagRule(
      id: 'rule-1',
      tag: 'Finance',
      keywords: splitAutoTagKeywords('receipt, invoice'),
    );
    final note = NoteEntry(
      id: 'auto-tag-1',
      vaultId: 'everyday',
      title: 'Receipt from cafe',
      body: 'Lunch meeting',
      tags: const ['Work'],
      createdAt: DateTime.utc(2026, 5, 20),
    );

    final tagged = applyAutoTagRules(note, [rule]);
    expect(tagged.tags, ['Work', 'Finance']);
    expect(applyAutoTagRules(tagged, [rule]).tags, ['Work', 'Finance']);
    expect(applyAutoTagRules(note, [rule.copyWith(enabled: false)]).tags, [
      'Work',
    ]);
  });

  test('notes controller applies auto tag rules when saving notes', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(76));
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
        .read(autoTagRulesControllerProvider.notifier)
        .addRule(tag: 'Finance', keywords: ['receipt']);
    final controller = container.read(notesControllerProvider.notifier);
    await controller.restoreCompleted;
    await controller.upsert(
      NoteEntry(
        id: 'auto-tag-save',
        vaultId: 'everyday',
        title: 'Receipt from cafe',
        body: 'Lunch meeting',
        createdAt: DateTime.utc(2026, 5, 20),
      ),
    );

    final saved = container
        .read(notesControllerProvider)
        .singleWhere((note) => note.id == 'auto-tag-save');
    expect(saved.tags, ['Finance']);
    expect(saved.syncState, NoteSyncState.pendingUpload);
  });

  test('native tag suggestions strip markdown JSON wrappers', () {
    final suggestions = sanitizeSuggestedTags(
      const ['```json\n["買い物", "旅行", "json", "```"]\n```', 'tags: 家族, 買い物'],
      existingTags: const ['旅行'],
    );

    expect(suggestions, ['買い物', '家族']);
  });

  test('native tag suggestions reject code fence fragments', () {
    final suggestions = sanitizeSuggestedTags(const [
      '```json',
      '``` json',
      '```JSON\n["travel", "family"]\n```',
      'tags: work\n```',
    ]);

    expect(suggestions, ['travel', 'family', 'work']);
    expect(suggestions, isNot(contains('```json')));
    expect(suggestions, isNot(contains('``` json')));
  });

  test('sync exclusion tags always keep the built-in system tag', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(syncExclusionTagsControllerProvider), [
      systemSyncExcludedTag,
    ]);

    await container
        .read(syncExclusionTagsControllerProvider.notifier)
        .addTag(' Local Only ');
    await container
        .read(syncExclusionTagsControllerProvider.notifier)
        .removeTag(systemSyncExcludedTag);

    expect(container.read(syncExclusionTagsControllerProvider), [
      systemSyncExcludedTag,
      'Local Only',
    ]);
  });

  test('tag rename and delete update every visible note safely', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(73));
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
        id: 'tag-edit-1',
        vaultId: 'everyday',
        title: 'First',
        body: '',
        tags: const ['Work', 'Alpha'],
        createdAt: DateTime.utc(2026, 5, 17),
      ),
    );
    await controller.upsert(
      NoteEntry(
        id: 'tag-edit-2',
        vaultId: 'everyday',
        title: 'Second',
        body: '',
        tags: const ['work', 'Home'],
        createdAt: DateTime.utc(2026, 5, 17, 1),
      ),
    );
    await controller.upsert(
      NoteEntry(
        id: 'tag-edit-system',
        vaultId: 'everyday',
        title: 'System',
        body: '',
        tags: const [systemSyncExcludedTag],
        createdAt: DateTime.utc(2026, 5, 17, 2),
      ),
    );

    expect(await controller.renameTag(from: 'work', to: 'Home'), 2);
    final renamed = container.read(notesControllerProvider);
    expect(renamed.singleWhere((note) => note.id == 'tag-edit-1').tags, [
      'Home',
      'Alpha',
    ]);
    expect(renamed.singleWhere((note) => note.id == 'tag-edit-2').tags, [
      'Home',
    ]);
    expect(
      renamed.singleWhere((note) => note.id == 'tag-edit-1').syncState,
      NoteSyncState.pendingUpload,
    );

    expect(await controller.deleteTag('home'), 2);
    final deleted = container.read(notesControllerProvider);
    expect(deleted.singleWhere((note) => note.id == 'tag-edit-1').tags, [
      'Alpha',
    ]);
    expect(
      deleted.singleWhere((note) => note.id == 'tag-edit-2').tags,
      isEmpty,
    );

    expect(
      await controller.renameTag(from: systemSyncExcludedTag, to: 'Archive'),
      0,
    );
    expect(await controller.deleteTag(systemSyncExcludedTag), 0);
    expect(
      container
          .read(notesControllerProvider)
          .singleWhere((note) => note.id == 'tag-edit-system')
          .tags,
      [systemSyncExcludedTag],
    );
  });

  test('notes with sync exclusion tags are omitted from snapshots', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(71));
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
        id: 'excluded-note',
        vaultId: 'everyday',
        title: 'Local private draft',
        body: 'This note must not enter cloud sync.',
        createdAt: DateTime.utc(2026, 5, 17),
        tags: const [systemSyncExcludedTag],
      ),
    );
    await controller.upsert(
      NoteEntry(
        id: 'regular-note',
        vaultId: 'everyday',
        title: 'Regular note',
        body: 'This note can sync.',
        createdAt: DateTime.utc(2026, 5, 17, 1),
      ),
    );

    final notes = container.read(notesControllerProvider);
    expect(
      notes.singleWhere((note) => note.id == 'excluded-note').syncState,
      NoteSyncState.localOnly,
    );
    expect(
      notes.singleWhere((note) => note.id == 'regular-note').syncState,
      NoteSyncState.pendingUpload,
    );

    final snapshot = await controller.notesForSyncSnapshot();
    expect(snapshot.map((note) => note.id), ['regular-note']);

    await controller.upsert(
      notes
          .singleWhere((note) => note.id == 'excluded-note')
          .copyWith(tags: const <String>[]),
    );
    final restoredNote = container
        .read(notesControllerProvider)
        .singleWhere((note) => note.id == 'excluded-note');
    expect(restoredNote.syncState, NoteSyncState.pendingUpload);
    final restoredSnapshot = await controller.notesForSyncSnapshot();
    expect(
      restoredSnapshot.map((note) => note.id),
      containsAll(['excluded-note', 'regular-note']),
    );
  });

  test('search filters can partition notes by year', () async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = MemorySecureKeyValueStore();
    final encryptionService = EncryptionService(random: Random(7));
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
            id: 'year-2025',
            vaultId: 'everyday',
            title: 'Older note',
            body: 'Older body',
            createdAt: DateTime(2025, 12, 31, 23, 0),
          ),
        );
    await container
        .read(notesControllerProvider.notifier)
        .upsert(
          NoteEntry(
            id: 'year-2026',
            vaultId: 'everyday',
            title: 'Current note',
            body: 'Current body',
            createdAt: DateTime(2026, 1, 1, 8, 0),
          ),
        );

    expect(container.read(visibleNoteYearsProvider), [2026, 2025]);
    expect(
      container
          .read(visibleNotesByDayProvider)[DateTime(2026, 1, 1)]
          ?.map((note) => note.id),
      ['year-2026'],
    );

    container.read(searchFiltersControllerProvider.notifier).setYear(2025);
    expect(container.read(visibleNotesProvider).map((note) => note.id), [
      'year-2025',
    ]);
  });

  test(
    'archived notes stay out of normal search until archive mode is enabled',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secureStore = MemorySecureKeyValueStore();
      final encryptionService = EncryptionService(random: Random(8));
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
      await controller.upsert(
        NoteEntry(
          id: 'archive-old',
          vaultId: 'everyday',
          title: 'Old archive target',
          body: 'Find me only in archive mode',
          createdAt: DateTime(2020, 1, 1),
        ),
      );
      await controller.upsert(
        NoteEntry(
          id: 'archive-current',
          vaultId: 'everyday',
          title: 'Current note',
          body: 'Visible normally',
          createdAt: DateTime.now(),
        ),
      );

      expect(
        await controller.archiveNotesOlderThan(const Duration(days: 365)),
        1,
      );
      expect(container.read(archivedNoteCountProvider), 1);
      expect(container.read(visibleNotesProvider).map((note) => note.id), [
        'archive-current',
      ]);

      container.read(searchQueryProvider.notifier).setQuery('archive mode');
      expect(container.read(visibleNotesProvider), isEmpty);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setArchivedOnly(true);
      expect(container.read(visibleNotesProvider).map((note) => note.id), [
        'archive-old',
      ]);

      expect(await controller.unarchiveAll(), 1);
      container.read(searchFiltersControllerProvider.notifier).reset();
      container.read(searchQueryProvider.notifier).setQuery('');
      expect(container.read(visibleNotesProvider).map((note) => note.id), [
        'archive-old',
        'archive-current',
      ]);
    },
  );
}

Future<File> _writePayloadFile(
  Directory directory,
  String fileName, {
  required int sizeBytes,
  required int byte,
}) async {
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(List<int>.filled(sizeBytes, byte), flush: true);
  return file;
}

Future<_GoogleDriveSyncHarness> _createGoogleDriveSyncHarness(
  GoogleDriveSyncTransport transport, {
  required String tempPrefix,
  int randomSeed = 66,
}) async {
  final tempDirectory = await Directory.systemTemp.createTemp(tempPrefix);
  final secureStore = MemorySecureKeyValueStore();
  final encryptionService = EncryptionService(random: Random(randomSeed));
  final masterKeyService = MasterKeyService(
    secureStore: secureStore,
    keyFactory: encryptionService.generateKeyBytes,
  );
  final noteDatabase = EncryptedNoteDatabase(executor: NativeDatabase.memory());
  final noteStore = EncryptedNoteStore(
    encryptionService: encryptionService,
    masterKeyService: masterKeyService,
    database: noteDatabase,
    directoryProvider: () async => tempDirectory,
    sharedPreferencesProvider: SharedPreferences.getInstance,
  );
  final attachmentStore = EncryptedAttachmentStore(
    encryptionService: encryptionService,
    masterKeyService: masterKeyService,
    directoryProvider: () async => tempDirectory,
    sharedPreferencesProvider: SharedPreferences.getInstance,
  );
  final container = ProviderContainer(
    overrides: [
      secureKeyValueStoreProvider.overrideWithValue(secureStore),
      encryptionServiceProvider.overrideWithValue(encryptionService),
      masterKeyServiceProvider.overrideWithValue(masterKeyService),
      encryptedNoteStoreProvider.overrideWithValue(noteStore),
      encryptedNoteDatabaseProvider.overrideWithValue(noteDatabase),
      encryptedAttachmentStoreProvider.overrideWithValue(attachmentStore),
      secureSyncBundleStoreProvider.overrideWith(
        (ref) => SecureSyncBundleStore(
          encryptionService: encryptionService,
          syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
          legacyMasterKeyService: masterKeyService,
          directoryProvider: () async => tempDirectory,
          sharedPreferencesProvider: SharedPreferences.getInstance,
        ),
      ),
      syncBundleStateStoreProvider.overrideWithValue(
        SyncBundleStateStore(storageKey: 'sync.bundle_state.$tempPrefix'),
      ),
      googleDriveSyncTransportProvider.overrideWithValue(transport),
      syncAuthGatewayProvider.overrideWithValue(
        FakeGoogleDriveSyncAuthGateway(fallback: DefaultSyncAuthGateway()),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(noteDatabase.close);
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  await container
      .read(syncProviderControllerProvider.notifier)
      .setProvider(SyncProvider.googleDrive);
  await container
      .read(syncAuthControllerProvider.notifier)
      .connect(SyncProvider.googleDrive);
  await container.read(notesControllerProvider.notifier).restoreCompleted;

  return _GoogleDriveSyncHarness(
    container: container,
    tempDirectory: tempDirectory,
    attachmentStore: attachmentStore,
  );
}

class _GoogleDriveSyncHarness {
  const _GoogleDriveSyncHarness({
    required this.container,
    required this.tempDirectory,
    required this.attachmentStore,
  });

  final ProviderContainer container;
  final Directory tempDirectory;
  final EncryptedAttachmentStore attachmentStore;
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

class _FakeDeviceAuthGateway implements DeviceAuthGateway {
  int authenticateCalls = 0;
  final Completer<bool> _authenticateCompleter = Completer<bool>();

  @override
  Future<DeviceAuthState> checkAvailability() async {
    return const DeviceAuthState(
      availability: DeviceAuthAvailability.available,
      methods: ['Face ID'],
    );
  }

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) {
    authenticateCalls += 1;
    return _authenticateCompleter.future;
  }

  void completeAuthentication(bool value) {
    if (_authenticateCompleter.isCompleted) {
      return;
    }
    _authenticateCompleter.complete(value);
  }
}

class _FakeNetworkConnectionService extends NetworkConnectionService {
  const _FakeNetworkConnectionService(this.kind);

  final NetworkConnectionKind kind;

  @override
  Future<NetworkConnectionKind> currentKind() async => kind;
}

class _FailingAttachmentUploadTransport
    extends InMemoryGoogleDriveSyncTransport {
  _FailingAttachmentUploadTransport() : super(uploadDelay: Duration.zero);

  int attachmentUploadCalls = 0;
  int bundleUploadCalls = 0;

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) async {
    attachmentUploadCalls += 1;
    throw StateError('simulated attachment upload failure');
  }

  @override
  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  }) {
    bundleUploadCalls += 1;
    return super.uploadBundle(
      encodedPayload: encodedPayload,
      deviceId: deviceId,
      noteCount: noteCount,
      attachmentCount: attachmentCount,
    );
  }
}

class _FailingBundleUploadTransport extends InMemoryGoogleDriveSyncTransport {
  _FailingBundleUploadTransport() : super(uploadDelay: Duration.zero);

  int attachmentUploadCalls = 0;
  int bundleUploadCalls = 0;

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) async {
    attachmentUploadCalls += 1;
    await super.uploadAttachmentObject(
      contentHash: contentHash,
      encodedPayload: encodedPayload,
      type: type,
      label: label,
      sizeBytes: sizeBytes,
      skipExistingCheck: skipExistingCheck,
    );
  }

  @override
  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  }) async {
    bundleUploadCalls += 1;
    throw StateError('simulated bundle upload failure');
  }
}
