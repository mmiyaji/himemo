import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/home_repository.dart';
import '../domain/note_entry.dart';
import '../domain/vault_models.dart';

part 'home_providers.g.dart';

enum AppColorTheme { blue, green, orange }

enum SyncProvider { off, iCloud, googleDrive }

enum AppLaunchSurface { splash, onboarding, ready }

@Riverpod(keepAlive: true)
HomeRepository homeRepository(Ref ref) => SeededHomeRepository();

final appLaunchControllerProvider =
    NotifierProvider<AppLaunchController, AppLaunchSurface>(
      AppLaunchController.new,
    );

class AppLaunchController extends Notifier<AppLaunchSurface> {
  static const _storageKey = 'app.onboarding_completed';
  bool _restored = false;

  @override
  AppLaunchSurface build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppLaunchSurface.splash;
  }

  Future<void> completeOnboarding() async {
    state = AppLaunchSurface.ready;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, true);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_storageKey) ?? false;
      state = completed ? AppLaunchSurface.ready : AppLaunchSurface.onboarding;
    } catch (_) {
      state = AppLaunchSurface.onboarding;
    }
  }
}

@Riverpod(keepAlive: true)
class ThemeModeController extends _$ThemeModeController {
  static const _storageKey = 'settings.theme_mode';
  bool _restored = false;

  @override
  ThemeMode build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return ThemeMode.light;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = ThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ThemeMode.light,
      );
    } catch (_) {}
  }
}

final appColorThemeControllerProvider =
    NotifierProvider<AppColorThemeController, AppColorTheme>(
      AppColorThemeController.new,
    );

class AppColorThemeController extends Notifier<AppColorTheme> {
  static const _storageKey = 'settings.color_theme';
  bool _restored = false;

  @override
  AppColorTheme build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppColorTheme.blue;
  }

  Future<void> setTheme(AppColorTheme theme) async {
    state = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, theme.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = AppColorTheme.values.firstWhere(
        (theme) => theme.name == stored,
        orElse: () => AppColorTheme.blue,
      );
    } catch (_) {}
  }
}

final appLockSettingsControllerProvider =
    NotifierProvider<AppLockSettingsController, bool>(
      AppLockSettingsController.new,
    );

class AppLockSettingsController extends Notifier<bool> {
  static const _storageKey = 'settings.app_lock_enabled';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, enabled);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? false;
    } catch (_) {}
  }
}

final syncProviderControllerProvider =
    NotifierProvider<SyncProviderController, SyncProvider>(
      SyncProviderController.new,
    );

class SyncProviderController extends Notifier<SyncProvider> {
  static const _storageKey = 'settings.sync_provider';
  bool _restored = false;

  @override
  SyncProvider build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return SyncProvider.off;
  }

  Future<void> setProvider(SyncProvider provider) async {
    state = provider;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, provider.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }
      state = SyncProvider.values.firstWhere(
        (provider) => provider.name == stored,
        orElse: () => SyncProvider.off,
      );
    } catch (_) {}
  }
}

final privateVaultSessionControllerProvider =
    NotifierProvider<PrivateVaultSessionController, bool>(
      PrivateVaultSessionController.new,
    );

class PrivateVaultSessionController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() => state = false;
}

final privateVaultSecretControllerProvider =
    NotifierProvider<PrivateVaultSecretController, bool>(
      PrivateVaultSecretController.new,
    );

class PrivateVaultSecretController extends Notifier<bool> {
  static const _saltKey = 'security.private_vault_salt';
  static const _digestKey = 'security.private_vault_digest';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> configure(String secret) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    final digest = _deriveDigest(secret, salt);
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_digestKey, digest);
    state = true;
    ref.read(privateVaultSessionControllerProvider.notifier).unlock();
  }

  Future<bool> verify(String secret) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salt = prefs.getString(_saltKey);
      final expected = prefs.getString(_digestKey);
      if (salt == null || expected == null) {
        return false;
      }
      final actual = _deriveDigest(secret, salt);
      final matched = actual == expected;
      if (matched) {
        ref.read(privateVaultSessionControllerProvider.notifier).unlock();
      }
      return matched;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_saltKey);
      await prefs.remove(_digestKey);
    } catch (_) {}
    state = false;
    ref.read(privateVaultSessionControllerProvider.notifier).lock();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getString(_saltKey) != null && prefs.getString(_digestKey) != null;
    } catch (_) {}
  }

  String _generateSalt() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64Encode(bytes);
  }

  String _deriveDigest(String secret, String salt) {
    List<int> bytes = utf8.encode('$salt:$secret');
    for (var i = 0; i < 120000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }
}

@Riverpod(keepAlive: true)
class ActiveIdentity extends _$ActiveIdentity {
  static const _storageKey = 'settings.active_identity';
  bool _restored = false;

  @override
  String build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return 'daily';
  }

  Future<void> switchTo(String identityId) async {
    state = identityId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, identityId);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null) {
        state = stored;
      }
    } catch (_) {}
  }
}

@Riverpod(keepAlive: true)
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

@Riverpod(keepAlive: true)
class NotesController extends _$NotesController {
  static const _storageKey = 'notes.entries.v1';
  bool _restored = false;

  @override
  List<NoteEntry> build() {
    final seeded = ref.read(homeRepositoryProvider).seededNotes;
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return List<NoteEntry>.from(seeded);
  }

  Future<void> upsert(NoteEntry note) async {
    final next = [...state];
    final index = next.indexWhere((entry) => entry.id == note.id);
    if (index == -1) {
      next.add(note);
    } else {
      next[index] = note;
    }
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> delete(String noteId) async {
    state = state.where((note) => note.id != noteId).toList(growable: false);
    await _persist();
  }

  Future<void> seedIfEmpty() async {
    if (state.isNotEmpty) {
      return;
    }
    state = List<NoteEntry>.from(ref.read(homeRepositoryProvider).seededNotes);
    _sort(state);
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        final seeded =
            List<NoteEntry>.from(ref.read(homeRepositoryProvider).seededNotes);
        _sort(seeded);
        state = seeded;
        return;
      }

      final decoded = (jsonDecode(stored) as List<dynamic>)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .map(NoteEntry.fromJson)
          .toList(growable: false);
      final restored = [...decoded];
      _sort(restored);
      state = restored;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(state.map((note) => note.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  void _sort(List<NoteEntry> notes) {
    notes.sort((left, right) {
      if (left.isPinned != right.isPinned) {
        return right.isPinned ? 1 : -1;
      }
      return right.createdAt.compareTo(left.createdAt);
    });
  }
}

@riverpod
List<VaultBucket> vaults(Ref ref) => ref.watch(homeRepositoryProvider).vaults;

@riverpod
List<UnlockIdentity> identities(Ref ref) =>
    ref.watch(homeRepositoryProvider).identities;

@riverpod
UnlockIdentity activeIdentityData(Ref ref) {
  final activeId = ref.watch(activeIdentityProvider);
  return ref
      .watch(identitiesProvider)
      .firstWhere((identity) => identity.id == activeId);
}

@riverpod
List<VaultBucket> visibleVaults(Ref ref) {
  final activeIdentity = ref.watch(activeIdentityDataProvider);
  final privateVaultUnlocked = ref.watch(privateVaultSessionControllerProvider);
  return ref
      .watch(vaultsProvider)
      .where((vault) => activeIdentity.visibleVaultIds.contains(vault.id))
      .where((vault) => vault.id != 'private' || privateVaultUnlocked)
      .toList(growable: false);
}

@riverpod
List<NoteEntry> visibleNotes(Ref ref) {
  final visibleIds = ref.watch(visibleVaultsProvider).map((vault) => vault.id).toSet();
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final notes = ref
      .watch(notesControllerProvider)
      .where((note) => visibleIds.contains(note.vaultId))
      .where((note) {
        if (query.isEmpty) {
          return true;
        }
        final haystacks = [
          note.title,
          note.body,
          ...note.attachments.map((attachment) => attachment.label),
        ];
        return haystacks.any((value) => value.toLowerCase().contains(query));
      })
      .toList(growable: false);
  return notes;
}

@riverpod
List<NoteEntry> notesForVault(Ref ref, String vaultId) {
  return ref
      .watch(visibleNotesProvider)
      .where((note) => note.vaultId == vaultId)
      .toList(growable: false);
}

@riverpod
VaultBucket vaultById(Ref ref, String vaultId) {
  return ref.watch(vaultsProvider).firstWhere((vault) => vault.id == vaultId);
}

@riverpod
NoteEntry? noteById(Ref ref, String noteId) {
  for (final note in ref.watch(visibleNotesProvider)) {
    if (note.id == noteId) {
      return note;
    }
  }
  return null;
}
