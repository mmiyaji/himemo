import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/profile_data_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('encrypted note editor drafts', () {
    test('normal drafts are not stored as plaintext', () async {
      final fixture = _DraftStoreFixture();
      final draft = _draft(vaultId: 'everyday', content: 'normal secret text');

      await fixture.store.save(draft);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('notes.editor_draft.v1');
      expect(stored, isNotNull);
      expect(stored, isNot(contains('normal secret text')));
      expect((await fixture.store.load())?.quickContent, 'normal secret text');
    });

    test(
      'private drafts stay hidden until their profile is unlocked',
      () async {
        final fixture = _DraftStoreFixture();
        const vaultId = 'private_profile:alpha';
        await fixture.profileKeys.configureProfile(
          vaultId: vaultId,
          password: 'private-passphrase',
        );
        await fixture.store.save(
          _draft(vaultId: vaultId, content: 'private draft content'),
        );

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('notes.editor_draft.v1'),
          isNot(contains('private draft content')),
        );

        fixture.profileKeys.lockProfile(vaultId);
        expect(await fixture.store.load(), isNull);

        expect(
          await fixture.profileKeys.unlockProfile(
            vaultId: vaultId,
            password: 'private-passphrase',
          ),
          isTrue,
        );
        expect(
          (await fixture.store.load())?.quickContent,
          'private draft content',
        );
      },
    );

    test('legacy plaintext private drafts are sealed before unlock', () async {
      const vaultId = 'private_profile:legacy';
      final legacy = _draft(vaultId: vaultId, content: 'legacy private draft');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'notes.editor_draft.v1': jsonEncode(legacy.toJson()),
      });
      final fixture = _DraftStoreFixture();
      await fixture.profileKeys.configureProfile(
        vaultId: vaultId,
        password: 'legacy-passphrase',
      );
      fixture.profileKeys.lockProfile(vaultId);

      expect(await fixture.store.load(), isNull);
      final prefs = await SharedPreferences.getInstance();
      final sealed = prefs.getString('notes.editor_draft.v1');
      expect(sealed, isNotNull);
      expect(sealed, isNot(contains('legacy private draft')));
      expect(jsonDecode(sealed!)['keyScope'], 'deviceMigration');

      expect(
        await fixture.profileKeys.unlockProfile(
          vaultId: vaultId,
          password: 'legacy-passphrase',
        ),
        isTrue,
      );
      expect(
        (await fixture.store.load())?.quickContent,
        'legacy private draft',
      );
      expect(
        jsonDecode(prefs.getString('notes.editor_draft.v1')!)['keyScope'],
        'profile',
      );
    });
  });

  group('private profile password updates', () {
    test('rejects weak and duplicate passwords', () async {
      final fixture = _ProfileStoreFixture();
      expect(
        await fixture.store.addProfile(name: 'Weak', password: 'short'),
        contains('10'),
      );
      expect(
        await fixture.store.addProfile(
          name: 'Alpha',
          password: 'alpha-passphrase',
        ),
        isNull,
      );
      expect(
        await fixture.store.addProfile(
          name: 'Beta',
          password: 'beta-passphrase',
        ),
        isNull,
      );
      final alpha = (await fixture.store.listProfiles()).singleWhere(
        (profile) => profile.name == 'Alpha',
      );
      fixture.profileKeys.lockProfile(alpha.vaultId);
      expect(
        await fixture.store.addProfile(
          name: 'Duplicate',
          password: 'alpha-passphrase',
        ),
        contains('another profile'),
      );
      expect(fixture.profileKeys.isProfileUnlocked(alpha.vaultId), isFalse);
      final beta = (await fixture.store.listProfiles()).singleWhere(
        (profile) => profile.name == 'Beta',
      );

      expect(
        await fixture.store.updateProfilePassword(
          id: beta.id,
          password: 'alpha-passphrase',
        ),
        contains('another profile'),
      );
    });

    test('wrapped key remains unlockable when verifier update fails', () async {
      final secureStore = _ToggleFailSecureStore();
      final fixture = _ProfileStoreFixture(secureStore: secureStore);
      expect(
        await fixture.store.addProfile(
          name: 'Alpha',
          password: 'original-passphrase',
        ),
        isNull,
      );
      final profile = (await fixture.store.listProfiles()).single;
      secureStore.failVerifierWrites = true;

      expect(
        await fixture.store.updateProfilePassword(
          id: profile.id,
          password: 'replacement-passphrase',
        ),
        isNull,
      );
      fixture.profileKeys.lockProfile(profile.vaultId);

      expect(
        await fixture.store.verifyAny('replacement-passphrase'),
        isNotNull,
      );
      fixture.profileKeys.lockProfile(profile.vaultId);
      expect(await fixture.store.verifyAny('original-passphrase'), isNull);
    });
  });
}

NoteEditorDraftSnapshot _draft({
  required String vaultId,
  required String content,
}) {
  return NoteEditorDraftSnapshot(
    createdAt: DateTime.utc(2026, 7, 10),
    isPinned: false,
    editorMode: NoteEditorMode.quick,
    vaultId: vaultId,
    tags: const <String>[],
    quickContent: content,
    quickAttachments: const <NoteAttachment>[],
    richBlocks: const <NoteBlock>[],
  );
}

class _DraftStoreFixture {
  _DraftStoreFixture()
    : secureStore = MemorySecureKeyValueStore(),
      encryption = EncryptionService() {
    masterKey = MasterKeyService(
      secureStore: secureStore,
      keyFactory: encryption.generateKeyBytes,
    );
    profileKeys = ProfileDataKeyService(
      secureStore: secureStore,
      encryptionService: encryption,
      normalMasterKeyService: masterKey,
    );
    store = NoteEditorDraftStore(
      encryptionService: encryption,
      masterKeyService: masterKey,
      profileDataKeyService: profileKeys,
    );
  }

  final MemorySecureKeyValueStore secureStore;
  final EncryptionService encryption;
  late final MasterKeyService masterKey;
  late final ProfileDataKeyService profileKeys;
  late final NoteEditorDraftStore store;
}

class _ProfileStoreFixture {
  _ProfileStoreFixture({_ToggleFailSecureStore? secureStore})
    : secureStore = secureStore ?? _ToggleFailSecureStore(),
      encryption = EncryptionService() {
    masterKey = MasterKeyService(
      secureStore: this.secureStore,
      keyFactory: encryption.generateKeyBytes,
    );
    profileKeys = ProfileDataKeyService(
      secureStore: this.secureStore,
      encryptionService: encryption,
      normalMasterKeyService: masterKey,
    );
    store = PrivateMemoProfileStore(
      secureStore: this.secureStore,
      encryptionService: encryption,
      profileDataKeyService: profileKeys,
    );
  }

  final _ToggleFailSecureStore secureStore;
  final EncryptionService encryption;
  late final MasterKeyService masterKey;
  late final ProfileDataKeyService profileKeys;
  late final PrivateMemoProfileStore store;
}

class _ToggleFailSecureStore implements SecureKeyValueStore {
  final Map<String, String> _values = <String, String>{};
  bool failVerifierWrites = false;

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failVerifierWrites &&
        key.startsWith('security.private_profile.verifier.')) {
      throw StateError('simulated verifier write failure');
    }
    _values[key] = value;
  }
}
