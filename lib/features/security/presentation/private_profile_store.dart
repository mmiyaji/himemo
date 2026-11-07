part of '../../home/presentation/home_providers.dart';

class PrivateMemoProfileStore {
  PrivateMemoProfileStore({
    required this._secureStore,
    required this._encryptionService,
    required this._profileDataKeyService,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.listStorageKey = 'security.private_profiles.list.v1',
    this.verifierStoragePrefix = 'security.private_profile.verifier.',
  }) : _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final ProfileDataKeyService _profileDataKeyService;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String listStorageKey;
  final String verifierStoragePrefix;

  static const minimumPasswordLength = 10;

  String? _passwordValidationError(String password) {
    if (password.runes.length < minimumPasswordLength) {
      return 'Use at least $minimumPasswordLength characters for a private profile password.';
    }
    return null;
  }

  Future<List<PrivateMemoProfile>> listProfiles() async {
    final prefs = await _sharedPreferencesProvider();
    final payload = prefs.getString(listStorageKey);
    if (payload == null || payload.isEmpty) {
      return const <PrivateMemoProfile>[];
    }
    try {
      final decoded = (jsonDecode(payload) as List)
          .cast<Map>()
          .map(
            (entry) => PrivateMemoProfile.fromJson(
              Map<String, dynamic>.from(entry.cast<String, dynamic>()),
            ),
          )
          .toList(growable: false);
      return decoded;
    } catch (_) {
      return const <PrivateMemoProfile>[];
    }
  }

  Future<bool> hasProfiles() async => (await listProfiles()).isNotEmpty;

  Future<Map<String, dynamic>> exportSyncPayload() async {
    final profiles = await listProfiles();
    final verifiers = <Map<String, dynamic>>[];
    for (final profile in profiles) {
      final stored = await _secureStore.read(
        '$verifierStoragePrefix${profile.id}',
      );
      if (stored == null || stored.isEmpty) {
        continue;
      }
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(stored) as Map);
        if (decoded['salt'] is String && decoded['verifier'] is String) {
          verifiers.add(<String, dynamic>{'profileId': profile.id, ...decoded});
        }
      } catch (_) {
        // Malformed optional verifier metadata is skipped during profile export.
      }
    }
    final dataKeys = await _profileDataKeyService.exportWrappedProfileKeys(
      profiles.map((profile) => profile.vaultId),
    );
    return <String, dynamic>{
      'version': 1,
      'profiles': [for (final profile in profiles) profile.toJson()],
      'verifiers': verifiers,
      'dataKeys': dataKeys,
    };
  }

  Future<int> importSyncPayload(Object? payload) async {
    if (payload is! Map) {
      return 0;
    }
    final decoded = Map<String, dynamic>.from(payload);
    if (decoded['version'] != 1) {
      return 0;
    }

    var imported = 0;
    final existing = await listProfiles();
    final profilesById = <String, PrivateMemoProfile>{
      for (final profile in existing) profile.id: profile,
    };
    for (final rawProfile
        in (decoded['profiles'] as List<dynamic>? ?? const <dynamic>[])) {
      if (rawProfile is! Map) {
        continue;
      }
      try {
        final profile = PrivateMemoProfile.fromJson(
          Map<String, dynamic>.from(rawProfile),
        );
        profilesById[profile.id] = profile;
        imported += 1;
      } catch (_) {
        // Invalid imported profile entries are skipped; valid entries continue.
      }
    }
    if (imported > 0) {
      final profiles = profilesById.values.toList(growable: false)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _saveProfiles(profiles);
    }

    for (final rawVerifier
        in (decoded['verifiers'] as List<dynamic>? ?? const <dynamic>[])) {
      if (rawVerifier is! Map) {
        continue;
      }
      final verifier = Map<String, dynamic>.from(rawVerifier);
      final profileId = verifier['profileId'] as String?;
      final salt = verifier['salt'];
      final secretVerifier = verifier['verifier'];
      if (profileId == null ||
          !profilesById.containsKey(profileId) ||
          salt is! String ||
          salt.isEmpty ||
          secretVerifier is! String ||
          secretVerifier.isEmpty) {
        continue;
      }
      await _secureStore.write(
        '$verifierStoragePrefix$profileId',
        jsonEncode({'salt': salt, 'verifier': secretVerifier}),
      );
      imported += 1;
    }

    imported += await _profileDataKeyService.importWrappedProfileKeys(
      decoded['dataKeys'] as List<dynamic>? ?? const <dynamic>[],
      overwrite: true,
    );
    return imported;
  }

  Future<String?> addProfile({
    required String name,
    required String password,
  }) async {
    final validationError = _passwordValidationError(password);
    if (validationError != null) {
      return validationError;
    }
    final existing = await listProfiles();
    for (final profile in existing) {
      final duplicate = await _profileDataKeyService.verifyProfilePassword(
        vaultId: profile.vaultId,
        password: password,
      );
      if (duplicate) {
        return 'That password already unlocks another profile.';
      }
    }
    final profile = PrivateMemoProfile(
      id: _createProfileId(),
      name: name.trim().isEmpty
          ? _nextDefaultName(existing.length + 1)
          : name.trim(),
      createdAt: DateTime.now(),
    );
    final salt = _encryptionService.generateSalt();
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: password,
      salt: salt,
    );
    await _secureStore.write(
      '$verifierStoragePrefix${profile.id}',
      jsonEncode({'salt': base64Encode(salt), 'verifier': verifier}),
    );
    await _profileDataKeyService.configureProfile(
      vaultId: profile.vaultId,
      password: password,
    );
    await _saveProfiles([...existing, profile]);
    return null;
  }

  Future<UnlockProfileResult?> verifyAny(String password) async {
    final profiles = await listProfiles();
    final matches = <PrivateMemoProfile>[];
    for (final profile in profiles) {
      final unlocked = await _profileDataKeyService.unlockProfile(
        vaultId: profile.vaultId,
        password: password,
      );
      if (unlocked) {
        matches.add(profile);
      }
    }
    if (matches.isNotEmpty) {
      matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final profile = matches.first;
      for (final extraMatch in matches.skip(1)) {
        _profileDataKeyService.lockProfile(extraMatch.vaultId);
      }
      return UnlockProfileResult(
        vaultId: profile.vaultId,
        label: profile.name,
        isLegacy: false,
      );
    }
    return null;
  }

  Future<void> deleteProfile(String id) async {
    final existing = await listProfiles();
    await _saveProfiles(
      existing.where((profile) => profile.id != id).toList(growable: false),
    );
    await _secureStore.delete('$verifierStoragePrefix$id');
    await _profileDataKeyService.deleteProfileKey(
      '$customPrivateVaultPrefix$id',
    );
  }

  Future<void> renameProfile({required String id, required String name}) async {
    final nextName = name.trim();
    if (nextName.isEmpty) {
      return;
    }
    final existing = await listProfiles();
    final changed = existing.any(
      (profile) => profile.id == id && profile.name != nextName,
    );
    if (!changed) {
      return;
    }
    final renamed = [
      for (final profile in existing)
        if (profile.id == id) profile.copyWith(name: nextName) else profile,
    ];
    await _saveProfiles(renamed);
  }

  Future<String?> updateProfilePassword({
    required String id,
    required String password,
  }) async {
    final validationError = _passwordValidationError(password);
    if (validationError != null) {
      return validationError;
    }
    final profiles = await listProfiles();
    if (!profiles.any((profile) => profile.id == id)) {
      return 'Private profile was not found.';
    }
    final vaultId = '$customPrivateVaultPrefix$id';
    if (!_profileDataKeyService.isProfileUnlocked(vaultId)) {
      return 'Unlock this private profile before changing its password.';
    }
    for (final profile in profiles.where((profile) => profile.id != id)) {
      final duplicate = await _profileDataKeyService.verifyProfilePassword(
        vaultId: profile.vaultId,
        password: password,
      );
      if (duplicate) {
        return 'That password already unlocks another profile.';
      }
    }
    final salt = _encryptionService.generateSalt();
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: password,
      salt: salt,
    );
    final changed = await _profileDataKeyService.changeProfilePassword(
      vaultId: vaultId,
      newPassword: password,
    );
    if (!changed) {
      return 'The private profile password could not be changed.';
    }
    try {
      await _secureStore.write(
        '$verifierStoragePrefix$id',
        jsonEncode({'salt': base64Encode(salt), 'verifier': verifier}),
      );
    } catch (_) {
      // The wrapped data key is the authentication source of truth. Remove a
      // stale verifier rather than leaving the two records contradictory.
      await _secureStore.delete('$verifierStoragePrefix$id');
    }
    return null;
  }

  Future<void> _saveProfiles(List<PrivateMemoProfile> profiles) async {
    final prefs = await _sharedPreferencesProvider();
    await prefs.setString(
      listStorageKey,
      jsonEncode([for (final profile in profiles) profile.toJson()]),
    );
  }

  String _createProfileId() {
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'profile_$random';
  }

  String _nextDefaultName(int index) => 'Profile $index';
}
