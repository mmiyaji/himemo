import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pinput/pinput.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../app/diagnostic_log.dart';
import '../../../app/audit_log.dart';
import '../../../l10n/app_strings.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/encryption_service.dart';
import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/google_sign_in_initializer.dart';
import '../../sync/data/sync_attachment_refs.dart';
import '../../sync/data/sync_bundle_preview.dart';
import '../../sync/data/sync_bundle_state_store.dart';
import '../../sync/data/sync_bundle_key_service.dart';
import '../../sync/data/sync_engine.dart';
import '../../sync/presentation/google_sign_in_web_button.dart';
import '../domain/note_entry.dart';
import '../domain/note_tags.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';
import 'web_video_element_view_stub.dart'
    if (dart.library.html) 'web_video_element_view_web.dart';
import 'web_video_object_url_stub.dart'
    if (dart.library.html) 'web_video_object_url_web.dart';
import 'video_player_controller_factory_stub.dart'
    if (dart.library.io) 'video_player_controller_factory_io.dart';

part 'home_settings_screen.dart';
part 'home_private_profile_settings.dart';
part 'home_settings_components.dart';
part 'home_note_content.dart';
part 'home_sync_support.dart';
part 'home_media_viewers.dart';
part 'home_trash_widgets.dart';
part 'home_sidebar.dart';
part 'home_note_lists.dart';
part 'home_note_detail.dart';
part 'home_calendar_screen.dart';
part 'home_insights_screen.dart';
part 'home_notes_screen.dart';
part 'home_trash_screen.dart';
part 'home_tags_screen.dart';
part 'home_google_drive_panel.dart';

const _appStoreId = String.fromEnvironment('HIMEMO_APP_STORE_ID');
const _androidStorePackageName = 'org.ruhenheim.himemo';
const _buildDateIso = String.fromEnvironment('HIMEMO_BUILD_DATE');
const _termsUrl = 'https://mmiyaji.github.io/himemo/terms.html';
const _privacyUrl = 'https://mmiyaji.github.io/himemo/privacy.html';
const _contactUrl = 'https://mmiyaji.github.io/himemo/contact.html';
const _helpUrl = 'https://mmiyaji.github.io/himemo/help.html';
const _httpUserAgent = 'HiMemo/1.0 (+$_contactUrl)';
const _appAuthor = '@mmiyaji';
const _appAuthorUrl = 'https://ruhenheim.org/';

enum AppSection { notes, calendar, insights, trash, tags, settings }

final _noteOverlaySheetDepth = ValueNotifier<int>(0);
final _mobileNoteDetailSheetDepth = ValueNotifier<int>(0);
final _mobileNoteDetailCloseRequests = ValueNotifier<int>(0);

void _pushNoteOverlaySheet() {
  _noteOverlaySheetDepth.value = _noteOverlaySheetDepth.value + 1;
}

void _popNoteOverlaySheet() {
  if (_noteOverlaySheetDepth.value > 0) {
    _noteOverlaySheetDepth.value = _noteOverlaySheetDepth.value - 1;
  }
}

void _pushMobileNoteDetailSheet() {
  _mobileNoteDetailSheetDepth.value = _mobileNoteDetailSheetDepth.value + 1;
}

void _popMobileNoteDetailSheet() {
  if (_mobileNoteDetailSheetDepth.value > 0) {
    _mobileNoteDetailSheetDepth.value = _mobileNoteDetailSheetDepth.value - 1;
  }
}

void _requestMobileNoteDetailClose() {
  _mobileNoteDetailCloseRequests.value =
      _mobileNoteDetailCloseRequests.value + 1;
}

void _debugNotePerf(String message) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('[note-perf] ${DateTime.now().toIso8601String()} $message');
}

String _notePerfLabel(NoteEntry note) {
  final title = note.title.trim();
  final displayTitle = title.isEmpty ? '(untitled)' : title;
  return 'id=${note.id} title="$displayTitle" attachments=${note.attachments.length} blocks=${note.blocks.length}';
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  static const notesNavKey = Key('nav-notes');
  static const calendarNavKey = Key('nav-calendar');
  static const insightsNavKey = Key('nav-insights');
  static const settingsNavKey = Key('nav-settings');
  static const addNoteKey = Key('add-note-button');
  static const syncIndicatorKey = Key('sync-progress-indicator-button');
  static const privateProfileAccessKey = Key('private-profile-access-button');

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _compactBottomNavLabelBreakpoint = 380.0;
  static const _createNoteNavTopOffset = -4.0;

  bool _sidebarCollapsed = false;
  AppSection? _lastObservedSection;
  bool _noteOverlayWasOpen = false;
  bool _releaseNotesChecked = false;
  DateTime? _suppressProfileAccessUntil;
  Timer? _profileAccessSuppressionTimer;

  @override
  void initState() {
    super.initState();
    _noteOverlaySheetDepth.addListener(_handleNoteOverlayChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showReleaseNotesIfNeeded());
    });
  }

  @override
  void dispose() {
    _profileAccessSuppressionTimer?.cancel();
    _noteOverlaySheetDepth.removeListener(_handleNoteOverlayChanged);
    super.dispose();
  }

  void _handleNoteOverlayChanged() {
    final noteOverlayOpen = _noteOverlaySheetDepth.value > 0;
    if (_noteOverlayWasOpen && !noteOverlayOpen) {
      _suppressProfileAccessUntil = DateTime.now().add(
        const Duration(milliseconds: 450),
      );
      _profileAccessSuppressionTimer?.cancel();
      _profileAccessSuppressionTimer = Timer(
        const Duration(milliseconds: 450),
        () {
          _suppressProfileAccessUntil = null;
          if (mounted) {
            setState(() {});
          }
        },
      );
    }
    _noteOverlayWasOpen = noteOverlayOpen;
    if (mounted) {
      setState(() {});
    }
  }

  bool get _profileAccessBlocked {
    final until = _suppressProfileAccessUntil;
    return _noteOverlaySheetDepth.value > 0 ||
        (until != null && DateTime.now().isBefore(until));
  }

  void _handleProfileAccessTap(BuildContext context, WidgetRef ref) {
    if (_profileAccessBlocked) {
      return;
    }
    if (ref.read(privateProfileUnlockControllerProvider).isLoading) {
      return;
    }
    _showProfileAccessDialog(context, ref);
  }

  Future<void> _showReleaseNotesIfNeeded() async {
    if (_releaseNotesChecked || !mounted) {
      return;
    }
    _releaseNotesChecked = true;
    final releaseNote = await ref.read(unseenReleaseNoteProvider.future);
    if (!mounted || releaseNote == null) {
      return;
    }
    await _showReleaseNotesDialog(context, releaseNote);
    if (!mounted) {
      return;
    }
    await ref.read(releaseNotesSeenControllerProvider).markCurrentSeen();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 840;
    final section = _sectionForLocation(GoRouterState.of(context).uri.path);
    _closeNotesOverlayOnRouteSectionChange(context, ref, section);
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final activePrivateProfileLabel = ref.watch(
      activePrivateProfileLabelProvider,
    );
    final adminMode = ref.watch(adminModeSessionControllerProvider);
    final profileUnlocking = ref.watch(
      privateProfileUnlockControllerProvider.select((value) => value.isLoading),
    );
    final profileAccessBlocked = _profileAccessBlocked;
    final privateProfileActive =
        !adminMode && activePrivateProfileLabel != null;
    final colorScheme = Theme.of(context).colorScheme;
    final privateProfileActiveColor = colorScheme.primary;
    final profileAccessBusyTooltip = strings.localized(
      en: 'Opening private profile...',
      ja: 'プライベートプロファイルを開いています...',
      zh: '正在打开私密档案...',
      ko: '비공개 프로필을 여는 중...',
      es: 'Abriendo perfil privado...',
      de: 'Privates Profil wird geöffnet...',
    );
    final profileAccessTooltip = adminMode
        ? (context.strings.text('home.admin.mode.active'))
        : (activePrivateProfileLabel != null
              ? context.strings.viewingPrivateProfile(activePrivateProfileLabel)
              : (context.strings.text('home.unlock.private.profile')));
    final profileAccessPillLabel = adminMode
        ? profileAccessTooltip
        : activePrivateProfileLabel;
    final effectiveProfileAccessTooltip = profileUnlocking
        ? profileAccessBusyTooltip
        : profileAccessTooltip;
    final syncTransferState = ref.watch(syncTransferControllerProvider);
    final tutorialStep = ref.watch(appTutorialControllerProvider);

    final shell = Scaffold(
      appBar: AppBar(
        title: const _AppBrandTitle(),
        actions: [
          if (syncTransferState.stage == SyncTransferStage.busy)
            Padding(
              padding: EdgeInsetsDirectional.only(
                end: privateProfileActive || adminMode ? 8 : 4,
              ),
              child: _HeaderSyncIndicator(
                state: syncTransferState,
                provider: ref.watch(syncProviderControllerProvider),
              ),
            ),
          if (useRail)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: IconButton(
                key: AppShell.addNoteKey,
                tooltip: strings.addNote,
                onPressed: () => showNoteEditorSheet(context, ref),
                icon: const Icon(Icons.edit_note_rounded),
              ),
            ),
          if (privateProfileActive || adminMode)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(220, width * 0.42),
                ),
                child: Tooltip(
                  message: effectiveProfileAccessTooltip,
                  child: Material(
                    color: privateProfileActiveColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      key: AppShell.privateProfileAccessKey,
                      borderRadius: BorderRadius.circular(999),
                      onTap: profileAccessBlocked || profileUnlocking
                          ? null
                          : () => _handleProfileAccessTap(context, ref),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          10,
                          7,
                          12,
                          7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (profileUnlocking)
                              SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: privateProfileActiveColor,
                                ),
                              )
                            else
                              _PrivateProfileAccessIcon(
                                kind: adminMode
                                    ? _PrivateProfileAccessIconKind.admin
                                    : _PrivateProfileAccessIconKind.unlocked,
                                size: 20,
                                color: privateProfileActiveColor,
                              ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                profileAccessPillLabel ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: privateProfileActiveColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              width: 72,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: effectiveProfileAccessTooltip,
                  child: SizedBox.square(
                    dimension: 40,
                    child: Semantics(
                      button: true,
                      enabled: !profileAccessBlocked && !profileUnlocking,
                      label: effectiveProfileAccessTooltip,
                      onTap: profileAccessBlocked || profileUnlocking
                          ? null
                          : () => _handleProfileAccessTap(context, ref),
                      child: Material(
                        type: MaterialType.transparency,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: AppShell.privateProfileAccessKey,
                          customBorder: const CircleBorder(),
                          onTap: profileAccessBlocked || profileUnlocking
                              ? null
                              : () => _handleProfileAccessTap(context, ref),
                          child: Center(
                            child: profileUnlocking
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.3,
                                    ),
                                  )
                                : _PrivateProfileAccessIcon(
                                    kind: adminMode
                                        ? _PrivateProfileAccessIconKind.admin
                                        : activePrivateProfileLabel != null
                                        ? _PrivateProfileAccessIconKind.unlocked
                                        : _PrivateProfileAccessIconKind.locked,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Theme.of(context).dividerColor),
        ),
      ),
      body: SafeArea(
        child: useRail
            ? Row(
                children: [
                  _Sidebar(
                    section: section,
                    activeIdentity: activeIdentity,
                    collapsed: _sidebarCollapsed,
                    tagSummaries: ref.watch(visibleTagSummariesProvider),
                    activeTags: ref.watch(searchFiltersControllerProvider).tags,
                    onToggleCollapsed: () {
                      setState(() {
                        _sidebarCollapsed = !_sidebarCollapsed;
                      });
                    },
                    onSectionSelected: (target) =>
                        _goToSection(context, ref, target),
                    onShowAllNotes: () => _showAllNotes(context, ref),
                    onTagSelected: (tag) => _openTagFilter(context, ref, tag),
                    onAddNote: () => showNoteEditorSheet(context, ref),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  Expanded(child: widget.child),
                ],
              )
            : widget.child,
      ),
      bottomNavigationBar: useRail
          ? null
          : LayoutBuilder(
              builder: (context, constraints) {
                final hideBottomNavLabels =
                    constraints.maxWidth < _compactBottomNavLabelBreakpoint;
                String bottomNavLabel(String label) {
                  if (hideBottomNavLabels) {
                    return '';
                  }
                  if (constraints.maxWidth < 420 && label == 'Einstellungen') {
                    return 'Einstell.';
                  }
                  return label;
                }

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    NavigationBar(
                      labelBehavior: hideBottomNavLabels
                          ? NavigationDestinationLabelBehavior.alwaysHide
                          : NavigationDestinationLabelBehavior.alwaysShow,
                      selectedIndex: _bottomNavIndexForSection(section),
                      onDestinationSelected: (index) {
                        if (index == 2) {
                          showNoteEditorSheet(context, ref);
                          return;
                        }
                        _goToSection(
                          context,
                          ref,
                          _sectionForBottomNavIndex(index),
                        );
                      },
                      destinations: [
                        NavigationDestination(
                          key: AppShell.notesNavKey,
                          icon: const Icon(Icons.notes_outlined),
                          selectedIcon: const Icon(Icons.notes_rounded),
                          label: bottomNavLabel(strings.notes),
                          tooltip: strings.notes,
                        ),
                        NavigationDestination(
                          key: AppShell.calendarNavKey,
                          icon: const Icon(Icons.calendar_month_outlined),
                          selectedIcon: const Icon(
                            Icons.calendar_month_rounded,
                          ),
                          label: bottomNavLabel(strings.calendar),
                          tooltip: strings.calendar,
                        ),
                        const NavigationDestination(
                          enabled: false,
                          icon: SizedBox.shrink(),
                          selectedIcon: SizedBox.shrink(),
                          label: '',
                          tooltip: '',
                        ),
                        NavigationDestination(
                          key: AppShell.insightsNavKey,
                          icon: const Icon(Icons.insert_chart_outlined_rounded),
                          selectedIcon: const Icon(Icons.insert_chart_rounded),
                          label: bottomNavLabel(strings.insights),
                          tooltip: strings.insights,
                        ),
                        NavigationDestination(
                          key: AppShell.settingsNavKey,
                          icon: const Icon(Icons.settings_outlined),
                          selectedIcon: const Icon(Icons.settings_rounded),
                          label: bottomNavLabel(strings.settings),
                          tooltip: strings.settings,
                        ),
                      ],
                    ),
                    Positioned(
                      top: _createNoteNavTopOffset,
                      child: _CreateNoteNavButton(
                        key: AppShell.addNoteKey,
                        onPressed: () => showNoteEditorSheet(context, ref),
                        tooltip: strings.addNote,
                      ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: null,
    );
    return Stack(
      children: [
        shell,
        if (tutorialStep != null)
          _AppTutorialOverlay(
            step: tutorialStep,
            useRail: useRail,
            onPrevious: ref
                .read(appTutorialControllerProvider.notifier)
                .previous,
            onNext: ref.read(appTutorialControllerProvider.notifier).next,
            onClose: ref.read(appTutorialControllerProvider.notifier).close,
          ),
      ],
    );
  }

  int _bottomNavIndexForSection(AppSection section) {
    return switch (section) {
      AppSection.notes => 0,
      AppSection.calendar => 1,
      AppSection.insights => 3,
      AppSection.trash => 4,
      AppSection.tags => 4,
      AppSection.settings => 4,
    };
  }

  AppSection _sectionForBottomNavIndex(int index) {
    return switch (index) {
      0 => AppSection.notes,
      1 => AppSection.calendar,
      3 => AppSection.insights,
      4 => AppSection.settings,
      _ => AppSection.notes,
    };
  }

  void _goToSection(BuildContext context, WidgetRef ref, AppSection section) {
    final currentSection = _sectionForLocation(
      GoRouterState.of(context).uri.path,
    );
    if (currentSection != section) {
      _dismissOpenSheet(context, force: true);
    }
    if (currentSection == AppSection.notes && section != AppSection.notes) {
      ref.read(selectedNoteIdProvider.notifier).select(null);
    }
    switch (section) {
      case AppSection.notes:
        context.go('/notes');
      case AppSection.calendar:
        context.go('/calendar');
      case AppSection.insights:
        context.go('/insights');
      case AppSection.trash:
        context.go('/trash');
      case AppSection.tags:
        context.go('/tags');
      case AppSection.settings:
        context.go('/settings');
    }
  }

  void _showAllNotes(BuildContext context, WidgetRef ref) {
    ref.read(searchFiltersControllerProvider.notifier).setTags(const []);
    ref.read(searchQueryProvider.notifier).setQuery('');
    ref.read(selectedNoteIdProvider.notifier).select(null);
    context.go('/notes');
  }

  void _openTagFilter(BuildContext context, WidgetRef ref, String tag) {
    ref.read(searchFiltersControllerProvider.notifier).setTags([tag]);
    ref.read(searchQueryProvider.notifier).setQuery('');
    ref.read(selectedNoteIdProvider.notifier).select(null);
    context.go('/notes');
  }

  void _closeNotesOverlayOnRouteSectionChange(
    BuildContext context,
    WidgetRef ref,
    AppSection section,
  ) {
    final previous = _lastObservedSection;
    _lastObservedSection = section;
    if (previous == null ||
        previous == section ||
        previous != AppSection.notes ||
        section == AppSection.notes) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(selectedNoteIdProvider.notifier).select(null);
      _dismissOpenSheet(context, force: true);
    });
  }

  void _dismissOpenSheet(BuildContext context, {bool force = false}) {
    if (!force && _noteOverlaySheetDepth.value <= 0) {
      return;
    }
    if (_mobileNoteDetailSheetDepth.value > 0) {
      _requestMobileNoteDetailClose();
      return;
    }
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  AppSection _sectionForLocation(String location) {
    if (location.startsWith('/calendar')) {
      return AppSection.calendar;
    }
    if (location.startsWith('/insights')) {
      return AppSection.insights;
    }
    if (location.startsWith('/trash')) {
      return AppSection.trash;
    }
    if (location.startsWith('/tags')) {
      return AppSection.tags;
    }
    if (location.startsWith('/settings')) {
      return AppSection.settings;
    }
    return AppSection.notes;
  }
}

class _AppTutorialOverlay extends StatelessWidget {
  const _AppTutorialOverlay({
    required this.step,
    required this.useRail,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final AppTutorialStep step;
  final bool useRail;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final media = MediaQuery.of(context);
    final size = media.size;
    final highlightRect = _highlightRect(size, media.padding);
    final isFirst = step == AppTutorialStep.values.first;
    final isLast = step == AppTutorialStep.values.last;
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onNext,
                child: CustomPaint(
                  painter: _TutorialScrimPainter(
                    highlightRect: highlightRect,
                    color: Colors.black.withValues(alpha: 0.62),
                    borderColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: highlightRect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.36),
                        blurRadius: 22,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: _cardAlignment,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Card(
                    margin: const EdgeInsets.all(18),
                    elevation: 10,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tips_and_updates_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _title(strings),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: strings.close,
                                onPressed: onClose,
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _body(strings),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            strings.localized(
                              en: 'Step ${AppTutorialStep.values.indexOf(step) + 1} of ${AppTutorialStep.values.length}',
                              ja: '${AppTutorialStep.values.indexOf(step) + 1} / ${AppTutorialStep.values.length}',
                              zh: '第 ${AppTutorialStep.values.indexOf(step) + 1} 步，共 ${AppTutorialStep.values.length} 步',
                              ko: '${AppTutorialStep.values.indexOf(step) + 1}/${AppTutorialStep.values.length}단계',
                              es: 'Paso ${AppTutorialStep.values.indexOf(step) + 1} de ${AppTutorialStep.values.length}',
                              de: 'Schritt ${AppTutorialStep.values.indexOf(step) + 1} von ${AppTutorialStep.values.length}',
                            ),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              TextButton(
                                onPressed: isFirst ? null : onPrevious,
                                child: Text(
                                  strings.localized(
                                    en: 'Back',
                                    ja: '戻る',
                                    zh: '上一步',
                                    ko: '이전',
                                    es: 'Atras',
                                    de: 'Zurueck',
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: onClose,
                                child: Text(strings.skip),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: isLast ? onClose : onNext,
                                child: Text(
                                  isLast
                                      ? strings.localized(
                                          en: 'Done',
                                          ja: '完了',
                                          zh: '完成',
                                          ko: '완료',
                                          es: 'Listo',
                                          de: 'Fertig',
                                        )
                                      : strings.next,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Alignment get _cardAlignment {
    return switch (step) {
      AppTutorialStep.privateProfile => Alignment.bottomCenter,
      AppTutorialStep.addNote =>
        useRail ? Alignment.bottomRight : Alignment.topCenter,
      AppTutorialStep.syncStatus => Alignment.bottomCenter,
      AppTutorialStep.navigation => Alignment.topCenter,
    };
  }

  Rect _highlightRect(Size size, EdgeInsets padding) {
    final top = padding.top;
    final bottom = padding.bottom;
    return switch (step) {
      AppTutorialStep.privateProfile => Rect.fromLTWH(
        size.width - 92,
        top + 8,
        74,
        52,
      ),
      AppTutorialStep.addNote =>
        useRail
            ? Rect.fromLTWH(size.width - 78, top + 8, 56, 52)
            : Rect.fromCircle(
                center: Offset(size.width / 2, size.height - bottom - 46),
                radius: 42,
              ),
      AppTutorialStep.syncStatus => Rect.fromLTWH(
        size.width - (useRail ? 150 : 132),
        top + 8,
        56,
        52,
      ),
      AppTutorialStep.navigation =>
        useRail
            ? Rect.fromLTWH(10, top + 70, 234, 270)
            : Rect.fromLTWH(0, size.height - bottom - 92, size.width, 92),
    }.inflate(6);
  }

  String _title(AppStrings strings) {
    return switch (step) {
      AppTutorialStep.privateProfile => strings.localized(
        en: 'Private profile unlock',
        ja: 'プライベート解除',
        zh: '私密档案解锁',
        ko: '비공개 프로필 잠금 해제',
        es: 'Desbloqueo privado',
        de: 'Privates Profil entsperren',
      ),
      AppTutorialStep.addNote => strings.localized(
        en: 'Create a memo',
        ja: 'メモを作成',
        zh: '创建备忘',
        ko: '메모 만들기',
        es: 'Crear memo',
        de: 'Notiz erstellen',
      ),
      AppTutorialStep.syncStatus => strings.localized(
        en: 'Sync status',
        ja: '同期状況',
        zh: '同步状态',
        ko: '동기화 상태',
        es: 'Estado de sincronizacion',
        de: 'Synchronisierungsstatus',
      ),
      AppTutorialStep.navigation => strings.localized(
        en: 'Main navigation',
        ja: '画面の切り替え',
        zh: '主导航',
        ko: '주요 탐색',
        es: 'Navegacion principal',
        de: 'Hauptnavigation',
      ),
    };
  }

  String _body(AppStrings strings) {
    return switch (step) {
      AppTutorialStep.privateProfile => strings.localized(
        en: 'Use the lock icon in the header to unlock or switch private profiles. App lock also uses this area when protection is enabled.',
        ja: '画面右上のロックアイコンからプライベートプロファイルの解除や切り替えができます。アプリ保護を有効にした場合もここが入口になります。',
        zh: '可从标题栏右上角的锁图标解锁或切换私密档案。启用应用保护后，这里也是入口。',
        ko: '화면 오른쪽 위 잠금 아이콘에서 비공개 프로필을 잠금 해제하거나 전환할 수 있습니다. 앱 보호를 켠 경우에도 이 영역을 사용합니다.',
        es: 'Usa el icono de candado del encabezado para desbloquear o cambiar perfiles privados. La proteccion de la app tambien entra por aqui.',
        de: 'Ueber das Schloss oben rechts kannst du private Profile entsperren oder wechseln. Auch der App-Schutz nutzt diesen Bereich.',
      ),
      AppTutorialStep.addNote => strings.localized(
        en: 'Tap the center compose button to add a new memo. You can attach photos, videos, audio, files, tags, and dates from the editor.',
        ja: '中央の作成ボタンから新しいメモを追加します。編集画面では写真、動画、音声、ファイル、タグ、日付を追加できます。',
        zh: '点击中央的创建按钮添加新备忘。可在编辑器中添加照片、视频、音频、文件、标签和日期。',
        ko: '가운데 작성 버튼으로 새 메모를 추가합니다. 편집 화면에서 사진, 동영상, 오디오, 파일, 태그, 날짜를 추가할 수 있습니다.',
        es: 'Toca el boton central para crear un memo. En el editor puedes agregar fotos, videos, audio, archivos, etiquetas y fechas.',
        de: 'Mit der mittleren Schaltflaeche erstellst du eine neue Notiz. Im Editor kannst du Fotos, Videos, Audio, Dateien, Tags und Daten hinzufuegen.',
      ),
      AppTutorialStep.syncStatus => strings.localized(
        en: 'When sync is running, this indicator rotates and shows progress. Tap it to see the current step and item counts.',
        ja: '同期中はこのインジケーターが回転し、進捗を示します。タップすると現在の処理や件数進捗を確認できます。',
        zh: '同步运行时，此指示器会旋转并显示进度。点击可查看当前步骤和项目数量。',
        ko: '동기화 중에는 이 표시기가 회전하며 진행률을 보여줍니다. 탭하면 현재 단계와 항목 수를 볼 수 있습니다.',
        es: 'Durante la sincronizacion, este indicador gira y muestra el progreso. Tocalo para ver el paso actual y los conteos.',
        de: 'Waehrend der Synchronisierung dreht sich diese Anzeige und zeigt den Fortschritt. Tippe darauf, um Schritt und Anzahl zu sehen.',
      ),
      AppTutorialStep.navigation => strings.localized(
        en: 'Use the navigation to move between notes, calendar, insights, trash, and settings. Settings contains sync, app protection, profiles, and help.',
        ja: 'ナビゲーションからノート、カレンダー、記録、ゴミ箱、設定へ移動できます。設定には同期、アプリ保護、プロファイル、ヘルプがあります。',
        zh: '使用导航在笔记、日历、记录、回收站和设置之间移动。设置中包含同步、应用保护、档案和帮助。',
        ko: '탐색 메뉴에서 노트, 캘린더, 기록, 휴지통, 설정으로 이동합니다. 설정에는 동기화, 앱 보호, 프로필, 도움말이 있습니다.',
        es: 'Usa la navegacion para moverte entre notas, calendario, registros, papelera y ajustes. Ajustes contiene sincronizacion, proteccion, perfiles y ayuda.',
        de: 'Mit der Navigation wechselst du zwischen Notizen, Kalender, Auswertung, Papierkorb und Einstellungen. Dort findest du Synchronisierung, App-Schutz, Profile und Hilfe.',
      ),
    };
  }
}

class _TutorialScrimPainter extends CustomPainter {
  const _TutorialScrimPainter({
    required this.highlightRect,
    required this.color,
    required this.borderColor,
  });

  final Rect highlightRect;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()..addRect(Offset.zero & size);
    final highlightPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(highlightRect, const Radius.circular(18)),
      );
    final path = Path.combine(
      ui.PathOperation.difference,
      overlayPath,
      highlightPath,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TutorialScrimPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor;
  }
}

class _HeaderSyncIndicator extends StatefulWidget {
  const _HeaderSyncIndicator({required this.state, required this.provider});

  final SyncTransferState state;
  final SyncProvider provider;

  @override
  State<_HeaderSyncIndicator> createState() => _HeaderSyncIndicatorState();
}

class _HeaderSyncIndicatorState extends State<_HeaderSyncIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    final label = _syncProgressLabel(strings, widget.state);
    final description = _syncProgressDescription(
      strings,
      widget.state,
      widget.provider,
    );
    final tooltip = strings.localized(
      en: '$label\n$description\nTap to show sync progress.',
      ja: '$label\n$description\nタップすると同期の進捗を表示します。',
      zh: '$label\n$description\n点按可显示同步进度。',
      ko: '$label\n$description\n탭하면 동기화 진행 상황을 표시합니다.',
      es: '$label\n$description\nToca para ver el progreso de sincronización.',
      de: '$label\n$description\nTippe, um den Synchronisierungsfortschritt anzuzeigen.',
    );
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: label,
        value: description,
        onTap: () => _showHeaderSyncProgressDialog(context),
        child: SizedBox.square(
          dimension: 40,
          child: InkResponse(
            key: AppShell.syncIndicatorKey,
            radius: 20,
            onTap: () => _showHeaderSyncProgressDialog(context),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      value: _syncProgressValueForState(widget.state),
                      color: colorScheme.primary,
                      backgroundColor: colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: disableAnimations
                        ? const AlwaysStoppedAnimation<double>(0)
                        : ReverseAnimation(_rotationController),
                    child: Icon(
                      Icons.sync_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHeaderSyncProgressDialog(BuildContext context) {
    final strings = context.strings;
    final container = ProviderScope.containerOf(context);
    return showDialog<void>(
      context: context,
      builder: (context) {
        return UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(syncTransferControllerProvider);
              final provider = ref.watch(syncProviderControllerProvider);
              final label = _syncProgressLabel(strings, state);
              final description = _syncProgressDescription(
                strings,
                state,
                provider,
              );
              final itemProgress = _syncProgressItemProgressText(
                strings,
                state,
              );
              final progressValue = _syncProgressValueForState(state);
              return AlertDialog(
                title: Text(
                  strings.localized(
                    en: 'Sync progress',
                    ja: '同期の進捗',
                    zh: '同步进度',
                    ko: '동기화 진행 상황',
                    es: 'Progreso de sincronización',
                    de: 'Synchronisierungsfortschritt',
                  ),
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: progressValue),
                      if (itemProgress != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          itemProgress,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.cancel),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _CreateNoteNavButton extends StatelessWidget {
  const _CreateNoteNavButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  static const _verticalOffset = 12.0;
  static const _tapSize = 68.0;
  static const _buttonSize = 56.0;
  static const _iconSize = 44.0;

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onPressed,
        child: SizedBox(
          width: _tapSize,
          height: _tapSize + _verticalOffset,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox.square(
                dimension: _tapSize,
                child: Center(
                  child: Container(
                    width: _buttonSize,
                    height: _buttonSize,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: _CreateNoteIcon(size: _iconSize),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _PrivateProfileAccessIconKind { locked, unlocked, admin }

class _PrivateProfileAccessIcon extends StatelessWidget {
  const _PrivateProfileAccessIcon({
    required this.kind,
    required this.size,
    this.color,
  });

  final _PrivateProfileAccessIconKind kind;
  final double size;
  final Color? color;

  IconData get _icon {
    switch (kind) {
      case _PrivateProfileAccessIconKind.locked:
        return Icons.lock_outline;
      case _PrivateProfileAccessIconKind.unlocked:
        return Icons.lock_open_outlined;
      case _PrivateProfileAccessIconKind.admin:
        return Icons.admin_panel_settings_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;

    return Icon(_icon, size: size, color: effectiveColor);
  }
}

class _CreateNoteIcon extends StatelessWidget {
  const _CreateNoteIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/actions/create-note.svg',
      width: size,
      height: size,
      colorMapper: _CreateNoteIconColorMapper(Theme.of(context).colorScheme),
    );
  }
}

@immutable
class _CreateNoteIconColorMapper extends ColorMapper {
  const _CreateNoteIconColorMapper(this.colorScheme);

  final ColorScheme colorScheme;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (color == const Color(0xFFFFF7F4)) {
      return colorScheme.onPrimary;
    }
    if (color == const Color(0xFFF7DADF)) {
      return Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.14),
        colorScheme.onPrimary,
      );
    }
    if (color == const Color(0xFF9F5261)) {
      return colorScheme.primary;
    }
    if (color == const Color(0xFFD77E8D)) {
      return colorScheme.primary.withValues(alpha: 0.72);
    }
    return color;
  }

  @override
  bool operator ==(Object other) {
    return other is _CreateNoteIconColorMapper &&
        other.colorScheme.primary == colorScheme.primary &&
        other.colorScheme.onPrimary == colorScheme.onPrimary;
  }

  @override
  int get hashCode => Object.hash(colorScheme.primary, colorScheme.onPrimary);
}

class _AppBrandTitle extends StatelessWidget {
  const _AppBrandTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/app-icon.png',
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'HiMemo',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

Future<void> _showReleaseNotesDialog(
  BuildContext context,
  ReleaseNote releaseNote,
) {
  final strings = context.strings;
  final locale = strings.locale;
  final colorScheme = Theme.of(context).colorScheme;
  final dateLabel = releaseNote.date == null
      ? null
      : MaterialLocalizations.of(context).formatMediumDate(releaseNote.date!);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.new_releases_outlined, color: colorScheme.primary),
      title: Text(releaseNote.localizedTitle(locale)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dateLabel != null) ...[
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (releaseNote.localizedSummary(locale).isNotEmpty) ...[
                Text(releaseNote.localizedSummary(locale)),
                const SizedBox(height: 16),
              ],
              for (final item in releaseNote.items) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        _releaseNoteItemIcon(item.type),
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.localizedTitle(locale),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.localizedBody(locale),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            strings.localized(
              en: 'Close',
              ja: '\u9589\u3058\u308b',
              zh: '\u5173\u95ed',
              ko: '\ub2eb\uae30',
              es: 'Cerrar',
              de: 'Schliessen',
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _showReleaseNotesHistoryDialog(
  BuildContext context,
  List<ReleaseNote> releaseNotes,
  String? currentVersion,
) async {
  final strings = context.strings;
  final locale = strings.locale;
  final colorScheme = Theme.of(context).colorScheme;
  final sortedReleaseNotes = [...releaseNotes]
    ..sort((a, b) {
      final aDate = a.date;
      final bDate = b.date;
      if (aDate != null && bDate != null) {
        final dateOrder = bDate.compareTo(aDate);
        if (dateOrder != 0) {
          return dateOrder;
        }
      } else if (aDate != null) {
        return -1;
      } else if (bDate != null) {
        return 1;
      }
      return b.version.compareTo(a.version);
    });
  final selected = await showDialog<ReleaseNote>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.history_rounded, color: colorScheme.primary),
      title: Text(
        strings.localized(
          en: 'Update history',
          ja: '\u66f4\u65b0\u5c65\u6b74',
          zh: '\u66f4\u65b0\u5386\u53f2',
          ko: '\uc5c5\ub370\uc774\ud2b8 \uae30\ub85d',
          es: 'Historial de novedades',
          de: 'Versionsverlauf',
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: math.min(MediaQuery.sizeOf(context).height * 0.65, 520),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in sortedReleaseNotes.indexed) ...[
                if (entry.$1 > 0) const Divider(height: 1),
                _ReleaseNoteHistoryTile(
                  releaseNote: entry.$2,
                  currentVersion: currentVersion,
                  locale: locale,
                  currentVersionLabel: strings.localized(
                    en: 'Current version',
                    ja: '\u73fe\u5728\u306e\u30d0\u30fc\u30b8\u30e7\u30f3',
                    zh: '\u5f53\u524d\u7248\u672c',
                    ko: '\ud604\uc7ac \ubc84\uc804',
                    es: 'Version actual',
                    de: 'Aktuelle Version',
                  ),
                  onTap: () => Navigator.of(context).pop(entry.$2),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            strings.localized(
              en: 'Close',
              ja: '\u9589\u3058\u308b',
              zh: '\u5173\u95ed',
              ko: '\ub2eb\uae30',
              es: 'Cerrar',
              de: 'Schliessen',
            ),
          ),
        ),
      ],
    ),
  );
  if (selected != null && context.mounted) {
    await _showReleaseNotesDialog(context, selected);
  }
}

class _ReleaseNoteHistoryTile extends StatelessWidget {
  const _ReleaseNoteHistoryTile({
    required this.releaseNote,
    required this.currentVersion,
    required this.locale,
    required this.currentVersionLabel,
    required this.onTap,
  });

  final ReleaseNote releaseNote;
  final String? currentVersion;
  final Locale locale;
  final String currentVersionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCurrent = releaseNote.version == currentVersion;
    final dateLabel = releaseNote.date == null
        ? null
        : MaterialLocalizations.of(context).formatMediumDate(releaseNote.date!);
    final summary = releaseNote.localizedSummary(locale);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        [
          releaseNote.version,
          releaseNote.localizedTitle(locale),
        ].where((value) => value.isNotEmpty).join(' - '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [?dateLabel, if (summary.isNotEmpty) summary].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isCurrent
          ? Tooltip(
              message: currentVersionLabel,
              child: Icon(
                Icons.check_circle_outline,
                color: colorScheme.primary,
              ),
            )
          : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

IconData _releaseNoteItemIcon(ReleaseNoteItemType type) {
  return switch (type) {
    ReleaseNoteItemType.feature => Icons.auto_awesome_outlined,
    ReleaseNoteItemType.improvement => Icons.tune_outlined,
    ReleaseNoteItemType.fix => Icons.build_circle_outlined,
    ReleaseNoteItemType.security => Icons.verified_user_outlined,
  };
}

Future<void> _showProfileAccessDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = context.strings;
  final activeLabel = ref.read(activePrivateProfileLabelProvider);
  final adminMode = ref.read(adminModeSessionControllerProvider);
  final result = await showDialog<_ProfileAccessDialogResult>(
    context: context,
    builder: (_) =>
        _ProfileAccessDialog(adminMode: adminMode, activeLabel: activeLabel),
  );
  if (result == null || !context.mounted) {
    return;
  }
  if (result.createProfile) {
    await _showAddPrivateProfileDialogFromHeader(context, ref);
    return;
  }
  final password = result.password;
  if (password == null || password.isEmpty) {
    return;
  }
  final unlocked = await ref
      .read(privateProfileUnlockControllerProvider.notifier)
      .unlockWithPassword(password);
  if (!context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      showCloseIcon: true,
      content: Text(
        unlocked == null
            ? (strings.text('home.no.private.profile.matched.that.password'))
            : (strings.text('home.private.profile.unlocked')),
      ),
    ),
  );
}

Future<void> _showAddPrivateProfileDialogFromHeader(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = context.strings;
  final draft = await showDialog<_PrivateProfileDraft>(
    context: context,
    builder: (_) => const _AddPrivateProfileDialog(),
  );
  if (draft == null) {
    return;
  }
  final error = await ref
      .read(privateMemoProfilesControllerProvider.notifier)
      .addProfile(name: draft.name, password: draft.password);
  if (error == null) {
    await ref
        .read(privateProfileUnlockControllerProvider.notifier)
        .unlockWithPassword(draft.password);
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      showCloseIcon: true,
      content: Text(
        error ?? (strings.text('home.private.profile.added.and.opened')),
      ),
    ),
  );
}

class _ProfileAccessDialogResult {
  const _ProfileAccessDialogResult._({
    this.password,
    this.createProfile = false,
  });

  const _ProfileAccessDialogResult.unlock(String password)
    : this._(password: password);

  const _ProfileAccessDialogResult.createProfile()
    : this._(createProfile: true);

  final String? password;
  final bool createProfile;
}

class _ProfileAccessDialog extends ConsumerStatefulWidget {
  const _ProfileAccessDialog({
    required this.adminMode,
    required this.activeLabel,
  });

  final bool adminMode;
  final String? activeLabel;

  @override
  ConsumerState<_ProfileAccessDialog> createState() =>
      _ProfileAccessDialogState();
}

class _ProfileAccessDialogState extends ConsumerState<_ProfileAccessDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(
        context,
      ).pop(_ProfileAccessDialogResult.unlock(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final hasActiveAccess = widget.adminMode || widget.activeLabel != null;
    return AlertDialog(
      title: Text(
        hasActiveAccess
            ? (strings.text('home.switch.private.access'))
            : (strings.text('home.unlock.private.profile.2')),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasActiveAccess) ...[
                Text(
                  widget.adminMode
                      ? (strings.text('home.admin.mode.is.currently.active'))
                      : strings.currentPrivateProfile(widget.activeLabel),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('private-profile-unlock-password-input'),
                controller: _controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: strings.text('home.profile.password'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? (strings.text('home.enter.a.password'))
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (hasActiveAccess)
          TextButton(
            onPressed: () {
              ref.read(adminModeSessionControllerProvider.notifier).lock();
              ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
              Navigator.of(context).pop();
            },
            child: Text(strings.text('home.lock.private.access')),
          ),
        TextButton(
          key: const Key('private-profile-unlock-create-profile'),
          onPressed: () => Navigator.of(
            context,
          ).pop(const _ProfileAccessDialogResult.createProfile()),
          child: Text(strings.text('home.add.private.profile')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const Key('private-profile-unlock-submit'),
          onPressed: _submit,
          child: Text(strings.text('home.unlock')),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime value, AppStrings strings) {
  final normalized = strings.isJapanese
      ? value.toUtc().add(const Duration(hours: 9))
      : value.toUtc();
  final year = normalized.year.toString().padLeft(4, '0');
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  final hour = normalized.hour.toString().padLeft(2, '0');
  final minute = normalized.minute.toString().padLeft(2, '0');
  final zone = strings.isJapanese ? 'JST' : 'UTC';
  return '$year/$month/$day $hour:$minute $zone';
}

String _displayNoteTag(BuildContext context, String tag) {
  final strings = context.strings;
  if (isSystemSyncExclusionTag(tag)) {
    return strings.localized(
      en: 'Local only',
      ja: '\u3053\u306e\u7aef\u672b\u306e\u307f',
      zh: '\u4ec5\u6b64\u8bbe\u5907',
      ko: '\uc774 \uae30\uae30\uc5d0\ub9cc',
      es: 'Solo este dispositivo',
      de: 'Nur dieses Geraet',
    );
  }
  return tag;
}

String _displayNoteTagWithHash(BuildContext context, String tag) =>
    '#${_displayNoteTag(context, tag)}';

Future<String?> _showPinSetupDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _PinSetupDialog(title: title, confirmLabel: confirmLabel),
  );
}

String _spotlightAppLockWarningText(AppStrings strings) {
  return strings.localized(
    en: 'App lock does not hide notes from iOS Spotlight. If Spotlight indexing is enabled, standard note titles and text can appear in system search results before HiMemo is unlocked.',
    ja: 'アプリロックはiOS Spotlight上のメモを隠しません。Spotlight検索を許可すると、HiMemoのロック解除前でも標準メモのタイトルや本文がシステム検索結果に表示される場合があります。',
    zh: 'App lock does not hide notes from iOS Spotlight. If Spotlight indexing is enabled, standard note titles and text can appear in system search results before HiMemo is unlocked.',
    ko: 'App lock does not hide notes from iOS Spotlight. If Spotlight indexing is enabled, standard note titles and text can appear in system search results before HiMemo is unlocked.',
    es: 'App lock does not hide notes from iOS Spotlight. If Spotlight indexing is enabled, standard note titles and text can appear in system search results before HiMemo is unlocked.',
    de: 'App lock does not hide notes from iOS Spotlight. If Spotlight indexing is enabled, standard note titles and text can appear in system search results before HiMemo is unlocked.',
  );
}

class _DeleteNoteDialogResult {
  const _DeleteNoteDialogResult({required this.deletePermanently});

  final bool deletePermanently;
}

Future<_DeleteNoteDialogResult?> _showDeleteNoteDialog(
  BuildContext context,
  NoteEntry note,
) {
  final strings = context.strings;
  var deletePermanently = false;
  return showDialog<_DeleteNoteDialogResult>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              deletePermanently
                  ? strings.deletePermanently
                  : strings.moveNoteToTrash,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deletePermanently
                      ? strings.deleteNoteConfirmation(note.title)
                      : strings.moveNoteToTrashConfirmation(note.title),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: deletePermanently,
                  title: Text(strings.deletePermanently),
                  subtitle: Text(strings.deletePermanentlyOptionDescription),
                  onChanged: (value) {
                    setDialogState(() {
                      deletePermanently = value ?? false;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                key: const Key('delete-note-button'),
                onPressed: () => Navigator.of(context).pop(
                  _DeleteNoteDialogResult(deletePermanently: deletePermanently),
                ),
                child: Text(
                  deletePermanently
                      ? strings.deletePermanently
                      : strings.moveNoteToTrash,
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showSpotlightAppLockWarningDialog(
  BuildContext context,
  AppStrings strings,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: Text(
        strings.localized(
          en: 'Spotlight may show locked notes',
          ja: 'Spotlightにロック中のメモが表示される場合があります',
          zh: 'Spotlight may show locked notes',
          ko: 'Spotlight may show locked notes',
          es: 'Spotlight may show locked notes',
          de: 'Spotlight may show locked notes',
        ),
      ),
      content: Text(_spotlightAppLockWarningText(strings)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
    ),
  );
}

BoxDecoration _sectionDecoration(BuildContext context) {
  return BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: Theme.of(context).dividerColor),
  );
}

Color _selectedSurfaceColor(BuildContext context) {
  return Theme.of(context).colorScheme.surfaceContainerHighest;
}

Color _mutedTextColor(BuildContext context) {
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

Color _strongMutedTextColor(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.82);
}

IconData _iconForAttachment(AttachmentType type) {
  switch (type) {
    case AttachmentType.photo:
      return Icons.photo_outlined;
    case AttachmentType.video:
      return Icons.videocam_outlined;
    case AttachmentType.audio:
      return Icons.mic_none_rounded;
    case AttachmentType.file:
      return Icons.insert_drive_file_outlined;
  }
}
