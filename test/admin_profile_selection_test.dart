import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/l10n/app_localizations.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('admin entry lets the user choose which profile to unlock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'settings.locale': 'japanese',
      'security.private_profiles.list.v1': jsonEncode([
        PrivateMemoProfile(
          id: 'family',
          name: '家族',
          createdAt: DateTime.utc(2026, 1, 1),
        ).toJson(),
        PrivateMemoProfile(
          id: 'work',
          name: '仕事',
          createdAt: DateTime.utc(2026, 2, 2),
        ).toJson(),
      ]),
    });
    final secureStore = MemorySecureKeyValueStore();
    final encryption = EncryptionService();
    final master = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryption.generateKeyBytes,
    );
    final database = EncryptedNoteDatabase(executor: NativeDatabase.memory());
    final admin = _AdminWithMissingProfiles();
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(secureStore),
        encryptionServiceProvider.overrideWithValue(encryption),
        masterKeyServiceProvider.overrideWithValue(master),
        encryptedNoteDatabaseProvider.overrideWithValue(database),
        encryptedNoteStoreProvider.overrideWithValue(
          EncryptedNoteStore(
            encryptionService: encryption,
            masterKeyService: master,
            database: database,
            directoryProvider: () async => Directory.systemTemp,
          ),
        ),
        deviceAuthGatewayProvider.overrideWithValue(_DeviceAuth()),
        adminModeSessionControllerProvider.overrideWith(() => admin),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
    await tester.runAsync(() async {
      await container.read(notesControllerProvider.notifier).restoreCompleted;
      await container
          .read(privateMemoProfilesControllerProvider.notifier)
          .refresh();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('ja'),
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
    expect(find.text('家族'), findsNothing);
    expect(find.text('仕事'), findsNothing);
    await tester.ensureVisible(find.text('プライベートプロファイル'));
    await tester.tap(find.text('プライベートプロファイル'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(SettingsScreen.privateProfileAdminModeKey),
    );
    await tester.tap(find.byKey(SettingsScreen.privateProfileAdminModeKey));
    await tester.pumpAndSettle();
    expect(container.read(adminModeSessionControllerProvider), isTrue);
    expect(find.byType(AdminProfileUnlockDialog), findsNothing);
    expect(admin.requestedVault, isNull);
    final workRow = find.byKey(SettingsScreen.privateProfileOpenKey('work'));
    await tester.ensureVisible(workRow);
    await tester.tap(workRow);
    await tester.pumpAndSettle();
    final dialog = find.byType(AdminProfileUnlockDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('仕事')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('家族')),
      findsNothing,
    );
    expect(admin.requestedVault, isNull);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'work-password',
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();
    expect(admin.requestedVault, 'private_profile:work');
    expect(tester.takeException(), isNull);
  });
}

class _AdminWithMissingProfiles extends AdminModeSessionController {
  String? requestedVault;
  @override
  Future<List<String>> unlock() async {
    state = true;
    return ['private_profile:family', 'private_profile:work'];
  }

  @override
  Future<bool> unlockProfile(String vaultId, String password) async {
    requestedVault = vaultId;
    return false;
  }
}

class _DeviceAuth implements DeviceAuthGateway {
  @override
  Future<DeviceAuthState> checkAvailability() async => const DeviceAuthState(
    availability: DeviceAuthAvailability.available,
    methods: ['Face ID'],
  );

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async => true;
}
