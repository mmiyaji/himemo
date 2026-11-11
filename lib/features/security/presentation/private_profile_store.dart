part of '../../home/presentation/home_providers.dart';

class PrivateMemoProfileStore {
  PrivateMemoProfileStore({
    required this._secureStore,
    required this._encryptionService,
    required this._profileDataKeyService,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    DeviceIdentityStore? deviceIdentityStore,
    this.listStorageKey = 'security.private_profiles.list.v1',
    this.verifierStoragePrefix = 'security.private_profile.verifier.',
  }) : _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance,
       _deviceIdentityStore =
           deviceIdentityStore ??
           DeviceIdentityStore(
             sharedPreferencesProvider: sharedPreferencesProvider,
           );

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final ProfileDataKeyService _profileDataKeyService;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final DeviceIdentityStore _deviceIdentityStore;
  final String listStorageKey;
  final String verifierStoragePrefix;

  static const minimumPasswordLength = 10;
  static const minimumPinLength = 4;
  static final _pinDigits = RegExp(r'^[0-9]+$');

  static bool isValidPin(String value) =>
      value.length >= minimumPinLength && _pinDigits.hasMatch(value);

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

  Future<Map<String, dynamic>> exportSyncPayload({
    List<PrivateMemoProfile>? snapshot,
    bool namesOnly = false,
  }) async {
    final profiles = snapshot ?? await listProfiles();
    if (namesOnly) {
      return {
        'version': 1,
        'namesOnly': true,
        'profiles': [
          for (final profile in profiles)
            if (profile.nameSync.sendableId != null)
              profile.toJson(includePending: false),
        ],
      };
    }
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
      'profiles': [
        for (final profile in profiles) profile.toJson(includePending: false),
      ],
      'verifiers': verifiers,
      'dataKeys': dataKeys,
    };
  }

  Future<int> importSyncPayload(Object? payload) =>
      _serializeProfiles(() => _importSyncPayload(payload));

  Future<Map<String, int>> pendingCredentialRevisions(
    List<PrivateMemoProfile> profiles,
  ) => _profileDataKeyService.pendingCredentialRevisions(
    profiles.map((profile) => profile.vaultId),
  );

  Future<void> acknowledgeCredentialRevisions(Map<String, int> revisions) =>
      _serializeProfiles(
        () => _profileDataKeyService.acknowledgeCredentialRevisions(revisions),
      );

  Future<int> _importSyncPayload(Object? payload) async {
    if (payload is! Map) {
      return 0;
    }
    final decoded = Map<String, dynamic>.from(payload);
    if (decoded['version'] != 1) {
      return 0;
    }

    var imported = 0;
    final existing = await listProfiles();
    final existingIds = existing.map((profile) => profile.id).toSet();
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
        final local = profilesById[profile.id];
        final merged = (local?.nameSync ?? const ProfileNameSync()).merge(
          profile.nameSync,
        );
        if (decoded['namesOnly'] == true && profile.nameSync.heads.isEmpty) {
          continue;
        }
        final keepLocalName =
            local != null &&
            merged.hasConflict &&
            merged.heads.any((head) => head.name == local.name);
        profilesById[profile.id] = (local ?? profile).copyWith(
          name: keepLocalName
              ? local.name
              : merged.preferredName ?? profile.name,
          nameSync: merged,
        );
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

    if (decoded['namesOnly'] == true) return imported;

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
          existingIds.contains(profileId) ||
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
      requireNewerCredential: true,
    );
    return imported;
  }

  Future<String?> addProfile({
    required String name,
    required String password,
    bool usePin = false,
    String? recoveryPassword,
  }) async {
    final validationError = usePin
        ? (isValidPin(password)
              ? null
              : 'Use at least $minimumPinLength digits for a private profile PIN.')
        : _passwordValidationError(password);
    if (validationError != null) {
      return validationError;
    }
    final portablePassword = usePin ? recoveryPassword ?? '' : password;
    if (usePin &&
        (_profileDataKeyService.devicePinStore == null ||
            _passwordValidationError(portablePassword) != null ||
            RegExp(r'^\d+$').hasMatch(portablePassword.trim()))) {
      return 'A device PIN requires a recovery password of at least 10 characters that is not all digits.';
    }
    final existing = await listProfiles();
    for (final profile in existing) {
      final duplicate = await _profileDataKeyService.verifyProfilePassword(
        vaultId: profile.vaultId,
        password: portablePassword,
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
      secret: portablePassword,
      salt: salt,
    );
    await _secureStore.write(
      '$verifierStoragePrefix${profile.id}',
      jsonEncode({'salt': base64Encode(salt), 'verifier': verifier}),
    );
    await _profileDataKeyService.configureProfile(
      vaultId: profile.vaultId,
      password: portablePassword,
      queueCredentialSync: usePin,
    );
    if (usePin &&
        !await _profileDataKeyService.setDevicePin(
          vaultId: profile.vaultId,
          recoveryPassword: portablePassword,
          pin: password,
        )) {
      await _profileDataKeyService.deleteProfileKey(profile.vaultId);
      await _secureStore.delete('$verifierStoragePrefix${profile.id}');
      return 'The device PIN could not be saved.';
    }
    await _serializeProfiles(() async {
      await _saveProfiles([...await listProfiles(), profile]);
    });
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
      return UnlockProfileResult(
        vaultId: profile.vaultId,
        label: profile.name,
        isLegacy: false,
        additionalVaultIds: [
          for (final match in matches.skip(1)) match.vaultId,
        ],
      );
    }
    return null;
  }

  Future<void> deleteProfile(String id) => _serializeProfiles(() async {
    final existing = await listProfiles();
    await _saveProfiles(existing.where((profile) => profile.id != id).toList());
    await _secureStore.delete('$verifierStoragePrefix$id');
    await _profileDataKeyService.deleteProfileKey(
      '$customPrivateVaultPrefix$id',
    );
  });

  Future<bool> renameProfile({required String id, required String name}) =>
      _renameProfile(id: id, name: name);

  Future<bool> resolveNameConflict({
    required String id,
    required String name,
    required Set<String> expectedChangeIds,
  }) =>
      _renameProfile(id: id, name: name, expectedChangeIds: expectedChangeIds);

  Future<bool> _renameProfile({
    required String id,
    required String name,
    Set<String>? expectedChangeIds,
  }) => _serializeProfiles(() async {
    final nextName = name.trim();
    if (nextName.isEmpty) return false;
    final profiles = (await listProfiles()).toList();
    final index = profiles.indexWhere((profile) => profile.id == id);
    if (index == -1) return false;
    final profile = profiles[index];
    if (expectedChangeIds == null) {
      if (profile.name == nextName || profile.nameSync.hasConflict) {
        return false;
      }
    } else if (!profile.nameSync.hasConflict ||
        !setEquals(
          expectedChangeIds,
          profile.nameSync.heads.map((head) => head.id).toSet(),
        ) ||
        !profile.nameSync.heads.any((head) => head.name == nextName)) {
      return false;
    }
    final random = math.Random.secure();
    final changeId = base64UrlEncode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    profiles[index] = profile.copyWith(
      name: nextName,
      nameSync: profile.nameSync.rename(
        name: nextName,
        deviceId: await _deviceIdentityStore.obtain(),
        changeId: changeId,
      ),
    );
    await _saveProfiles(profiles);
    return true;
  });

  Future<void> acknowledgeNameChanges(Map<String, String> sentIds) =>
      _serializeProfiles(() async {
        final profiles = (await listProfiles()).toList();
        var changed = false;
        for (var i = 0; i < profiles.length; i++) {
          final profile = profiles[i];
          final id = sentIds[profile.id];
          if (id == null || id != profile.nameSync.pendingId) continue;
          profiles[i] = profile.copyWith(
            nameSync: profile.nameSync.acknowledge(id),
          );
          changed = true;
        }
        if (changed) await _saveProfiles(profiles);
      });

  Future<T> _serializeProfiles<T>(Future<T> Function() operation) =>
      StorageSerialExecutor.run(
        PreferencesKeyValueStore(),
        listStorageKey,
        operation,
      );

  Future<String?> updateProfilePassword({
    required String id,
    required String password,
  }) => _serializeProfiles(() async {
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
  });

  Future<void> _saveProfiles(List<PrivateMemoProfile> profiles) async {
    final prefs = await _sharedPreferencesProvider();
    if (!await prefs.setString(
      listStorageKey,
      jsonEncode([for (final profile in profiles) profile.toJson()]),
    )) {
      throw StateError('Could not save private profiles.');
    }
  }

  String _createProfileId() {
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'profile_$random';
  }

  String _nextDefaultName(int index) => 'Profile $index';
}
