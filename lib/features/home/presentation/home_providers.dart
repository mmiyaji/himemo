import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/home_repository.dart';
import '../domain/note_entry.dart';
import '../domain/vault_models.dart';

part 'home_providers.g.dart';

@Riverpod(keepAlive: true)
HomeRepository homeRepository(Ref ref) => SeededHomeRepository();

@Riverpod(keepAlive: true)
class ThemeModeController extends _$ThemeModeController {
  @override
  ThemeMode build() => ThemeMode.light;

  void setMode(ThemeMode mode) => state = mode;
}

@Riverpod(keepAlive: true)
class ActiveIdentity extends _$ActiveIdentity {
  @override
  String build() => 'daily';

  void switchTo(String identityId) => state = identityId;
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
  return ref
      .watch(vaultsProvider)
      .where((vault) => activeIdentity.visibleVaultIds.contains(vault.id))
      .toList(growable: false);
}

@riverpod
List<NoteEntry> visibleNotes(Ref ref) {
  final visibleIds = ref
      .watch(activeIdentityDataProvider)
      .visibleVaultIds
      .toSet();
  final notes = ref
      .watch(homeRepositoryProvider)
      .notes
      .where((note) => visibleIds.contains(note.vaultId))
      .toList(growable: false);
  notes.sort((left, right) => right.createdAt.compareTo(left.createdAt));
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
