import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/audit_log.dart';
import 'package:himemo/app/diagnostic_log.dart';
import 'package:himemo/app/firebase_observability.dart';
import 'package:himemo/app/in_app_update_service.dart';
import 'package:himemo/app/network_connection.dart';
import 'package:himemo/app/play_integrity_service.dart';
import 'package:himemo/features/home/domain/note_tags.dart';
import 'package:himemo/features/home/presentation/media_duration_io.dart';
import 'package:himemo/features/home/presentation/video_player_controller_factory_io.dart';
import 'package:himemo/features/home/presentation/video_thumbnail_generator_io.dart';
import 'package:himemo/features/home/presentation/web_video_element_view_stub.dart';
import 'package:himemo/features/home/presentation/web_video_object_url_stub.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/private_vault_secret_store.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/security/data/web_attachment_payload_store_stub.dart';
import 'package:himemo/features/sync/data/sync_bundle_key_service.dart';
import 'package:himemo/features/sync/presentation/src/google_sign_in_web_button_stub.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('small coverage gaps', () {
    test(
      'note tag normalization trims hashes, whitespace, empties, and dupes',
      () {
        expect(normalizeNoteTag('  ### Home   Office  '), 'Home Office');
        expect(canonicalizeNoteTag('  #MiXeD  Case '), 'mixed case');
        expect(
          dedupeNoteTags([' ', '###', '#Home', 'home', 'Work', ' work ']),
          ['Home', 'Work'],
        );
      },
    );

    test('memory and web attachment stores expose no-op behavior', () async {
      final secureStore = MemorySecureKeyValueStore();
      await secureStore.write('key', 'value');
      expect(await secureStore.read('key'), 'value');
      await secureStore.delete('key');
      expect(await secureStore.read('key'), isNull);

      const webStore = WebAttachmentPayloadStore();
      await webStore.put('id', 'payload');
      expect(await webStore.get('id'), isNull);
      await webStore.delete('id');
    });

    test(
      'media helpers handle empty local inputs without plugin calls',
      () async {
        expect(await probeAudioDurationMs(''), isNull);
        expect(await probeVideoDurationMs(''), isNull);
        expect(await generateVideoThumbnailBytes(XFile('')), isNull);
      },
    );

    test('local video controller factory creates a controller', () async {
      final controller = createLocalVideoController('__missing_video__.mp4');
      expect(controller.dataSource, contains('__missing_video__.mp4'));
      await controller.dispose();
    });

    testWidgets('web video and Google sign-in stubs render inert widgets', (
      tester,
    ) async {
      final video = buildWebVideoElementView(
        viewType: 'video-view',
        objectUrl: 'blob:video',
        autoplay: true,
        muted: false,
        fillAvailableHeight: true,
      );
      await tester.pumpWidget(MaterialApp(home: video));
      expect(find.byType(SizedBox), findsOneWidget);

      updateWebVideoElementMuted('video-view', true);
      expect(
        createWebVideoObjectUrl(Uint8List.fromList([1, 2, 3]), 'video/mp4'),
        isNull,
      );
      revokeWebVideoObjectUrl('blob:video');

      await tester.pumpWidget(
        MaterialApp(home: buildGoogleSignInWebButton(locale: 'ja')),
      );
      expect(find.byType(SizedBox), findsOneWidget);
    });
  });

  group('log services', () {
    test(
      'diagnostic log gates normal records and persists forced records',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = DiagnosticLogService.instance;

        expect(await service.isEnabled(), isFalse);
        await service.record('sync', 'ignored while disabled');
        expect(await service.entries(), isEmpty);

        await service.record(
          'sync',
          'forced record',
          data: {'path': 'a b', 'skip': null, 'line': 'x\ny'},
          force: true,
        );
        var entries = await service.entries();
        expect(entries, hasLength(1));
        expect(entries.single, contains('[sync] forced record'));
        expect(entries.single, contains('path=a_b'));
        expect(entries.single, contains('line=x_y'));
        expect(entries.single, isNot(contains('skip=')));

        expect(await service.toggleEnabled(), isTrue);
        expect(await service.isEnabled(), isTrue);
        await service.record('sync', 'enabled record');
        entries = await service.entries();
        expect(entries.last, contains('[sync] enabled record'));

        final exported = await service.exportText();
        expect(exported, contains('HiMemo diagnostic log'));
        expect(exported, contains('enabled=true'));

        await service.clear();
        expect((await service.entries()).single, contains('log cleared'));
        await service.setEnabled(false);
        expect(await service.isEnabled(), isFalse);
      },
    );

    test(
      'audit log records sanitized values and exports immutable entries',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = AuditLogService.instance;

        await service.record(
          'sync.upload',
          data: {'note': 'a b', 'skip': null, 'line': 'x\ny'},
        );
        final entries = await service.entries();
        expect(entries, isNotEmpty);
        expect(entries.last, contains('[audit] sync.upload'));
        expect(entries.last, contains('note=a_b'));
        expect(entries.last, contains('line=x_y'));
        expect(entries.last, isNot(contains('skip=')));
        expect(() => entries.add('mutate'), throwsUnsupportedError);

        final exported = await service.exportText();
        expect(exported, contains('HiMemo audit log'));
        expect(exported, contains('sync.upload'));
      },
    );
  });

  group('PrivateVaultSecretStore edge paths', () {
    test('reports missing secrets and verifies configured secrets', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrivateVaultSecretStore(
        secureStore: MemorySecureKeyValueStore(),
        encryptionService: EncryptionService(random: Random(101)),
      );

      expect(await store.hasSecret(), isFalse);
      expect(await store.verify('missing'), isFalse);

      await store.configure('profile-pass');
      expect(await store.hasSecret(), isTrue);
      expect(await store.verify('profile-pass'), isTrue);
      expect(await store.verify('wrong-pass'), isFalse);

      await store.clear();
      expect(await store.hasSecret(), isFalse);
    });

    test('migrates legacy verifier values into secure storage', () async {
      final encryptionService = EncryptionService(random: Random(102));
      final salt = encryptionService.generateSalt();
      final verifier = await encryptionService.deriveSecretVerifier(
        secret: 'legacy-pass',
        salt: salt,
      );
      SharedPreferences.setMockInitialValues({
        'security.private_vault_salt': base64Encode(salt),
        'security.private_vault_digest': verifier,
      });
      final secureStore = MemorySecureKeyValueStore();
      final store = PrivateVaultSecretStore(
        secureStore: secureStore,
        encryptionService: encryptionService,
      );

      expect(await store.hasSecret(), isTrue);
      expect(
        await secureStore.read('security.private_vault.verifier.v1'),
        isNotNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('security.private_vault_salt'), isNull);
      expect(prefs.getString('security.private_vault_digest'), isNull);
      expect(await store.verify('legacy-pass'), isTrue);
    });

    test('ignores incomplete legacy verifier pairs', () async {
      SharedPreferences.setMockInitialValues({
        'security.private_vault_salt': base64Encode(List<int>.filled(16, 1)),
      });
      final secureStore = MemorySecureKeyValueStore();
      final store = PrivateVaultSecretStore(
        secureStore: secureStore,
        encryptionService: EncryptionService(random: Random(103)),
      );

      expect(await store.hasSecret(), isFalse);
      expect(
        await secureStore.read('security.private_vault.verifier.v1'),
        isNull,
      );
    });
  });

  group('NetworkConnectionService', () {
    const channel = MethodChannel('org.ruhenheim.himemo/network');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps native connection kinds and unknown values', () async {
      SharedPreferences.setMockInitialValues({});
      final responses = ['wifi', 'satellite'];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'currentConnectionKind');
            return responses.removeAt(0);
          });

      const service = NetworkConnectionService();
      expect(await service.currentKind(), NetworkConnectionKind.wifi);
      expect(await service.currentKind(), NetworkConnectionKind.unknown);
    });

    test('returns unknown when the native channel fails', () async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'offline');
          });

      expect(
        await const NetworkConnectionService().currentKind(),
        NetworkConnectionKind.unknown,
      );
    });
  });

  group('PlayIntegrityService', () {
    const channel = MethodChannel('org.ruhenheim.himemo/integrity');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reports unsupported status off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final status = await const PlayIntegrityService().checkAvailability();
      expect(status.isAvailable, isFalse);
      expect(status.message, contains('only available on Android'));
      await expectLater(
        const PlayIntegrityService().requestClassicToken(requestHash: 'hash'),
        throwsStateError,
      );
    });

    test('reads Android availability and requests trimmed tokens', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'checkAvailability':
                return {
                  'available': true,
                  'message': 'ready',
                  'installerPackage': 'com.android.vending',
                  'projectNumber': '123',
                };
              case 'requestToken':
                expect(call.arguments, {'requestHash': 'abc'});
                return 'token';
            }
            fail('Unexpected method ${call.method}');
          });

      final service = const PlayIntegrityService();
      final status = await service.checkAvailability();
      expect(status.isAvailable, isTrue);
      expect(status.message, 'ready');
      expect(status.installerPackage, 'com.android.vending');
      expect(status.projectNumber, '123');
      expect(await service.requestClassicToken(requestHash: ' abc '), 'token');
    });

    test('handles Android availability and token errors', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'checkAvailability') {
              throw PlatformException(code: 'failed', message: 'native error');
            }
            return '';
          });

      final service = const PlayIntegrityService();
      final status = await service.checkAvailability();
      expect(status.isAvailable, isFalse);
      expect(status.message, contains('native error'));
      expect(
        () => service.requestClassicToken(requestHash: '  '),
        throwsArgumentError,
      );
      await expectLater(
        service.requestClassicToken(requestHash: 'abc'),
        throwsStateError,
      );
    });
  });

  group('unsupported platform service paths', () {
    test('in-app update methods are no-ops off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const service = InAppUpdateService();

      final status = await service.checkForUpdate();
      expect(status.isSupported, isFalse);
      expect(status.updateAvailable, isFalse);
      expect(status.message, contains('only available on Android'));

      await service.performFlexibleUpdate();
      await service.performImmediateUpdate();
      await service.completeFlexibleUpdate();
    });

    test(
      'firebase observability wrappers call the action when unsupported',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;

        await configureFirebaseObservability(enableCollection: true);
        await recordNonFatalError(
          StateError('nonfatal'),
          StackTrace.current,
          reason: 'test',
          information: ['info'],
        );
        await logFirebaseBreadcrumb('breadcrumb');

        expect(await runFirebaseTrace('success', () async => 7), 7);
        await expectLater(
          runFirebaseTrace<void>('failure', () async {
            throw StateError('trace failed');
          }),
          throwsStateError,
        );
      },
    );
  });

  group('SyncBundleKeyService edge paths', () {
    test('imports fallback secure store values without cloud escrow', () async {
      final fallbackStore = MemorySecureKeyValueStore();
      final bytes = List<int>.generate(32, (index) => index + 11);
      await fallbackStore.write('sync-key', base64Encode(bytes));
      final cloudStore = _MemoryCloudSyncBundleKeyStore();
      final service = SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        fallbackStore: fallbackStore,
        cloudStore: cloudStore,
        keyFactory: () => List<int>.filled(32, 1),
        storageKey: 'sync-key',
      );

      expect(
        await service.fingerprint(),
        sha256.convert(bytes).toString().substring(0, 12),
      );
      expect(cloudStore.backupCode, isNull);
    });

    test('continues when legacy cloud read fails', () async {
      final secureStore = MemorySecureKeyValueStore();
      final bytes = List<int>.generate(32, (index) => index + 21);
      await secureStore.write('sync-key', base64Encode(bytes));
      final service = SyncBundleKeyService(
        secureStore: secureStore,
        cloudStore: _ThrowingCloudSyncBundleKeyStore(),
        keyFactory: () => List<int>.filled(32, 2),
        storageKey: 'sync-key',
      );

      expect(await service.requireExisting(), isNotNull);
      expect(
        await service.fingerprint(),
        sha256.convert(bytes).toString().substring(0, 12),
      );
    });

    test('rejects short backup codes', () {
      final service = SyncBundleKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: () => List<int>.filled(32, 3),
      );
      final shortCode =
          '${SyncBundleKeyService.backupCodePrefix}${base64Encode([1, 2, 3])}';

      expect(
        () => service.previewBackupCodeFingerprint(shortCode),
        throwsFormatException,
      );
    });
  });
}

class _MemoryCloudSyncBundleKeyStore implements CloudSyncBundleKeyStore {
  String? backupCode;

  @override
  Future<String?> readBackupCode() async => backupCode;
}

class _ThrowingCloudSyncBundleKeyStore implements CloudSyncBundleKeyStore {
  @override
  Future<String?> readBackupCode() async {
    throw StateError('cloud unavailable');
  }
}
