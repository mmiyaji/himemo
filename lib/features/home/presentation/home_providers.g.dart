// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(homeRepository)
final homeRepositoryProvider = HomeRepositoryProvider._();

final class HomeRepositoryProvider
    extends $FunctionalProvider<HomeRepository, HomeRepository, HomeRepository>
    with $Provider<HomeRepository> {
  HomeRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeRepositoryHash();

  @$internal
  @override
  $ProviderElement<HomeRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HomeRepository create(Ref ref) {
    return homeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomeRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomeRepository>(value),
    );
  }
}

String _$homeRepositoryHash() => r'a443190873d652b92d1acbe931b3f6fbfc1bb26e';

@ProviderFor(ThemeModeController)
final themeModeControllerProvider = ThemeModeControllerProvider._();

final class ThemeModeControllerProvider
    extends $NotifierProvider<ThemeModeController, ThemeMode> {
  ThemeModeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeControllerHash();

  @$internal
  @override
  ThemeModeController create() => ThemeModeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeControllerHash() =>
    r'edde557ac82fa3bdcba52e8465098fd74e3422cc';

abstract class _$ThemeModeController extends $Notifier<ThemeMode> {
  ThemeMode build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ThemeMode, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeMode, ThemeMode>,
              ThemeMode,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(ActiveIdentity)
final activeIdentityProvider = ActiveIdentityProvider._();

final class ActiveIdentityProvider
    extends $NotifierProvider<ActiveIdentity, String> {
  ActiveIdentityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeIdentityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeIdentityHash();

  @$internal
  @override
  ActiveIdentity create() => ActiveIdentity();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$activeIdentityHash() => r'033c86b481da0b3bb2dc8c997b240e776e09d458';

abstract class _$ActiveIdentity extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SearchQuery)
final searchQueryProvider = SearchQueryProvider._();

final class SearchQueryProvider extends $NotifierProvider<SearchQuery, String> {
  SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchQueryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchQueryHash();

  @$internal
  @override
  SearchQuery create() => SearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$searchQueryHash() => r'0fa228511ddd8c322643e29f0040d15dd9c2b8d9';

abstract class _$SearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(NotesController)
final notesControllerProvider = NotesControllerProvider._();

final class NotesControllerProvider
    extends $NotifierProvider<NotesController, List<NoteEntry>> {
  NotesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notesControllerHash();

  @$internal
  @override
  NotesController create() => NotesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<NoteEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<NoteEntry>>(value),
    );
  }
}

String _$notesControllerHash() => r'40a9fd56507836957bc50611157f25c7926dcd51';

abstract class _$NotesController extends $Notifier<List<NoteEntry>> {
  List<NoteEntry> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<NoteEntry>, List<NoteEntry>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<NoteEntry>, List<NoteEntry>>,
              List<NoteEntry>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(vaults)
final vaultsProvider = VaultsProvider._();

final class VaultsProvider
    extends
        $FunctionalProvider<
          List<VaultBucket>,
          List<VaultBucket>,
          List<VaultBucket>
        >
    with $Provider<List<VaultBucket>> {
  VaultsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultsHash();

  @$internal
  @override
  $ProviderElement<List<VaultBucket>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<VaultBucket> create(Ref ref) {
    return vaults(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<VaultBucket> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<VaultBucket>>(value),
    );
  }
}

String _$vaultsHash() => r'230001206e8ca835a67e01f45163de191077b30d';

@ProviderFor(identities)
final identitiesProvider = IdentitiesProvider._();

final class IdentitiesProvider
    extends
        $FunctionalProvider<
          List<UnlockIdentity>,
          List<UnlockIdentity>,
          List<UnlockIdentity>
        >
    with $Provider<List<UnlockIdentity>> {
  IdentitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'identitiesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$identitiesHash();

  @$internal
  @override
  $ProviderElement<List<UnlockIdentity>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<UnlockIdentity> create(Ref ref) {
    return identities(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<UnlockIdentity> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<UnlockIdentity>>(value),
    );
  }
}

String _$identitiesHash() => r'5d86371f121dcfb5c969f4cff935030b12bff992';

@ProviderFor(activeIdentityData)
final activeIdentityDataProvider = ActiveIdentityDataProvider._();

final class ActiveIdentityDataProvider
    extends $FunctionalProvider<UnlockIdentity, UnlockIdentity, UnlockIdentity>
    with $Provider<UnlockIdentity> {
  ActiveIdentityDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeIdentityDataProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeIdentityDataHash();

  @$internal
  @override
  $ProviderElement<UnlockIdentity> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UnlockIdentity create(Ref ref) {
    return activeIdentityData(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UnlockIdentity value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UnlockIdentity>(value),
    );
  }
}

String _$activeIdentityDataHash() =>
    r'bd177454e377412629b757f84f3f4c8c7911dfbd';

@ProviderFor(visibleVaults)
final visibleVaultsProvider = VisibleVaultsProvider._();

final class VisibleVaultsProvider
    extends
        $FunctionalProvider<
          List<VaultBucket>,
          List<VaultBucket>,
          List<VaultBucket>
        >
    with $Provider<List<VaultBucket>> {
  VisibleVaultsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleVaultsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleVaultsHash();

  @$internal
  @override
  $ProviderElement<List<VaultBucket>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<VaultBucket> create(Ref ref) {
    return visibleVaults(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<VaultBucket> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<VaultBucket>>(value),
    );
  }
}

String _$visibleVaultsHash() => r'cd72d7281f498471af92dec611cea16c0ab92c3e';

@ProviderFor(visibleNotes)
final visibleNotesProvider = VisibleNotesProvider._();

final class VisibleNotesProvider
    extends
        $FunctionalProvider<List<NoteEntry>, List<NoteEntry>, List<NoteEntry>>
    with $Provider<List<NoteEntry>> {
  VisibleNotesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleNotesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleNotesHash();

  @$internal
  @override
  $ProviderElement<List<NoteEntry>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<NoteEntry> create(Ref ref) {
    return visibleNotes(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<NoteEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<NoteEntry>>(value),
    );
  }
}

String _$visibleNotesHash() => r'e481b17ae1fa985db1c943e972e240460965f188';

@ProviderFor(notesForVault)
final notesForVaultProvider = NotesForVaultFamily._();

final class NotesForVaultProvider
    extends
        $FunctionalProvider<List<NoteEntry>, List<NoteEntry>, List<NoteEntry>>
    with $Provider<List<NoteEntry>> {
  NotesForVaultProvider._({
    required NotesForVaultFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'notesForVaultProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$notesForVaultHash();

  @override
  String toString() {
    return r'notesForVaultProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<NoteEntry>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<NoteEntry> create(Ref ref) {
    final argument = this.argument as String;
    return notesForVault(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<NoteEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<NoteEntry>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NotesForVaultProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$notesForVaultHash() => r'b3c5b8a78d1cc28120f99f9469ffdc6c8870dfc6';

final class NotesForVaultFamily extends $Family
    with $FunctionalFamilyOverride<List<NoteEntry>, String> {
  NotesForVaultFamily._()
    : super(
        retry: null,
        name: r'notesForVaultProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NotesForVaultProvider call(String vaultId) =>
      NotesForVaultProvider._(argument: vaultId, from: this);

  @override
  String toString() => r'notesForVaultProvider';
}

@ProviderFor(selectedSyncAuthState)
final selectedSyncAuthStateProvider = SelectedSyncAuthStateProvider._();

final class SelectedSyncAuthStateProvider
    extends $FunctionalProvider<SyncAuthState, SyncAuthState, SyncAuthState>
    with $Provider<SyncAuthState> {
  SelectedSyncAuthStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedSyncAuthStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedSyncAuthStateHash();

  @$internal
  @override
  $ProviderElement<SyncAuthState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncAuthState create(Ref ref) {
    return selectedSyncAuthState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncAuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncAuthState>(value),
    );
  }
}

String _$selectedSyncAuthStateHash() =>
    r'35f5290140c6d298be03ec709cda2a043ed29d47';

@ProviderFor(vaultById)
final vaultByIdProvider = VaultByIdFamily._();

final class VaultByIdProvider
    extends $FunctionalProvider<VaultBucket, VaultBucket, VaultBucket>
    with $Provider<VaultBucket> {
  VaultByIdProvider._({
    required VaultByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'vaultByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$vaultByIdHash();

  @override
  String toString() {
    return r'vaultByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<VaultBucket> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultBucket create(Ref ref) {
    final argument = this.argument as String;
    return vaultById(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultBucket value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultBucket>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VaultByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$vaultByIdHash() => r'37f4ac8498a693dbf2bc3723b5a81d25ae5d3640';

final class VaultByIdFamily extends $Family
    with $FunctionalFamilyOverride<VaultBucket, String> {
  VaultByIdFamily._()
    : super(
        retry: null,
        name: r'vaultByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  VaultByIdProvider call(String vaultId) =>
      VaultByIdProvider._(argument: vaultId, from: this);

  @override
  String toString() => r'vaultByIdProvider';
}

@ProviderFor(noteById)
final noteByIdProvider = NoteByIdFamily._();

final class NoteByIdProvider
    extends $FunctionalProvider<NoteEntry?, NoteEntry?, NoteEntry?>
    with $Provider<NoteEntry?> {
  NoteByIdProvider._({
    required NoteByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'noteByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$noteByIdHash();

  @override
  String toString() {
    return r'noteByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<NoteEntry?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NoteEntry? create(Ref ref) {
    final argument = this.argument as String;
    return noteById(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NoteEntry? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NoteEntry?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NoteByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$noteByIdHash() => r'8cf1b09f20013491d1eb5a357544ae352d57ac80';

final class NoteByIdFamily extends $Family
    with $FunctionalFamilyOverride<NoteEntry?, String> {
  NoteByIdFamily._()
    : super(
        retry: null,
        name: r'noteByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NoteByIdProvider call(String noteId) =>
      NoteByIdProvider._(argument: noteId, from: this);

  @override
  String toString() => r'noteByIdProvider';
}
