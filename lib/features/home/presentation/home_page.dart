import 'dart:async';
import 'dart:convert';
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

    return Scaffold(
      appBar: AppBar(
        title: const _AppBrandTitle(),
        actions: [
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
                String bottomNavLabel(String label) =>
                    hideBottomNavLabels ? '' : label;
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

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  static const double _defaultSplitListFraction = 5 / 11;
  static const double _narrowSplitListFraction = 0.36;
  static const double _wideSplitListFraction = 0.58;
  static const double _minSplitListWidth = 320;
  static const double _maxSplitListFraction = 0.62;

  double _splitListFraction = _defaultSplitListFraction;

  void _resizeSplitList(double delta, double availableWidth) {
    if (availableWidth <= 0) {
      return;
    }
    final currentWidth = availableWidth * _splitListFraction;
    final minWidth = math.min(_minSplitListWidth, availableWidth * 0.45);
    final maxWidth = math.max(minWidth, availableWidth * _maxSplitListFraction);
    setState(() {
      _splitListFraction =
          (currentWidth + delta).clamp(minWidth, maxWidth) / availableWidth;
    });
  }

  void _cycleSplitListWidth(double availableWidth) {
    if (availableWidth <= 0) {
      return;
    }
    setState(() {
      if (_splitListFraction < _defaultSplitListFraction - 0.02) {
        _splitListFraction = _defaultSplitListFraction;
      } else if (_splitListFraction < _wideSplitListFraction - 0.02) {
        _splitListFraction = _wideSplitListFraction;
      } else {
        _splitListFraction = _narrowSplitListFraction;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width;
    final useSplitView = width >= 1180;
    final useCompactHeader =
        !useSplitView && width < 720 && screenSize.height > screenSize.width;
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final privateVaultUnlocked = ref.watch(
      privateVaultSessionControllerProvider,
    );
    final visibleNotes = ref.watch(visibleNotesProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final vaultNameById = {
      for (final vault in visibleVaults)
        vault.id: _vaultDisplayName(context, vault),
    };
    final listDensity = ref.watch(notesListDensityControllerProvider);
    final sortField = ref.watch(notesListSortControllerProvider);
    final attachmentPreviewFit = ref.watch(
      attachmentPreviewFitControllerProvider,
    );
    final query = ref.watch(searchQueryProvider).trim();
    final selectedNoteId = ref.watch(selectedNoteIdProvider);
    final syncProvider = ref.watch(syncProviderControllerProvider);

    if (!useSplitView) {
      return _MobileNotesList(
        activeIdentity: activeIdentity,
        showPrivateVaultNotice:
            activeIdentity.id == 'private' && !privateVaultUnlocked,
        compactHeader: useCompactHeader,
        vaultNameById: vaultNameById,
        showVaultName: visibleVaults.length > 1,
        allVisibleNotes: visibleNotes,
        selectedNoteId: selectedNoteId,
        density: listDensity,
        sortField: sortField,
        attachmentPreviewFit: attachmentPreviewFit,
        query: query,
        onRefresh: syncProvider == SyncProvider.off
            ? null
            : () => _refreshNotesFromCloud(context),
        onNoteSelected: (note) =>
            _openMobileNoteActions(context, note, visibleNotes),
      );
    }

    final visibleNoteIndexById = ref.watch(visibleNoteIndexByIdProvider);
    final selectedIndex = selectedNoteId == null
        ? -1
        : (visibleNoteIndexById[selectedNoteId] ?? -1);
    final effectiveSelectedNoteId = selectedNoteId != null && selectedIndex >= 0
        ? selectedNoteId
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final minWidth = math.min(_minSplitListWidth, availableWidth * 0.45);
        final maxWidth = math.max(
          minWidth,
          availableWidth * _maxSplitListFraction,
        );
        final listWidth = (availableWidth * _splitListFraction).clamp(
          minWidth,
          maxWidth,
        );
        return Row(
          children: [
            SizedBox(
              width: listWidth,
              child: _SplitNotesListPane(
                activeIdentity: activeIdentity,
                showPrivateVaultNotice:
                    activeIdentity.id == 'private' && !privateVaultUnlocked,
                notes: visibleNotes,
                selectedNoteId: effectiveSelectedNoteId,
                vaultNameById: vaultNameById,
                showVaultName: visibleVaults.length > 1,
                density: listDensity,
                sortField: sortField,
                attachmentPreviewFit: attachmentPreviewFit,
                query: query,
                onAddNote: () => showNoteEditorSheet(context, ref),
                onRefresh: syncProvider == SyncProvider.off
                    ? null
                    : () => _refreshNotesFromCloud(context),
                onNoteSelected: (note) {
                  _debugNotePerf('select split-list ${_notePerfLabel(note)}');
                  ref.read(selectedNoteIdProvider.notifier).select(note.id);
                },
              ),
            ),
            _SplitPaneResizeHandle(
              onDragDelta: (delta) => _resizeSplitList(delta, availableWidth),
              onTap: () => _cycleSplitListWidth(availableWidth),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: visibleNotes.isEmpty
                    ? const _EmptyNotesState()
                    : selectedIndex < 0
                    ? const _EmptyNoteSelectionState()
                    : _StaticNoteDetailView(
                        notes: visibleNotes,
                        selectedIndex: selectedIndex,
                        onSelected: (index) => ref
                            .read(selectedNoteIdProvider.notifier)
                            .select(visibleNotes[index].id),
                        onEdit: (note) =>
                            showNoteEditorSheet(context, ref, note: note),
                        onDelete: (note) => _deleteNote(context, note),
                        onTagTap: (tag) => _applyTagFilter(context, tag),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openMobileNoteActions(
    BuildContext context,
    NoteEntry note,
    List<NoteEntry> visibleNotes,
  ) async {
    _debugNotePerf('open mobile detail ${_notePerfLabel(note)}');
    final hostContext = context;
    final initialIndex = visibleNotes.indexWhere(
      (entry) => entry.id == note.id,
    );
    BuildContext? sheetContextForClose;
    void handleCloseRequest() {
      final sheetContext = sheetContextForClose;
      if (sheetContext != null && sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
    }

    _pushNoteOverlaySheet();
    _pushMobileNoteDetailSheet();
    _mobileNoteDetailCloseRequests.addListener(handleCloseRequest);
    try {
      await showModalBottomSheet<void>(
        context: hostContext,
        isScrollControlled: true,
        showDragHandle: false,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (sheetContext) {
          sheetContextForClose = sheetContext;
          final mediaQuery = MediaQuery.of(sheetContext);
          return LayoutBuilder(
            builder: (context, constraints) {
              final sheetHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : mediaQuery.size.height;
              return SizedBox(
                height: sheetHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                  child: _NoteDetailPager(
                    notes: visibleNotes,
                    selectedIndex: initialIndex < 0 ? 0 : initialIndex,
                    onPageChanged: (index) => ref
                        .read(selectedNoteIdProvider.notifier)
                        .select(visibleNotes[index].id),
                    onEdit: (selectedNote) async {
                      Navigator.of(sheetContext).pop();
                      await showNoteEditorSheet(
                        hostContext,
                        ref,
                        note: selectedNote,
                      );
                    },
                    onDelete: (selectedNote) async {
                      Navigator.of(sheetContext).pop();
                      await _deleteNote(hostContext, selectedNote);
                    },
                    onClose: () => Navigator.of(sheetContext).pop(),
                    onTagTap: (tag) {
                      Navigator.of(sheetContext).pop();
                      _applyTagFilter(hostContext, tag);
                    },
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _mobileNoteDetailCloseRequests.removeListener(handleCloseRequest);
      _popMobileNoteDetailSheet();
      _popNoteOverlaySheet();
    }
  }

  Future<void> _refreshNotesFromCloud(BuildContext context) async {
    final strings = context.strings;
    final warning = await ref
        .read(syncTransferControllerProvider.notifier)
        .largeMobileTransferWarning(includeUpload: true, includeDownload: true);
    if (!context.mounted) {
      return;
    }
    final confirmed = warning == null
        ? true
        : await _showLargeMobileSyncConfirmDialog(context, warning) ?? false;
    if (!confirmed || !context.mounted) {
      return;
    }
    await ref
        .read(syncTransferControllerProvider.notifier)
        .syncNow(allowLargeMobileTransfer: true);
    if (!context.mounted) {
      return;
    }
    final syncProvider = ref.read(syncProviderControllerProvider);
    if (syncProvider == SyncProvider.off) {
      return;
    }
    final message = _cloudSyncSnackBarMessage(
      strings,
      ref.read(syncTransferControllerProvider),
      _CloudSyncSnackBarAction.syncNow,
      syncProvider,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
  }

  Future<void> _deleteNote(BuildContext context, NoteEntry note) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.deleteNote),
          content: Text(strings.deleteNoteConfirmation(note.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const Key('delete-note-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.delete),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(notesControllerProvider.notifier).delete(note.id);
      if (ref.read(selectedNoteIdProvider) == note.id) {
        ref.read(selectedNoteIdProvider.notifier).select(null);
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(strings.noteDeleted(note.title)),
          action: SnackBarAction(
            label: strings.undo,
            onPressed: () {
              ref
                  .read(notesControllerProvider.notifier)
                  .upsert(
                    note.copyWith(
                      deletedAt: null,
                      syncState: NoteSyncState.pendingUpload,
                      updatedAt: DateTime.now(),
                      revision: note.revision + 1,
                    ),
                  );
            },
          ),
        ),
      );
    }
  }

  void _applyTagFilter(BuildContext context, String tag) {
    ref.read(searchFiltersControllerProvider.notifier).setTags([tag]);
    ref.read(searchQueryProvider.notifier).setQuery('');
    ref.read(selectedNoteIdProvider.notifier).select(null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(context.strings.filteredByTag(tag)),
      ),
    );
  }
}

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      ref
          .read(notesControllerProvider.notifier)
          .purgeTrashOlderThan(NotesController.trashRetention);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final notes = ref.watch(trashedNotesProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final vaultNameById = {
      for (final vault in visibleVaults)
        vault.id: _vaultDisplayName(context, vault),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.localized(
            en: 'Trash',
            ja: 'ゴミ箱',
            zh: '废纸篓',
            ko: '휴지통',
            es: 'Papelera',
            de: 'Papierkorb',
          ),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          strings.localized(
            en: 'Deleted notes are hidden from normal lists, search, and Spotlight. Notes older than 7 days are permanently deleted with their attachments.',
            ja: '削除したメモは通常の一覧、検索、Spotlightから除外されます。7日を過ぎたメモは添付と一緒に完全削除されます。',
            zh: '已删除的备忘录不会出现在普通列表、搜索和 Spotlight 中。超过 7 天的备忘录及其附件会被永久删除。',
            ko: '삭제한 메모는 일반 목록, 검색, Spotlight에서 제외됩니다. 7일이 지난 메모는 첨부와 함께 완전히 삭제됩니다.',
            es: 'Las notas eliminadas se ocultan de las listas normales, busqueda y Spotlight. Tras 7 dias se borran definitivamente con sus adjuntos.',
            de: 'Geloeschte Notizen werden aus normalen Listen, Suche und Spotlight ausgeblendet. Nach 7 Tagen werden sie mit ihren Anhaengen endgueltig geloescht.',
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          _EmptyTrashState(strings: strings)
        else
          for (final note in notes) ...[
            _TrashNoteTile(
              note: note,
              vaultName: vaultNameById[note.vaultId],
              onRestore: () => _restoreNote(context, note),
              onDeletePermanently: () => _deletePermanently(context, note),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _restoreNote(BuildContext context, NoteEntry note) async {
    final strings = context.strings;
    await ref.read(notesControllerProvider.notifier).restoreFromTrash(note.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Restored note.',
            ja: 'メモを復元しました。',
            zh: '已恢复备忘录。',
            ko: '메모를 복원했습니다.',
            es: 'Nota restaurada.',
            de: 'Notiz wiederhergestellt.',
          ),
        ),
      ),
    );
  }

  Future<void> _deletePermanently(BuildContext context, NoteEntry note) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.localized(
            en: 'Delete permanently?',
            ja: '完全に削除しますか？',
            zh: '要永久删除吗？',
            ko: '완전히 삭제할까요?',
            es: 'Borrar definitivamente?',
            de: 'Endgueltig loeschen?',
          ),
        ),
        content: Text(
          strings.localized(
            en: 'This removes the note and its attachments from this device. This cannot be undone.',
            ja: 'この端末からメモと添付を削除します。この操作は元に戻せません。',
            zh: '这会从此设备删除备忘录及其附件。此操作无法撤销。',
            ko: '이 기기에서 메모와 첨부를 삭제합니다. 이 작업은 되돌릴 수 없습니다.',
            es: 'Esto elimina la nota y sus adjuntos de este dispositivo. No se puede deshacer.',
            de: 'Dies entfernt die Notiz und ihre Anhaenge von diesem Geraet. Das kann nicht rueckgaengig gemacht werden.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(notesControllerProvider.notifier).deletePermanently(note.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Deleted permanently.',
            ja: '完全に削除しました。',
            zh: '已永久删除。',
            ko: '완전히 삭제했습니다.',
            es: 'Borrada definitivamente.',
            de: 'Endgueltig geloescht.',
          ),
        ),
      ),
    );
  }
}

class _GoogleDriveWebSignInPanel extends ConsumerStatefulWidget {
  const _GoogleDriveWebSignInPanel();

  @override
  ConsumerState<_GoogleDriveWebSignInPanel> createState() =>
      _GoogleDriveWebSignInPanelState();
}

class _GoogleDriveWebSignInPanelState
    extends ConsumerState<_GoogleDriveWebSignInPanel> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await GoogleSignInInitializer.ensureInitialized(
        ref.read(googleDriveAuthConfigProvider),
      );
      _subscription = GoogleSignIn.instance.authenticationEvents.listen(
        _handleAuthenticationEvent,
        onError: _handleAuthenticationError,
      );
      GoogleSignIn.instance.attemptLightweightAuthentication();
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = false;
        _error = error is GoogleDriveAuthConfigurationException
            ? error.message
            : error;
      });
    }
  }

  Future<void> _handleAuthenticationEvent(
    GoogleSignInAuthenticationEvent event,
  ) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(user: final user):
        await ref
            .read(syncAuthControllerProvider.notifier)
            .completeGoogleDriveWebAuthentication(user);
      case GoogleSignInAuthenticationEventSignOut():
        await ref
            .read(syncAuthControllerProvider.notifier)
            .disconnect(SyncProvider.googleDrive);
    }
  }

  void _handleAuthenticationError(Object error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    final error = _error;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.googleDriveWebSignInTitle,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            strings.googleDriveWebSignInBody,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_ready)
            buildGoogleSignInWebButton(locale: strings.locale.languageCode)
          else
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              '$error',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
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
