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

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _collapsedDayNoteLimit = 24;

  DateTime _selectedDay = DateTime.now();
  late DateTime _visibleMonth;
  bool _dayNotesExpanded = false;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final noteDays = ref.watch(unfilteredVisibleNoteDaysProvider);
    final notesByDay = ref.watch(unfilteredVisibleNotesByDayProvider);
    final markedDays = noteDays.toSet();
    final sameDayNotes =
        notesByDay[_calendarDayKey(_selectedDay)] ?? const <NoteEntry>[];
    final shouldCollapseDayNotes = sameDayNotes.length > _collapsedDayNoteLimit;
    final visibleDayNoteCount = shouldCollapseDayNotes && !_dayNotesExpanded
        ? _collapsedDayNoteLimit
        : sameDayNotes.length;
    final previousDay = _adjacentNoteDay(
      noteDays,
      _selectedDay,
      backwards: true,
    );
    final nextDay = _adjacentNoteDay(noteDays, _selectedDay, backwards: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: _sectionDecoration(context),
          padding: const EdgeInsets.all(12),
          child: _MarkedCalendar(
            visibleMonth: _visibleMonth,
            selectedDay: _selectedDay,
            markedDays: markedDays,
            onPreviousMonth: () {
              setState(() {
                _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month - 1,
                );
              });
            },
            onNextMonth: () {
              setState(() {
                _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month + 1,
                );
              });
            },
            onTodaySelected: () {
              final today = DateTime.now();
              setState(() {
                _selectedDay = today;
                _visibleMonth = DateTime(today.year, today.month);
                _dayNotesExpanded = false;
              });
            },
            onDateSelected: (date) {
              setState(() {
                _selectedDay = date;
                _visibleMonth = DateTime(date.year, date.month);
                _dayNotesExpanded = false;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: _sectionDecoration(context),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: previousDay == null
                        ? null
                        : () => _selectCalendarDay(previousDay),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: strings.text('home.previous.day.with.notes'),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${_selectedDay.year}/${_selectedDay.month.toString().padLeft(2, '0')}/${_selectedDay.day.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => showNoteEditorSheet(
                      context,
                      ref,
                      initialCreatedAt: _selectedDateWithCurrentTime(),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    tooltip: strings.addNote,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: nextDay == null
                        ? null
                        : () => _selectCalendarDay(nextDay),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: strings.text('home.next.day.with.notes'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (sameDayNotes.isEmpty)
                Text(
                  strings.text('home.no.notes.on.this.day.yet'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                )
              else
                _CalendarDayNotesList(
                  notes: sameDayNotes,
                  itemCount: visibleDayNoteCount,
                  expanded: _dayNotesExpanded,
                  onTap: (index) => _openCalendarNoteDetails(
                    context,
                    noteDays,
                    notesByDay,
                    _selectedDay,
                    index,
                  ),
                ),
              if (shouldCollapseDayNotes) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _dayNotesExpanded = !_dayNotesExpanded;
                      });
                    },
                    icon: Icon(
                      _dayNotesExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(
                      _dayNotesExpanded
                          ? strings.localized(
                              en: 'Show fewer notes',
                              ja: '表示件数を減らす',
                              zh: '显示较少笔记',
                              ko: '노트 적게 표시',
                              es: 'Mostrar menos notas',
                              de: 'Weniger Notizen anzeigen',
                            )
                          : strings.localized(
                              en: 'Show all ${sameDayNotes.length} notes',
                              ja: '${sameDayNotes.length}件すべて表示',
                              zh: '显示全部 ${sameDayNotes.length} 条笔记',
                              ko: '노트 ${sameDayNotes.length}개 모두 표시',
                              es: 'Mostrar las ${sameDayNotes.length} notas',
                              de: 'Alle ${sameDayNotes.length} Notizen anzeigen',
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  DateTime _calendarDayKey(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _selectedDateWithCurrentTime() {
    final now = DateTime.now();
    return DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      now.hour,
      now.minute,
    );
  }

  DateTime? _adjacentNoteDay(
    List<DateTime> noteDays,
    DateTime currentDay, {
    required bool backwards,
  }) {
    if (noteDays.isEmpty) {
      return null;
    }
    if (backwards) {
      for (var i = noteDays.length - 1; i >= 0; i -= 1) {
        if (noteDays[i].isBefore(currentDay)) {
          return noteDays[i];
        }
      }
      return null;
    }
    for (final day in noteDays) {
      if (day.isAfter(currentDay)) {
        return day;
      }
    }
    return null;
  }

  void _selectCalendarDay(DateTime day) {
    setState(() {
      _selectedDay = day;
      _visibleMonth = DateTime(day.year, day.month);
      _dayNotesExpanded = false;
    });
  }

  Future<void> _openCalendarNoteDetails(
    BuildContext context,
    List<DateTime> noteDays,
    Map<DateTime, List<NoteEntry>> notesByDay,
    DateTime initialDay,
    int initialIndex,
  ) async {
    final hostContext = context;
    final strings = context.strings;
    await showModalBottomSheet<void>(
      context: hostContext,
      isScrollControlled: true,
      showDragHandle: false,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        var selectedDay = DateTime(
          initialDay.year,
          initialDay.month,
          initialDay.day,
        );
        var selectedIndex = initialIndex;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final dayNotes =
                notesByDay[_calendarDayKey(selectedDay)] ?? const <NoteEntry>[];
            if (dayNotes.isEmpty) {
              return const SizedBox.shrink();
            }
            if (selectedIndex >= dayNotes.length) {
              selectedIndex = dayNotes.length - 1;
            }
            final previousDay = _adjacentNoteDay(
              noteDays,
              selectedDay,
              backwards: true,
            );
            final nextDay = _adjacentNoteDay(
              noteDays,
              selectedDay,
              backwards: false,
            );
            return SizedBox(
              height: mediaQuery.size.height,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: previousDay == null
                              ? null
                              : () {
                                  setModalState(() {
                                    selectedDay = previousDay;
                                    selectedIndex = 0;
                                  });
                                },
                          icon: const Icon(Icons.chevron_left_rounded),
                          tooltip: strings.text(
                            'home.previous.day.with.notes.2',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Text(
                            '${selectedDay.year}/${selectedDay.month.toString().padLeft(2, '0')}/${selectedDay.day.toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: nextDay == null
                              ? null
                              : () {
                                  setModalState(() {
                                    selectedDay = nextDay;
                                    selectedIndex = 0;
                                  });
                                },
                          icon: const Icon(Icons.chevron_right_rounded),
                          tooltip: strings.text('home.next.day.with.notes.2'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    Expanded(
                      child: _NoteDetailPager(
                        notes: dayNotes,
                        selectedIndex: selectedIndex,
                        onPageChanged: (index) {
                          setModalState(() {
                            selectedIndex = index;
                          });
                        },
                        onEdit: (selectedNote) async {
                          Navigator.of(context).pop();
                          await showNoteEditorSheet(
                            hostContext,
                            ref,
                            note: selectedNote,
                          );
                        },
                        onDelete: (selectedNote) async {
                          Navigator.of(context).pop();
                          final confirmed = await showDialog<bool>(
                            context: hostContext,
                            builder: (context) => AlertDialog(
                              title: Text(strings.text('home.delete.note')),
                              content: Text(
                                strings.deleteNoteConfirmation(
                                  selectedNote.title,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: Text(strings.cancel),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: Text(strings.text('home.delete')),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await ref
                                .read(notesControllerProvider.notifier)
                                .delete(selectedNote.id);
                          }
                        },
                        onClose: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MarkedCalendar extends StatelessWidget {
  const _MarkedCalendar({
    required this.visibleMonth,
    required this.selectedDay,
    required this.markedDays,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onTodaySelected,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final Set<DateTime> markedDays;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onTodaySelected;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final weekdays = strings.weekdayShortLabels;
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leadingEmpty = (firstDay.weekday + 6) % 7;
    final totalCells = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;
    final monthLabel =
        '${visibleMonth.year}/${visibleMonth.month.toString().padLeft(2, '0')}';
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onPreviousMonth,
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: strings.text('home.previous.month'),
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(onPressed: onTodaySelected, child: Text(strings.today)),
            IconButton(
              onPressed: onNextMonth,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: strings.text('home.next.month'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final weekday in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    weekday,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < totalCells / 7; row++) ...[
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final index = row * 7 + column;
                      final dayNumber = index - leadingEmpty + 1;
                      if (dayNumber < 1 || dayNumber > daysInMonth) {
                        return const SizedBox(height: 44);
                      }

                      final date = DateTime(
                        visibleMonth.year,
                        visibleMonth.month,
                        dayNumber,
                      );
                      final isSelected = _isSameDay(date, selectedDay);
                      final isToday = _isSameDay(date, DateTime.now());
                      final hasNote = markedDays.contains(date);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 2,
                          horizontal: 1,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onDateSelected(date),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isToday
                                  ? Border.all(color: colorScheme.primary)
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dayNumber.toString(),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: hasNote
                                        ? (isSelected
                                              ? colorScheme.primary
                                              : colorScheme.secondary)
                                        : Colors.transparent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          if (row != totalCells / 7 - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  List<NoteEntry>? _cachedNotes;
  Locale? _cachedLocale;
  _InsightsData? _cachedInsights;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final notes = ref.watch(unfilteredVisibleNotesProvider);
    final locale = Localizations.localeOf(context);
    var insights = _cachedInsights;
    if (insights == null ||
        !identical(_cachedNotes, notes) ||
        _cachedLocale != locale) {
      insights = _buildInsightsData(context, notes);
      _cachedNotes = notes;
      _cachedLocale = locale;
      _cachedInsights = insights;
    }
    final summary = insights.summary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: _sectionDecoration(context),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('home.writing.activity'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                summary.message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _strongMutedTextColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InsightsSummaryGrid(summary: summary),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.text('home.monthly.notes'),
          description: strings.text(
            'home.notes.created.over.the.last.6.months',
          ),
          child: _InsightLineChart(
            buckets: insights.monthlyBuckets,
            valueSuffix: strings.text('home.notes'),
          ),
        ),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.text('home.recent.days'),
          description: strings.text(
            'home.daily.note.count.over.the.last.14.days',
          ),
          child: _InsightBarChart(
            buckets: insights.recentDayBuckets,
            valueSuffix: strings.text('home.notes'),
          ),
        ),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.text('home.weekday.and.time.rhythm'),
          description: strings.text(
            'home.notes.by.weekday.and.3.hour.time.block',
          ),
          child: _WeekdayHourHistogram(
            buckets: insights.weekdayHourBuckets,
            valueSuffix: strings.text('home.notes'),
          ),
        ),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.text('home.attachments'),
          description: strings.text(
            'home.how.often.photos.videos.and.audio.are.used',
          ),
          child: _InsightHorizontalBarChart(
            buckets: insights.attachmentBuckets,
            valueSuffix: strings.text('home.items'),
          ),
        ),
      ],
    );
  }
}

class _InsightsSummaryGrid extends StatelessWidget {
  const _InsightsSummaryGrid({required this.summary});

  final _InsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      child: Wrap(
        children: [
          _InsightKpiTile(
            label: strings.text('home.current.streak'),
            value: '${summary.currentStreak}',
            helper: strings.text('home.days'),
          ),
          _InsightKpiTile(
            label: strings.text('home.this.month'),
            value: '${summary.thisMonthCount}',
            helper: strings.text('home.notes.2'),
          ),
          _InsightKpiTile(
            label: strings.text('home.characters'),
            value: '${summary.totalCharacters}',
            helper: strings.text('home.total'),
          ),
          _InsightKpiTile(
            label: strings.text('home.attachments'),
            value: '${summary.totalAttachments}',
            helper: strings.text('home.items.2'),
          ),
          _InsightKpiTile(
            label: strings.text('home.best.day'),
            value: summary.bestDayLabel,
            helper: strings.notesCount(summary.bestDayValue),
          ),
          _InsightKpiTile(
            label: strings.text('home.best.hour'),
            value: summary.bestHourLabel,
            helper: strings.text('home.peak.time'),
          ),
          _InsightKpiTile(
            label: strings.text('home.monthly.trend'),
            value: summary.monthlyDeltaLabel,
            helper: strings.text('home.vs.last.month'),
          ),
        ],
      ),
    );
  }
}

class _InsightKpiTile extends StatelessWidget {
  const _InsightKpiTile({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width < 560
          ? (MediaQuery.sizeOf(context).width - 64) / 2
          : 220,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _mutedTextColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    helper,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightChartSection extends StatelessWidget {
  const _InsightChartSection({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InsightBarChart extends StatefulWidget {
  const _InsightBarChart({required this.buckets, required this.valueSuffix});

  final List<_InsightBucket> buckets;
  final String valueSuffix;

  @override
  State<_InsightBarChart> createState() => _InsightBarChartState();
}

class _InsightBarChartState extends State<_InsightBarChart> {
  final ScrollController _scrollController = ScrollController();
  Object? _lastScrolledBuckets;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToLatest();
  }

  @override
  void didUpdateWidget(covariant _InsightBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.buckets, widget.buckets)) {
      _scheduleScrollToLatest();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      if (identical(_lastScrolledBuckets, widget.buckets)) {
        return;
      }
      _lastScrolledBuckets = widget.buckets;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final buckets = widget.buckets;
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    if (buckets.isEmpty) {
      return Text(
        strings.text('home.no.data.yet'),
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        final itemWidth = math.max(44.0, (chartWidth / buckets.length) - 8);
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bucket in buckets)
                SizedBox(
                  width: itemWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${bucket.value}${widget.valueSuffix}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: _mutedTextColor(context)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 140,
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: FractionallySizedBox(
                            heightFactor: maxValue == 0
                                ? 0.04
                                : bucket.value / maxValue,
                            widthFactor: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.82),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                  bottom: Radius.circular(7),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          bucket.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InsightLineChart extends StatelessWidget {
  const _InsightLineChart({required this.buckets, required this.valueSuffix});

  final List<_InsightBucket> buckets;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return _NoInsightData();
    }
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 172,
          child: CustomPaint(
            painter: _InsightLineChartPainter(
              buckets: buckets,
              maxValue: maxValue,
              lineColor: Theme.of(context).colorScheme.primary,
              fillColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              gridColor: Theme.of(context).dividerColor,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                buckets.first.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ),
            Text(
              '${buckets.last.value}$valueSuffix',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Expanded(
              child: Text(
                buckets.last.label,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InsightLineChartPainter extends CustomPainter {
  const _InsightLineChartPainter({
    required this.buckets,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<_InsightBucket> buckets;
  final int maxValue;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final factor in const [0.25, 0.5, 0.75, 1.0]) {
      final y = size.height - size.height * factor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (buckets.isEmpty) {
      return;
    }
    final denominator = math.max(1, maxValue);
    final points = <Offset>[];
    for (var i = 0; i < buckets.length; i++) {
      final x = buckets.length == 1
          ? size.width / 2
          : size.width * i / (buckets.length - 1);
      final y = size.height - size.height * buckets[i].value / denominator;
      points.add(Offset(x, y));
    }
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final pointPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _InsightLineChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _InsightHorizontalBarChart extends StatelessWidget {
  const _InsightHorizontalBarChart({
    required this.buckets,
    required this.valueSuffix,
  });

  final List<_InsightBucket> buckets;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return _NoInsightData();
    }
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final bucket in buckets) ...[
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  bucket.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 12,
                    value: maxValue == 0 ? 0 : bucket.value / maxValue,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 68,
                child: Text(
                  '${bucket.value}$valueSuffix',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ),
            ],
          ),
          if (bucket != buckets.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _WeekdayHourHistogram extends StatelessWidget {
  const _WeekdayHourHistogram({
    required this.buckets,
    required this.valueSuffix,
  });

  final List<_WeekdayHourBucket> buckets;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return _NoInsightData();
    }
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    final strings = context.strings;
    final weekdays = strings.weekdayShortLabels;
    final timeLabels = [
      for (var hour = 0; hour < 24; hour += 3)
        '${hour.toString().padLeft(2, '0')}-${(hour + 2).toString().padLeft(2, '0')}',
    ];
    final colorScheme = Theme.of(context).colorScheme;
    final bucketByKey = {
      for (final bucket in buckets)
        '${bucket.weekday}-${bucket.startHour}': bucket,
    };

    Color cellColor(int value) {
      if (value == 0 || maxValue == 0) {
        return colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
      }
      final intensity = value / maxValue;
      return Color.lerp(
        colorScheme.primary.withValues(alpha: 0.12),
        colorScheme.primary,
        intensity.clamp(0.0, 1.0),
      )!;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        const labelWidth = 34.0;
        const gap = 4.0;
        final cellSize = ((maxWidth - labelWidth - gap * 7) / 7).clamp(
          18.0,
          30.0,
        );
        final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _mutedTextColor(context),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: labelWidth),
                for (final weekday in weekdays)
                  SizedBox(
                    width: cellSize + gap,
                    child: Text(
                      weekday,
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var row = 0; row < timeLabels.length; row++) ...[
              Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(
                      row.isEven ? timeLabels[row].substring(0, 2) : '',
                      style: labelStyle?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  for (var weekday = 1; weekday <= 7; weekday++)
                    Padding(
                      padding: const EdgeInsets.only(right: gap, bottom: gap),
                      child: _WeekdayHourCell(
                        size: cellSize,
                        value: bucketByKey['$weekday-${row * 3}']?.value ?? 0,
                        maxValue: maxValue,
                        valueSuffix: valueSuffix,
                        color: cellColor(
                          bucketByKey['$weekday-${row * 3}']?.value ?? 0,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.text('home.less'),
                  style: labelStyle?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                for (final alpha in const [0.0, 0.25, 0.5, 0.75, 1.0]) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        colorScheme.primary,
                        alpha,
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: const SizedBox(width: 10, height: 10),
                  ),
                  const SizedBox(width: 3),
                ],
                const SizedBox(width: 3),
                Text(
                  strings.text('home.more'),
                  style: labelStyle?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _WeekdayHourCell extends StatelessWidget {
  const _WeekdayHourCell({
    required this.size,
    required this.value,
    required this.maxValue,
    required this.valueSuffix,
    required this.color,
  });

  final double size;
  final int value;
  final int maxValue;
  final String valueSuffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$value$valueSuffix',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: SizedBox(width: size, height: size),
      ),
    );
  }
}

class _NoInsightData extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      context.strings.text('home.no.data.yet'),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
    );
  }
}

class _InsightBucket {
  const _InsightBucket({required this.label, required this.value});

  final String label;
  final int value;
}

class _WeekdayHourBucket {
  const _WeekdayHourBucket({
    required this.weekday,
    required this.startHour,
    required this.value,
  });

  final int weekday;
  final int startHour;
  final int value;
}

class _InsightsSummary {
  const _InsightsSummary({
    required this.currentStreak,
    required this.thisMonthCount,
    required this.totalCharacters,
    required this.totalAttachments,
    required this.bestDayLabel,
    required this.bestDayValue,
    required this.bestHourLabel,
    required this.monthlyDeltaLabel,
    required this.message,
  });

  final int currentStreak;
  final int thisMonthCount;
  final int totalCharacters;
  final int totalAttachments;
  final String bestDayLabel;
  final int bestDayValue;
  final String bestHourLabel;
  final String monthlyDeltaLabel;
  final String message;
}

class _InsightsData {
  const _InsightsData({
    required this.summary,
    required this.monthlyBuckets,
    required this.recentDayBuckets,
    required this.weekdayHourBuckets,
    required this.attachmentBuckets,
  });

  final _InsightsSummary summary;
  final List<_InsightBucket> monthlyBuckets;
  final List<_InsightBucket> recentDayBuckets;
  final List<_WeekdayHourBucket> weekdayHourBuckets;
  final List<_InsightBucket> attachmentBuckets;
}

_InsightsData _buildInsightsData(BuildContext context, List<NoteEntry> notes) {
  final watch = kDebugMode ? (Stopwatch()..start()) : null;
  final strings = context.strings;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final previousMonth = DateTime(now.year, now.month - 1);
  var thisMonthCount = 0;
  var previousMonthCount = 0;
  var totalCharacters = 0;
  var totalAttachments = 0;
  final activeDaysSet = <DateTime>{};
  final monthCounts = <int, int>{};
  final dayCounts = <DateTime, int>{};
  final weekdayHourCounts = <String, int>{};
  final hourCounts = <int, int>{};
  var photoAttachments = 0;
  var videoAttachments = 0;
  var audioAttachments = 0;

  for (final note in notes) {
    final createdAt = note.createdAt.toLocal();
    totalCharacters += note.body.trim().length;
    totalAttachments += note.attachments.length;
    if (createdAt.year == now.year && createdAt.month == now.month) {
      thisMonthCount += 1;
    }
    if (createdAt.year == previousMonth.year &&
        createdAt.month == previousMonth.month) {
      previousMonthCount += 1;
    }
    final monthKey = createdAt.year * 12 + createdAt.month;
    monthCounts[monthKey] = (monthCounts[monthKey] ?? 0) + 1;
    final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
    activeDaysSet.add(day);
    dayCounts[day] = (dayCounts[day] ?? 0) + 1;
    final weekdayStartHour = (createdAt.hour ~/ 3) * 3;
    final weekdayHourKey = '${createdAt.weekday}:$weekdayStartHour';
    weekdayHourCounts[weekdayHourKey] =
        (weekdayHourCounts[weekdayHourKey] ?? 0) + 1;
    final hourStart = (createdAt.hour ~/ 4) * 4;
    hourCounts[hourStart] = (hourCounts[hourStart] ?? 0) + 1;
    for (final attachment in note.attachments) {
      switch (attachment.type) {
        case AttachmentType.photo:
          photoAttachments += 1;
        case AttachmentType.video:
          videoAttachments += 1;
        case AttachmentType.audio:
          audioAttachments += 1;
        case AttachmentType.file:
          break;
      }
    }
  }

  final activeDays = activeDaysSet.toList()..sort((a, b) => b.compareTo(a));
  var currentStreak = 0;
  if (activeDays.isNotEmpty) {
    var cursor = activeDays.first;
    for (final day in activeDays) {
      if (_isSameCalendarDay(day, cursor)) {
        currentStreak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      }
    }
  }

  final recentDayBuckets = <_InsightBucket>[];
  final recent31DayBuckets = <_InsightBucket>[];
  for (var i = 30; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    final bucket = _InsightBucket(
      label: '${day.month}/${day.day}',
      value: dayCounts[day] ?? 0,
    );
    recent31DayBuckets.add(bucket);
    if (i < 14) {
      recentDayBuckets.add(bucket);
    }
  }
  final monthlyBuckets = <_InsightBucket>[];
  for (var i = 5; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    monthlyBuckets.add(
      _InsightBucket(
        label: strings.monthBucketLabel(month.month),
        value: monthCounts[month.year * 12 + month.month] ?? 0,
      ),
    );
  }
  final weekdayHourBuckets = [
    for (var startHour = 0; startHour < 24; startHour += 3)
      for (var weekday = 1; weekday <= 7; weekday++)
        _WeekdayHourBucket(
          weekday: weekday,
          startHour: startHour,
          value: weekdayHourCounts['$weekday:$startHour'] ?? 0,
        ),
  ];
  final hourBuckets = [
    for (var hour = 0; hour < 24; hour += 4)
      _InsightBucket(
        label:
            '${hour.toString().padLeft(2, '0')}-${(hour + 3).toString().padLeft(2, '0')}',
        value: hourCounts[hour] ?? 0,
      ),
  ];
  final bestDay = recent31DayBuckets
      .where((bucket) => bucket.value > 0)
      .fold<_InsightBucket?>(
        null,
        (best, bucket) =>
            best == null || bucket.value > best.value ? bucket : best,
      );
  final bestHour = hourBuckets
      .where((bucket) => bucket.value > 0)
      .fold<_InsightBucket?>(
        null,
        (best, bucket) =>
            best == null || bucket.value > best.value ? bucket : best,
      );
  final monthlyDelta = thisMonthCount - previousMonthCount;
  final message = bestDay == null || bestDay.value == 0
      ? strings.text('home.insights.summary.empty')
      : strings.text('home.insights.summary.active', {
          'thisMonthCount': thisMonthCount,
          'bestDayLabel': bestDay.label,
        });
  final data = _InsightsData(
    summary: _InsightsSummary(
      currentStreak: currentStreak,
      thisMonthCount: thisMonthCount,
      totalCharacters: totalCharacters,
      totalAttachments: totalAttachments,
      bestDayLabel: bestDay?.label ?? '-',
      bestDayValue: bestDay?.value ?? 0,
      bestHourLabel: bestHour?.label ?? '-',
      monthlyDeltaLabel: monthlyDelta == 0
          ? '0'
          : monthlyDelta > 0
          ? '+$monthlyDelta'
          : '$monthlyDelta',
      message: message,
    ),
    monthlyBuckets: List.unmodifiable(monthlyBuckets),
    recentDayBuckets: List.unmodifiable(recentDayBuckets),
    weekdayHourBuckets: List.unmodifiable(weekdayHourBuckets),
    attachmentBuckets: [
      _InsightBucket(
        label: strings.text('home.photo'),
        value: photoAttachments,
      ),
      _InsightBucket(
        label: strings.text('home.video'),
        value: videoAttachments,
      ),
      _InsightBucket(
        label: strings.text('home.audio'),
        value: audioAttachments,
      ),
    ],
  );
  final elapsed = watch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugNotePerf(
      'insights build notes=${notes.length} attachments=$totalAttachments completed ${elapsed / 1000}ms',
    );
  }
  return data;
}

bool _isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
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

class _EmptyTrashState extends StatelessWidget {
  const _EmptyTrashState({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.delete_outline_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            strings.localized(
              en: 'Trash is empty',
              ja: 'ゴミ箱は空です',
              zh: '废纸篓是空的',
              ko: '휴지통이 비어 있습니다',
              es: 'La papelera esta vacia',
              de: 'Der Papierkorb ist leer',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _TrashNoteTile extends StatelessWidget {
  const _TrashNoteTile({
    required this.note,
    required this.vaultName,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  final NoteEntry note;
  final String? vaultName;
  final VoidCallback onRestore;
  final VoidCallback onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final deletedAt = note.deletedAt?.toLocal();
    final title = note.title.trim().isEmpty
        ? strings.localized(
            en: 'Untitled note',
            ja: '無題のメモ',
            zh: '无标题备忘录',
            ko: '제목 없는 메모',
            es: 'Nota sin titulo',
            de: 'Unbenannte Notiz',
          )
        : note.title.trim();
    final body = note.body.trim();
    return DecoratedBox(
      decoration: _sectionDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (note.attachments.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.attach_file_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  Text('${note.attachments.length}'),
                ],
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (deletedAt != null)
                  _TrashMetaChip(
                    icon: Icons.schedule_rounded,
                    label: strings.localized(
                      en: 'Deleted ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      ja: '削除 ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      zh: '删除 ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      ko: '삭제 ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      es: 'Borrada ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      de: 'Geloescht ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                if (vaultName != null)
                  _TrashMetaChip(
                    icon: Icons.folder_outlined,
                    label: vaultName!,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(
                    strings.localized(
                      en: 'Restore',
                      ja: '復元',
                      zh: '恢复',
                      ko: '복원',
                      es: 'Restaurar',
                      de: 'Wiederherstellen',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDeletePermanently,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    strings.localized(
                      en: 'Delete',
                      ja: '削除',
                      zh: '删除',
                      ko: '삭제',
                      es: 'Borrar',
                      de: 'Loeschen',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashMetaChip extends StatelessWidget {
  const _TrashMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.activeIdentity,
    required this.collapsed,
    required this.tagSummaries,
    required this.activeTags,
    required this.onToggleCollapsed,
    required this.onSectionSelected,
    required this.onShowAllNotes,
    required this.onTagSelected,
    required this.onAddNote,
  });

  final AppSection section;
  final UnlockIdentity activeIdentity;
  final bool collapsed;
  final List<VisibleTagSummary> tagSummaries;
  final List<String> activeTags;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<AppSection> onSectionSelected;
  final VoidCallback onShowAllNotes;
  final ValueChanged<String> onTagSelected;
  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? 72 : 256,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (activeIdentity.id != 'daily') ...[
                  if (collapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      child: Tooltip(
                        message: strings.identityActive(activeIdentity.name),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: Text(
                            activeIdentity.name.characters.first,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          strings.identityActive(activeIdentity.name),
                          style: Theme.of(context).textTheme.labelMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                ],
                const SizedBox(height: 8),
                _SidebarItem(
                  icon: Icons.notes_outlined,
                  selectedIcon: Icons.notes_rounded,
                  label: strings.notes,
                  showLabel: !collapsed,
                  selected: section == AppSection.notes,
                  onTap: activeTags.isEmpty
                      ? () => onSectionSelected(AppSection.notes)
                      : onShowAllNotes,
                ),
                if (!collapsed && tagSummaries.isNotEmpty)
                  _SidebarTagSection(
                    summaries: tagSummaries,
                    activeTags: activeTags,
                    onTagSelected: onTagSelected,
                  ),
                _SidebarItem(
                  icon: Icons.calendar_month_outlined,
                  selectedIcon: Icons.calendar_month_rounded,
                  label: strings.calendar,
                  showLabel: !collapsed,
                  selected: section == AppSection.calendar,
                  onTap: () => onSectionSelected(AppSection.calendar),
                ),
                _SidebarItem(
                  icon: Icons.insert_chart_outlined_rounded,
                  selectedIcon: Icons.insert_chart_rounded,
                  label: strings.insights,
                  showLabel: !collapsed,
                  selected: section == AppSection.insights,
                  onTap: () => onSectionSelected(AppSection.insights),
                ),
                _SidebarItem(
                  icon: Icons.delete_outline_rounded,
                  selectedIcon: Icons.delete_rounded,
                  label: strings.localized(
                    en: 'Trash',
                    ja: 'ゴミ箱',
                    zh: '废纸篓',
                    ko: '휴지통',
                    es: 'Papelera',
                    de: 'Papierkorb',
                  ),
                  showLabel: !collapsed,
                  selected: section == AppSection.trash,
                  onTap: () => onSectionSelected(AppSection.trash),
                ),
                _SidebarItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: strings.settings,
                  showLabel: !collapsed,
                  selected: section == AppSection.settings,
                  onTap: () => onSectionSelected(AppSection.settings),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: EdgeInsets.fromLTRB(10, 12, 10, collapsed ? 8 : 10),
            child: _SidebarCreateNoteButton(
              key: AppShell.addNoteKey,
              collapsed: collapsed,
              onPressed: onAddNote,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: collapsed ? Alignment.center : Alignment.centerRight,
              child: IconButton(
                onPressed: onToggleCollapsed,
                icon: Icon(
                  collapsed
                      ? Icons.keyboard_double_arrow_right_rounded
                      : Icons.keyboard_double_arrow_left_rounded,
                ),
                tooltip: collapsed
                    ? strings.expandSidebar
                    : strings.collapseSidebar,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarCreateNoteButton extends StatelessWidget {
  const _SidebarCreateNoteButton({
    super.key,
    required this.collapsed,
    required this.onPressed,
  });

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    final icon = _CreateNoteIcon(size: collapsed ? 30 : 26);
    if (collapsed) {
      return Center(
        child: Tooltip(
          message: strings.addNote,
          child: SizedBox(
            width: 48,
            height: 48,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: icon,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(strings.addNote),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.showLabel,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool showLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Tooltip(
          message: label,
          child: IconButton(
            key: Key('sidebar-${label.toLowerCase()}'),
            onPressed: onTap,
            icon: Icon(selected ? selectedIcon : icon),
            isSelected: selected,
            style: IconButton.styleFrom(
              backgroundColor: selected ? _selectedSurfaceColor(context) : null,
              foregroundColor: selected
                  ? Theme.of(context).colorScheme.primary
                  : null,
              minimumSize: const Size(52, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        key: Key('sidebar-${label.toLowerCase()}'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        leading: Icon(selected ? selectedIcon : icon),
        title: Text(label),
        selected: selected,
        selectedTileColor: _selectedSurfaceColor(context),
        onTap: onTap,
      ),
    );
  }
}

class _SidebarTagSection extends StatefulWidget {
  const _SidebarTagSection({
    required this.summaries,
    required this.activeTags,
    required this.onTagSelected,
  });

  final List<VisibleTagSummary> summaries;
  final List<String> activeTags;
  final ValueChanged<String> onTagSelected;

  @override
  State<_SidebarTagSection> createState() => _SidebarTagSectionState();
}

class _SidebarTagSectionState extends State<_SidebarTagSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final activeKeys = widget.activeTags.map(canonicalizeNoteTag).toSet();
    final selectedSummaries = activeKeys.isEmpty
        ? const <VisibleTagSummary>[]
        : widget.summaries
              .where(
                (summary) =>
                    activeKeys.contains(canonicalizeNoteTag(summary.name)),
              )
              .toList(growable: false);
    final baseSummaries = widget.summaries
        .take(_expanded ? 14 : 5)
        .toList(growable: true);
    for (final selected in selectedSummaries) {
      final selectedKey = canonicalizeNoteTag(selected.name);
      if (!baseSummaries.any(
        (summary) => canonicalizeNoteTag(summary.name) == selectedKey,
      )) {
        baseSummaries.add(selected);
      }
    }
    final visibleSummaries = List<VisibleTagSummary>.unmodifiable(
      baseSummaries,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withValues(
            alpha: 0.66,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.sell_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.text('home.tags'),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded || activeKeys.isNotEmpty)
              ...visibleSummaries.map((summary) {
                final selected = activeKeys.contains(
                  canonicalizeNoteTag(summary.name),
                );
                return _SidebarTagTile(
                  summary: summary,
                  selected: selected,
                  onTap: () => widget.onTagSelected(summary.name),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SidebarTagTile extends StatelessWidget {
  const _SidebarTagTile({
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final VisibleTagSummary summary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: selected ? _selectedSurfaceColor(context) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 4, 7),
            child: Row(
              children: [
                Icon(
                  Icons.tag_rounded,
                  size: 16,
                  color: selected
                      ? colorScheme.primary
                      : _mutedTextColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? colorScheme.primary : null,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${summary.count}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected
                        ? colorScheme.primary
                        : _mutedTextColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.identity});

  final UnlockIdentity identity;

  @override
  Widget build(BuildContext context) {
    final accent = Color(identity.accentHex);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 56, height: 4, color: accent),
          const SizedBox(height: 12),
          Text(
            identity.name,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            identity.tagline,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _strongMutedTextColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivateVaultLockedNotice extends StatelessWidget {
  const _PrivateVaultLockedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.strings.text(
                'home.locked.profiles.are.hidden.unlock.the.target.profile.fro',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _vaultDisplayName(BuildContext context, VaultBucket vault) {
  if (vault.id == 'everyday') {
    return context.strings.notes;
  }
  if (vault.id == legacyPrivateVaultId &&
      (vault.name == 'Private profile' ||
          vault.name == '__private_profile__')) {
    return context.strings.text('home.private.profile');
  }
  if (vault.name == 'Notes' || vault.name == '__notes__') {
    return context.strings.notes;
  }
  return vault.name;
}

DateTime _noteListMoment(NoteEntry note, NotesListSortField sortField) {
  return switch (sortField) {
    NotesListSortField.updatedAt => note.updatedAt ?? note.createdAt,
    NotesListSortField.createdAt => note.createdAt,
  };
}

bool _isSameNoteDay(
  NoteEntry left,
  NoteEntry right,
  NotesListSortField sortField,
) {
  final leftMoment = _noteListMoment(left, sortField).toLocal();
  final rightMoment = _noteListMoment(right, sortField).toLocal();
  return leftMoment.year == rightMoment.year &&
      leftMoment.month == rightMoment.month &&
      leftMoment.day == rightMoment.day;
}

class _MobileNotesList extends StatefulWidget {
  const _MobileNotesList({
    required this.activeIdentity,
    required this.showPrivateVaultNotice,
    required this.compactHeader,
    required this.vaultNameById,
    required this.showVaultName,
    required this.allVisibleNotes,
    required this.selectedNoteId,
    required this.density,
    required this.sortField,
    required this.attachmentPreviewFit,
    required this.query,
    required this.onRefresh,
    required this.onNoteSelected,
  });

  final UnlockIdentity activeIdentity;
  final bool showPrivateVaultNotice;
  final bool compactHeader;
  final Map<String, String> vaultNameById;
  final bool showVaultName;
  final List<NoteEntry> allVisibleNotes;
  final String? selectedNoteId;
  final NotesListDensity density;
  final NotesListSortField sortField;
  final AttachmentPreviewFit attachmentPreviewFit;
  final String query;
  final Future<void> Function()? onRefresh;
  final ValueChanged<NoteEntry> onNoteSelected;

  @override
  State<_MobileNotesList> createState() => _MobileNotesListState();
}

class _MobileNotesListState extends State<_MobileNotesList> {
  late List<_MobileNoteRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows();
  }

  @override
  void didUpdateWidget(covariant _MobileNotesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.allVisibleNotes, widget.allVisibleNotes) ||
        oldWidget.activeIdentity.id != widget.activeIdentity.id ||
        oldWidget.showPrivateVaultNotice != widget.showPrivateVaultNotice ||
        oldWidget.compactHeader != widget.compactHeader ||
        oldWidget.density != widget.density ||
        oldWidget.sortField != widget.sortField ||
        oldWidget.attachmentPreviewFit != widget.attachmentPreviewFit ||
        oldWidget.showVaultName != widget.showVaultName ||
        oldWidget.vaultNameById.length != widget.vaultNameById.length) {
      _rows = _buildRows();
    }
  }

  List<_MobileNoteRow> _buildRows() {
    final watch = kDebugMode ? (Stopwatch()..start()) : null;
    final rows = _buildMobileNoteRows(
      activeIdentity: widget.activeIdentity,
      showPrivateVaultNotice: widget.showPrivateVaultNotice,
      compactHeader: widget.compactHeader,
      notes: widget.allVisibleNotes,
      density: widget.density,
      sortField: widget.sortField,
    );
    if (watch != null) {
      watch.stop();
      _debugNotePerf(
        'mobile list rows notes=${widget.allVisibleNotes.length} rows=${rows.length} completed ${watch.elapsedMicroseconds / 1000}ms',
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      physics: widget.onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        return switch (row) {
          _MobileIdentityRow() => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _IdentityHeader(identity: widget.activeIdentity),
          ),
          _MobilePrivateNoticeRow() => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _PrivateVaultLockedNotice(),
          ),
          _MobileToolbarRow() => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _NotesToolbar(compact: widget.compactHeader),
          ),
          _MobileEmptyRow() => const _EmptyNotesState(),
          _MobileDayRow(:final date) => _DecoratedMobileNoteRow(
            position: row.position,
            child: _NoteDayDivider(date: date),
          ),
          _MobileTileRow(:final note) => _DecoratedMobileNoteRow(
            position: row.position,
            child: RepaintBoundary(
              child: _NoteListTile(
                note: note,
                vaultName: widget.vaultNameById[note.vaultId] ?? note.vaultId,
                showVaultName: widget.showVaultName,
                density: widget.density,
                attachmentPreviewFit: widget.attachmentPreviewFit,
                query: widget.query,
                selected: note.id == widget.selectedNoteId,
                onTap: () => widget.onNoteSelected(note),
              ),
            ),
          ),
          _MobileDividerRow() => _DecoratedMobileNoteRow(
            position: row.position,
            child: const _IntraDayNoteGap(),
          ),
        };
      },
    );
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      return list;
    }
    return RefreshIndicator(onRefresh: onRefresh, child: list);
  }
}

List<_MobileNoteRow> _buildMobileNoteRows({
  required UnlockIdentity activeIdentity,
  required bool showPrivateVaultNotice,
  required bool compactHeader,
  required List<NoteEntry> notes,
  required NotesListDensity density,
  required NotesListSortField sortField,
}) {
  final rows = <_MobileNoteRow>[
    if (activeIdentity.id != 'daily') const _MobileIdentityRow(),
    if (showPrivateVaultNotice) const _MobilePrivateNoticeRow(),
    _MobileToolbarRow(compactHeader),
  ];
  if (notes.isEmpty) {
    rows.add(const _MobileEmptyRow());
    return rows;
  }

  final noteRows = <_MobileNoteRow>[];
  for (var i = 0; i < notes.length; i++) {
    if (density != NotesListDensity.compact &&
        (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i], sortField))) {
      noteRows.add(_MobileDayRow(_noteListMoment(notes[i], sortField)));
    }
    noteRows.add(_MobileTileRow(notes[i]));
    if (density != NotesListDensity.compact &&
        i != notes.length - 1 &&
        _isSameNoteDay(notes[i], notes[i + 1], sortField)) {
      noteRows.add(const _MobileDividerRow());
    }
  }
  for (var i = 0; i < noteRows.length; i++) {
    rows.add(
      noteRows[i].withPosition(
        _MobileNoteRowPosition(first: i == 0, last: i == noteRows.length - 1),
      ),
    );
  }
  return rows;
}

class _MobileNoteRowPosition {
  const _MobileNoteRowPosition({required this.first, required this.last});

  final bool first;
  final bool last;
}

sealed class _MobileNoteRow {
  const _MobileNoteRow({this.position});

  final _MobileNoteRowPosition? position;

  _MobileNoteRow withPosition(_MobileNoteRowPosition position);
}

class _MobileIdentityRow extends _MobileNoteRow {
  const _MobileIdentityRow();

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobilePrivateNoticeRow extends _MobileNoteRow {
  const _MobilePrivateNoticeRow();

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobileToolbarRow extends _MobileNoteRow {
  const _MobileToolbarRow(this.compact);

  final bool compact;

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobileEmptyRow extends _MobileNoteRow {
  const _MobileEmptyRow();

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobileDayRow extends _MobileNoteRow {
  const _MobileDayRow(this.date, {super.position});

  final DateTime date;

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) =>
      _MobileDayRow(date, position: position);
}

class _MobileTileRow extends _MobileNoteRow {
  const _MobileTileRow(this.note, {super.position});

  final NoteEntry note;

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) =>
      _MobileTileRow(note, position: position);
}

class _MobileDividerRow extends _MobileNoteRow {
  const _MobileDividerRow({super.position});

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) =>
      _MobileDividerRow(position: position);
}

class _DecoratedMobileNoteRow extends StatelessWidget {
  const _DecoratedMobileNoteRow({required this.position, required this.child});

  final _MobileNoteRowPosition? position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(pos?.first == true ? 6 : 0),
      bottom: Radius.circular(pos?.last == true ? 6 : 0),
    );
    final border = Border(
      left: BorderSide(color: Theme.of(context).dividerColor),
      right: BorderSide(color: Theme.of(context).dividerColor),
      top: pos?.first == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
      bottom: pos?.last == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
    );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );
  }
}

class _NoteDayDivider extends StatelessWidget {
  const _NoteDayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final label = strings.noteDayLabel(date);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final dayDiff = today.difference(target).inDays;
    final suffix = switch (dayDiff) {
      0 => strings.today,
      1 => strings.yesterday,
      _ => null,
    };
    final weekendColor = _noteDayWeekendColor(context, date);
    final effectiveColor = weekendColor ?? _mutedTextColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 1, color: Theme.of(context).dividerColor),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:
                  weekendColor?.withValues(alpha: 0.08) ??
                  Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color:
                    weekendColor?.withValues(alpha: 0.45) ??
                    Theme.of(context).dividerColor,
              ),
            ),
            child: Text(
              suffix == null ? label : '$label  $suffix',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: effectiveColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Container(height: 1, color: Theme.of(context).dividerColor),
          ),
        ],
      ),
    );
  }
}

class _IntraDayNoteGap extends StatelessWidget {
  const _IntraDayNoteGap();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        height: 1,
        color: Theme.of(context).dividerColor.withValues(alpha: 0.62),
      ),
    );
  }
}

Color? _noteDayWeekendColor(BuildContext context, DateTime date) {
  final brightness = Theme.of(context).brightness;
  if (date.weekday == DateTime.saturday) {
    return brightness == Brightness.dark
        ? const Color(0xFF7DB7FF)
        : const Color(0xFF0B63CE);
  }
  if (date.weekday == DateTime.sunday) {
    return brightness == Brightness.dark
        ? const Color(0xFFFF8A8A)
        : const Color(0xFFC62828);
  }
  return null;
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.vaultName,
    required this.showVaultName,
    required this.density,
    required this.attachmentPreviewFit,
    required this.query,
    required this.selected,
    required this.onTap,
  });

  final NoteEntry note;
  final String vaultName;
  final bool showVaultName;
  final NotesListDensity density;
  final AttachmentPreviewFit attachmentPreviewFit;
  final String query;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isPrivateNote = isPrivateVaultId(note.vaultId);
    final changedAt = (note.updatedAt ?? note.createdAt).toLocal();
    final dateLabel =
        '${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;
    final compactPreview = _normalizePreviewText(
      note.body,
      query: query,
      maxChars: 140,
    );
    final bodyPreview = _normalizePreviewText(
      note.body,
      query: query,
      maxChars: 360,
    );
    final tags = note.normalizedTags;
    final previewFacts = _notePreviewFacts(note);
    final hasLocationPreview = _firstLocationPreview(note) != null;
    final showLocationPreviewIconOnly =
        attachmentPreviewFit == AttachmentPreviewFit.icon && hasLocationPreview;
    final visiblePreviewFacts =
        (showLocationPreviewIconOnly
                ? previewFacts.where(
                    (fact) => fact.icon != Icons.location_on_outlined,
                  )
                : previewFacts)
            .take(3)
            .toList(growable: false);
    final hasCompactMediaAttachment = note.attachments.any(
      (attachment) =>
          attachment.type == AttachmentType.photo ||
          attachment.type == AttachmentType.video ||
          attachment.type == AttachmentType.audio,
    );
    final hasDistinctBody =
        bodyPreview.isNotEmpty && bodyPreview != note.title.trim();
    final showAttachmentPreviews = density != NotesListDensity.compact;
    final thumbnailSize = switch (density) {
      NotesListDensity.compact => 44.0,
      NotesListDensity.standard => 56.0,
    };
    const maxThumbs = 3;
    final bodyLines = switch (density) {
      NotesListDensity.compact => 1,
      NotesListDensity.standard => 2,
    };

    if (density == NotesListDensity.compact) {
      return _NoteListTileSelectionSurface(
        selected: selected,
        child: InkWell(
          key: Key('note-tile-${note.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    dateLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (isPrivateNote) ...[
                  const _PrivateNoteMarker(compact: true),
                  const SizedBox(width: 8),
                ],
                if (note.syncState == NoteSyncState.conflict) ...[
                  const _SyncConflictChip(compact: true),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _HighlightedText(
                    text: compactPreview.isEmpty ? note.title : compactPreview,
                    query: query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _strongMutedTextColor(context),
                    ),
                  ),
                ),
                if (note.isPinned) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.push_pin_rounded,
                    size: 14,
                    color: _mutedTextColor(context),
                  ),
                ],
                if (hasLocationPreview) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: _mutedTextColor(context),
                  ),
                ],
                if (hasCompactMediaAttachment) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.perm_media_outlined,
                    size: 14,
                    color: _mutedTextColor(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return _NoteListTileSelectionSurface(
      selected: selected,
      child: InkWell(
        key: Key('note-tile-${note.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isPrivateNote) ...[
                    const _PrivateNoteMarker(),
                    const SizedBox(width: 8),
                  ],
                  if (note.syncState == NoteSyncState.conflict) ...[
                    const _SyncConflictChip(),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _HighlightedText(
                      text: note.title,
                      query: query,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (note.isPinned)
                    Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: _mutedTextColor(context),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (hasDistinctBody)
                _HighlightedText(
                  text: density == NotesListDensity.compact
                      ? compactPreview
                      : bodyPreview,
                  query: query,
                  maxLines: bodyLines,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _strongMutedTextColor(context),
                  ),
                ),
              if (visiblePreviewFacts.isNotEmpty ||
                  showLocationPreviewIconOnly) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final fact in visiblePreviewFacts)
                      _NotePreviewFactChip(fact: fact),
                    if (showLocationPreviewIconOnly)
                      const _NotePreviewFactIcon(
                        icon: Icons.location_on_outlined,
                      ),
                  ],
                ),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags.take(4))
                      _NoteTagChip(tag: tag, compact: true),
                    if (tags.length > 4)
                      _NoteTagChip(tag: '+${tags.length - 4}', compact: true),
                  ],
                ),
              ],
              if (showAttachmentPreviews && note.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (
                      var i = 0;
                      i < note.attachments.length && i < maxThumbs;
                      i++
                    ) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          right: i == maxThumbs - 1 ? 0 : 8,
                        ),
                        child: _NoteListAttachmentPreview(
                          attachment: note.attachments[i],
                          size: thumbnailSize,
                          previewFit: attachmentPreviewFit,
                        ),
                      ),
                    ],
                    if (note.attachments.length > maxThumbs) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          width: thumbnailSize,
                          height: thumbnailSize,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '+${note.attachments.length - maxThumbs}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (showVaultName)
                    Text(
                      vaultName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isPrivateNote
                            ? Theme.of(context).colorScheme.primary
                            : _mutedTextColor(context),
                        fontWeight: isPrivateNote ? FontWeight.w600 : null,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    isEdited ? strings.editedAt(dateLabel) : dateLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotePreviewFact {
  const _NotePreviewFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _PrivateNoteMarker extends StatelessWidget {
  const _PrivateNoteMarker({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = compact ? 22.0 : 24.0;
    final iconSize = compact ? 13.0 : 14.0;
    return Tooltip(
      message: context.strings.text('home.private.profile'),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.28),
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.lock_outline_rounded,
          size: iconSize,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

class _SyncConflictChip extends StatelessWidget {
  const _SyncConflictChip({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = context.strings.localized(
      en: 'Conflict',
      ja: '競合',
      zh: '冲突',
      ko: '충돌',
      es: 'Conflicto',
      de: 'Konflikt',
    );
    return Tooltip(
      message: context.strings.localized(
        en: 'This note has conflicting local and remote changes.',
        ja: 'このメモはローカルとリモートの変更が競合しています。',
        zh: '此笔记存在本地和远程更改冲突。',
        ko: '이 메모는 로컬 변경과 원격 변경이 충돌합니다.',
        es: 'Esta nota tiene cambios locales y remotos en conflicto.',
        de: 'Diese Notiz hat widersprechende lokale und Remote-Anderungen.',
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.56)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync_problem_rounded,
              size: compact ? 13 : 15,
              color: colorScheme.onErrorContainer,
            ),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncConflictNotice extends StatelessWidget {
  const _SyncConflictNotice({required this.onResolve});

  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.56)),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              strings.localized(
                en: 'This note has conflicting local and remote changes.',
                ja: 'このメモはローカルとリモートの変更が競合しています。',
                zh: '此笔记存在本地和远程更改冲突。',
                ko: '이 메모는 로컬 변경과 원격 변경이 충돌합니다.',
                es: 'Esta nota tiene cambios locales y remotos en conflicto.',
                de: 'Diese Notiz hat widersprechende lokale und Remote-Anderungen.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            onPressed: onResolve,
            icon: const Icon(Icons.rule_rounded),
            label: Text(
              strings.localized(
                en: 'Resolve',
                ja: '解決',
                zh: '解决',
                ko: '해결',
                es: 'Resolver',
                de: 'Losen',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<_NotePreviewFact> _notePreviewFacts(NoteEntry note) {
  final facts = <_NotePreviewFact>[];
  final location = _firstLocationPreview(note);
  if (location != null) {
    facts.add(
      _NotePreviewFact(
        icon: Icons.location_on_outlined,
        label: location.address?.trim().isNotEmpty == true
            ? location.address!.trim()
            : '${location.latitude}, ${location.longitude}',
      ),
    );
  }

  for (final attachment in note.attachments) {
    final durationMs = attachment.durationMs;
    if (durationMs == null || durationMs <= 0) {
      continue;
    }
    final type = attachment.type;
    if (type != AttachmentType.audio && type != AttachmentType.video) {
      continue;
    }
    facts.add(
      _NotePreviewFact(
        icon: type == AttachmentType.audio
            ? Icons.graphic_eq_rounded
            : Icons.videocam_outlined,
        label: _formatAudioDuration(Duration(milliseconds: durationMs)),
      ),
    );
  }
  return facts;
}

_LocationMemoData? _firstLocationPreview(NoteEntry note) {
  final metadataLocation = note.location;
  if (metadataLocation != null) {
    return _locationMemoDataFromMetadata(metadataLocation);
  }
  for (final block in note.blocks) {
    if (block.type != NoteBlockType.paragraph) {
      continue;
    }
    final text = block.text;
    if (text == null || text.trim().isEmpty) {
      continue;
    }
    final location = _tryParseLocationMemo(text);
    if (location != null) {
      return location;
    }
  }
  return _tryParseLocationMemo(note.body);
}

class _NotePreviewFactChip extends StatelessWidget {
  const _NotePreviewFactChip({required this.fact});

  final _NotePreviewFact fact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              fact.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotePreviewFactIcon extends StatelessWidget {
  const _NotePreviewFactIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
    );
  }
}

class _NoteListTileSelectionSurface extends StatelessWidget {
  const _NoteListTileSelectionSurface({
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return Material(color: Colors.transparent, child: child);
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(color: _selectedSurfaceColor(context), child: child),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return Text(text, maxLines: maxLines, overflow: overflow, style: style);
    }
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (true) {
      final matchIndex = lower.indexOf(normalizedQuery, cursor);
      if (matchIndex == -1) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (matchIndex > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, matchIndex)));
      }
      spans.add(
        TextSpan(
          text: text.substring(matchIndex, matchIndex + normalizedQuery.length),
          style: style?.copyWith(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.16),
          ),
        ),
      );
      cursor = matchIndex + normalizedQuery.length;
      if (cursor >= text.length) {
        break;
      }
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

String _normalizePreviewText(
  String value, {
  String query = '',
  int maxChars = 360,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final normalizedQuery = query.trim().toLowerCase();
  var source = trimmed;
  var hasPrefix = false;
  var hasSuffix = false;
  if (normalizedQuery.isNotEmpty) {
    final matchIndex = trimmed.toLowerCase().indexOf(normalizedQuery);
    if (matchIndex > maxChars ~/ 2) {
      final start = math.max(0, matchIndex - (maxChars ~/ 3));
      final end = math.min(trimmed.length, start + maxChars);
      hasPrefix = start > 0;
      hasSuffix = end < trimmed.length;
      source = trimmed.substring(start, end);
    } else if (trimmed.length > maxChars) {
      hasSuffix = true;
      source = trimmed.substring(0, maxChars);
    }
  } else if (trimmed.length > maxChars) {
    hasSuffix = true;
    source = trimmed.substring(0, maxChars);
  }

  final normalized = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return '';
  }
  final prefix = hasPrefix ? '... ' : '';
  final suffix = hasSuffix ? ' ...' : '';
  return '$prefix$normalized$suffix';
}

class _SplitPaneResizeHandle extends StatefulWidget {
  const _SplitPaneResizeHandle({
    required this.onDragDelta,
    required this.onTap,
  });

  final ValueChanged<double> onDragDelta;
  final VoidCallback onTap;

  @override
  State<_SplitPaneResizeHandle> createState() => _SplitPaneResizeHandleState();
}

class _SplitPaneResizeHandleState extends State<_SplitPaneResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;
    final strings = context.strings;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: strings.localized(
          en: 'Drag to resize the note list. Tap to switch widths.',
          ja: 'ドラッグでノート一覧の幅を変更します。タップで幅を切り替えます。',
          zh: '拖动可调整笔记列表宽度。点击可切换宽度。',
          ko: '드래그하여 노트 목록 너비를 조정합니다. 탭하면 너비가 전환됩니다.',
          es: 'Arrastra para cambiar el ancho de la lista. Toca para alternar anchos.',
          de: 'Ziehen, um die Breite der Notizliste zu ändern. Tippen, um Breiten zu wechseln.',
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          onHorizontalDragUpdate: (details) {
            widget.onDragDelta(details.delta.dx);
          },
          child: SizedBox(
            width: 14,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).dividerColor,
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: active ? 5 : 3,
                  height: active ? 56 : 42,
                  decoration: BoxDecoration(
                    color: active
                        ? colorScheme.primary.withValues(alpha: 0.72)
                        : colorScheme.outlineVariant.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitNotesListPane extends StatefulWidget {
  const _SplitNotesListPane({
    required this.activeIdentity,
    required this.showPrivateVaultNotice,
    required this.notes,
    required this.selectedNoteId,
    required this.vaultNameById,
    required this.showVaultName,
    required this.density,
    required this.sortField,
    required this.attachmentPreviewFit,
    required this.query,
    required this.onAddNote,
    required this.onRefresh,
    required this.onNoteSelected,
  });

  final UnlockIdentity activeIdentity;
  final bool showPrivateVaultNotice;
  final List<NoteEntry> notes;
  final String? selectedNoteId;
  final Map<String, String> vaultNameById;
  final bool showVaultName;
  final NotesListDensity density;
  final NotesListSortField sortField;
  final AttachmentPreviewFit attachmentPreviewFit;
  final String query;
  final VoidCallback onAddNote;
  final Future<void> Function()? onRefresh;
  final ValueChanged<NoteEntry> onNoteSelected;

  @override
  State<_SplitNotesListPane> createState() => _SplitNotesListPaneState();
}

class _SplitNotesListPaneState extends State<_SplitNotesListPane> {
  late List<_SplitNoteRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows();
  }

  @override
  void didUpdateWidget(covariant _SplitNotesListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notes, widget.notes) ||
        oldWidget.density != widget.density ||
        oldWidget.sortField != widget.sortField ||
        oldWidget.attachmentPreviewFit != widget.attachmentPreviewFit ||
        oldWidget.showPrivateVaultNotice != widget.showPrivateVaultNotice ||
        oldWidget.activeIdentity.id != widget.activeIdentity.id) {
      _rows = _buildRows();
    }
  }

  List<_SplitNoteRow> _buildRows() {
    return _buildSplitNoteRows(
      activeIdentity: widget.activeIdentity,
      showPrivateVaultNotice: widget.showPrivateVaultNotice,
      notes: widget.notes,
      density: widget.density,
      sortField: widget.sortField,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      physics: widget.onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        return switch (row) {
          _SplitNoteIdentityRow() => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _IdentityHeader(identity: widget.activeIdentity),
          ),
          _SplitNotePrivateNoticeRow() => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _PrivateVaultLockedNotice(),
          ),
          _SplitNoteToolbarRow() => const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: _NotesToolbar(),
          ),
          _SplitNoteEmptyRow() => const _EmptyNotesState(),
          _SplitNoteDayRow(:final date) => _DecoratedSplitNoteRow(
            position: row.position,
            child: _NoteDayDivider(date: date),
          ),
          _SplitNoteTileRow(:final note) => _DecoratedSplitNoteRow(
            position: row.position,
            child: RepaintBoundary(
              child: _NoteListTile(
                note: note,
                vaultName: widget.vaultNameById[note.vaultId] ?? note.vaultId,
                showVaultName: widget.showVaultName,
                density: widget.density,
                attachmentPreviewFit: widget.attachmentPreviewFit,
                query: widget.query,
                selected: widget.selectedNoteId == note.id,
                onTap: () => widget.onNoteSelected(note),
              ),
            ),
          ),
          _SplitNoteDividerRow() => _DecoratedSplitNoteRow(
            position: row.position,
            child: const _IntraDayNoteGap(),
          ),
        };
      },
    );
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      return list;
    }
    return RefreshIndicator(onRefresh: onRefresh, child: list);
  }
}

List<_SplitNoteRow> _buildSplitNoteRows({
  required UnlockIdentity activeIdentity,
  required bool showPrivateVaultNotice,
  required List<NoteEntry> notes,
  required NotesListDensity density,
  required NotesListSortField sortField,
}) {
  final rows = <_SplitNoteRow>[
    if (activeIdentity.id != 'daily') const _SplitNoteIdentityRow(),
    if (showPrivateVaultNotice) const _SplitNotePrivateNoticeRow(),
    const _SplitNoteToolbarRow(),
  ];
  if (notes.isEmpty) {
    rows.add(const _SplitNoteEmptyRow());
    return rows;
  }

  final noteRows = <_SplitNoteRow>[];
  for (var i = 0; i < notes.length; i++) {
    if (density != NotesListDensity.compact &&
        (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i], sortField))) {
      noteRows.add(_SplitNoteDayRow(_noteListMoment(notes[i], sortField)));
    }
    noteRows.add(_SplitNoteTileRow(notes[i]));
    if (density != NotesListDensity.compact &&
        i != notes.length - 1 &&
        _isSameNoteDay(notes[i], notes[i + 1], sortField)) {
      noteRows.add(const _SplitNoteDividerRow());
    }
  }

  for (var i = 0; i < noteRows.length; i++) {
    rows.add(
      noteRows[i].withPosition(
        _SplitNoteRowPosition(first: i == 0, last: i == noteRows.length - 1),
      ),
    );
  }
  return rows;
}

class _SplitNoteRowPosition {
  const _SplitNoteRowPosition({required this.first, required this.last});

  final bool first;
  final bool last;
}

sealed class _SplitNoteRow {
  const _SplitNoteRow({this.position});

  final _SplitNoteRowPosition? position;

  _SplitNoteRow withPosition(_SplitNoteRowPosition position);
}

class _SplitNoteIdentityRow extends _SplitNoteRow {
  const _SplitNoteIdentityRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNotePrivateNoticeRow extends _SplitNoteRow {
  const _SplitNotePrivateNoticeRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNoteToolbarRow extends _SplitNoteRow {
  const _SplitNoteToolbarRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNoteEmptyRow extends _SplitNoteRow {
  const _SplitNoteEmptyRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNoteDayRow extends _SplitNoteRow {
  const _SplitNoteDayRow(this.date, {super.position});

  final DateTime date;

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) =>
      _SplitNoteDayRow(date, position: position);
}

class _SplitNoteTileRow extends _SplitNoteRow {
  const _SplitNoteTileRow(this.note, {super.position});

  final NoteEntry note;

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) =>
      _SplitNoteTileRow(note, position: position);
}

class _SplitNoteDividerRow extends _SplitNoteRow {
  const _SplitNoteDividerRow({super.position});

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) =>
      _SplitNoteDividerRow(position: position);
}

class _DecoratedSplitNoteRow extends StatelessWidget {
  const _DecoratedSplitNoteRow({required this.position, required this.child});

  final _SplitNoteRowPosition? position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(pos?.first == true ? 6 : 0),
      bottom: Radius.circular(pos?.last == true ? 6 : 0),
    );
    final border = Border(
      left: BorderSide(color: Theme.of(context).dividerColor),
      right: BorderSide(color: Theme.of(context).dividerColor),
      top: pos?.first == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
      bottom: pos?.last == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
    );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );
  }
}

class _StaticNoteDetailView extends ConsumerWidget {
  const _StaticNoteDetailView({
    required this.notes,
    required this.selectedIndex,
    required this.onSelected,
    required this.onEdit,
    required this.onDelete,
    this.onTagTap,
  });

  final List<NoteEntry> notes;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<NoteEntry> onEdit;
  final ValueChanged<NoteEntry> onDelete;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final note = notes[selectedIndex];
    final canMovePrevious = selectedIndex > 0;
    final canMoveNext = selectedIndex < notes.length - 1;
    _debugNotePerf(
      'detail static build index=$selectedIndex ${_notePerfLabel(note)}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              IconButton(
                onPressed: canMovePrevious
                    ? () => onSelected(selectedIndex - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: strings.text('home.previous.note'),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: canMoveNext
                    ? () => onSelected(selectedIndex + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: strings.text('home.next.note'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Text(
                '${selectedIndex + 1} / ${notes.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _NoteDetailPane(
            note: note,
            isActive: true,
            vaultName: _vaultDisplayName(
              context,
              ref.watch(vaultByIdProvider(note.vaultId)),
            ),
            onEdit: () => onEdit(note),
            onDelete: () => onDelete(note),
            onTagTap: onTagTap,
          ),
        ),
      ],
    );
  }
}

class _NoteDetailPager extends ConsumerStatefulWidget {
  const _NoteDetailPager({
    required this.notes,
    required this.selectedIndex,
    required this.onPageChanged,
    required this.onEdit,
    required this.onDelete,
    this.onClose,
    this.onTagTap,
  });

  final List<NoteEntry> notes;
  final int selectedIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<NoteEntry> onEdit;
  final ValueChanged<NoteEntry> onDelete;
  final VoidCallback? onClose;
  final ValueChanged<String>? onTagTap;

  @override
  ConsumerState<_NoteDetailPager> createState() => _NoteDetailPagerState();
}

class _NoteDetailPagerState extends ConsumerState<_NoteDetailPager> {
  static const double _edgeDismissThreshold = 72;
  late final PageController _pageController;
  int? _programmaticPageTarget;
  double _edgeDismissPull = 0;
  _EdgeDismissDirection? _edgeDismissDirection;
  bool _edgeDismissClosing = false;
  bool _detailScrollAtTop = true;
  bool _detailScrollAtBottom = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.selectedIndex);
  }

  @override
  void didUpdateWidget(covariant _NoteDetailPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _debugNotePerf(
        'detail pager selectedIndex ${oldWidget.selectedIndex}->${widget.selectedIndex}',
      );
    }
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        _pageController.hasClients) {
      final currentPage = _pageController.page?.round();
      if (currentPage != widget.selectedIndex) {
        _debugNotePerf(
          'detail pager jumpToPage ${widget.selectedIndex} current=$currentPage',
        );
        _programmaticPageTarget = widget.selectedIndex;
        _pageController.jumpToPage(widget.selectedIndex);
        Timer(const Duration(milliseconds: 250), () {
          if (mounted && _programmaticPageTarget == widget.selectedIndex) {
            _programmaticPageTarget = null;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _applyEdgeDismissPull(double signedDelta) {
    if (widget.onClose == null || _edgeDismissClosing || signedDelta == 0) {
      return;
    }
    final direction =
        _edgeDismissDirection ??
        (signedDelta > 0
            ? _EdgeDismissDirection.down
            : _EdgeDismissDirection.up);
    final nextPull = switch (direction) {
      _EdgeDismissDirection.down => (_edgeDismissPull + signedDelta).clamp(
        0.0,
        _edgeDismissThreshold,
      ),
      _EdgeDismissDirection.up => (_edgeDismissPull + signedDelta).clamp(
        -_edgeDismissThreshold,
        0.0,
      ),
    };
    if (nextPull != _edgeDismissPull) {
      setState(() {
        _edgeDismissDirection = direction;
        _edgeDismissPull = nextPull.toDouble();
      });
    } else if (_edgeDismissDirection == null) {
      setState(() {
        _edgeDismissDirection = direction;
      });
    }
  }

  void _resetEdgeDismissPull() {
    if (_edgeDismissPull == 0 && _edgeDismissDirection == null) {
      return;
    }
    setState(() {
      _edgeDismissPull = 0;
      _edgeDismissDirection = null;
    });
  }

  void _finishEdgeDismissGesture() {
    if (_edgeDismissClosing || _edgeDismissPull == 0) {
      return;
    }
    if (_edgeDismissPull.abs() >= _edgeDismissThreshold) {
      _edgeDismissClosing = true;
      widget.onClose?.call();
      return;
    }
    _resetEdgeDismissPull();
  }

  bool _handleDetailScrollNotification(ScrollNotification notification) {
    if (widget.onClose == null ||
        _edgeDismissClosing ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final metrics = notification.metrics;
    final isAtTop = metrics.pixels <= metrics.minScrollExtent + 2;
    final isAtBottom = metrics.pixels >= metrics.maxScrollExtent - 2;
    _detailScrollAtTop = isAtTop;
    _detailScrollAtBottom = isAtBottom;
    if (notification is OverscrollNotification) {
      if (isAtTop && notification.overscroll < 0) {
        _applyEdgeDismissPull(-notification.overscroll);
        return false;
      }
      if (isAtBottom && notification.overscroll > 0) {
        _applyEdgeDismissPull(-notification.overscroll);
        return false;
      }
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      if (!isAtTop && !isAtBottom && _edgeDismissPull != 0) {
        _resetEdgeDismissPull();
      }
      return false;
    }

    if (notification is ScrollEndNotification && _edgeDismissPull != 0) {
      _finishEdgeDismissGesture();
    }
    return false;
  }

  void _handleDetailPointerMove(PointerMoveEvent event) {
    if (_detailScrollAtTop && event.delta.dy > 0) {
      _applyEdgeDismissPull(event.delta.dy);
    } else if (_detailScrollAtBottom && event.delta.dy < 0) {
      _applyEdgeDismissPull(event.delta.dy);
    } else if (_edgeDismissPull != 0) {
      _resetEdgeDismissPull();
    }
  }

  void _handleDetailPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (_detailScrollAtTop && event.scrollDelta.dy < 0) {
      _applyEdgeDismissPull(-event.scrollDelta.dy * 0.3);
    } else if (_detailScrollAtBottom && event.scrollDelta.dy > 0) {
      _applyEdgeDismissPull(-event.scrollDelta.dy * 0.3);
    }
  }

  void _handleHeaderDismissDragUpdate(DragUpdateDetails details) {
    if (widget.onClose == null || _edgeDismissClosing) {
      return;
    }
    final delta = details.primaryDelta ?? 0;
    if (delta != 0) {
      _applyEdgeDismissPull(delta);
    }
  }

  void _handleHeaderDismissDragEnd(DragEndDetails details) {
    _finishEdgeDismissGesture();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canMovePrevious = widget.selectedIndex > 0;
    final canMoveNext = widget.selectedIndex < widget.notes.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _handleHeaderDismissDragUpdate,
          onVerticalDragEnd: _handleHeaderDismissDragEnd,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: strings.close,
                    visualDensity: VisualDensity.compact,
                  ),
                const Spacer(),
                IconButton(
                  onPressed: canMovePrevious
                      ? () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: strings.text('home.previous.note'),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: canMoveNext
                      ? () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: strings.text('home.next.note'),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  '${widget.selectedIndex + 1} / ${widget.notes.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleDetailScrollNotification,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: _handleDetailPointerMove,
              onPointerUp: (_) => _finishEdgeDismissGesture(),
              onPointerCancel: (_) => _resetEdgeDismissPull(),
              onPointerSignal: _handleDetailPointerSignal,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: widget.notes.length,
                    onPageChanged: (index) {
                      final programmaticTarget = _programmaticPageTarget;
                      if (programmaticTarget != null) {
                        if (index == programmaticTarget) {
                          _programmaticPageTarget = null;
                        }
                        _debugNotePerf(
                          'detail pager ignored programmatic onPageChanged index=$index target=$programmaticTarget',
                        );
                        return;
                      }
                      widget.onPageChanged(index);
                    },
                    itemBuilder: (context, index) {
                      final note = widget.notes[index];
                      _debugNotePerf(
                        'detail page build index=$index ${_notePerfLabel(note)}',
                      );
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _NoteDetailPane(
                          note: note,
                          isActive: index == widget.selectedIndex,
                          vaultName: _vaultDisplayName(
                            context,
                            ref.watch(vaultByIdProvider(note.vaultId)),
                          ),
                          onEdit: () => widget.onEdit(note),
                          onDelete: () => widget.onDelete(note),
                          onTagTap: widget.onTagTap,
                        ),
                      );
                    },
                  ),
                  if (widget.onClose != null)
                    _EdgePullDismissHint(
                      progress: _edgeDismissPull.abs() / _edgeDismissThreshold,
                      direction:
                          _edgeDismissDirection ?? _EdgeDismissDirection.down,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _EdgeDismissDirection { up, down }

class _EdgePullDismissHint extends StatelessWidget {
  const _EdgePullDismissHint({required this.progress, required this.direction});

  final double progress;
  final _EdgeDismissDirection direction;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = progress.clamp(0.0, 1.0);
    final visible = effectiveProgress > 0.04;
    final colorScheme = Theme.of(context).colorScheme;
    final strings = context.strings;
    final isUp = direction == _EdgeDismissDirection.up;
    return Positioned(
      left: 0,
      right: 0,
      top: isUp ? null : 16,
      bottom: isUp ? 16 : null,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: Offset(0, visible ? 0 : (isUp ? 0.2 : -0.2)),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Center(
              child: SizedBox(
                width: 252,
                height: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.inverseSurface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(
                            0,
                            (isUp ? -3 : 3) * effectiveProgress,
                          ),
                          child: Icon(
                            effectiveProgress >= 1
                                ? (isUp
                                      ? Icons.keyboard_double_arrow_up_rounded
                                      : Icons
                                            .keyboard_double_arrow_down_rounded)
                                : (isUp
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded),
                            color: colorScheme.onInverseSurface,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            effectiveProgress >= 0.92
                                ? strings.close
                                : strings.localized(
                                    en: 'Release past the edge to close',
                                    ja: 'さらに下へスクロールして閉じる',
                                    zh: '继续向下滚动以关闭',
                                    ko: '더 아래로 스크롤해 닫기',
                                    es: 'Sigue desplazando para cerrar',
                                    de: 'Weiter scrollen zum Schließen',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: colorScheme.onInverseSurface),
                          ),
                        ),
                      ],
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

enum _NoteDetailAction { copy, share }

Future<void> _handleNoteDetailAction(
  BuildContext context,
  NoteEntry note,
  _NoteDetailAction action,
) async {
  final text = _shareTextForNote(note);
  switch (action) {
    case _NoteDetailAction.copy:
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            context.strings.localized(
              en: 'Note text copied.',
              ja: 'メモのテキストをコピーしました。',
              zh: '已复制笔记文本。',
              ko: '메모 텍스트를 복사했습니다.',
              es: 'Texto de la nota copiado.',
              de: 'Notiztext kopiert.',
            ),
          ),
        ),
      );
    case _NoteDetailAction.share:
      await SharePlus.instance.share(
        ShareParams(text: text, subject: note.title),
      );
  }
}

String _shareTextForNote(NoteEntry note) {
  final buffer = StringBuffer(note.title.trim());
  final body = note.body.trim();
  if (body.isNotEmpty && body != note.title.trim()) {
    buffer
      ..writeln()
      ..writeln()
      ..write(body);
  }
  if (note.tags.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(note.tags.map((tag) => '#$tag').join(' '));
  }
  if (note.location != null) {
    final location = note.location!;
    buffer
      ..writeln()
      ..writeln(
        location.address?.trim().isNotEmpty == true
            ? location.address!.trim()
            : '${location.latitude}, ${location.longitude}',
      );
  }
  return buffer.toString().trim();
}

class _NoteDetailPane extends ConsumerWidget {
  const _NoteDetailPane({
    required this.note,
    required this.isActive,
    required this.vaultName,
    this.onEdit,
    this.onDelete,
    this.onTagTap,
  });

  final NoteEntry note;
  final bool isActive;
  final String vaultName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final note = ref.watch(
      notesControllerProvider.select((notes) {
        for (final candidate in notes) {
          if (candidate.id == this.note.id) {
            return candidate;
          }
        }
        return this.note;
      }),
    );
    final createdAt = note.createdAt.toLocal();
    final createdLabel =
        '${createdAt.year}/${createdAt.month}/${createdAt.day} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    final changedAt = (note.updatedAt ?? note.createdAt).toLocal();
    final updatedLabel =
        '${changedAt.year}/${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;
    final tags = note.normalizedTags;
    final buildWatch = kDebugMode ? (Stopwatch()..start()) : null;
    if (buildWatch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        buildWatch.stop();
        _debugNotePerf(
          'detail pane frame ${buildWatch.elapsedMicroseconds / 1000}ms ${_notePerfLabel(note)} tags=${tags.length}',
        );
      });
    }

    return Container(
      decoration: _sectionDecoration(context),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        vaultName,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _mutedTextColor(context),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref
                          .read(notesControllerProvider.notifier)
                          .togglePinned(note.id),
                      icon: Icon(
                        note.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                      ),
                      tooltip: note.isPinned
                          ? strings.localized(
                              en: 'Unpin note',
                              ja: 'ピン留めを解除',
                              zh: '取消置顶',
                              ko: '고정 해제',
                              es: 'Desfijar nota',
                              de: 'Notiz lösen',
                            )
                          : strings.pinThisNote,
                    ),
                    PopupMenuButton<_NoteDetailAction>(
                      tooltip: strings.localized(
                        en: 'Note actions',
                        ja: 'メモ操作',
                        zh: '笔记操作',
                        ko: '메모 작업',
                        es: 'Acciones de nota',
                        de: 'Notizaktionen',
                      ),
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (action) =>
                          _handleNoteDetailAction(context, note, action),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _NoteDetailAction.copy,
                          child: _MediaMenuEntry(
                            icon: Icons.content_copy_rounded,
                            label: strings.localized(
                              en: 'Copy text',
                              ja: 'テキストをコピー',
                              zh: '复制文本',
                              ko: '텍스트 복사',
                              es: 'Copiar texto',
                              de: 'Text kopieren',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: _NoteDetailAction.share,
                          child: _MediaMenuEntry(
                            icon: Icons.ios_share_rounded,
                            label: strings.localized(
                              en: 'Share',
                              ja: '共有',
                              zh: '分享',
                              ko: '공유',
                              es: 'Compartir',
                              de: 'Teilen',
                            ),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      key: const Key('edit-note-button'),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: strings.editNote,
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: strings.deleteNote,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  isEdited ? strings.editedAt(updatedLabel) : createdLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
                if (note.syncState == NoteSyncState.conflict) ...[
                  const SizedBox(height: 12),
                  _SyncConflictNotice(
                    onResolve: () =>
                        _showNoteConflictResolver(context, ref, note),
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags)
                        _NoteTagChip(
                          tag: tag,
                          onTap: onTagTap == null ? null : () => onTagTap!(tag),
                        ),
                    ],
                  ),
                ],
                if (isEdited)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      strings.createdRevision(createdLabel, note.revision),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedTextColor(context),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: _DetailContentSliver(note: note, mediaActive: isActive),
          ),
        ],
      ),
    );
  }
}

class _LinkifiedMemoText extends StatefulWidget {
  const _LinkifiedMemoText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_LinkifiedMemoText> createState() => _LinkifiedMemoTextState();
}

class _LinkifiedMemoTextState extends State<_LinkifiedMemoText> {
  static final _urlPattern = RegExp(r'((?:https?:\/\/|www\.)[^\s<>()]+)');
  final List<TapGestureRecognizer> _recognizers = [];
  late List<_MemoTextSegment> _segments;

  @override
  void initState() {
    super.initState();
    _segments = _parseSegments(widget.text);
  }

  @override
  void didUpdateWidget(covariant _LinkifiedMemoText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
      _segments = _parseSegments(widget.text);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    if (_segments.length == 1 && !_segments.single.isLink) {
      return SelectableText(_segments.single.text, style: style);
    }

    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );
    return SelectableText.rich(
      TextSpan(
        style: style,
        children: [
          for (final segment in _segments)
            TextSpan(
              text: segment.text,
              style: segment.isLink ? linkStyle : null,
              recognizer: segment.recognizer,
            ),
        ],
      ),
    );
  }

  List<_MemoTextSegment> _parseSegments(String text) {
    final matches = _urlPattern.allMatches(text).toList(growable: false);
    if (matches.isEmpty) {
      return [_MemoTextSegment.text(text)];
    }

    final segments = <_MemoTextSegment>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        segments.add(
          _MemoTextSegment.text(text.substring(cursor, match.start)),
        );
      }

      final rawMatch = match.group(0)!;
      final trimmed = _trimTrailingUrlPunctuation(rawMatch);
      final trailing = rawMatch.substring(trimmed.length);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openMemoLink(context, trimmed);
      _recognizers.add(recognizer);
      segments.add(_MemoTextSegment.link(trimmed, recognizer));
      if (trailing.isNotEmpty) {
        segments.add(_MemoTextSegment.text(trailing));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      segments.add(_MemoTextSegment.text(text.substring(cursor)));
    }
    return segments;
  }
}

class _MemoTextSegment {
  const _MemoTextSegment.text(this.text) : recognizer = null, isLink = false;

  const _MemoTextSegment.link(this.text, this.recognizer) : isLink = true;

  final String text;
  final TapGestureRecognizer? recognizer;
  final bool isLink;
}

String _trimTrailingUrlPunctuation(String value) {
  var end = value.length;
  while (end > 0 && '.,;:!?、。)]）}'.contains(value[end - 1])) {
    end -= 1;
  }
  return value.substring(0, end);
}

Future<void> _openMemoLink(BuildContext context, String rawUrl) async {
  final normalized = rawUrl.startsWith(RegExp(r'https?://'))
      ? rawUrl
      : 'https://$rawUrl';
  final shouldOpen = await _confirmExternalLinkOpen(context, normalized);
  if (!shouldOpen || !context.mounted) {
    return;
  }
  final uri = Uri.tryParse(normalized);
  if (uri != null) {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        return;
      }
    } catch (_) {
      // Show a visible failure below.
    }
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      showCloseIcon: true,
      content: Text(context.strings.linkOpenFailed),
    ),
  );
}

Future<bool> _confirmExternalLinkOpen(BuildContext context, String url) async {
  final strings = context.strings;
  return await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(strings.openExternalLinkTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.openExternalLinkMessage),
                const SizedBox(height: 12),
                SelectableText(
                  url,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(strings.openLink),
              ),
            ],
          );
        },
      ) ??
      false;
}

class _DetailContentSliver extends StatefulWidget {
  const _DetailContentSliver({required this.note, required this.mediaActive});

  final NoteEntry note;
  final bool mediaActive;

  @override
  State<_DetailContentSliver> createState() => _DetailContentSliverState();
}

class _DetailContentSliverState extends State<_DetailContentSliver> {
  late List<_DetailContentItem> _items;
  late List<NoteAttachment> _photoAttachments;

  @override
  void initState() {
    super.initState();
    _rebuildContentCache();
  }

  @override
  void didUpdateWidget(covariant _DetailContentSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note != widget.note) {
      _rebuildContentCache();
    }
  }

  void _rebuildContentCache() {
    final watch = kDebugMode ? (Stopwatch()..start()) : null;
    final items = _buildDetailContentItems(widget.note);
    final photoAttachments = items
        .map((item) => item.attachment)
        .whereType<NoteAttachment>()
        .where((attachment) => attachment.type == AttachmentType.photo)
        .toList(growable: false);
    _items = items;
    _photoAttachments = photoAttachments;
    final elapsed = watch?.elapsedMicroseconds;
    if (elapsed != null &&
        (widget.note.blocks.length >= 20 ||
            widget.note.attachments.length >= 10 ||
            elapsed >= 2000)) {
      _debugNotePerf(
        'detail content cache items=${items.length} photos=${photoAttachments.length} ${_notePerfLabel(widget.note)} completed ${elapsed / 1000}ms',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final child = _DetailContentItemWidget(
          item: item,
          mediaActive: widget.mediaActive,
          photoAttachments: _photoAttachments,
        );
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
          child: child,
        );
      },
    );
  }
}

class _DetailContentItemWidget extends StatelessWidget {
  const _DetailContentItemWidget({
    required this.item,
    required this.mediaActive,
    required this.photoAttachments,
  });

  final _DetailContentItem item;
  final bool mediaActive;
  final List<NoteAttachment> photoAttachments;

  @override
  Widget build(BuildContext context) {
    final location = item.location;
    if (location != null) {
      return _LocationMemoCard(
        location: location,
        strings: context.strings,
        width: double.infinity,
      );
    }
    final text = item.text;
    if (text != null) {
      return _LinkifiedMemoText(
        text: text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    final attachment = item.attachment;
    if (attachment == null) {
      return const SizedBox.shrink();
    }
    return _EmbeddedAttachmentBlock(
      attachment: attachment,
      mediaActive: mediaActive,
      photoAttachments: photoAttachments,
      photoIndex: item.photoIndex,
    );
  }
}

class _DetailContentItem {
  const _DetailContentItem.text(this.text)
    : attachment = null,
      location = null,
      photoIndex = null;

  const _DetailContentItem.attachment(this.attachment, {this.photoIndex})
    : text = null,
      location = null;

  const _DetailContentItem.location(this.location)
    : text = null,
      attachment = null,
      photoIndex = null;

  final String? text;
  final NoteAttachment? attachment;
  final _LocationMemoData? location;
  final int? photoIndex;
}

List<_DetailContentItem> _buildDetailContentItems(NoteEntry note) {
  final blocks = note.blocks.isNotEmpty
      ? note.blocks
      : _legacyBlocksFromNote(note);
  if (blocks.isEmpty && note.location == null) {
    return [_DetailContentItem.text(note.body)];
  }

  final items = <_DetailContentItem>[];
  var photoIndex = 0;
  for (final block in blocks) {
    switch (block.type) {
      case NoteBlockType.paragraph:
        final text = block.text?.trim() ?? '';
        if (text.isNotEmpty) {
          final location = _tryParseLocationMemo(text);
          items.add(
            location == null
                ? _DetailContentItem.text(text)
                : _DetailContentItem.location(location),
          );
        }
      case NoteBlockType.photo:
      case NoteBlockType.video:
      case NoteBlockType.audio:
      case NoteBlockType.file:
        final attachment = block.attachment;
        if (attachment != null) {
          items.add(
            _DetailContentItem.attachment(
              attachment,
              photoIndex: attachment.type == AttachmentType.photo
                  ? photoIndex++
                  : null,
            ),
          );
        }
    }
  }
  if (note.location != null) {
    items.add(
      _DetailContentItem.location(
        _locationMemoDataFromMetadata(note.location!),
      ),
    );
  }
  return items;
}

List<NoteBlock> _legacyBlocksFromNote(NoteEntry note) {
  final blocks = <NoteBlock>[];
  if (note.body.trim().isNotEmpty) {
    blocks.add(NoteBlock(type: NoteBlockType.paragraph, text: note.body));
  }
  for (final attachment in note.attachments) {
    blocks.add(
      NoteBlock(
        type: switch (attachment.type) {
          AttachmentType.photo => NoteBlockType.photo,
          AttachmentType.video => NoteBlockType.video,
          AttachmentType.audio => NoteBlockType.audio,
          AttachmentType.file => NoteBlockType.file,
        },
        attachment: attachment,
      ),
    );
  }
  return blocks;
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
