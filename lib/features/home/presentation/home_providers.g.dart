// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DiagnosticLogController)
final diagnosticLogControllerProvider = DiagnosticLogControllerProvider._();

final class DiagnosticLogControllerProvider
    extends
        $AsyncNotifierProvider<DiagnosticLogController, DiagnosticLogSnapshot> {
  DiagnosticLogControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticLogControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticLogControllerHash();

  @$internal
  @override
  DiagnosticLogController create() => DiagnosticLogController();
}

String _$diagnosticLogControllerHash() =>
    r'ba7b6918441d93a128f9e9ba6b3c174daa86e0f9';

abstract class _$DiagnosticLogController
    extends $AsyncNotifier<DiagnosticLogSnapshot> {
  FutureOr<DiagnosticLogSnapshot> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<DiagnosticLogSnapshot>, DiagnosticLogSnapshot>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<DiagnosticLogSnapshot>,
                DiagnosticLogSnapshot
              >,
              AsyncValue<DiagnosticLogSnapshot>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

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

String _$homeRepositoryHash() => r'7210df92520e837404787af3d6401ba7bcfc2f9d';

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

@ProviderFor(WidgetQuickCaptureSettingsController)
final widgetQuickCaptureSettingsControllerProvider =
    WidgetQuickCaptureSettingsControllerProvider._();

final class WidgetQuickCaptureSettingsControllerProvider
    extends $NotifierProvider<WidgetQuickCaptureSettingsController, bool> {
  WidgetQuickCaptureSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'widgetQuickCaptureSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$widgetQuickCaptureSettingsControllerHash();

  @$internal
  @override
  WidgetQuickCaptureSettingsController create() =>
      WidgetQuickCaptureSettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$widgetQuickCaptureSettingsControllerHash() =>
    r'8d5f4dd6def5256df5ac081fb5c61259aee6efb3';

abstract class _$WidgetQuickCaptureSettingsController extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(WidgetQuickCaptureRequestController)
final widgetQuickCaptureRequestControllerProvider =
    WidgetQuickCaptureRequestControllerProvider._();

final class WidgetQuickCaptureRequestControllerProvider
    extends
        $NotifierProvider<
          WidgetQuickCaptureRequestController,
          QuickCaptureRequest?
        > {
  WidgetQuickCaptureRequestControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'widgetQuickCaptureRequestControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$widgetQuickCaptureRequestControllerHash();

  @$internal
  @override
  WidgetQuickCaptureRequestController create() =>
      WidgetQuickCaptureRequestController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(QuickCaptureRequest? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<QuickCaptureRequest?>(value),
    );
  }
}

String _$widgetQuickCaptureRequestControllerHash() =>
    r'0e0943731fee378b16f9f9780ff1e93622455d98';

abstract class _$WidgetQuickCaptureRequestController
    extends $Notifier<QuickCaptureRequest?> {
  QuickCaptureRequest? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<QuickCaptureRequest?, QuickCaptureRequest?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<QuickCaptureRequest?, QuickCaptureRequest?>,
              QuickCaptureRequest?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(widgetQuickCaptureBridge)
final widgetQuickCaptureBridgeProvider = WidgetQuickCaptureBridgeProvider._();

final class WidgetQuickCaptureBridgeProvider
    extends
        $FunctionalProvider<
          WidgetQuickCaptureBridge,
          WidgetQuickCaptureBridge,
          WidgetQuickCaptureBridge
        >
    with $Provider<WidgetQuickCaptureBridge> {
  WidgetQuickCaptureBridgeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'widgetQuickCaptureBridgeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$widgetQuickCaptureBridgeHash();

  @$internal
  @override
  $ProviderElement<WidgetQuickCaptureBridge> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WidgetQuickCaptureBridge create(Ref ref) {
    return widgetQuickCaptureBridge(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WidgetQuickCaptureBridge value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WidgetQuickCaptureBridge>(value),
    );
  }
}

String _$widgetQuickCaptureBridgeHash() =>
    r'11395e86315d7e676b712bda2a12f6532d5b3f29';

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

@ProviderFor(NotesListDensityController)
final notesListDensityControllerProvider =
    NotesListDensityControllerProvider._();

final class NotesListDensityControllerProvider
    extends $NotifierProvider<NotesListDensityController, NotesListDensity> {
  NotesListDensityControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notesListDensityControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notesListDensityControllerHash();

  @$internal
  @override
  NotesListDensityController create() => NotesListDensityController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotesListDensity value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotesListDensity>(value),
    );
  }
}

String _$notesListDensityControllerHash() =>
    r'1fb15ccf5157b1b9ac49e2a07c68ac45f3db2b0f';

abstract class _$NotesListDensityController
    extends $Notifier<NotesListDensity> {
  NotesListDensity build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<NotesListDensity, NotesListDensity>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NotesListDensity, NotesListDensity>,
              NotesListDensity,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(AttachmentPreviewFitController)
final attachmentPreviewFitControllerProvider =
    AttachmentPreviewFitControllerProvider._();

final class AttachmentPreviewFitControllerProvider
    extends
        $NotifierProvider<
          AttachmentPreviewFitController,
          AttachmentPreviewFit
        > {
  AttachmentPreviewFitControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'attachmentPreviewFitControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$attachmentPreviewFitControllerHash();

  @$internal
  @override
  AttachmentPreviewFitController create() => AttachmentPreviewFitController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AttachmentPreviewFit value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AttachmentPreviewFit>(value),
    );
  }
}

String _$attachmentPreviewFitControllerHash() =>
    r'f9a503a1ed2d920dca90514b3e6a1558ef3f0050';

abstract class _$AttachmentPreviewFitController
    extends $Notifier<AttachmentPreviewFit> {
  AttachmentPreviewFit build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AttachmentPreviewFit, AttachmentPreviewFit>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AttachmentPreviewFit, AttachmentPreviewFit>,
              AttachmentPreviewFit,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(NotesListSortController)
final notesListSortControllerProvider = NotesListSortControllerProvider._();

final class NotesListSortControllerProvider
    extends $NotifierProvider<NotesListSortController, NotesListSortField> {
  NotesListSortControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notesListSortControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notesListSortControllerHash();

  @$internal
  @override
  NotesListSortController create() => NotesListSortController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotesListSortField value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotesListSortField>(value),
    );
  }
}

String _$notesListSortControllerHash() =>
    r'58a4857acfee0c928f1f59a523f3c059e8db6f04';

abstract class _$NotesListSortController extends $Notifier<NotesListSortField> {
  NotesListSortField build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<NotesListSortField, NotesListSortField>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NotesListSortField, NotesListSortField>,
              NotesListSortField,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(LastNoteEditorSettingsController)
final lastNoteEditorSettingsControllerProvider =
    LastNoteEditorSettingsControllerProvider._();

final class LastNoteEditorSettingsControllerProvider
    extends
        $NotifierProvider<
          LastNoteEditorSettingsController,
          LastNoteEditorSettings
        > {
  LastNoteEditorSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastNoteEditorSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastNoteEditorSettingsControllerHash();

  @$internal
  @override
  LastNoteEditorSettingsController create() =>
      LastNoteEditorSettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LastNoteEditorSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LastNoteEditorSettings>(value),
    );
  }
}

String _$lastNoteEditorSettingsControllerHash() =>
    r'8500b8058fe26eb308a91da26b23ae7b01836400';

abstract class _$LastNoteEditorSettingsController
    extends $Notifier<LastNoteEditorSettings> {
  LastNoteEditorSettings build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<LastNoteEditorSettings, LastNoteEditorSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LastNoteEditorSettings, LastNoteEditorSettings>,
              LastNoteEditorSettings,
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

String _$notesControllerHash() => r'7049f864891806499206f7d9bb86f2f9b6d39a21';

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

String _$visibleVaultsHash() => r'9f89f1c3e27882cb99cb05b472b52014115ca5b2';

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

String _$visibleNotesHash() => r'7e26afead3351ff35452052d30f98c33e259bb61';

@ProviderFor(visibleNoteYears)
final visibleNoteYearsProvider = VisibleNoteYearsProvider._();

final class VisibleNoteYearsProvider
    extends $FunctionalProvider<List<int>, List<int>, List<int>>
    with $Provider<List<int>> {
  VisibleNoteYearsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleNoteYearsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleNoteYearsHash();

  @$internal
  @override
  $ProviderElement<List<int>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<int> create(Ref ref) {
    return visibleNoteYears(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<int> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<int>>(value),
    );
  }
}

String _$visibleNoteYearsHash() => r'136dd345d35c9b912c306d291b7c979849cb3e2b';

@ProviderFor(noteSearchIndex)
final noteSearchIndexProvider = NoteSearchIndexProvider._();

final class NoteSearchIndexProvider
    extends
        $FunctionalProvider<
          Map<String, String>,
          Map<String, String>,
          Map<String, String>
        >
    with $Provider<Map<String, String>> {
  NoteSearchIndexProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'noteSearchIndexProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$noteSearchIndexHash();

  @$internal
  @override
  $ProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, String> create(Ref ref) {
    return noteSearchIndex(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, String>>(value),
    );
  }
}

String _$noteSearchIndexHash() => r'301a44c758c248de44d84b54dd8e486fcbd51380';

@ProviderFor(visibleTagSuggestions)
final visibleTagSuggestionsProvider = VisibleTagSuggestionsProvider._();

final class VisibleTagSuggestionsProvider
    extends $FunctionalProvider<List<String>, List<String>, List<String>>
    with $Provider<List<String>> {
  VisibleTagSuggestionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleTagSuggestionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleTagSuggestionsHash();

  @$internal
  @override
  $ProviderElement<List<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<String> create(Ref ref) {
    return visibleTagSuggestions(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$visibleTagSuggestionsHash() =>
    r'370a3f322fe6496edec62f04707eb699b4ba75c8';

@ProviderFor(visibleNotesByVault)
final visibleNotesByVaultProvider = VisibleNotesByVaultProvider._();

final class VisibleNotesByVaultProvider
    extends
        $FunctionalProvider<
          Map<String, List<NoteEntry>>,
          Map<String, List<NoteEntry>>,
          Map<String, List<NoteEntry>>
        >
    with $Provider<Map<String, List<NoteEntry>>> {
  VisibleNotesByVaultProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleNotesByVaultProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleNotesByVaultHash();

  @$internal
  @override
  $ProviderElement<Map<String, List<NoteEntry>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, List<NoteEntry>> create(Ref ref) {
    return visibleNotesByVault(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, List<NoteEntry>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, List<NoteEntry>>>(value),
    );
  }
}

String _$visibleNotesByVaultHash() =>
    r'881041395ffe42092370531f0a2a98fd5b8dda24';

@ProviderFor(visibleNoteIndexById)
final visibleNoteIndexByIdProvider = VisibleNoteIndexByIdProvider._();

final class VisibleNoteIndexByIdProvider
    extends
        $FunctionalProvider<
          Map<String, int>,
          Map<String, int>,
          Map<String, int>
        >
    with $Provider<Map<String, int>> {
  VisibleNoteIndexByIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleNoteIndexByIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleNoteIndexByIdHash();

  @$internal
  @override
  $ProviderElement<Map<String, int>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Map<String, int> create(Ref ref) {
    return visibleNoteIndexById(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, int> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, int>>(value),
    );
  }
}

String _$visibleNoteIndexByIdHash() =>
    r'aaa067a43784e2bdd7bb5c956325706ae1b3ad4e';

@ProviderFor(visibleNotesByDay)
final visibleNotesByDayProvider = VisibleNotesByDayProvider._();

final class VisibleNotesByDayProvider
    extends
        $FunctionalProvider<
          Map<DateTime, List<NoteEntry>>,
          Map<DateTime, List<NoteEntry>>,
          Map<DateTime, List<NoteEntry>>
        >
    with $Provider<Map<DateTime, List<NoteEntry>>> {
  VisibleNotesByDayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleNotesByDayProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleNotesByDayHash();

  @$internal
  @override
  $ProviderElement<Map<DateTime, List<NoteEntry>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<DateTime, List<NoteEntry>> create(Ref ref) {
    return visibleNotesByDay(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<DateTime, List<NoteEntry>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<DateTime, List<NoteEntry>>>(
        value,
      ),
    );
  }
}

String _$visibleNotesByDayHash() => r'fe52c8564c6fcf40ee305b44463002a4f5c17f60';

@ProviderFor(visibleNoteDays)
final visibleNoteDaysProvider = VisibleNoteDaysProvider._();

final class VisibleNoteDaysProvider
    extends $FunctionalProvider<List<DateTime>, List<DateTime>, List<DateTime>>
    with $Provider<List<DateTime>> {
  VisibleNoteDaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visibleNoteDaysProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visibleNoteDaysHash();

  @$internal
  @override
  $ProviderElement<List<DateTime>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<DateTime> create(Ref ref) {
    return visibleNoteDays(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<DateTime> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<DateTime>>(value),
    );
  }
}

String _$visibleNoteDaysHash() => r'10450d731d3732c0bae25e4aba884cfef4fb1faa';

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

String _$notesForVaultHash() => r'aa63776e491f57fbf6dec303241c72952777cd07';

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

String _$vaultByIdHash() => r'63205554e94772f11e363f640d13ec78c525b3b2';

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

String _$noteByIdHash() => r'2a38235766101426bb0eccb41ba2af7ed1eb9437';

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
