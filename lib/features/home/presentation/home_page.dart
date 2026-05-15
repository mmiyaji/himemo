import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import '../../../l10n/app_strings.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/encryption_service.dart';
import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/google_sign_in_initializer.dart';
import '../../sync/data/sync_bundle_preview.dart';
import '../../sync/data/sync_bundle_state_store.dart';
import '../../sync/data/sync_bundle_key_service.dart';
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
const _remoteSyncAttachmentObjectPrefix = 'sync-attachment-object://';

enum AppSection { notes, calendar, insights, trash, settings }

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
  DateTime? _suppressProfileAccessUntil;
  Timer? _profileAccessSuppressionTimer;

  @override
  void initState() {
    super.initState();
    _noteOverlaySheetDepth.addListener(_handleNoteOverlayChanged);
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

    return Scaffold(
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
  }

  int _bottomNavIndexForSection(AppSection section) {
    return switch (section) {
      AppSection.notes => 0,
      AppSection.calendar => 1,
      AppSection.insights => 3,
      AppSection.trash => 4,
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
    if (location.startsWith('/settings')) {
      return AppSection.settings;
    }
    return AppSection.notes;
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
    return showDialog<void>(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(syncTransferControllerProvider);
            final provider = ref.watch(syncProviderControllerProvider);
            final label = _syncProgressLabel(strings, state);
            final description = _syncProgressDescription(
              strings,
              state,
              provider,
            );
            final itemProgress = _syncProgressItemProgressText(strings, state);
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
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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

Future<void> _showProfileAccessDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final strings = context.strings;
  final activeLabel = ref.read(activePrivateProfileLabelProvider);
  final adminMode = ref.read(adminModeSessionControllerProvider);
  final result = await showDialog<String>(
    context: context,
    builder: (_) =>
        _ProfileAccessDialog(adminMode: adminMode, activeLabel: activeLabel),
  );
  if (result == null || result.isEmpty || !context.mounted) {
    return;
  }
  final unlocked = await ref
      .read(privateProfileUnlockControllerProvider.notifier)
      .unlockWithPassword(result);
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
      Navigator.of(context).pop(_controller.text);
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
