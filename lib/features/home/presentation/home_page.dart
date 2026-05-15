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

String _syncProgressLabel(AppStrings strings, SyncTransferState transferState) {
  if (transferState.stage != SyncTransferStage.busy) {
    return strings.localized(
      en: 'Sync',
      ja: '同期',
      zh: '同步',
      ko: '동기화',
      es: 'Sincronizar',
      de: 'Synchronisieren',
    );
  }
  return switch (transferState.progress) {
    SyncTransferProgress.checkingRemote => strings.localized(
      en: 'Checking',
      ja: '確認中',
      zh: '检查中',
      ko: '확인 중',
      es: 'Comprobando',
      de: 'Prufen',
    ),
    SyncTransferProgress.preparingBundle => strings.localized(
      en: 'Preparing',
      ja: '準備中',
      zh: '准备中',
      ko: '준비 중',
      es: 'Preparando',
      de: 'Vorbereiten',
    ),
    SyncTransferProgress.uploadingBundle => strings.localized(
      en: 'Uploading',
      ja: 'アップロード中',
      zh: '上传中',
      ko: '업로드 중',
      es: 'Subiendo',
      de: 'Hochladen',
    ),
    SyncTransferProgress.downloadingBundle => strings.localized(
      en: 'Downloading',
      ja: 'ダウンロード中',
      zh: '下载中',
      ko: '다운로드 중',
      es: 'Descargando',
      de: 'Herunterladen',
    ),
    SyncTransferProgress.applyingBundle => strings.localized(
      en: 'Applying',
      ja: '適用中',
      zh: '应用中',
      ko: '적용 중',
      es: 'Aplicando',
      de: 'Anwenden',
    ),
    SyncTransferProgress.finalizing => strings.localized(
      en: 'Finishing',
      ja: '完了処理中',
      zh: '完成中',
      ko: '마무리 중',
      es: 'Finalizando',
      de: 'Abschliessen',
    ),
    SyncTransferProgress.none => strings.localized(
      en: 'Syncing',
      ja: '同期中',
      zh: '同步中',
      ko: '동기화 중',
      es: 'Sincronizando',
      de: 'Synchronisierung',
    ),
  };
}

String _syncProgressDescription(
  AppStrings strings,
  SyncTransferState transferState,
  SyncProvider provider,
) {
  if (transferState.stage == SyncTransferStage.busy) {
    return switch (transferState.progress) {
      SyncTransferProgress.checkingRemote => strings.localized(
        en: 'Checking the latest cloud bundle and local queue.',
        ja: 'クラウド上の最新バンドルとこの端末の未同期変更を確認しています。',
        zh: '正在检查最新云端包和本机待同步更改。',
        ko: '최신 클라우드 번들과 이 기기의 미동기화 변경 사항을 확인하고 있습니다.',
        es: 'Comprobando el ultimo paquete en la nube y la cola local.',
        de: 'Aktuelles Cloud-Paket und lokale Warteschlange werden gepruft.',
      ),
      SyncTransferProgress.preparingBundle => strings.localized(
        en: 'Preparing an encrypted bundle from local notes and attachments.',
        ja: 'ローカルのメモと添付から暗号化バンドルを準備しています。',
        zh: '正在根据本机备忘和附件准备加密包。',
        ko: '로컬 메모와 첨부 파일로 암호화 번들을 준비하고 있습니다.',
        es: 'Preparando un paquete cifrado con notas y adjuntos locales.',
        de: 'Verschlusseltes Paket aus lokalen Notizen und Anhangen wird vorbereitet.',
      ),
      SyncTransferProgress.uploadingBundle => strings.localized(
        en: 'Uploading the encrypted bundle to the selected cloud target.',
        ja: '暗号化バンドルを選択中のクラウド同期先へアップロードしています。',
        zh: '正在将加密包上传到选定的云同步目标。',
        ko: '암호화 번들을 선택한 클라우드 동기화 대상으로 업로드하고 있습니다.',
        es: 'Subiendo el paquete cifrado al destino de nube seleccionado.',
        de: 'Verschlusseltes Paket wird zum ausgewahlten Cloud-Ziel hochgeladen.',
      ),
      SyncTransferProgress.downloadingBundle => strings.localized(
        en: 'Downloading the remote bundle before applying cloud changes.',
        ja: 'クラウド側の変更を適用するため、リモートバンドルをダウンロードしています。',
        zh: '正在下载远程包以应用云端更改。',
        ko: '클라우드 변경 사항을 적용하기 위해 원격 번들을 다운로드하고 있습니다.',
        es: 'Descargando el paquete remoto antes de aplicar cambios de nube.',
        de: 'Remote-Paket wird heruntergeladen, bevor Cloud-Anderungen angewendet werden.',
      ),
      SyncTransferProgress.applyingBundle => strings.localized(
        en: 'Decrypting and applying the downloaded bundle to local notes.',
        ja: 'ダウンロードしたバンドルを復号し、ローカルのメモへ適用しています。',
        zh: '正在解密下载的包并应用到本机备忘。',
        ko: '다운로드한 번들을 복호화하여 로컬 메모에 적용하고 있습니다.',
        es: 'Descifrando y aplicando el paquete descargado a las notas locales.',
        de: 'Heruntergeladenes Paket wird entschlusselt und lokal angewendet.',
      ),
      SyncTransferProgress.finalizing => strings.localized(
        en: 'Finishing sync and updating local metadata.',
        ja: '同期を完了し、ローカルの同期情報を更新しています。',
        zh: '正在完成同步并更新本机元数据。',
        ko: '동기화를 완료하고 로컬 메타데이터를 업데이트하고 있습니다.',
        es: 'Finalizando la sincronizacion y actualizando metadatos locales.',
        de: 'Synchronisierung wird abgeschlossen und lokale Metadaten aktualisiert.',
      ),
      SyncTransferProgress.none => strings.localized(
        en: 'Cloud sync is running.',
        ja: 'クラウド同期を実行しています。',
        zh: '云同步正在运行。',
        ko: '클라우드 동기화를 실행하고 있습니다.',
        es: 'La sincronizacion en la nube esta en curso.',
        de: 'Cloud-Synchronisierung lauft.',
      ),
    };
  }
  final message = transferState.message;
  if (message != null && message.isNotEmpty) {
    return _localizedSyncTransferMessage(strings, message, provider);
  }
  return switch (transferState.stage) {
    SyncTransferStage.success => strings.localized(
      en: 'The last sync operation completed.',
      ja: '直近の同期操作は完了しています。',
      zh: '最近的同步操作已完成。',
      ko: '최근 동기화 작업이 완료되었습니다.',
      es: 'La ultima operacion de sincronizacion se completo.',
      de: 'Der letzte Synchronisierungsvorgang ist abgeschlossen.',
    ),
    SyncTransferStage.error => strings.localized(
      en: 'The last sync operation needs attention.',
      ja: '直近の同期操作で確認が必要です。',
      zh: '最近的同步操作需要确认。',
      ko: '최근 동기화 작업에 확인이 필요합니다.',
      es: 'La ultima operacion de sincronizacion requiere atencion.',
      de: 'Der letzte Synchronisierungsvorgang erfordert Aufmerksamkeit.',
    ),
    SyncTransferStage.idle || SyncTransferStage.busy => strings.localized(
      en: 'Sync is ready.',
      ja: '同期を実行できます。',
      zh: '可以同步。',
      ko: '동기화할 수 있습니다.',
      es: 'La sincronizacion esta lista.',
      de: 'Synchronisierung ist bereit.',
    ),
  };
}

String _localizedSyncTransferMessage(
  AppStrings strings,
  String message,
  SyncProvider provider,
) {
  final providerName = _syncProviderName(provider);
  switch (message) {
    case 'sync.error.local_snapshot_incomplete':
      return strings.localized(
        en: 'Some pending notes cannot be uploaded yet. If private profile notes are included, open the matching private profile on this device and sync again.',
        ja: '未同期の一部のメモはまだアップロードできません。プライベートプロファイルのメモが含まれる場合は、この端末で該当プロファイルを開いてからもう一度同期してください。',
        zh: '部分待同步笔记暂时无法上传。如果包含私密配置文件的笔记，请先在此设备上打开对应配置文件，然后再次同步。',
        ko: '일부 대기 중인 메모는 아직 업로드할 수 없습니다. 비공개 프로필 메모가 포함된 경우 이 기기에서 해당 프로필을 연 뒤 다시 동기화하세요.',
        es: 'Algunas notas pendientes todavia no se pueden subir. Si incluyen notas de perfiles privados, abre el perfil privado correspondiente en este dispositivo y vuelve a sincronizar.',
        de: 'Einige ausstehende Notizen konnen noch nicht hochgeladen werden. Wenn private Profilnotizen enthalten sind, offne das passende private Profil auf diesem Gerat und synchronisiere erneut.',
      );
    case 'sync.error.bundle_decryption_failed':
      return strings.localized(
        en:
            'Sync data could not be decrypted.\n'
            '- The cloud recovery key may be different. Copy the cloud recovery key from the original device and import it on this device.\n'
            '- If notes or attachments were repaired on the original device, re-upload all notes from that device and sync again.\n'
            '- If private profile notes are included, open the target private profile on this device, then apply the bundle again.',
        ja:
            '同期データを復号できませんでした。\n'
            '・クラウド復元キーが違う可能性があります。元端末でクラウド復元キーをコピーし、この端末へ読み込んでください。\n'
            '・元端末で添付やメモを修復した場合は、元端末で全メモを再アップロードしてから同期してください。\n'
            '・プライベートプロファイルのメモが含まれる場合は、同期先端末で対象プロファイルを開いてから、もう一度適用してください。',
        zh:
            '无法解密同步数据。\n'
            '- 云恢复密钥可能不同。请从原设备复制云恢复密钥，并在此设备导入。\n'
            '- 如果在原设备修复了备忘或附件，请从原设备重新上传全部备忘后再同步。\n'
            '- 如果包含私密配置文件的备忘，请先在此设备打开目标私密配置文件，然后再次应用同步包。',
        ko:
            '동기화 데이터를 복호화할 수 없습니다.\n'
            '- 클라우드 복구 키가 다를 수 있습니다. 원래 기기에서 클라우드 복구 키를 복사해 이 기기로 가져오세요.\n'
            '- 원래 기기에서 메모나 첨부 파일을 복구했다면, 그 기기에서 모든 메모를 다시 업로드한 뒤 동기화하세요.\n'
            '- 개인 프로필 메모가 포함된 경우 이 기기에서 대상 개인 프로필을 연 뒤 번들을 다시 적용하세요.',
        es:
            'No se pudieron descifrar los datos de sincronizacion.\n'
            '- Es posible que la clave de recuperacion en la nube sea distinta. Copiala desde el dispositivo original e importala en este dispositivo.\n'
            '- Si reparaste notas o adjuntos en el dispositivo original, vuelve a subir todas las notas desde ese dispositivo y sincroniza de nuevo.\n'
            '- Si incluye notas de perfiles privados, abre el perfil privado correspondiente en este dispositivo y vuelve a aplicar el paquete.',
        de:
            'Synchronisierungsdaten konnten nicht entschlusselt werden.\n'
            '- Der Cloud-Wiederherstellungsschlussel ist moglicherweise anders. Kopiere ihn vom ursprunglichen Gerat und importiere ihn auf diesem Gerat.\n'
            '- Wenn Notizen oder Anhange auf dem ursprunglichen Gerat repariert wurden, lade alle Notizen von dort erneut hoch und synchronisiere noch einmal.\n'
            '- Wenn Notizen privater Profile enthalten sind, offne das Zielprofil auf diesem Gerat und wende das Paket erneut an.',
      );
    case 'sync.error.bundle_key_missing':
      return strings.localized(
        en: 'The cloud recovery key for this sync bundle is not available on this device. Copy the cloud recovery key from the original device, import it here, then sync again.',
        ja: '同期バンドルを読むためのクラウド復元キーがこの端末にありません。元端末でクラウド復元キーをコピーし、この端末へ読み込んでから、もう一度同期してください。',
        zh: '此设备没有读取同步包所需的云恢复密钥。请从原设备复制云恢复密钥并在此设备导入，然后再次同步。',
        ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 없습니다. 원래 기기에서 키를 복사해 이 기기로 가져온 뒤 다시 동기화하세요.',
        es: 'La clave de recuperacion en la nube para este paquete no esta disponible en este dispositivo. Copiala desde el dispositivo original, importala aqui y sincroniza de nuevo.',
        de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Synchronisierungspaket ist auf diesem Gerat nicht verfugbar. Kopiere ihn vom ursprunglichen Gerat, importiere ihn hier und synchronisiere erneut.',
      );
    case 'sync.error.icloud_keychain_waiting':
      return strings.localized(
        en: 'The cloud recovery key for this sync bundle is not on this device yet. iCloud Keychain may still be syncing. Wait a little and try again, or copy the cloud recovery key from the original device and import it here.',
        ja: '同期バンドルを読むためのクラウド復元キーがまだこの端末にありません。iCloud Keychain の同期待ちの可能性があります。しばらく待ってから再試行するか、元端末でクラウド復元キーをコピーしてこの端末へ読み込んでください。',
        zh: '此设备还没有读取同步包所需的云恢复密钥。可能正在等待 iCloud Keychain 同步。请稍后重试，或从原设备复制云恢复密钥并在此设备导入。',
        ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 아직 없습니다. iCloud Keychain 동기화 대기 중일 수 있습니다. 잠시 후 다시 시도하거나 원래 기기에서 키를 복사해 가져오세요.',
        es: 'La clave de recuperacion en la nube para este paquete aun no esta en este dispositivo. Es posible que iCloud Keychain siga sincronizando. Espera un poco e intentalo de nuevo, o copia la clave desde el dispositivo original e importala aqui.',
        de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Paket ist noch nicht auf diesem Gerat. iCloud Keychain synchronisiert moglicherweise noch. Warte kurz und versuche es erneut oder importiere den Schlussel vom ursprunglichen Gerat.',
      );
    case 'sync.info.select_target_for_remote_status':
      return strings.localized(
        en: 'Select a cloud sync target before checking the remote status.',
        ja: 'リモートの状態を確認するには、先にクラウド同期先を選択してください。',
        zh: '请先选择云同步目标，再检查远程状态。',
        ko: '원격 상태를 확인하기 전에 클라우드 동기화 대상을 선택하세요.',
        es: 'Selecciona un destino de sincronizacion en la nube antes de comprobar el estado remoto.',
        de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du den Remote-Status prufst.',
      );
    case 'sync.info.no_remote_bundle':
      return strings.localized(
        en: 'No remote bundle has been saved yet.',
        ja: 'リモートにはまだバンドルが保存されていません。',
        zh: '远程还没有保存同步包。',
        ko: '원격에 저장된 번들이 아직 없습니다.',
        es: 'Todavia no se ha guardado ningun paquete remoto.',
        de: 'Es wurde noch kein Remote-Paket gespeichert.',
      );
    case 'sync.info.remote_bundle_refreshed':
      return strings.localized(
        en: '$providerName bundle information was refreshed.',
        ja: '$providerName のバンドル情報を更新しました。',
        zh: '$providerName 的同步包信息已更新。',
        ko: '$providerName 번들 정보를 새로 고쳤습니다.',
        es: 'Se actualizo la informacion del paquete de $providerName.',
        de: 'Die Paketinformationen von $providerName wurden aktualisiert.',
      );
    case 'sync.error.select_target_for_upload':
    case 'sync.error.select_target_for_reupload':
    case 'sync.error.select_target_for_download':
      return strings.localized(
        en: 'Select a cloud sync target before continuing.',
        ja: '先にクラウド同期先を選択してください。',
        zh: '请先选择云同步目标再继续。',
        ko: '계속하기 전에 클라우드 동기화 대상을 선택하세요.',
        es: 'Selecciona un destino de sincronizacion en la nube antes de continuar.',
        de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du fortfahrst.',
      );
    case 'sync.error.conflict_download_first_or_force_upload':
      return strings.localized(
        en: 'This device has unsynced changes and the remote bundle may be newer. Download and apply the remote bundle first, or use force upload if you want this device to overwrite the remote bundle.',
        ja: 'この端末に未同期の変更があり、リモートにはより新しいバンドルがある可能性があります。先にリモートのバンドルをダウンロードして適用するか、上書きする場合は強制アップロードを使用してください。',
        zh: '此设备有未同步的更改，远程包可能更新。请先下载并应用远程包；如果要用此设备覆盖远程包，请使用强制上传。',
        ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 먼저 원격 번들을 다운로드해 적용하거나, 이 기기로 덮어쓰려면 강제 업로드를 사용하세요.',
        es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Descarga y aplica primero el paquete remoto, o usa la subida forzada si quieres sobrescribirlo desde este dispositivo.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Lade es zuerst herunter und wende es an, oder nutze erzwungenes Hochladen, wenn dieses Gerat das Remote-Paket uberschreiben soll.',
      );
    case 'sync.error.conflict_pending_remote_newer':
      return strings.localized(
        en: 'This device has unsynced changes, and a newer bundle exists on the remote sync target.',
        ja: 'この端末に未同期の変更があり、リモートにはより新しいバンドルがあります。',
        zh: '此设备有未同步的更改，远程同步目标上有较新的捆绑包。',
        ko: '이 기기에 동기화되지 않은 변경 사항이 있으며, 원격 동기화 대상에 더 새로운 번들이 있습니다.',
        es: 'Este dispositivo tiene cambios sin sincronizar y hay un paquete mas reciente en el destino remoto.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen, und auf dem Remote-Synchronisierungsziel liegt ein neueres Paket vor.',
      );
    case 'sync.error.local_bundle_prepare_failed':
      return strings.localized(
        en: 'The local sync bundle could not be prepared.',
        ja: 'ローカルの同期バンドルを準備できませんでした。',
        zh: '无法准备本地同步包。',
        ko: '로컬 동기화 번들을 준비할 수 없습니다.',
        es: 'No se pudo preparar el paquete de sincronizacion local.',
        de: 'Das lokale Synchronisierungspaket konnte nicht vorbereitet werden.',
      );
    case 'sync.error.large_mobile_transfer_requires_confirmation':
      return strings.localized(
        en: 'This sync is large and the current connection appears to be mobile data. Confirm from the sync button before continuing.',
        ja: 'この同期は大きく、現在の接続はモバイル回線のようです。続行するには同期ボタンから確認してください。',
        zh: '本次同步较大，当前连接似乎是移动数据。请从同步按钮确认后继续。',
        ko: '이번 동기화는 크고 현재 연결이 모바일 데이터로 보입니다. 계속하려면 동기화 버튼에서 확인하세요.',
        es: 'Esta sincronizacion es grande y la conexion actual parece ser de datos moviles. Confirma desde el boton de sincronizacion antes de continuar.',
        de: 'Diese Synchronisierung ist gross und die aktuelle Verbindung scheint mobil zu sein. Bestatige uber die Synchronisierungsschaltflache, bevor du fortfahrst.',
      );
    case 'sync.info.upload_success':
      return strings.localized(
        en: 'Encrypted bundle uploaded to $providerName.',
        ja: '暗号化したバンドルを $providerName にアップロードしました。',
        zh: '已将加密同步包上传到 $providerName。',
        ko: '암호화된 번들을 $providerName에 업로드했습니다.',
        es: 'Paquete cifrado subido a $providerName.',
        de: 'Verschlusseltes Paket wurde zu $providerName hochgeladen.',
      );
    case 'sync.error.conflict_review_remote':
      return strings.localized(
        en: 'This device has unsynced changes and the remote bundle may be newer. Review the remote changes before syncing.',
        ja: 'この端末に未同期の変更があり、リモートにはより新しいバンドルがある可能性があります。リモートの変更を確認してから同期してください。',
        zh: '此设备有未同步的更改，远程包可能更新。请先确认远程更改再同步。',
        ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 동기화하기 전에 원격 변경 사항을 확인하세요.',
        es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Revisa los cambios remotos antes de sincronizar.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Prufe die Remote-Anderungen vor der Synchronisierung.',
      );
    case 'sync.info.no_bundle_to_sync':
    case 'sync.info.no_usable_remote_bundle':
      return strings.localized(
        en: 'No usable sync bundle is available in $providerName.',
        ja: '$providerName に利用できる同期バンドルはありません。',
        zh: '$providerName 中没有可用的同步包。',
        ko: '$providerName에 사용할 수 있는 동기화 번들이 없습니다.',
        es: 'No hay ningun paquete de sincronizacion disponible en $providerName.',
        de: 'In $providerName ist kein nutzbares Synchronisierungspaket verfugbar.',
      );
    case 'sync.info.sync_success':
      return strings.localized(
        en: 'Synced with $providerName.',
        ja: '$providerName と同期済みです。',
        zh: '已与 $providerName 同步。',
        ko: '$providerName와 동기화되었습니다.',
        es: 'Sincronizado con $providerName.',
        de: 'Mit $providerName synchronisiert.',
      );
    case 'sync.error.selected_bundle_download_failed':
    case 'sync.error.remote_bundle_download_failed':
      return strings.localized(
        en: 'The selected remote bundle could not be downloaded.',
        ja: '選択したリモートバンドルをダウンロードできませんでした。',
        zh: '无法下载选定的远程同步包。',
        ko: '선택한 원격 번들을 다운로드할 수 없습니다.',
        es: 'No se pudo descargar el paquete remoto seleccionado.',
        de: 'Das ausgewahlte Remote-Paket konnte nicht heruntergeladen werden.',
      );
    case 'sync.error.download_before_apply':
    case 'sync.error.download_before_review':
      return strings.localized(
        en: 'Download a remote bundle before continuing.',
        ja: '続行する前にリモートバンドルをダウンロードしてください。',
        zh: '请先下载远程包再继续。',
        ko: '계속하기 전에 원격 번들을 다운로드하세요.',
        es: 'Descarga un paquete remoto antes de continuar.',
        de: 'Lade zuerst ein Remote-Paket herunter, bevor du fortfahrst.',
      );
    case 'sync.error.downloaded_bundle_decryption_failed':
      return strings.localized(
        en: 'The downloaded bundle could not be decrypted.',
        ja: 'ダウンロードしたバンドルを復号できませんでした。',
        zh: '无法解密已下载的同步包。',
        ko: '다운로드한 번들을 복호화할 수 없습니다.',
        es: 'No se pudo descifrar el paquete descargado.',
        de: 'Das heruntergeladene Paket konnte nicht entschlusselt werden.',
      );
    case 'sync.error.attachment_object_hash_mismatch':
      return strings.localized(
        en: 'A downloaded attachment did not match its sync metadata. Re-upload all notes from the original device and sync again.',
        ja: 'ダウンロードした添付が同期メタデータと一致しませんでした。元端末で全メモを再アップロードしてから、もう一度同期してください。',
        zh: '下载的附件与同步元数据不匹配。请从原设备重新上传全部备忘后再同步。',
        ko: '다운로드한 첨부가 동기화 메타데이터와 일치하지 않습니다. 원래 기기에서 모든 메모를 다시 업로드한 뒤 동기화하세요.',
        es: 'Un adjunto descargado no coincide con sus metadatos de sincronizacion. Vuelve a subir todas las notas desde el dispositivo original y sincroniza de nuevo.',
        de: 'Ein heruntergeladener Anhang passt nicht zu seinen Synchronisierungsmetadaten. Lade alle Notizen vom ursprunglichen Gerat erneut hoch und synchronisiere noch einmal.',
      );
    case 'sync.error.private_profile_locked':
      return strings.localized(
        en: 'This bundle contains private profile notes. Enter the same private profile password on this device, open that profile, then apply the bundle again.',
        ja: 'プライベートプロファイルのメモが含まれています。同期先端末で同じプロファイルパスワードを入力して開いてから、もう一度適用してください。',
        zh: '此同步包包含私密配置文件的备忘。请在此设备输入相同的配置文件密码并打开该配置文件，然后再次应用同步包。',
        ko: '이 번들에는 개인 프로필 메모가 포함되어 있습니다. 이 기기에서 동일한 프로필 비밀번호를 입력해 프로필을 연 뒤 번들을 다시 적용하세요.',
        es: 'Este paquete contiene notas de perfiles privados. Introduce la misma contrasena de perfil en este dispositivo, abre ese perfil y vuelve a aplicar el paquete.',
        de: 'Dieses Paket enthalt Notizen privater Profile. Gib auf diesem Gerat dasselbe Profilpasswort ein, offne das Profil und wende das Paket erneut an.',
      );
    case 'sync.info.apply_success':
      return strings.localized(
        en: 'Downloaded bundle applied to local notes.',
        ja: 'ダウンロードしたバンドルをローカルのノートに反映しました。',
        zh: '已将下载的同步包应用到本地笔记。',
        ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
        es: 'Paquete descargado aplicado a las notas locales.',
        de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
      );
    case 'sync.info.private_profile_notes_pending_unlock':
      return strings.localized(
        en: 'Sync completed. Private profile notes will be applied after you open the matching private profile on this device.',
        ja: '同期は完了しました。プライベートプロファイルのメモは、この端末で該当するプロファイルを開いたあとに反映されます。',
        zh: '同步已完成。私人配置文件中的笔记会在你在此设备上打开对应配置文件后应用。',
        ko: '동기화가 완료되었습니다. 비공개 프로필 메모는 이 기기에서 해당 프로필을 연 뒤 적용됩니다.',
        es: 'La sincronizacion se completo. Las notas de perfiles privados se aplicaran cuando abras el perfil privado correspondiente en este dispositivo.',
        de: 'Die Synchronisierung ist abgeschlossen. Notizen privater Profile werden angewendet, nachdem du das passende private Profil auf diesem Gerat geoffnet hast.',
      );
    case 'sync.info.deferred_attachments_downloaded':
      return strings.localized(
        en: 'Pending attachments were downloaded.',
        ja: '保留中の添付をダウンロードしました。',
        zh: '已下载待处理附件。',
        ko: '보류 중인 첨부를 다운로드했습니다.',
        es: 'Se descargaron los adjuntos pendientes.',
        de: 'Ausstehende Anhänge wurden heruntergeladen.',
      );
    case 'sync.info.no_deferred_attachments':
      return strings.localized(
        en: 'No pending attachments need to be downloaded.',
        ja: 'ダウンロード待ちの添付はありません。',
        zh: '没有需要下载的待处理附件。',
        ko: '다운로드할 보류 중인 첨부가 없습니다.',
        es: 'No hay adjuntos pendientes para descargar.',
        de: 'Keine ausstehenden Anhänge zum Herunterladen.',
      );
    case 'sync.info.remote_bundle_saved_locally':
      return strings.localized(
        en: '$providerName remote bundle was saved to protected local storage.',
        ja: '$providerName のリモートバンドルをローカルの保護ストレージに保存しました。',
        zh: '已将 $providerName 远程包保存到本地受保护存储。',
        ko: '$providerName 원격 번들을 로컬 보호 저장소에 저장했습니다.',
        es: 'El paquete remoto de $providerName se guardo en el almacenamiento local protegido.',
        de: 'Das Remote-Paket von $providerName wurde im geschutzten lokalen Speicher abgelegt.',
      );
  }
  if (message ==
      '同期データを復号できませんでした。\n'
          '・クラウド復元キーが違う可能性があります。元端末でクラウド復元キーをコピーし、この端末へ読み込んでください。\n'
          '・元端末で添付やメモを修復した場合は、元端末で全メモを再アップロードしてから同期してください。\n'
          '・プライベートプロファイルのメモが含まれる場合は、同期先端末で対象プロファイルを開いてから、もう一度適用してください。') {
    return strings.localized(
      en:
          'Sync data could not be decrypted.\n'
          '- The cloud recovery key may be different. Copy the cloud recovery key from the original device and import it on this device.\n'
          '- If notes or attachments were repaired on the original device, re-upload all notes from that device and sync again.\n'
          '- If private profile notes are included, open the target private profile on this device, then apply the bundle again.',
      ja: message,
      zh:
          '无法解密同步数据。\n'
          '- 云恢复密钥可能不同。请从原设备复制云恢复密钥，并在此设备导入。\n'
          '- 如果在原设备修复了备忘或附件，请从原设备重新上传全部备忘后再同步。\n'
          '- 如果包含私密配置文件的备忘，请先在此设备打开目标私密配置文件，然后再次应用同步包。',
      ko:
          '동기화 데이터를 복호화할 수 없습니다.\n'
          '- 클라우드 복구 키가 다를 수 있습니다. 원래 기기에서 클라우드 복구 키를 복사해 이 기기로 가져오세요.\n'
          '- 원래 기기에서 메모나 첨부 파일을 복구했다면, 그 기기에서 모든 메모를 다시 업로드한 뒤 동기화하세요.\n'
          '- 개인 프로필 메모가 포함된 경우 이 기기에서 대상 개인 프로필을 연 뒤 번들을 다시 적용하세요.',
      es:
          'No se pudieron descifrar los datos de sincronizacion.\n'
          '- Es posible que la clave de recuperacion en la nube sea distinta. Copiala desde el dispositivo original e importala en este dispositivo.\n'
          '- Si reparaste notas o adjuntos en el dispositivo original, vuelve a subir todas las notas desde ese dispositivo y sincroniza de nuevo.\n'
          '- Si incluye notas de perfiles privados, abre el perfil privado correspondiente en este dispositivo y vuelve a aplicar el paquete.',
      de:
          'Synchronisierungsdaten konnten nicht entschlusselt werden.\n'
          '- Der Cloud-Wiederherstellungsschlussel ist moglicherweise anders. Kopiere ihn vom ursprunglichen Gerat und importiere ihn auf diesem Gerat.\n'
          '- Wenn Notizen oder Anhange auf dem ursprunglichen Gerat repariert wurden, lade alle Notizen von dort erneut hoch und synchronisiere noch einmal.\n'
          '- Wenn Notizen privater Profile enthalten sind, offne das Zielprofil auf diesem Gerat und wende das Paket erneut an.',
    );
  }
  if (message ==
      '同期バンドルを読むためのクラウド復元キーがこの端末にありません。元端末でクラウド復元キーをコピーし、この端末へ読み込んでから、もう一度同期してください。') {
    return strings.localized(
      en: 'The cloud recovery key for this sync bundle is not available on this device. Copy the cloud recovery key from the original device, import it here, then sync again.',
      ja: message,
      zh: '此设备没有读取同步包所需的云恢复密钥。请从原设备复制云恢复密钥并在此设备导入，然后再次同步。',
      ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 없습니다. 원래 기기에서 키를 복사해 이 기기로 가져온 뒤 다시 동기화하세요.',
      es: 'La clave de recuperacion en la nube para este paquete no esta disponible en este dispositivo. Copiala desde el dispositivo original, importala aqui y sincroniza de nuevo.',
      de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Synchronisierungspaket ist auf diesem Gerat nicht verfugbar. Kopiere ihn vom ursprunglichen Gerat, importiere ihn hier und synchronisiere erneut.',
    );
  }
  if (message ==
      '同期バンドルを読むためのクラウド復元キーがまだこの端末にありません。iCloud Keychain の同期待ちの可能性があります。しばらく待ってから再試行するか、元端末でクラウド復元キーをコピーしてこの端末へ読み込んでください。') {
    return strings.localized(
      en: 'The cloud recovery key for this sync bundle is not on this device yet. iCloud Keychain may still be syncing. Wait a little and try again, or copy the cloud recovery key from the original device and import it here.',
      ja: message,
      zh: '此设备还没有读取同步包所需的云恢复密钥。可能正在等待 iCloud Keychain 同步。请稍后重试，或从原设备复制云恢复密钥并在此设备导入。',
      ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 아직 없습니다. iCloud Keychain 동기화 대기 중일 수 있습니다. 잠시 후 다시 시도하거나 원래 기기에서 키를 복사해 가져오세요.',
      es: 'La clave de recuperacion en la nube para este paquete aun no esta en este dispositivo. Es posible que iCloud Keychain siga sincronizando. Espera un poco e intentalo de nuevo, o copia la clave desde el dispositivo original e importala aqui.',
      de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Paket ist noch nicht auf diesem Gerat. iCloud Keychain synchronisiert moglicherweise noch. Warte kurz und versuche es erneut oder importiere den Schlussel vom ursprunglichen Gerat.',
    );
  }
  if (message == 'リモートの状態を確認するには、先にクラウド同期先を選択してください。') {
    return strings.localized(
      en: 'Select a cloud sync target before checking the remote status.',
      ja: message,
      zh: '请先选择云同步目标，再检查远程状态。',
      ko: '원격 상태를 확인하기 전에 클라우드 동기화 대상을 선택하세요.',
      es: 'Selecciona un destino de sincronizacion en la nube antes de comprobar el estado remoto.',
      de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du den Remote-Status prufst.',
    );
  }
  if (message == 'リモートにはまだバンドルが保存されていません。') {
    return strings.localized(
      en: 'No remote bundle has been saved yet.',
      ja: message,
      zh: '远程还没有保存同步包。',
      ko: '원격에 저장된 번들이 아직 없습니다.',
      es: 'Todavia no se ha guardado ningun paquete remoto.',
      de: 'Es wurde noch kein Remote-Paket gespeichert.',
    );
  }
  if (message == 'アップロードするには、先にクラウド同期先を選択してください。' ||
      message == '再アップロードするには、先にクラウド同期先を選択してください。' ||
      message == 'ダウンロードするには、先にクラウド同期先を選択してください。') {
    return strings.localized(
      en: 'Select a cloud sync target before continuing.',
      ja: message,
      zh: '请先选择云同步目标再继续。',
      ko: '계속하기 전에 클라우드 동기화 대상을 선택하세요.',
      es: 'Selecciona un destino de sincronizacion en la nube antes de continuar.',
      de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du fortfahrst.',
    );
  }
  if (message.contains('先にリモートのバンドルをダウンロードして適用するか')) {
    return strings.localized(
      en: 'This device has unsynced changes and the remote bundle may be newer. Download and apply the remote bundle first, or use force upload if you want this device to overwrite the remote bundle.',
      ja: message,
      zh: '此设备有未同步的更改，远程包可能更新。请先下载并应用远程包；如果要用此设备覆盖远程包，请使用强制上传。',
      ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 먼저 원격 번들을 다운로드해 적용하거나, 이 기기로 덮어쓰려면 강제 업로드를 사용하세요.',
      es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Descarga y aplica primero el paquete remoto, o usa la subida forzada si quieres sobrescribirlo desde este dispositivo.',
      de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Lade es zuerst herunter und wende es an, oder nutze erzwungenes Hochladen, wenn dieses Gerat das Remote-Paket uberschreiben soll.',
    );
  }
  if (message.contains('リモートの変更を確認してから同期してください。')) {
    return strings.localized(
      en: 'This device has unsynced changes and the remote bundle may be newer. Review the remote changes before syncing.',
      ja: message,
      zh: '此设备有未同步的更改，远程包可能更新。请先确认远程更改再同步。',
      ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 동기화하기 전에 원격 변경 사항을 확인하세요.',
      es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Revisa los cambios remotos antes de sincronizar.',
      de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Prufe die Remote-Anderungen vor der Synchronisierung.',
    );
  }
  if (message == 'ローカルの同期バンドルを準備できませんでした。') {
    return strings.localized(
      en: 'The local sync bundle could not be prepared.',
      ja: message,
      zh: '无法准备本地同步包。',
      ko: '로컬 동기화 번들을 준비할 수 없습니다.',
      es: 'No se pudo preparar el paquete de sincronizacion local.',
      de: 'Das lokale Synchronisierungspaket konnte nicht vorbereitet werden.',
    );
  }
  if (message == '暗号化したバンドルを $providerName にアップロードしました。') {
    return strings.localized(
      en: 'Encrypted bundle uploaded to $providerName.',
      ja: message,
      zh: '已将加密同步包上传到 $providerName。',
      ko: '암호화된 번들을 $providerName에 업로드했습니다.',
      es: 'Paquete cifrado subido a $providerName.',
      de: 'Verschlusseltes Paket wurde zu $providerName hochgeladen.',
    );
  }
  if (message == '$providerName と同期済みです。') {
    return strings.localized(
      en: 'Synced with $providerName.',
      ja: message,
      zh: '已与 $providerName 同步。',
      ko: '$providerName와 동기화되었습니다.',
      es: 'Sincronizado con $providerName.',
      de: 'Mit $providerName synchronisiert.',
    );
  }
  if (message.contains('に同期できるバンドルはありません') ||
      message.contains('に利用できるリモートバンドルはありません')) {
    return strings.localized(
      en: 'No usable sync bundle is available in $providerName.',
      ja: message,
      zh: '$providerName 中没有可用的同步包。',
      ko: '$providerName에 사용할 수 있는 동기화 번들이 없습니다.',
      es: 'No hay ningun paquete de sincronizacion disponible en $providerName.',
      de: 'In $providerName ist kein nutzbares Synchronisierungspaket verfugbar.',
    );
  }
  if (message == '適用する前にリモートバンドルをダウンロードしてください。' ||
      message == '確認する前にリモートバンドルをダウンロードしてください。') {
    return strings.localized(
      en: 'Download a remote bundle before continuing.',
      ja: message,
      zh: '请先下载远程包再继续。',
      ko: '계속하기 전에 원격 번들을 다운로드하세요.',
      es: 'Descarga un paquete remoto antes de continuar.',
      de: 'Lade zuerst ein Remote-Paket herunter, bevor du fortfahrst.',
    );
  }
  if (message == 'ダウンロードしたバンドルを復号できませんでした。') {
    return strings.localized(
      en: 'The downloaded bundle could not be decrypted.',
      ja: message,
      zh: '无法解密已下载的同步包。',
      ko: '다운로드한 번들을 복호화할 수 없습니다.',
      es: 'No se pudo descifrar el paquete descargado.',
      de: 'Das heruntergeladene Paket konnte nicht entschlusselt werden.',
    );
  }
  if (message ==
      'プライベートプロファイルのメモが含まれています。同期先端末で同じプロファイルパスワードを入力して開いてから、もう一度適用してください。') {
    return strings.localized(
      en: 'This bundle contains private profile notes. Enter the same private profile password on this device, open that profile, then apply the bundle again.',
      ja: message,
      zh: '此同步包包含私密配置文件的备忘。请在此设备输入相同的配置文件密码并打开该配置文件，然后再次应用同步包。',
      ko: '이 번들에는 개인 프로필 메모가 포함되어 있습니다. 이 기기에서 동일한 프로필 비밀번호를 입력해 프로필을 연 뒤 번들을 다시 적용하세요.',
      es: 'Este paquete contiene notas de perfiles privados. Introduce la misma contrasena de perfil en este dispositivo, abre ese perfil y vuelve a aplicar el paquete.',
      de: 'Dieses Paket enthalt Notizen privater Profile. Gib auf diesem Gerat dasselbe Profilpasswort ein, offne das Profil und wende das Paket erneut an.',
    );
  }
  if (message == 'ダウンロードしたバンドルをローカルのノートに反映しました。') {
    return strings.localized(
      en: 'Downloaded bundle applied to local notes.',
      ja: message,
      zh: '已将下载的同步包应用到本地笔记。',
      ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
      es: 'Paquete descargado aplicado a las notas locales.',
      de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
    );
  }
  if (message.contains('のリモートバンドルをローカルの保護ストレージに保存しました。')) {
    return strings.localized(
      en: '$providerName remote bundle was saved to protected local storage.',
      ja: message,
      zh: '已将 $providerName 远程包保存到本地受保护存储。',
      ko: '$providerName 원격 번들을 로컬 보호 저장소에 저장했습니다.',
      es: 'El paquete remoto de $providerName se guardo en el almacenamiento local protegido.',
      de: 'Das Remote-Paket von $providerName wurde im geschutzten lokalen Speicher abgelegt.',
    );
  }
  return message;
}

double? _syncProgressValue(SyncTransferProgress progress) {
  return switch (progress) {
    SyncTransferProgress.checkingRemote => 0.18,
    SyncTransferProgress.preparingBundle => 0.38,
    SyncTransferProgress.uploadingBundle => 0.64,
    SyncTransferProgress.downloadingBundle => 0.48,
    SyncTransferProgress.applyingBundle => 0.78,
    SyncTransferProgress.finalizing => 0.92,
    SyncTransferProgress.none => null,
  };
}

String _remoteBundleSummary(
  AppStrings strings,
  SyncProvider provider,
  SyncTransferState transferState,
  SyncBundleState? bundleState,
) {
  if (provider == SyncProvider.off) {
    return strings.text('home.remote.bundle.storage.is.not.configured.yet');
  }
  if (provider == SyncProvider.iCloud && transferState.remoteStatus == null) {
    return strings.text('home.no.icloud.bundle.metadata.loaded.yet');
  }
  if (provider != SyncProvider.googleDrive && provider != SyncProvider.iCloud) {
    return strings.text('home.remote.bundle.transport.is.not.available.yet');
  }
  if (provider == SyncProvider.off) {
    return strings.text('home.remote.bundle.storage.is.not.configured.yet.2');
  }
  if (provider == SyncProvider.iCloud && transferState.remoteStatus == null) {
    return strings.text('home.no.icloud.bundle.metadata.loaded.yet.2');
  }
  if (provider != SyncProvider.googleDrive && provider != SyncProvider.iCloud) {
    return strings.text(
      'home.remote.bundle.transport.is.only.wired.for.google.drive.r',
    );
  }
  final remote = transferState.remoteStatus;
  if (remote == null) {
    final lastRemoteAt = bundleState?.lastRemoteModifiedAt;
    if (lastRemoteAt != null) {
      final modifiedAt = _formatDateTime(lastRemoteAt, strings);
      return strings.localized(
        en: 'Last known remote bundle: $modifiedAt. Refresh to check for newer changes.',
        ja: '最後に確認したリモートバンドル: $modifiedAt。新しい変更を確認するには更新してください。',
        zh: '上次确认的远程包：$modifiedAt。请刷新以检查更新。',
        ko: '마지막으로 확인한 원격 번들: $modifiedAt. 새 변경 사항은 새로고침으로 확인하세요.',
        es: 'Ultimo paquete remoto conocido: $modifiedAt. Actualiza para comprobar cambios nuevos.',
        de: 'Zuletzt bekanntes Remote-Bundle: $modifiedAt. Aktualisiere, um neuere Anderungen zu prufen.',
      );
    }
    return strings.text('home.no.remote.bundle.metadata.loaded.yet');
  }
  final modifiedAt = remote.modifiedAt == null
      ? (strings.text('home.unknown.time'))
      : _formatDateTime(remote.modifiedAt!, strings);
  final sizeLabel = remote.sizeBytes == null
      ? (strings.text('home.size.unknown'))
      : strings.byteCount(remote.sizeBytes!);
  final noteCount = remote.noteCount == null ? '?' : '${remote.noteCount}';
  final attachmentCount = remote.attachmentCount == null
      ? '?'
      : '${remote.attachmentCount}';
  return strings.localized(
    en: 'Latest change bundle: $modifiedAt, $sizeLabel, $noteCount changed notes, $attachmentCount attachments.',
    ja: '最新の変更バンドル: $modifiedAt、$sizeLabel、変更ノート $noteCount 件、添付 $attachmentCount 件。',
    zh: '最新变更包：$modifiedAt，$sizeLabel，变更笔记 $noteCount 条，附件 $attachmentCount 个。',
    ko: '최신 변경 번들: $modifiedAt, $sizeLabel, 변경된 노트 $noteCount개, 첨부 $attachmentCount개.',
    es: 'Último paquete de cambios: $modifiedAt, $sizeLabel, $noteCount notas cambiadas, $attachmentCount adjuntos.',
    de: 'Letztes Änderungs-Bundle: $modifiedAt, $sizeLabel, $noteCount geänderte Notizen, $attachmentCount Anhänge.',
  );
}

enum _CloudSyncSnackBarAction {
  syncNow,
  refreshRemote,
  upload,
  download,
  apply,
}

String _cloudSyncSnackBarMessage(
  AppStrings strings,
  SyncTransferState state,
  _CloudSyncSnackBarAction action,
  SyncProvider provider,
) {
  final providerName = _syncProviderName(provider);
  if (state.stage == SyncTransferStage.error) {
    return switch (action) {
      _CloudSyncSnackBarAction.refreshRemote => strings.localized(
        en: 'Could not refresh remote sync status.',
        ja: 'リモート同期状態を更新できませんでした。',
        zh: '无法刷新远程同步状态。',
        ko: '원격 동기화 상태를 새로 고칠 수 없습니다.',
        es: 'No se pudo actualizar el estado de sincronizacion remota.',
        de: 'Der Remote-Synchronisierungsstatus konnte nicht aktualisiert werden.',
      ),
      _CloudSyncSnackBarAction.upload => strings.localized(
        en: 'Could not upload the sync bundle.',
        ja: '同期バンドルをアップロードできませんでした。',
        zh: '无法上传同步包。',
        ko: '동기화 번들을 업로드할 수 없습니다.',
        es: 'No se pudo subir el paquete de sincronizacion.',
        de: 'Das Synchronisierungspaket konnte nicht hochgeladen werden.',
      ),
      _CloudSyncSnackBarAction.download => strings.localized(
        en: 'Could not download the remote sync bundle.',
        ja: 'リモート同期バンドルをダウンロードできませんでした。',
        zh: '无法下载远程同步包。',
        ko: '원격 동기화 번들을 다운로드할 수 없습니다.',
        es: 'No se pudo descargar el paquete de sincronizacion remoto.',
        de: 'Das Remote-Synchronisierungspaket konnte nicht heruntergeladen werden.',
      ),
      _CloudSyncSnackBarAction.apply => strings.localized(
        en: 'Could not apply the downloaded sync bundle.',
        ja: 'ダウンロードした同期バンドルを適用できませんでした。',
        zh: '无法应用已下载的同步包。',
        ko: '다운로드한 동기화 번들을 적용할 수 없습니다.',
        es: 'No se pudo aplicar el paquete de sincronizacion descargado.',
        de: 'Das heruntergeladene Synchronisierungspaket konnte nicht angewendet werden.',
      ),
      _CloudSyncSnackBarAction.syncNow => strings.localized(
        en: 'Cloud sync could not be completed.',
        ja: 'クラウド同期を完了できませんでした。',
        zh: '无法完成云同步。',
        ko: '클라우드 동기화를 완료할 수 없습니다.',
        es: 'No se pudo completar la sincronizacion en la nube.',
        de: 'Die Cloud-Synchronisierung konnte nicht abgeschlossen werden.',
      ),
    };
  }
  return switch (action) {
    _CloudSyncSnackBarAction.refreshRemote =>
      state.remoteStatus == null
          ? strings.localized(
              en: 'No remote sync bundle has been saved yet.',
              ja: 'リモートにはまだ同期バンドルが保存されていません。',
              zh: '远程还没有保存同步包。',
              ko: '원격에 저장된 동기화 번들이 아직 없습니다.',
              es: 'Todavia no se ha guardado ningun paquete de sincronizacion remoto.',
              de: 'Es wurde noch kein Remote-Synchronisierungspaket gespeichert.',
            )
          : strings.localized(
              en: '$providerName bundle information was refreshed.',
              ja: '$providerName のバンドル情報を更新しました。',
              zh: '$providerName 的同步包信息已更新。',
              ko: '$providerName 번들 정보를 새로 고쳤습니다.',
              es: 'Se actualizo la informacion del paquete de $providerName.',
              de: 'Die Paketinformationen von $providerName wurden aktualisiert.',
            ),
    _CloudSyncSnackBarAction.upload => strings.localized(
      en: 'Encrypted bundle uploaded to $providerName.',
      ja: '暗号化したバンドルを $providerName にアップロードしました。',
      zh: '已将加密同步包上传到 $providerName。',
      ko: '암호화된 번들을 $providerName에 업로드했습니다.',
      es: 'Paquete cifrado subido a $providerName.',
      de: 'Verschlusseltes Paket wurde zu $providerName hochgeladen.',
    ),
    _CloudSyncSnackBarAction.download => strings.localized(
      en: 'Remote bundle download check completed for $providerName.',
      ja: '$providerName のリモートバンドル確認が完了しました。',
      zh: '$providerName 的远程包检查已完成。',
      ko: '$providerName 원격 번들 확인이 완료되었습니다.',
      es: 'Comprobacion de descarga del paquete remoto completada para $providerName.',
      de: 'Prufung des Remote-Paketdownloads fur $providerName abgeschlossen.',
    ),
    _CloudSyncSnackBarAction.apply => strings.localized(
      en: 'Downloaded bundle applied to local notes.',
      ja: 'ダウンロードしたバンドルをローカルのノートに反映しました。',
      zh: '已将下载的同步包应用到本地笔记。',
      ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
      es: 'Paquete descargado aplicado a las notas locales.',
      de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
    ),
    _CloudSyncSnackBarAction.syncNow => strings.localized(
      en: 'Synced with $providerName.',
      ja: '$providerName と同期済みです。',
      zh: '已与 $providerName 同步。',
      ko: '$providerName와 동기화되었습니다.',
      es: 'Sincronizado con $providerName.',
      de: 'Mit $providerName synchronisiert.',
    ),
  };
}

String? _cloudSyncAuthSnackBarMessage(AppStrings strings, String? message) {
  if (message == null || message.isEmpty) {
    return message;
  }
  return switch (message) {
    'Google Drive app-data access is authorized.' => strings.localized(
      en: 'Google Drive app-data access is authorized.',
      ja: 'Google Drive のアプリ専用領域へのアクセスを許可しました。',
      zh: '已授权访问 Google Drive 应用数据。',
      ko: 'Google Drive 앱 데이터 접근 권한이 승인되었습니다.',
      es: 'Se autorizo el acceso a los datos de la app en Google Drive.',
      de: 'Der Zugriff auf Google Drive-App-Daten wurde autorisiert.',
    ),
    'iCloud is selected as this device sync target.' => strings.localized(
      en: 'iCloud is selected as this device sync target.',
      ja: 'この端末の同期先として iCloud を選択しました。',
      zh: '已选择 iCloud 作为此设备的同步目标。',
      ko: '이 기기의 동기화 대상으로 iCloud를 선택했습니다.',
      es: 'iCloud esta seleccionado como destino de sincronizacion de este dispositivo.',
      de: 'iCloud ist als Synchronisierungsziel dieses Gerats ausgewahlt.',
    ),
    'iCloud sync is currently available on iPhone and iPad only.' =>
      strings.localized(
        en: 'iCloud sync is currently available on iPhone and iPad only.',
        ja: 'iCloud 同期は現在 iPhone と iPad でのみ利用できます。',
        zh: 'iCloud 同步目前仅可在 iPhone 和 iPad 上使用。',
        ko: 'iCloud 동기화는 현재 iPhone 및 iPad에서만 사용할 수 있습니다.',
        es: 'La sincronizacion con iCloud solo esta disponible en iPhone y iPad.',
        de: 'iCloud-Synchronisierung ist derzeit nur auf iPhone und iPad verfugbar.',
      ),
    _ => message,
  };
}

String _syncProviderName(SyncProvider provider) {
  return switch (provider) {
    SyncProvider.iCloud => 'iCloud',
    SyncProvider.googleDrive => 'Google Drive',
    SyncProvider.off => 'Cloud',
  };
}

Future<bool?> _showLargeMobileSyncConfirmDialog(
  BuildContext context,
  LargeSyncTransferWarning warning,
) {
  final strings = context.strings;
  final direction = switch (warning.direction) {
    LargeSyncTransferDirection.upload => strings.localized(
      en: 'upload',
      ja: 'アップロード',
      zh: '上传',
      ko: '업로드',
      es: 'subida',
      de: 'Upload',
    ),
    LargeSyncTransferDirection.download => strings.localized(
      en: 'download',
      ja: 'ダウンロード',
      zh: '下载',
      ko: '다운로드',
      es: 'descarga',
      de: 'Download',
    ),
  };
  final size = _formatBytes(warning.bytes);
  final threshold = _formatBytes(warning.thresholdBytes);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        strings.localized(
          en: 'Sync over mobile data?',
          ja: 'モバイル回線で同期しますか？',
          zh: '要通过移动数据同步吗？',
          ko: '모바일 데이터로 동기화할까요?',
          es: 'Sincronizar con datos moviles?',
          de: 'Uber mobile Daten synchronisieren?',
        ),
      ),
      content: Text(
        strings.localized(
          en: 'This sync $direction is about $size, which is larger than the $threshold guideline. Continue only if mobile data usage is acceptable.',
          ja: 'この同期の$directionは約$sizeです。目安の$thresholdを超えています。モバイルデータ通信量に問題がない場合だけ続行してください。',
          zh: '本次同步$direction约为 $size，超过 $threshold 的建议值。仅在可以接受移动数据用量时继续。',
          ko: '이번 동기화 $direction 크기는 약 $size이며 기준인 $threshold를 넘습니다. 모바일 데이터 사용량이 괜찮을 때만 계속하세요.',
          es: 'Esta $direction de sincronizacion es de unos $size, por encima de la referencia de $threshold. Continua solo si aceptas el uso de datos moviles.',
          de: 'Diese Synchronisierungs-$direction ist etwa $size gross und liegt uber dem Richtwert von $threshold. Fahre nur fort, wenn mobile Datennutzung akzeptabel ist.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            strings.localized(
              en: 'Continue',
              ja: '続行',
              zh: '继续',
              ko: '계속',
              es: 'Continuar',
              de: 'Fortfahren',
            ),
          ),
        ),
      ],
    ),
  );
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final fractionDigits = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

String _appUpdatesUnavailableDescription(AppStrings strings) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return strings.appUpdatesDescIos;
  }
  return strings.updateSupportedOnAndroidOnly;
}

String _versionWithBuildDate(AppStrings strings, String version) {
  final buildDate = _formattedBuildDate();
  if (buildDate == null) {
    return version;
  }
  return '$version / ${strings.buildDateLabel(buildDate)}';
}

String? _formattedBuildDate() {
  final value = _buildDateIso.trim();
  if (value.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  final date = parsed == null ? value : parsed.toLocal().toIso8601String();
  if (date.length >= 10) {
    return date.substring(0, 10).replaceAll('-', '/');
  }
  return value;
}

Future<void> _openStoreListingOrExplain(
  BuildContext context,
  AppStrings strings,
) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final id = _configuredAppStoreId();
    if (id == null) {
      _showStoreFeedback(context, strings.appStoreIdNotConfigured);
      return;
    }
    final opened = await _launchFirstExternal([
      Uri.parse('itms-apps://apps.apple.com/app/id$id'),
      Uri.parse('https://apps.apple.com/app/id$id'),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final opened = await _launchFirstExternal([
      Uri.parse('market://details?id=$_androidStorePackageName'),
      Uri.parse(
        'https://play.google.com/store/apps/details?id=$_androidStorePackageName',
      ),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  _showStoreFeedback(context, strings.updateStatusUnsupported);
}

Future<void> _openStoreReviewOrExplain(
  BuildContext context,
  AppStrings strings,
) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final id = _configuredAppStoreId();
    if (id == null) {
      _showStoreFeedback(context, strings.appStoreIdNotConfigured);
      return;
    }
    final opened = await _launchFirstExternal([
      Uri.parse('itms-apps://itunes.apple.com/app/id$id?action=write-review'),
      Uri.parse('https://apps.apple.com/app/id$id?action=write-review'),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  await _openStoreListingOrExplain(context, strings);
}

String? _configuredAppStoreId() {
  final value = _appStoreId.trim();
  return value.isEmpty ? null : value;
}

Future<bool> _launchFirstExternal(List<Uri> uris) async {
  for (final uri in uris) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Try the next URL, usually a web fallback after a store scheme.
    }
  }
  return false;
}

Future<void> _openExternalLink(
  BuildContext context,
  Uri uri,
  AppStrings strings,
) async {
  final shouldOpen = await _confirmExternalLinkOpen(context, uri.toString());
  if (!shouldOpen || !context.mounted) {
    return;
  }
  final opened = await _launchFirstExternal([uri]);
  if (!context.mounted || opened) {
    return;
  }
  _showStoreFeedback(context, strings.linkOpenFailed);
}

void _showStoreFeedback(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
}

enum _NoteConflictResolution { keepLocal, useRemote, merge }

Future<void> _showNoteConflictResolver(
  BuildContext context,
  WidgetRef ref,
  NoteEntry localNote,
) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      showCloseIcon: true,
      content: Text(
        strings.localized(
          en: 'Loading the latest remote version...',
          ja: 'リモートの最新版を読み込んでいます...',
          zh: '正在读取最新远程版本...',
          ko: '최신 원격 버전을 불러오는 중...',
          es: 'Cargando la version remota mas reciente...',
          de: 'Neueste Remote-Version wird geladen...',
        ),
      ),
    ),
  );
  final remoteNote = await ref
      .read(syncTransferControllerProvider.notifier)
      .downloadLatestRemoteNoteForConflict(localNote.id);
  messenger.hideCurrentSnackBar();
  if (!context.mounted) {
    return;
  }
  if (remoteNote == null) {
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'No remote version for this note was found in the latest bundle.',
            ja: '最新バンドルにこのメモのリモート版が見つかりませんでした。',
            zh: '最新捆绑包中未找到此笔记的远程版本。',
            ko: '최신 번들에서 이 메모의 원격 버전을 찾을 수 없습니다.',
            es: 'No se encontro una version remota de esta nota en el paquete mas reciente.',
            de: 'Im neuesten Paket wurde keine Remote-Version dieser Notiz gefunden.',
          ),
        ),
      ),
    );
    return;
  }

  final resolution = await showDialog<_NoteConflictResolution>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          strings.localized(
            en: 'Resolve note conflict',
            ja: 'メモの競合を解決',
            zh: '解决笔记冲突',
            ko: '메모 충돌 해결',
            es: 'Resolver conflicto de nota',
            de: 'Notizkonflikt losen',
          ),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.localized(
                    en: 'Compare the local and remote versions, then choose how to resolve this note.',
                    ja: 'ローカル版とリモート版の概要を確認し、このメモの扱いを選んでください。',
                    zh: '比较本地和远程版本，然后选择如何处理此笔记。',
                    ko: '로컬 버전과 원격 버전을 비교한 뒤 이 메모를 어떻게 처리할지 선택하세요.',
                    es: 'Compara las versiones local y remota y elige como resolver esta nota.',
                    de: 'Vergleiche lokale und Remote-Version und wahle, wie diese Notiz gelost wird.',
                  ),
                ),
                const SizedBox(height: 16),
                _ConflictVersionSummary(
                  label: strings.localized(
                    en: 'Local version',
                    ja: 'ローカル版',
                    zh: '本地版本',
                    ko: '로컬 버전',
                    es: 'Version local',
                    de: 'Lokale Version',
                  ),
                  note: localNote,
                ),
                const SizedBox(height: 12),
                _ConflictVersionSummary(
                  label: strings.localized(
                    en: 'Remote version',
                    ja: 'リモート版',
                    zh: '远程版本',
                    ko: '원격 버전',
                    es: 'Version remota',
                    de: 'Remote-Version',
                  ),
                  note: remoteNote,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_NoteConflictResolution.useRemote),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(
              strings.localized(
                en: 'Use remote',
                ja: 'リモートを採用',
                zh: '使用远程',
                ko: '원격 사용',
                es: 'Usar remoto',
                de: 'Remote verwenden',
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_NoteConflictResolution.merge),
            icon: const Icon(Icons.call_merge_rounded),
            label: Text(
              strings.localized(
                en: 'Merge',
                ja: 'マージ',
                zh: '合并',
                ko: '병합',
                es: 'Fusionar',
                de: 'Zusammenfuhren',
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_NoteConflictResolution.keepLocal),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(
              strings.localized(
                en: 'Keep local',
                ja: 'ローカルを採用',
                zh: '保留本地',
                ko: '로컬 유지',
                es: 'Mantener local',
                de: 'Lokal behalten',
              ),
            ),
          ),
        ],
      );
    },
  );
  if (resolution == null) {
    await ref
        .read(notesControllerProvider.notifier)
        .cleanupUnreferencedAttachments();
    return;
  }
  if (!context.mounted) {
    return;
  }

  try {
    switch (resolution) {
      case _NoteConflictResolution.keepLocal:
        final confirmed = await _confirmLargeMobileConflictUploadIfNeeded(
          context,
          ref,
        );
        if (!confirmed) {
          return;
        }
        await ref
            .read(notesControllerProvider.notifier)
            .resolveConflictKeepingLocal(localNote.id);
        await ref
            .read(syncTransferControllerProvider.notifier)
            .uploadCurrentBundle(force: true, allowLargeMobileTransfer: true);
        await ref
            .read(notesControllerProvider.notifier)
            .cleanupUnreferencedAttachments();
        break;
      case _NoteConflictResolution.useRemote:
        await ref
            .read(notesControllerProvider.notifier)
            .resolveConflictUsingRemote(remoteNote);
        await ref
            .read(syncTransferControllerProvider.notifier)
            .recordDownloadedBundleApplied();
        break;
      case _NoteConflictResolution.merge:
        final confirmed = await _confirmLargeMobileConflictUploadIfNeeded(
          context,
          ref,
        );
        if (!confirmed) {
          return;
        }
        await ref
            .read(notesControllerProvider.notifier)
            .resolveConflictByMerging(remoteNote);
        await ref
            .read(syncTransferControllerProvider.notifier)
            .uploadCurrentBundle(force: true, allowLargeMobileTransfer: true);
        break;
    }
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Note conflict resolved.',
            ja: 'メモの競合を解決しました。',
            zh: '笔记冲突已解决。',
            ko: '메모 충돌이 해결되었습니다.',
            es: 'Conflicto de nota resuelto.',
            de: 'Notizkonflikt gelost.',
          ),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

Future<bool> _confirmLargeMobileConflictUploadIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  final warning = await ref
      .read(syncTransferControllerProvider.notifier)
      .largeMobileTransferWarning(includeUpload: true, includeDownload: false);
  if (warning == null) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  return await _showLargeMobileSyncConfirmDialog(context, warning) ?? false;
}

class _ConflictVersionSummary extends StatelessWidget {
  const _ConflictVersionSummary({required this.label, required this.note});

  final String label;
  final NoteEntry note;

  @override
  Widget build(BuildContext context) {
    final changedAt = (note.updatedAt ?? note.createdAt).toLocal();
    final timeLabel =
        '${changedAt.year}/${changedAt.month}/${changedAt.day} '
        '${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final body = _normalizePreviewText(note.body, maxChars: 240);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            note.title.trim().isEmpty
                ? context.strings.localized(
                    en: '(Untitled)',
                    ja: '（無題）',
                    zh: '（无标题）',
                    ko: '(제목 없음)',
                    es: '(Sin titulo)',
                    de: '(Ohne Titel)',
                  )
                : note.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            body.isEmpty ? '-' : body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'rev ${note.revision} / $timeLabel / ${note.attachments.length} attachments',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: _mutedTextColor(context)),
          ),
        ],
      ),
    );
  }
}

enum _LocalArchiveExportKind { passwordProtectedZip, plainZip }

class _LocalArchiveExportOptions {
  const _LocalArchiveExportOptions({required this.kind, this.password});

  final _LocalArchiveExportKind kind;
  final String? password;
}

Future<void> _exportLocalArchive(
  BuildContext context,
  WidgetRef ref, {
  required Set<String> vaultIds,
}) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final options = await _showLocalArchiveExportDialog(context);
    if (options == null || !context.mounted) {
      return;
    }
    final archive = await ref
        .read(syncTransferControllerProvider.notifier)
        .exportLocalArchive(password: options.password, vaultIds: vaultIds);
    if (!context.mounted) {
      return;
    }
    final savedPath = await FilePicker.saveFile(
      dialogTitle: strings.localized(
        en: 'File export',
        ja: 'ファイルエクスポート',
        zh: '文件导出',
        ko: '파일 내보내기',
        es: 'Exportar archivo',
        de: 'Datei exportieren',
      ),
      fileName: archive.fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: archive.bytes,
    );
    if (!context.mounted) {
      return;
    }
    if (savedPath == null || savedPath.isEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              archive.bytes,
              name: archive.fileName,
              mimeType: 'application/zip',
            ),
          ],
          text: 'HiMemo ZIP archive',
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Exported ${archive.noteCount} notes and ${archive.attachmentCount} attachments.',
            ja: '${archive.noteCount}件のメモと${archive.attachmentCount}件の添付を書き出しました。',
            zh: '已导出 ${archive.noteCount} 条笔记和 ${archive.attachmentCount} 个附件。',
            ko: '${archive.noteCount}개의 메모와 ${archive.attachmentCount}개의 첨부 파일을 내보냈습니다.',
            es: 'Se exportaron ${archive.noteCount} notas y ${archive.attachmentCount} adjuntos.',
            de: '${archive.noteCount} Notizen und ${archive.attachmentCount} Anhänge wurden exportiert.',
          ),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

Future<void> _importLocalArchive(BuildContext context, WidgetRef ref) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.localized(
              en: 'The selected archive could not be read.',
              ja: '選択したアーカイブを読み込めませんでした。',
              zh: '无法读取所选归档。',
              ko: '선택한 아카이브를 읽을 수 없습니다.',
              es: 'No se pudo leer el archivo seleccionado.',
              de: 'Das ausgewählte Archiv konnte nicht gelesen werden.',
            ),
          ),
        ),
      );
      return;
    }
    final password = await _passwordForLocalArchivePreview(context, ref, bytes);
    if (password == _cancelledArchivePassword || !context.mounted) {
      return;
    }
    final preview = await ref
        .read(syncTransferControllerProvider.notifier)
        .importLocalArchiveBytes(bytes, password: password);
    if (!context.mounted) {
      return;
    }
    final confirmed =
        await _showBundlePreviewDialog(
          context,
          preview,
          confirmLabel: strings.localized(
            en: 'Import',
            ja: '読み込む',
            zh: '导入',
            ko: '가져오기',
            es: 'Importar',
            de: 'Importieren',
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }
    await ref
        .read(syncTransferControllerProvider.notifier)
        .applyLocalArchiveBytes(bytes, password: password);
    if (!context.mounted) {
      return;
    }
    final message =
        ref.read(syncTransferControllerProvider).message ??
        strings.localized(
          en: 'Archive imported.',
          ja: 'アーカイブを読み込みました。',
          zh: '归档已导入。',
          ko: '아카이브를 가져왔습니다.',
          es: 'Archivo importado.',
          de: 'Archiv importiert.',
        );
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text(message)),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

const _cancelledArchivePassword = '\u0000__cancelled__';

Future<String?> _passwordForLocalArchivePreview(
  BuildContext context,
  WidgetRef ref,
  List<int> bytes,
) async {
  try {
    await ref
        .read(syncTransferControllerProvider.notifier)
        .importLocalArchiveBytes(bytes);
    return null;
  } catch (_) {
    if (!context.mounted) {
      return _cancelledArchivePassword;
    }
    return _showArchivePasswordDialog(context);
  }
}

Future<_LocalArchiveExportOptions?> _showLocalArchiveExportDialog(
  BuildContext context,
) async {
  final strings = context.strings;
  return showDialog<_LocalArchiveExportOptions>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          strings.localized(
            en: 'File export',
            ja: 'ファイルエクスポート',
            zh: '文件导出',
            ko: '파일 내보내기',
            es: 'Exportar archivo',
            de: 'Datei exportieren',
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.localized(
                  en: 'Choose a portable ZIP format. Password-protected ZIP is safer for storage and sharing. Plain ZIP is readable without HiMemo and is useful for long-term recovery.',
                  ja: '持ち運びしやすいZIP形式で書き出します。保存や共有にはキー付きZIPが安全です。プレーンZIPはHiMemoなしでも読めるため、長期的な復旧に向いています。',
                  zh: '请选择可移植的 ZIP 格式。带密码的 ZIP 更适合保存和共享；纯 ZIP 无需 HiMemo 也能读取，适合长期恢复。',
                  ko: '휴대 가능한 ZIP 형식으로 내보냅니다. 비밀번호 ZIP은 보관과 공유에 더 안전하고, 일반 ZIP은 HiMemo 없이도 읽을 수 있어 장기 복구에 적합합니다.',
                  es: 'Elige un formato ZIP portátil. El ZIP con contraseña es más seguro para guardar y compartir. El ZIP sin cifrar se puede leer sin HiMemo y sirve para recuperación a largo plazo.',
                  de: 'Wähle ein portables ZIP-Format. Ein passwortgeschütztes ZIP ist sicherer zum Speichern und Teilen. Ein unverschlüsseltes ZIP ist ohne HiMemo lesbar und eignet sich zur langfristigen Wiederherstellung.',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(
                  strings.localized(
                    en: 'Password-protected ZIP',
                    ja: 'キー付きZIP',
                    zh: '带密码的 ZIP',
                    ko: '비밀번호 ZIP',
                    es: 'ZIP con contraseña',
                    de: 'Passwortgeschütztes ZIP',
                  ),
                ),
                subtitle: Text(
                  strings.localized(
                    en: 'Recommended for normal backups.',
                    ja: '通常のバックアップにおすすめです。',
                    zh: '推荐用于普通备份。',
                    ko: '일반 백업에 권장됩니다.',
                    es: 'Recomendado para copias de seguridad normales.',
                    de: 'Für normale Backups empfohlen.',
                  ),
                ),
                onTap: () async {
                  final password = await _showArchivePasswordDialog(
                    dialogContext,
                    confirmPassword: true,
                  );
                  if (password == null || password.isEmpty) {
                    return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(
                      _LocalArchiveExportOptions(
                        kind: _LocalArchiveExportKind.passwordProtectedZip,
                        password: password,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(
                  strings.localized(
                    en: 'Plain ZIP',
                    ja: 'プレーンZIP',
                    zh: '纯 ZIP',
                    ko: '일반 ZIP',
                    es: 'ZIP sin cifrar',
                    de: 'Unverschlüsseltes ZIP',
                  ),
                ),
                subtitle: Text(
                  strings.localized(
                    en: 'Readable outside the app. Anyone with the file can see its contents.',
                    ja: 'アプリ外でも読めます。ファイルを持つ人は内容を閲覧できます。',
                    zh: '可在应用外读取。持有文件的人都能查看内容。',
                    ko: '앱 밖에서도 읽을 수 있습니다. 파일을 가진 사람은 내용을 볼 수 있습니다.',
                    es: 'Se puede leer fuera de la app. Cualquier persona con el archivo puede ver su contenido.',
                    de: 'Außerhalb der App lesbar. Jede Person mit der Datei kann den Inhalt sehen.',
                  ),
                ),
                onTap: () async {
                  final confirmed = await _confirmPlainZipExport(dialogContext);
                  if (confirmed && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(
                      const _LocalArchiveExportOptions(
                        kind: _LocalArchiveExportKind.plainZip,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
        ],
      );
    },
  );
}

Future<bool> _confirmPlainZipExport(BuildContext context) async {
  final strings = context.strings;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        strings.localized(
          en: 'Export plain ZIP?',
          ja: 'プレーンZIPで書き出しますか？',
          zh: '导出纯 ZIP？',
          ko: '일반 ZIP으로 내보낼까요?',
          es: '¿Exportar ZIP sin cifrar?',
          de: 'Unverschlüsseltes ZIP exportieren?',
        ),
      ),
      content: Text(
        strings.localized(
          en: 'The exported file contains readable note text, tags, dates, locations, photos, videos, audio, and files. Store it only in a place you trust.',
          ja: '書き出したファイルには、メモ本文、タグ、日時、位置情報、写真、動画、音声、ファイルが読み取り可能な状態で含まれます。信頼できる場所にのみ保存してください。',
          zh: '导出的文件会以可读取状态包含笔记正文、标签、日期、位置、照片、视频、音频和文件。请只保存到可信位置。',
          ko: '내보낸 파일에는 메모 본문, 태그, 날짜, 위치, 사진, 동영상, 오디오, 파일이 읽을 수 있는 상태로 포함됩니다. 신뢰할 수 있는 위치에만 저장하세요.',
          es: 'El archivo exportado contiene texto, etiquetas, fechas, ubicaciones, fotos, videos, audio y archivos en formato legible. Guárdalo solo en un lugar de confianza.',
          de: 'Die exportierte Datei enthält lesbare Notiztexte, Tags, Daten, Standorte, Fotos, Videos, Audio und Dateien. Speichere sie nur an einem vertrauenswürdigen Ort.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            strings.localized(
              en: 'Export plain ZIP',
              ja: 'プレーンZIPで書き出す',
              zh: '导出纯 ZIP',
              ko: '일반 ZIP 내보내기',
              es: 'Exportar ZIP sin cifrar',
              de: 'Unverschlüsselt exportieren',
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> _showArchivePasswordDialog(
  BuildContext context, {
  bool confirmPassword = false,
}) async {
  final strings = context.strings;
  final controller = TextEditingController();
  final confirmController = TextEditingController();
  String? errorText;
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              confirmPassword
                  ? strings.localized(
                      en: 'Set archive key',
                      ja: 'アーカイブキーを設定',
                      zh: '设置归档密钥',
                      ko: '아카이브 키 설정',
                      es: 'Definir clave del archivo',
                      de: 'Archivschlüssel festlegen',
                    )
                  : strings.localized(
                      en: 'Archive key',
                      ja: 'アーカイブキー',
                      zh: '归档密钥',
                      ko: '아카이브 키',
                      es: 'Clave del archivo',
                      de: 'Archivschlüssel',
                    ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.localized(
                      en: 'This key is not stored by HiMemo. If you lose it, this ZIP cannot be imported.',
                      ja: 'このキーはHiMemoには保存されません。忘れると、このZIPは読み込めません。',
                      zh: '此密钥不会保存在 HiMemo 中。如果遗失，将无法导入此 ZIP。',
                      ko: '이 키는 HiMemo에 저장되지 않습니다. 잊어버리면 이 ZIP을 가져올 수 없습니다.',
                      es: 'HiMemo no guarda esta clave. Si la pierdes, no podrás importar este ZIP.',
                      de: 'HiMemo speichert diesen Schlüssel nicht. Wenn du ihn verlierst, kann dieses ZIP nicht importiert werden.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: strings.localized(
                        en: 'Key',
                        ja: 'キー',
                        zh: '密钥',
                        ko: '키',
                        es: 'Clave',
                        de: 'Schlüssel',
                      ),
                      errorText: errorText,
                    ),
                  ),
                  if (confirmPassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: strings.localized(
                          en: 'Confirm key',
                          ja: 'キーを確認',
                          zh: '确认密钥',
                          ko: '키 확인',
                          es: 'Confirmar clave',
                          de: 'Schlüssel bestätigen',
                        ),
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
              FilledButton(
                onPressed: () {
                  final password = controller.text;
                  if (password.length < 8) {
                    setState(() {
                      errorText = strings.localized(
                        en: 'Use at least 8 characters.',
                        ja: '8文字以上で入力してください。',
                        zh: '请至少输入 8 个字符。',
                        ko: '8자 이상 입력하세요.',
                        es: 'Usa al menos 8 caracteres.',
                        de: 'Mindestens 8 Zeichen verwenden.',
                      );
                    });
                    return;
                  }
                  if (confirmPassword && password != confirmController.text) {
                    setState(() {
                      errorText = strings.localized(
                        en: 'Keys do not match.',
                        ja: 'キーが一致しません。',
                        zh: '密钥不一致。',
                        ko: '키가 일치하지 않습니다.',
                        es: 'Las claves no coinciden.',
                        de: 'Die Schlüssel stimmen nicht überein.',
                      );
                    });
                    return;
                  }
                  Navigator.of(context).pop(password);
                },
                child: Text(
                  confirmPassword
                      ? strings.save
                      : strings.localized(
                          en: 'Continue',
                          ja: '続行',
                          zh: '继续',
                          ko: '계속',
                          es: 'Continuar',
                          de: 'Weiter',
                        ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  confirmController.dispose();
  return result;
}

Future<bool?> _showBundlePreviewDialog(
  BuildContext context,
  SyncBundlePreview preview, {
  required String confirmLabel,
}) {
  final strings = context.strings;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.text('home.bundle.review')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.bundleNotes(preview.noteCount)),
                Text(strings.bundleAttachments(preview.attachmentCount)),
                Text(strings.bundleAdds(preview.addedCount)),
                Text(strings.bundleUpdates(preview.updatedCount)),
                Text(strings.bundleRemovals(preview.removedCount)),
                if (preview.privateVaultNoteCount > 0)
                  Text(
                    strings.bundlePrivateVaultAffected(
                      preview.privateVaultNoteCount,
                    ),
                  ),
                if (preview.deviceId != null && preview.deviceId!.isNotEmpty)
                  Text(strings.bundleRemoteDevice(preview.deviceId!)),
                if (preview.exportedAt != null)
                  Text(
                    strings.bundleExportedAt(
                      _formatDateTime(preview.exportedAt!, strings),
                    ),
                  ),
                if (preview.sampleTitles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(strings.bundleSample(preview.sampleTitles.join(', '))),
                ],
                _PreviewTitlesSection(
                  title: strings.text('home.added.notes'),
                  titles: preview.addedTitles,
                ),
                _PreviewTitlesSection(
                  title: strings.text('home.updated.notes'),
                  titles: preview.updatedTitles,
                ),
                _PreviewTitlesSection(
                  title: strings.text('home.removed.locally.after.apply'),
                  titles: preview.removedTitles,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

class _PreviewTitlesSection extends StatelessWidget {
  const _PreviewTitlesSection({required this.title, required this.titles});

  final String title;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final entry in titles)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $entry'),
            ),
        ],
      ),
    );
  }
}

Future<RemoteSyncBundleStatus?> _showBundleHistoryDialog(
  BuildContext context,
  List<RemoteSyncBundleStatus> history,
) {
  final strings = context.strings;
  return showDialog<RemoteSyncBundleStatus>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.text('home.remote.bundle.history')),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = history[index];
              final modifiedAt = entry.modifiedAt == null
                  ? (strings.text('home.unknown.time.2'))
                  : _formatDateTime(entry.modifiedAt!, strings);
              final counts = strings.bundleHistoryCounts(
                notes: entry.noteCount,
                attachments: entry.attachmentCount,
              );
              final device = entry.deviceId == null || entry.deviceId!.isEmpty
                  ? (strings.text('home.unknown.device'))
                  : entry.deviceId!;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(modifiedAt),
                subtitle: Text('${entry.fileName}\n$counts\n$device'),
                isThreeLine: true,
                trailing: index == 0
                    ? const Icon(Icons.history_toggle_off_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(entry),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          ),
        ],
      );
    },
  );
}

Future<String?> _showSyncKeyImportDialog(BuildContext context) {
  final strings = context.strings;
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.text('home.import.recovery.key')),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: strings.text('home.paste.himemo.sync.key.v1'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(strings.text('home.import')),
          ),
        ],
      );
    },
  );
}

Future<void> _showSyncKeyQrDialog(
  BuildContext context, {
  required String backupCode,
}) {
  final strings = context.strings;
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          strings.localized(
            en: 'Cloud recovery key QR',
            ja: 'クラウド復元キーのQR',
            zh: '云恢复密钥 QR',
            ko: '클라우드 복구 키 QR',
            es: 'QR de clave de recuperacion',
            de: 'QR fur Cloud-Wiederherstellungsschlussel',
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.localized(
                  en: 'This QR code contains the full cloud recovery key. Show it only in a private place.',
                  ja: 'このQRコードにはクラウド復元キー全体が含まれます。周囲に見られない場所で表示してください。',
                  zh: '此 QR 码包含完整的云恢复密钥。请仅在私密场所显示。',
                  ko: '이 QR 코드에는 전체 클라우드 복구 키가 포함됩니다. 주변에 보이지 않는 곳에서만 표시하세요.',
                  es: 'Este QR contiene la clave de recuperacion completa. Muestralo solo en un lugar privado.',
                  de: 'Dieser QR-Code enthalt den vollstandigen Wiederherstellungsschlussel. Zeige ihn nur an einem privaten Ort.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _CloudRecoveryKeyQrImage(data: backupCode),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          ),
        ],
      );
    },
  );
}

class _CloudRecoveryKeyQrImage extends StatefulWidget {
  const _CloudRecoveryKeyQrImage({required this.data});

  final String data;

  @override
  State<_CloudRecoveryKeyQrImage> createState() =>
      _CloudRecoveryKeyQrImageState();
}

class _CloudRecoveryKeyQrImageState extends State<_CloudRecoveryKeyQrImage> {
  late Future<Uint8List> _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = _renderQrPng(widget.data);
  }

  @override
  void didUpdateWidget(covariant _CloudRecoveryKeyQrImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _imageBytes = _renderQrPng(widget.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 260,
      child: FutureBuilder<Uint8List>(
        future: _imageBytes,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Semantics(
              label: 'qr code',
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 32,
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Future<Uint8List> _renderQrPng(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: false,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    final byteData = await painter.toImageData(
      720,
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) {
      throw StateError('Failed to render recovery key QR code.');
    }
    return byteData.buffer.asUint8List();
  }
}

Future<String?> _showSyncKeyQrScannerDialog(BuildContext context) {
  final strings = context.strings;
  if (!_syncKeyQrScannerSupported) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.localized(
            en: 'QR scanning is unavailable',
            ja: 'QR読み取りを利用できません',
            zh: '无法扫描 QR',
            ko: 'QR 스캔을 사용할 수 없습니다',
            es: 'El escaneo QR no esta disponible',
            de: 'QR-Scan ist nicht verfugbar',
          ),
        ),
        content: Text(
          strings.localized(
            en: 'Use copy and paste to import the cloud recovery key on this platform.',
            ja: 'この環境では、コピーと貼り付けでクラウド復元キーをインポートしてください。',
            zh: '请在此平台上使用复制和粘贴导入云恢复密钥。',
            ko: '이 환경에서는 복사와 붙여넣기로 클라우드 복구 키를 가져오세요.',
            es: 'Usa copiar y pegar para importar la clave de recuperacion en esta plataforma.',
            de: 'Importiere den Cloud-Wiederherstellungsschlussel auf dieser Plattform per Kopieren und Einfugen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          ),
        ],
      ),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (context) => _SyncKeyQrScannerDialog(strings: strings),
  );
}

bool get _syncKeyQrScannerSupported {
  if (kIsWeb) {
    return true;
  }
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

class _SyncKeyQrScannerDialog extends StatefulWidget {
  const _SyncKeyQrScannerDialog({required this.strings});

  final AppStrings strings;

  @override
  State<_SyncKeyQrScannerDialog> createState() =>
      _SyncKeyQrScannerDialogState();
}

class _SyncKeyQrScannerDialogState extends State<_SyncKeyQrScannerDialog> {
  late final MobileScannerController _controller;
  bool _completed = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_completed) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      if (!raw.startsWith(SyncBundleKeyService.backupCodePrefix)) {
        setState(() {
          _errorText = widget.strings.localized(
            en: 'This QR code is not a HiMemo cloud recovery key.',
            ja: 'このQRコードはHiMemoのクラウド復元キーではありません。',
            zh: '此 QR 码不是 HiMemo 云恢复密钥。',
            ko: '이 QR 코드는 HiMemo 클라우드 복구 키가 아닙니다.',
            es: 'Este QR no es una clave de recuperacion de HiMemo.',
            de: 'Dieser QR-Code ist kein HiMemo-Cloud-Wiederherstellungsschlussel.',
          );
        });
        continue;
      }
      _completed = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(
        strings.localized(
          en: 'Scan recovery key QR',
          ja: '復元キーQRを読み取り',
          zh: '扫描恢复密钥 QR',
          ko: '복구 키 QR 스캔',
          es: 'Escanear QR de recuperacion',
          de: 'Wiederherstellungs-QR scannen',
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.localized(
                en: 'Point the camera at the QR code shown on the other device.',
                ja: '別の端末に表示したQRコードをカメラに向けてください。',
                zh: '将相机对准另一台设备上显示的 QR 码。',
                ko: '다른 기기에 표시된 QR 코드를 카메라로 비추세요.',
                es: 'Apunta la camara al QR mostrado en el otro dispositivo.',
                de: 'Richte die Kamera auf den QR-Code auf dem anderen Gerat.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _handleDetect,
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error.errorDetails?.message ?? error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
  }
}

Future<void> _handleSyncKeyImport(
  BuildContext context,
  WidgetRef ref,
  String backupCode,
) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final normalized = backupCode.trim();
    final currentFingerprint = await ref
        .read(syncBundleKeyServiceProvider)
        .fingerprint();
    if (!context.mounted) {
      return;
    }
    final incomingFingerprint = ref
        .read(syncBundleKeyServiceProvider)
        .previewBackupCodeFingerprint(normalized);
    final shouldImport =
        await _showSyncKeyImportConfirmDialog(
          context,
          currentFingerprint: currentFingerprint,
          incomingFingerprint: incomingFingerprint,
        ) ??
        false;
    if (!shouldImport || !context.mounted) {
      return;
    }
    final fingerprint = await ref
        .read(syncBundleKeyServiceProvider)
        .importBackupCode(normalized);
    ref.invalidate(syncBundleFingerprintProvider);
    ref.read(syncTransferControllerProvider.notifier).clearLocalBundleCache();
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(strings.recoveryKeyImported(fingerprint)),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

Future<String?> _showSingleSecretPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String helperText,
  required String actionLabel,
}) {
  final strings = context.strings;
  final controller = TextEditingController();
  String? errorText;
  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    helperText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.length < 4) {
                    setState(() {
                      errorText = strings.useAtLeast4Chars;
                    });
                    return;
                  }
                  Navigator.of(context).pop(value);
                },
                child: Text(actionLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> _showSecretSetupDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  required String helperText,
}) {
  final strings = context.strings;
  final secretController = TextEditingController();
  final confirmController = TextEditingController();
  String? errorText;

  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    helperText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secretController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: confirmLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final secret = secretController.text.trim();
                  final confirm = confirmController.text.trim();
                  if (secret.length < 4) {
                    setState(() {
                      errorText = strings.useAtLeast4Chars;
                    });
                    return;
                  }
                  if (secret != confirm) {
                    setState(() {
                      errorText = strings.keysDoNotMatch;
                    });
                    return;
                  }
                  Navigator.of(context).pop(secret);
                },
                child: Text(strings.save),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool?> _showSyncKeyImportConfirmDialog(
  BuildContext context, {
  required String currentFingerprint,
  required String incomingFingerprint,
}) {
  final strings = context.strings;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.replaceRecoveryKey),
        content: Text(
          strings.replaceRecoveryKeyBody(
            currentFingerprint: currentFingerprint,
            incomingFingerprint: incomingFingerprint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.replaceKey),
          ),
        ],
      );
    },
  );
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

Future<void> _openAttachmentViewer(
  BuildContext context,
  WidgetRef ref,
  NoteAttachment attachment, {
  List<NoteAttachment> photoAttachments = const [],
  int? initialPhotoIndex,
}) async {
  if (attachment.type == AttachmentType.photo) {
    final attachments = photoAttachments.isEmpty
        ? [attachment]
        : photoAttachments;
    final fallbackIndex = attachments.indexOf(attachment);
    final resolvedIndex =
        initialPhotoIndex != null &&
            initialPhotoIndex >= 0 &&
            initialPhotoIndex < attachments.length
        ? initialPhotoIndex
        : (fallbackIndex >= 0 ? fallbackIndex : 0);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.strings.closeImageViewer,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (context, _, _) => _PhotoLightboxDialog(
        attachments: attachments,
        initialIndex: resolvedIndex,
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
    return;
  }
  if (attachment.type == AttachmentType.video) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (context, _, _) =>
          _VideoLightboxDialog(attachment: attachment),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: _AttachmentViewerSheet(attachment: attachment),
      ),
    ),
  );
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('home.use.a.4.digit.pin.for.this.browser'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _PinEntryField(controller: _pinController, label: strings.pin),
            const SizedBox(height: 12),
            _PinEntryField(
              controller: _confirmController,
              label: strings.text('home.confirm.pin'),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
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
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }

  void _submit() {
    final strings = context.strings;
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length != 4) {
      setState(() {
        _errorText = strings.text('home.pin.must.be.exactly.4.digits');
      });
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      setState(() {
        _errorText = strings.text('home.pin.must.contain.digits.only');
      });
      return;
    }
    if (pin != confirm) {
      setState(() {
        _errorText = strings.text('home.pin.confirmation.did.not.match');
      });
      return;
    }
    Navigator.of(context).pop(pin);
  }
}

class _PinEntryField extends StatelessWidget {
  const _PinEntryField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Pinput(
          controller: controller,
          length: 4,
          obscureText: true,
          obscuringCharacter: '•',
          keyboardType: TextInputType.number,
          defaultPinTheme: PinTheme(
            width: 42,
            height: 52,
            textStyle: Theme.of(context).textTheme.titleMedium,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          focusedPinTheme: PinTheme(
            width: 42,
            height: 52,
            textStyle: Theme.of(context).textTheme.titleMedium,
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentViewerSheet extends ConsumerWidget {
  const _AttachmentViewerSheet({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(attachment.label, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _attachmentDescription(context, attachment),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
        ),
        const SizedBox(height: 4),
        _AttachmentSizeText(attachment: attachment),
        const SizedBox(height: 16),
        Expanded(
          child: switch (attachment.type) {
            AttachmentType.photo => _PhotoAttachmentViewer(
              attachment: attachment,
            ),
            AttachmentType.video => _VideoAttachmentViewer(
              attachment: attachment,
            ),
            AttachmentType.audio => _AudioAttachmentViewer(
              attachment: attachment,
            ),
            AttachmentType.file => _FileAttachmentViewer(
              attachment: attachment,
            ),
          },
        ),
      ],
    );
  }
}

class _FileAttachmentViewer extends ConsumerWidget {
  const _FileAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              attachment.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              context.strings.filePreviewUnavailable,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _shareAttachment(context, ref, attachment),
              icon: const Icon(Icons.ios_share_outlined),
              label: Text(context.strings.share),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoLightboxDialog extends ConsumerWidget {
  const _VideoLightboxDialog({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final sizeFuture = _attachmentSizeFuture(ref, attachment);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                FutureBuilder<int?>(
                  future: sizeFuture,
                  builder: (context, snapshot) {
                    final sizeLabel = _attachmentSizeLabel(
                      context,
                      snapshot.data,
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).closeButtonTooltip,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  attachment.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _shareAttachment(context, ref, attachment),
                                icon: const Icon(
                                  Icons.ios_share_outlined,
                                  color: Colors.white,
                                ),
                                tooltip: strings.share,
                              ),
                            ],
                          ),
                          if (sizeLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 56, top: 2),
                              child: Text(
                                sizeLabel,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: _VideoAttachmentViewer(
                      attachment: attachment,
                      autoLoad: true,
                      fillAvailableHeight: true,
                      showFullScreenAction: false,
                      showShareAction: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoControllerLightboxDialog extends StatefulWidget {
  const _VideoControllerLightboxDialog({
    required this.attachment,
    required this.controller,
    required this.initialMuted,
    this.sizeLabel,
    this.onMutedChanged,
    this.onShare,
  });

  final NoteAttachment attachment;
  final VideoPlayerController controller;
  final bool initialMuted;
  final String? sizeLabel;
  final ValueChanged<bool>? onMutedChanged;
  final VoidCallback? onShare;

  @override
  State<_VideoControllerLightboxDialog> createState() =>
      _VideoControllerLightboxDialogState();
}

class _VideoControllerLightboxDialogState
    extends State<_VideoControllerLightboxDialog> {
  Duration? _dragPosition;
  late bool _muted;

  VideoPlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _muted = widget.initialMuted;
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final duration = _controller.value.duration;
    final position = _clampMediaPosition(
      _dragPosition ?? _controller.value.position,
      duration,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.attachment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (widget.onShare != null)
                            IconButton(
                              onPressed: widget.onShare,
                              icon: const Icon(
                                Icons.ios_share_outlined,
                                color: Colors.white,
                              ),
                              tooltip: strings.share,
                            ),
                        ],
                      ),
                      if (widget.sizeLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 56, top: 2),
                          child: Text(
                            widget.sizeLabel!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final aspectRatio = _controller.value.aspectRatio <= 0
                            ? 16 / 9
                            : _controller.value.aspectRatio;
                        return Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                    maxHeight: constraints.maxHeight,
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: aspectRatio,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          AbsorbPointer(
                                            child: VideoPlayer(_controller),
                                          ),
                                          Positioned.fill(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: _togglePlayback,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _togglePlayback,
                                  icon: Icon(
                                    _controller.value.isPlaying
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  onPressed: _toggleMuted,
                                  icon: Icon(
                                    _muted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    color: Colors.white,
                                  ),
                                  tooltip: _videoMuteTooltip(_muted),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: duration <= Duration.zero
                                        ? 0
                                        : position.inMilliseconds
                                              .clamp(0, duration.inMilliseconds)
                                              .toDouble(),
                                    max: duration <= Duration.zero
                                        ? 1
                                        : duration.inMilliseconds.toDouble(),
                                    onChanged: duration <= Duration.zero
                                        ? null
                                        : (value) {
                                            setState(() {
                                              _dragPosition = Duration(
                                                milliseconds: value.round(),
                                              );
                                            });
                                          },
                                    onChangeEnd: duration <= Duration.zero
                                        ? null
                                        : (value) {
                                            unawaited(_seek(value, duration));
                                          },
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  '${_formatAudioDuration(position)} / '
                                  '${_formatAudioDuration(duration)}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _togglePlayback() {
    if (_controller.value.isPlaying) {
      unawaited(_controller.pause());
      return;
    }
    final duration = _controller.value.duration;
    if (duration > Duration.zero &&
        _controller.value.position >=
            duration - const Duration(milliseconds: 250)) {
      unawaited(
        _controller.seekTo(Duration.zero).then((_) => _controller.play()),
      );
    } else {
      unawaited(_controller.play());
    }
  }

  Future<void> _seek(double value, Duration duration) async {
    final target = _clampMediaPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
    await _controller.seekTo(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _dragPosition = null;
    });
  }

  void _toggleMuted() {
    final nextMuted = !_muted;
    unawaited(_controller.setVolume(nextMuted ? 0.0 : 1.0));
    widget.onMutedChanged?.call(nextMuted);
    setState(() {
      _muted = nextMuted;
    });
  }
}

class _WebVideoLightboxDialog extends StatefulWidget {
  const _WebVideoLightboxDialog({
    required this.attachment,
    required this.objectUrl,
    required this.muted,
    this.sizeLabel,
    this.onMutedChanged,
    this.onShare,
  });

  final NoteAttachment attachment;
  final String objectUrl;
  final bool muted;
  final String? sizeLabel;
  final ValueChanged<bool>? onMutedChanged;
  final VoidCallback? onShare;

  @override
  State<_WebVideoLightboxDialog> createState() =>
      _WebVideoLightboxDialogState();
}

class _WebVideoLightboxDialogState extends State<_WebVideoLightboxDialog> {
  late bool _muted;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
    _viewType = 'himemo-video-lightbox-${identityHashCode(this)}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.attachment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (widget.onShare != null)
                            IconButton(
                              onPressed: widget.onShare,
                              icon: const Icon(
                                Icons.ios_share_outlined,
                                color: Colors.white,
                              ),
                              tooltip: strings.share,
                            ),
                          IconButton(
                            onPressed: _toggleMuted,
                            icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                            ),
                            tooltip: _videoMuteTooltip(_muted),
                          ),
                        ],
                      ),
                      if (widget.sizeLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 56, top: 2),
                          child: Text(
                            widget.sizeLabel!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: buildWebVideoElementView(
                            viewType: _viewType,
                            objectUrl: widget.objectUrl,
                            autoplay: true,
                            muted: _muted,
                            fillAvailableHeight: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMuted() {
    final nextMuted = !_muted;
    updateWebVideoElementMuted(_viewType, nextMuted);
    widget.onMutedChanged?.call(nextMuted);
    setState(() {
      _muted = nextMuted;
    });
  }
}

class _PhotoLightboxDialog extends ConsumerStatefulWidget {
  const _PhotoLightboxDialog({
    required this.attachments,
    required this.initialIndex,
  });

  final List<NoteAttachment> attachments;
  final int initialIndex;

  @override
  ConsumerState<_PhotoLightboxDialog> createState() =>
      _PhotoLightboxDialogState();
}

class _PhotoLightboxDialogState extends ConsumerState<_PhotoLightboxDialog> {
  final TransformationController _transformationController =
      TransformationController();
  bool _edgeToEdge = false;
  bool _backgroundPanStartedOnImage = false;
  Offset? _lastLightboxTapDownPosition;
  late int _selectedIndex;

  NoteAttachment get _attachment => widget.attachments[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FutureBuilder<List<int>?>(
          future: _readPhotoAttachmentBytes(ref, _attachment),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (bytes == null || bytes.isEmpty) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.strings.unableToDecryptImage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: _LightboxTopBar(
                      attachment: _attachment,
                      edgeToEdge: _edgeToEdge,
                      canMovePrevious: _selectedIndex > 0,
                      canMoveNext:
                          _selectedIndex < widget.attachments.length - 1,
                      onClose: () => Navigator.of(context).pop(),
                      onZoomOut: null,
                      onZoomIn: null,
                      onReset: null,
                      onPrevious: _showPreviousImage,
                      onNext: _showNextImage,
                      onToggleEdgeToEdge: null,
                      onShare: null,
                    ),
                  ),
                ],
              );
            }

            return FutureBuilder<ui.Size>(
              future: _decodeImageSize(bytes),
              builder: (context, dimensionSnapshot) {
                final imageSize = dimensionSnapshot.data;
                if (dimensionSnapshot.hasError) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.strings.unableToLoadImage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: _LightboxTopBar(
                          attachment: _attachment,
                          edgeToEdge: _edgeToEdge,
                          canMovePrevious: _selectedIndex > 0,
                          canMoveNext:
                              _selectedIndex < widget.attachments.length - 1,
                          onClose: () => Navigator.of(context).pop(),
                          onZoomOut: null,
                          onZoomIn: null,
                          onReset: null,
                          onPrevious: _showPreviousImage,
                          onNext: _showNextImage,
                          onToggleEdgeToEdge: null,
                          onShare: null,
                        ),
                      ),
                    ],
                  );
                }
                if (imageSize == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = _edgeToEdge ? 0.0 : 24.0;
                    const verticalTopPadding = 72.0;
                    final verticalBottomPadding = _edgeToEdge ? 0.0 : 24.0;
                    final viewportWidth =
                        constraints.maxWidth - horizontalPadding * 2;
                    final viewportHeight =
                        constraints.maxHeight -
                        verticalTopPadding -
                        verticalBottomPadding;
                    final containScale = math.min(
                      viewportWidth / imageSize.width,
                      viewportHeight / imageSize.height,
                    );
                    final displayScale = math.min(1.0, containScale);
                    final displayedWidth = imageSize.width * displayScale;
                    final displayedHeight = imageSize.height * displayScale;
                    final maxScale = displayScale < 1 ? 1 / displayScale : 1.0;
                    final minScale = math.min(0.25, maxScale);
                    final imageBaseRect = Rect.fromLTWH(
                      horizontalPadding + (viewportWidth - displayedWidth) / 2,
                      verticalTopPadding +
                          (viewportHeight - displayedHeight) / 2,
                      displayedWidth,
                      displayedHeight,
                    );

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ExcludeSemantics(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) {
                                _backgroundPanStartedOnImage =
                                    _transformedImageRect(
                                      imageBaseRect,
                                    ).contains(details.localPosition);
                              },
                              onPanUpdate: (details) {
                                if (_backgroundPanStartedOnImage) {
                                  _panImageBy(details.delta);
                                }
                              },
                              onPanEnd: (_) {
                                _backgroundPanStartedOnImage = false;
                              },
                              onPanCancel: () {
                                _backgroundPanStartedOnImage = false;
                              },
                              onTapUp: (details) {
                                if (!_transformedImageRect(
                                  imageBaseRect,
                                ).contains(details.localPosition)) {
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              verticalTopPadding,
                              horizontalPadding,
                              verticalBottomPadding,
                            ),
                            child: Center(
                              child: SizedBox(
                                width: displayedWidth,
                                height: displayedHeight,
                                child: InteractiveViewer(
                                  transformationController:
                                      _transformationController,
                                  minScale: minScale,
                                  maxScale: math.max(maxScale, minScale),
                                  panEnabled: true,
                                  boundaryMargin: EdgeInsets.all(
                                    math.max(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    ),
                                  ),
                                  clipBehavior: Clip.none,
                                  child: SizedBox(
                                    width: displayedWidth,
                                    height: displayedHeight,
                                    child: Image.memory(
                                      Uint8List.fromList(bytes),
                                      width: displayedWidth,
                                      height: displayedHeight,
                                      fit: BoxFit.fill,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const _AttachmentImageErrorPanel(
                                          height: 180,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: ExcludeSemantics(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapDown: (details) {
                                _lastLightboxTapDownPosition =
                                    details.localPosition;
                              },
                              onTap: () {
                                final position = _lastLightboxTapDownPosition;
                                _lastLightboxTapDownPosition = null;
                                if (position == null ||
                                    !_transformedImageRect(
                                      imageBaseRect,
                                    ).contains(position)) {
                                  Navigator.of(context).pop();
                                }
                              },
                              onDoubleTapDown: (details) {
                                _lastLightboxTapDownPosition = null;
                                if (_transformedImageRect(
                                  imageBaseRect,
                                ).contains(details.localPosition)) {
                                  _toggleActualSize(maxScale);
                                }
                              },
                            ),
                          ),
                        ),
                        if (_selectedIndex > 0)
                          Positioned(
                            left: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _LightboxEdgeButton(
                                icon: Icons.chevron_left_rounded,
                                tooltip: context.strings.previousImage,
                                onPressed: _showPreviousImage,
                              ),
                            ),
                          ),
                        if (_selectedIndex < widget.attachments.length - 1)
                          Positioned(
                            right: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _LightboxEdgeButton(
                                icon: Icons.chevron_right_rounded,
                                tooltip: context.strings.nextImage,
                                onPressed: _showNextImage,
                              ),
                            ),
                          ),
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: _LightboxTopBar(
                            attachment: _attachment,
                            metadataLabel: _attachmentSizeLabel(
                              context,
                              bytes.length,
                            ),
                            edgeToEdge: _edgeToEdge,
                            canMovePrevious: _selectedIndex > 0,
                            canMoveNext:
                                _selectedIndex < widget.attachments.length - 1,
                            onClose: () => Navigator.of(context).pop(),
                            onZoomOut: () => _zoomOut(maxScale),
                            onZoomIn: () => _zoomIn(maxScale),
                            onReset: _resetTransform,
                            onPrevious: _showPreviousImage,
                            onNext: _showNextImage,
                            onToggleEdgeToEdge: () {
                              setState(() {
                                _edgeToEdge = !_edgeToEdge;
                              });
                            },
                            onShare: () => _shareImage(bytes),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _zoomIn(double maxScale) => _scaleBy(1.2, maxScale);

  void _zoomOut(double maxScale) => _scaleBy(1 / 1.2, maxScale);

  void _toggleActualSize(double maxScale) {
    final current = _transformationController.value.getMaxScaleOnAxis();
    if ((current - 1).abs() < 0.05 && maxScale > 1) {
      _scaleBy(maxScale, maxScale);
      return;
    }
    _resetTransform();
  }

  void _resetTransform() {
    _transformationController.value = Matrix4.identity();
  }

  void _panImageBy(Offset delta) {
    final matrix = _transformationController.value.clone();
    matrix.storage[12] += delta.dx;
    matrix.storage[13] += delta.dy;
    _transformationController.value = matrix;
  }

  Rect _transformedImageRect(Rect baseRect) {
    final matrix = _transformationController.value;
    final transformedTopLeft = MatrixUtils.transformPoint(matrix, Offset.zero);
    final transformedTopRight = MatrixUtils.transformPoint(
      matrix,
      Offset(baseRect.width, 0),
    );
    final transformedBottomLeft = MatrixUtils.transformPoint(
      matrix,
      Offset(0, baseRect.height),
    );
    final transformedBottomRight = MatrixUtils.transformPoint(
      matrix,
      Offset(baseRect.width, baseRect.height),
    );
    final transformedPoints = [
      transformedTopLeft,
      transformedTopRight,
      transformedBottomLeft,
      transformedBottomRight,
    ].map((point) => point + baseRect.topLeft);
    return transformedPoints.fold<Rect>(
      Rect.fromPoints(transformedPoints.first, transformedPoints.first),
      (rect, point) =>
          rect.expandToInclude(Rect.fromLTWH(point.dx, point.dy, 0, 0)),
    );
  }

  void _scaleBy(double factor, double maxScale) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.25, maxScale);
    final ratio = targetScale / currentScale;
    matrix.scaleByDouble(ratio, ratio, ratio, 1);
    _transformationController.value = matrix;
  }

  void _showPreviousImage() {
    if (_selectedIndex <= 0) {
      return;
    }
    setState(() {
      _selectedIndex -= 1;
      _resetTransform();
    });
  }

  void _showNextImage() {
    if (_selectedIndex >= widget.attachments.length - 1) {
      return;
    }
    setState(() {
      _selectedIndex += 1;
      _resetTransform();
    });
  }

  Future<void> _shareImage(List<int> bytes) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: _attachment.label,
            mimeType: 'image/*',
          ),
        ],
        subject: _attachment.label,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}

class _LightboxTopBar extends StatelessWidget {
  const _LightboxTopBar({
    required this.attachment,
    this.metadataLabel,
    required this.edgeToEdge,
    required this.canMovePrevious,
    required this.canMoveNext,
    required this.onClose,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleEdgeToEdge,
    required this.onShare,
  });

  final NoteAttachment attachment;
  final String? metadataLabel;
  final bool edgeToEdge;
  final bool canMovePrevious;
  final bool canMoveNext;
  final VoidCallback onClose;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onReset;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onToggleEdgeToEdge;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;
        final compact = width < 390;
        final veryCompact = width < 330;
        final zoomActions = <Widget>[
          if (onZoomOut != null)
            IconButton(
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove_rounded, color: Colors.white),
              tooltip: strings.zoomOut,
            ),
          if (onZoomIn != null)
            IconButton(
              onPressed: onZoomIn,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              tooltip: strings.zoomIn,
            ),
          if (onReset != null)
            IconButton(
              onPressed: onReset,
              icon: const Icon(
                Icons.center_focus_strong_rounded,
                color: Colors.white,
              ),
              tooltip: strings.fitToScreen,
            ),
        ];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: strings.close,
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (metadataLabel != null && metadataLabel!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            metadataLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ] else
                const Spacer(),
              IconButton(
                onPressed: canMovePrevious ? onPrevious : null,
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                ),
                tooltip: strings.previousImage,
              ),
              IconButton(
                onPressed: canMoveNext ? onNext : null,
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                ),
                tooltip: strings.nextImage,
              ),
              if (veryCompact && zoomActions.isNotEmpty)
                PopupMenuButton<_LightboxOverflowAction>(
                  tooltip: strings.localized(
                    en: 'More',
                    ja: 'その他',
                    zh: '更多',
                    ko: '더보기',
                    es: 'Mas',
                    de: 'Mehr',
                  ),
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _LightboxOverflowAction.zoomOut:
                        onZoomOut?.call();
                      case _LightboxOverflowAction.zoomIn:
                        onZoomIn?.call();
                      case _LightboxOverflowAction.reset:
                        onReset?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onZoomOut != null)
                      PopupMenuItem(
                        value: _LightboxOverflowAction.zoomOut,
                        child: Text(strings.zoomOut),
                      ),
                    if (onZoomIn != null)
                      PopupMenuItem(
                        value: _LightboxOverflowAction.zoomIn,
                        child: Text(strings.zoomIn),
                      ),
                    if (onReset != null)
                      PopupMenuItem(
                        value: _LightboxOverflowAction.reset,
                        child: Text(strings.fitToScreen),
                      ),
                  ],
                )
              else
                ...zoomActions,
              if (onToggleEdgeToEdge != null)
                IconButton(
                  onPressed: onToggleEdgeToEdge,
                  icon: Icon(
                    edgeToEdge
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  tooltip: edgeToEdge ? strings.restoreFrame : strings.maximize,
                ),
              if (onShare != null)
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  tooltip: strings.share,
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _LightboxOverflowAction { zoomOut, zoomIn, reset }

class _LightboxEdgeButton extends StatelessWidget {
  const _LightboxEdgeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
      ),
    );
  }
}

Future<ui.Size> _decodeImageSize(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  final image = frame.image;
  return ui.Size(image.width.toDouble(), image.height.toDouble());
}

Future<T> _profileNotePerfFuture<T>(
  String label,
  Future<T> Function() task,
) async {
  if (!kDebugMode) {
    return task();
  }
  final watch = Stopwatch()..start();
  try {
    final result = await task();
    watch.stop();
    _debugNotePerf('$label completed ${watch.elapsedMilliseconds}ms');
    return result;
  } catch (error) {
    watch.stop();
    _debugNotePerf('$label failed ${watch.elapsedMilliseconds}ms error=$error');
    rethrow;
  }
}

Future<List<int>?> _readPhotoAttachmentBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final filePath = attachment.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    List<int>? bytes;
    try {
      bytes = await _readDisplayAttachmentBytes(ref, attachment);
    } catch (error) {
      _logAttachmentDisplayDiagnostic(
        attachment,
        'attachment byte read failed',
        source: 'display',
        data: {'error': error},
      );
    }
    if (bytes != null && bytes.isNotEmpty) {
      _logAttachmentDisplayDiagnostic(
        attachment,
        'attachment byte read completed',
        source: 'display',
        data: {'bytes': bytes.length, ..._attachmentByteDiagnosticData(bytes)},
      );
      return bytes;
    }
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment byte read returned empty',
      source: 'display',
      data: {'hasPreview': attachment.previewBytesBase64?.isNotEmpty == true},
    );
    return _decodeAttachmentPreviewBytes(attachment);
  }
  _logAttachmentDisplayDiagnostic(
    attachment,
    'attachment has no file path for display',
    source: 'display',
    data: {'hasPreview': attachment.previewBytesBase64?.isNotEmpty == true},
  );
  return _decodeAttachmentPreviewBytes(attachment);
}

List<int>? _decodeAttachmentPreviewBytes(NoteAttachment attachment) {
  final previewBytesBase64 = attachment.previewBytesBase64;
  if (previewBytesBase64 == null || previewBytesBase64.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment preview bytes missing',
      source: 'preview',
    );
    return null;
  }
  try {
    final bytes = base64Decode(previewBytesBase64);
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment preview bytes decoded',
      source: 'preview',
      data: {'bytes': bytes.length, ..._attachmentByteDiagnosticData(bytes)},
    );
    return bytes;
  } on FormatException catch (error) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment preview bytes decode failed',
      source: 'preview',
      data: {'error': error},
    );
    return null;
  }
}

void _logAttachmentDisplayDiagnostic(
  NoteAttachment attachment,
  String message, {
  required String source,
  Map<String, Object?> data = const <String, Object?>{},
}) {
  final filePath = attachment.filePath;
  logDiagnostic(
    'attachment',
    message,
    data: {
      'source': source,
      'type': attachment.type.name,
      'label': attachment.label,
      'fileRef': _attachmentDiagnosticFileRef(filePath),
      'hasPreview': attachment.previewBytesBase64?.isNotEmpty == true,
      'previewBytesBase64Length': attachment.previewBytesBase64?.length,
      ...data,
    },
  );
}

Map<String, Object?> _attachmentByteDiagnosticData(List<int> bytes) {
  final header = bytes.take(16).toList(growable: false);
  return {
    'byteSignature': header
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' '),
    'detectedImageFormat': _detectImageFormat(bytes),
  };
}

String _detectImageFormat(List<int> bytes) {
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) {
      return false;
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  String asciiAt(int start, int end) {
    if (bytes.length < end) {
      return '';
    }
    return String.fromCharCodes(bytes.sublist(start, end));
  }

  if (startsWith(const [0xff, 0xd8, 0xff])) {
    return 'jpeg';
  }
  if (startsWith(const [0x89, 0x50, 0x4e, 0x47])) {
    return 'png';
  }
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) {
    return 'gif';
  }
  if (asciiAt(0, 4) == 'RIFF' && asciiAt(8, 12) == 'WEBP') {
    return 'webp';
  }
  final boxType = asciiAt(4, 12);
  if (boxType.startsWith('ftypheic') ||
      boxType.startsWith('ftypheix') ||
      boxType.startsWith('ftyphevc') ||
      boxType.startsWith('ftyphevx') ||
      boxType.startsWith('ftypheim') ||
      boxType.startsWith('ftypheis') ||
      boxType.startsWith('ftypmif1') ||
      boxType.startsWith('ftypmsf1')) {
    return 'heic';
  }
  return 'unknown';
}

String _attachmentDiagnosticFileRef(String? filePath) {
  if (filePath == null || filePath.isEmpty) {
    return 'none';
  }
  if (filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
    final hash = filePath.substring(_remoteSyncAttachmentObjectPrefix.length);
    final shortHash = hash.length <= 12 ? hash : hash.substring(0, 12);
    return '$_remoteSyncAttachmentObjectPrefix$shortHash';
  }
  return path.basename(filePath);
}

Future<List<int>?> _readDisplayAttachmentBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final filePath = attachment.filePath;
  if (filePath == null || filePath.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment display read skipped missing file path',
      source: 'display',
    );
    return null;
  }
  if (filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
    return _downloadRemoteSyncAttachmentBytes(ref, attachment);
  }
  final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
  final bytes = await attachmentStore.readAttachment(
    filePath,
    type: attachment.type,
  );
  if (bytes == null || bytes.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'local attachment read returned empty',
      source: 'display',
      data: await attachmentStore.storedPayloadDiagnostics(filePath),
    );
  }
  return bytes;
}

Future<List<int>?> _downloadRemoteSyncAttachmentBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final filePath = attachment.filePath;
  if (filePath == null ||
      !filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
    return null;
  }
  final contentHash = filePath.substring(
    _remoteSyncAttachmentObjectPrefix.length,
  );
  if (contentHash.isEmpty) {
    return null;
  }
  final provider = ref.read(syncProviderControllerProvider);
  _logAttachmentDisplayDiagnostic(
    attachment,
    'remote attachment object display download start',
    source: 'remote',
    data: {'provider': provider.name, 'contentHash': contentHash},
  );
  Future<String?> download() => switch (provider) {
    SyncProvider.iCloud =>
      ref
          .read(iCloudSyncTransportProvider)
          .downloadAttachmentObject(contentHash),
    SyncProvider.googleDrive =>
      ref
          .read(googleDriveSyncTransportProvider)
          .downloadAttachmentObject(contentHash),
    SyncProvider.off => Future<String?>.value(),
  };
  var encodedPayload = await download();
  if ((encodedPayload == null || encodedPayload.isEmpty) &&
      provider == SyncProvider.iCloud) {
    for (final delay in const [
      Duration(milliseconds: 700),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ]) {
      await Future<void>.delayed(delay);
      encodedPayload = await download();
      if (encodedPayload != null && encodedPayload.isNotEmpty) {
        break;
      }
    }
  }
  if (encodedPayload == null || encodedPayload.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object unavailable for display',
      source: 'remote',
      data: {'provider': provider.name, 'contentHash': contentHash},
    );
    return null;
  }
  late final Map<String, dynamic> decoded;
  try {
    decoded = await ref
        .read(secureSyncBundleStoreProvider)
        .readAttachmentObjectPayload(encodedPayload);
  } catch (error) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object decrypt failed',
      source: 'remote',
      data: {
        'provider': provider.name,
        'contentHash': contentHash,
        'error': error,
      },
    );
    return null;
  }
  final payloadHash = decoded['contentHash'] as String? ?? contentHash;
  if (payloadHash != contentHash) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object hash mismatch',
      source: 'remote',
      data: {'expectedHash': contentHash, 'payloadHash': payloadHash},
    );
    return null;
  }
  final payloadType = decoded['type'] as String?;
  if (payloadType != null && payloadType != attachment.type.name) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object type mismatch',
      source: 'remote',
      data: {'expectedType': attachment.type.name, 'payloadType': payloadType},
    );
    return null;
  }
  final bytesBase64 = decoded['bytesBase64'] as String?;
  if (bytesBase64 == null || bytesBase64.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object bytes missing',
      source: 'remote',
      data: {'contentHash': contentHash},
    );
    return null;
  }
  late final List<int> bytes;
  try {
    bytes = base64Decode(bytesBase64);
  } on FormatException catch (error) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object base64 decode failed',
      source: 'remote',
      data: {'contentHash': contentHash, 'error': error},
    );
    return null;
  }
  if (sha256.convert(bytes).toString() != contentHash) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object clear hash mismatch',
      source: 'remote',
      data: {'contentHash': contentHash, 'bytes': bytes.length},
    );
    return null;
  }
  _logAttachmentDisplayDiagnostic(
    attachment,
    'remote attachment object display download completed',
    source: 'remote',
    data: {
      'provider': provider.name,
      'contentHash': contentHash,
      'bytes': bytes.length,
    },
  );
  return bytes;
}

Future<List<int>?> _readPhotoAttachmentDetailBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) {
  final previewBytesBase64 = attachment.previewBytesBase64;
  if (previewBytesBase64 != null && previewBytesBase64.isNotEmpty) {
    try {
      final bytes = base64Decode(previewBytesBase64);
      _logAttachmentDisplayDiagnostic(
        attachment,
        'detail preview bytes decoded',
        source: 'detail',
        data: {'bytes': bytes.length},
      );
      return Future<List<int>?>.value(bytes);
    } on FormatException catch (error) {
      _logAttachmentDisplayDiagnostic(
        attachment,
        'detail preview bytes decode failed',
        source: 'detail',
        data: {'error': error},
      );
      return Future<List<int>?>.value(null);
    }
  }
  return _readPhotoAttachmentBytes(ref, attachment);
}

String _attachmentCacheKey(NoteAttachment attachment) {
  final filePath = attachment.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    return '$filePath:${attachment.previewBytesBase64 ?? ''}';
  }
  return '${attachment.label}:${attachment.previewBytesBase64 ?? ''}';
}

const _photoAttachmentBytesCacheLimit = 24;
final _photoAttachmentBytesCache = <String, Future<List<int>?>>{};

Future<List<int>?> _readPhotoAttachmentBytesWithPerf(
  WidgetRef ref,
  NoteAttachment attachment, {
  required String source,
}) {
  final filePath = attachment.filePath;
  final cacheKey = _attachmentCacheKey(attachment);
  final cached = _photoAttachmentBytesCache[cacheKey];
  if (cached != null) {
    _debugNotePerf(
      '$source photo read cache-hit label="${attachment.label}" file=${filePath == null ? 'inline' : path.basename(filePath)}',
    );
    return cached;
  }
  if (_photoAttachmentBytesCache.length >= _photoAttachmentBytesCacheLimit) {
    _photoAttachmentBytesCache.remove(_photoAttachmentBytesCache.keys.first);
  }
  final future = _profileNotePerfFuture(
    '$source photo read label="${attachment.label}" file=${filePath == null ? 'inline' : path.basename(filePath)}',
    () => _readPhotoAttachmentDetailBytes(ref, attachment),
  );
  _photoAttachmentBytesCache[cacheKey] = future;
  future.then((bytes) {
    if (bytes == null || bytes.isEmpty) {
      _photoAttachmentBytesCache.remove(cacheKey);
    }
  });
  future.catchError((Object _) {
    _photoAttachmentBytesCache.remove(cacheKey);
    return null;
  });
  return future;
}

class _PhotoAttachmentViewer extends ConsumerWidget {
  const _PhotoAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<int>?>(
      future: _readPhotoAttachmentBytesWithPerf(
        ref,
        attachment,
        source: 'viewer',
      ),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (bytes == null || bytes.isEmpty) {
          return Center(child: Text(context.strings.unableToDecryptImage));
        }
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                _logAttachmentDisplayDiagnostic(
                  attachment,
                  'image decode failed',
                  source: 'viewer',
                  data: {
                    'error': error,
                    'bytes': bytes.length,
                    ..._attachmentByteDiagnosticData(bytes),
                  },
                );
                return const _AttachmentImageErrorPanel(height: 180);
              },
            ),
          ),
        );
      },
    );
  }
}

class _VideoAttachmentViewer extends ConsumerStatefulWidget {
  const _VideoAttachmentViewer({
    required this.attachment,
    this.fillAvailableHeight = false,
    this.autoLoad = false,
    this.onOpenFullScreen,
    this.showFullScreenAction = true,
    this.showShareAction = true,
  });

  final NoteAttachment attachment;
  final bool fillAvailableHeight;
  final bool autoLoad;
  final VoidCallback? onOpenFullScreen;
  final bool showFullScreenAction;
  final bool showShareAction;

  @override
  ConsumerState<_VideoAttachmentViewer> createState() =>
      _VideoAttachmentViewerState();
}

class _VideoAttachmentViewerState
    extends ConsumerState<_VideoAttachmentViewer> {
  VideoPlayerController? _controller;
  String? _tempFilePath;
  String? _webObjectUrl;
  String? _webVideoViewType;
  bool _webVideoAutoplay = false;
  String? _errorMessage;
  bool _wasPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _dragPosition;
  int _loadGeneration = 0;
  int _videoViewGeneration = 0;
  bool _loading = false;
  bool _playWhenLoaded = false;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _muted = ref.read(videoPlaybackMutedByDefaultControllerProvider);
    if (widget.autoLoad) {
      unawaited(_load(playWhenLoaded: false));
    }
  }

  @override
  void didUpdateWidget(covariant _VideoAttachmentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.filePath == widget.attachment.filePath &&
        oldWidget.attachment.type == widget.attachment.type &&
        oldWidget.attachment.label == widget.attachment.label) {
      return;
    }
    unawaited(_resetAndMaybeLoad());
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    final controller = _controller;
    controller?.removeListener(_handleControllerChanged);
    unawaited(controller?.dispose());
    final tempFilePath = _tempFilePath;
    final webObjectUrl = _webObjectUrl;
    if (tempFilePath != null) {
      unawaited(
        ref
            .read(encryptedAttachmentStoreProvider)
            .deleteMaterializedFile(tempFilePath),
      );
    }
    if (webObjectUrl != null) {
      revokeWebVideoObjectUrl(webObjectUrl);
    }
    super.dispose();
  }

  Future<void> _resetAndMaybeLoad() async {
    final generation = ++_loadGeneration;
    final controller = _controller;
    final tempFilePath = _tempFilePath;
    final webObjectUrl = _webObjectUrl;
    setState(() {
      _controller = null;
      _tempFilePath = null;
      _webObjectUrl = null;
      _webVideoViewType = null;
      _webVideoAutoplay = false;
      _errorMessage = null;
      _wasPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _dragPosition = null;
      _loading = false;
      _playWhenLoaded = false;
      _muted = ref.read(videoPlaybackMutedByDefaultControllerProvider);
    });
    controller?.removeListener(_handleControllerChanged);
    await controller?.dispose();
    if (tempFilePath != null) {
      await ref
          .read(encryptedAttachmentStoreProvider)
          .deleteMaterializedFile(tempFilePath);
    }
    if (webObjectUrl != null) {
      revokeWebVideoObjectUrl(webObjectUrl);
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    if (widget.autoLoad) {
      await _load(playWhenLoaded: false);
    }
  }

  Future<void> _load({required bool playWhenLoaded}) async {
    if (_loading || _controller != null) {
      return;
    }
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _playWhenLoaded = playWhenLoaded;
      _errorMessage = null;
    });
    await _loadAttachment(
      generation: generation,
      playWhenLoaded: playWhenLoaded,
    );
  }

  Future<void> _loadAttachment({
    required int generation,
    required bool playWhenLoaded,
  }) async {
    final filePath = widget.attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _errorMessage = context.strings.videoPreviewUnavailableWeb;
          _loading = false;
          _playWhenLoaded = false;
        });
      }
      return;
    }
    String? tempFilePath;
    String? webObjectUrl;
    try {
      final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
      final VideoPlayerController controller;
      if (kIsWeb) {
        final bytes = await _readDisplayAttachmentBytes(ref, widget.attachment);
        if (!mounted || generation != _loadGeneration) {
          return;
        }
        if (bytes == null || bytes.isEmpty) {
          setState(() {
            _errorMessage = context.strings.videoPreviewUnavailableWeb;
            _loading = false;
            _playWhenLoaded = false;
          });
          return;
        }
        final mimeType = _mimeTypeForVideoAttachment(widget.attachment);
        webObjectUrl = createWebVideoObjectUrl(
          Uint8List.fromList(bytes),
          mimeType,
        );
        if (webObjectUrl == null) {
          setState(() {
            _errorMessage = context.strings.videoPreviewUnavailableWeb;
            _loading = false;
            _playWhenLoaded = false;
          });
          return;
        }
        setState(() {
          _webObjectUrl = webObjectUrl;
          _webVideoViewType =
              'himemo-video-${DateTime.now().microsecondsSinceEpoch}';
          _webVideoAutoplay = playWhenLoaded;
          _loading = false;
          _playWhenLoaded = false;
        });
        return;
      } else {
        if (filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
          final bytes = await _readDisplayAttachmentBytes(
            ref,
            widget.attachment,
          );
          if (bytes != null && bytes.isNotEmpty) {
            tempFilePath = await attachmentStore.materializeDecryptedBytes(
              bytes,
              type: widget.attachment.type,
              preferredFileName: widget.attachment.label,
            );
          }
        } else {
          tempFilePath = await attachmentStore.materializeDecryptedFile(
            filePath,
            type: widget.attachment.type,
            preferredFileName: widget.attachment.label,
          );
        }
        if (!mounted || generation != _loadGeneration) {
          if (tempFilePath != null) {
            await attachmentStore.deleteMaterializedFile(tempFilePath);
          }
          return;
        }
        if (tempFilePath == null) {
          setState(() {
            _errorMessage = context.strings.videoPreviewUnavailableWeb;
            _loading = false;
            _playWhenLoaded = false;
          });
          return;
        }
        controller = createLocalVideoController(tempFilePath);
      }
      await controller.initialize().timeout(const Duration(seconds: 15));
      await _applyMutedState(controller);
      controller.addListener(_handleControllerChanged);
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        await attachmentStore.deleteMaterializedFile(tempFilePath);
        return;
      }
      if (playWhenLoaded) {
        unawaited(controller.play());
      }
      setState(() {
        _tempFilePath = tempFilePath;
        _webObjectUrl = webObjectUrl;
        _controller = controller;
        _wasPlaying = controller.value.isPlaying;
        _position = controller.value.position;
        _duration = controller.value.duration;
        _loading = false;
        _playWhenLoaded = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Video playback load failed: $error\n$stackTrace');
      if (tempFilePath != null) {
        unawaited(
          ref
              .read(encryptedAttachmentStoreProvider)
              .deleteMaterializedFile(tempFilePath),
        );
      }
      if (webObjectUrl != null) {
        revokeWebVideoObjectUrl(webObjectUrl);
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _errorMessage = context.strings.videoPreviewUnavailableWeb;
        _loading = false;
        _playWhenLoaded = false;
      });
    }
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    final isPlaying = controller.value.isPlaying;
    final position = controller.value.position;
    final duration = controller.value.duration;
    if (isPlaying == _wasPlaying &&
        (position - _position).abs() < const Duration(milliseconds: 250) &&
        duration == _duration) {
      return;
    }
    setState(() {
      _wasPlaying = isPlaying;
      _position = position;
      _duration = duration;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(child: Text(errorMessage));
    }
    if (kIsWeb && _webObjectUrl != null && _webVideoViewType != null) {
      return _buildWebVideo(
        context,
        _webObjectUrl!,
        _webVideoViewType!,
        muted: _muted,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return _buildDeferredPreview(context, loading: _loading);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 520.0;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        const controlsHeight = 96.0;
        final maxVideoHeight = math.max(96.0, availableHeight - controlsHeight);
        final aspectRatio = controller.value.aspectRatio <= 0
            ? 16 / 9
            : controller.value.aspectRatio;
        final duration = _duration <= Duration.zero
            ? controller.value.duration
            : _duration;
        final boundedPosition = _clampMediaPosition(_position, duration);
        final displayPosition = _dragPosition == null
            ? boundedPosition
            : _clampMediaPosition(_dragPosition!, duration);
        final controlsOnDark = widget.fillAvailableHeight;
        final controlColor = controlsOnDark ? Colors.white : null;
        final secondaryControlColor = controlsOnDark
            ? Colors.white70
            : _mutedTextColor(context);
        final videoTapHandler = widget.fillAvailableHeight
            ? () => _togglePlayback(controller)
            : _openFullScreen;
        final videoPane = SizedBox(
          height: maxVideoHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxVideoHeight,
              ),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AbsorbPointer(
                        child: VideoPlayer(
                          controller,
                          key: ValueKey(_videoViewGeneration),
                        ),
                      ),
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: videoTapHandler,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        return Column(
          mainAxisSize: widget.fillAvailableHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (widget.fillAvailableHeight)
              Expanded(child: videoPane)
            else
              videoPane,
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () => _togglePlayback(controller),
                  icon: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    color: controlColor,
                  ),
                ),
                IconButton(
                  onPressed: _toggleMuted,
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: controlColor,
                  ),
                  tooltip: _videoMuteTooltip(_muted),
                ),
                Expanded(
                  child: Slider(
                    value: duration <= Duration.zero
                        ? 0
                        : displayPosition.inMilliseconds
                              .clamp(0, duration.inMilliseconds)
                              .toDouble(),
                    max: duration <= Duration.zero
                        ? 1
                        : duration.inMilliseconds.toDouble(),
                    onChanged: duration <= Duration.zero
                        ? null
                        : (value) {
                            setState(() {
                              _dragPosition = Duration(
                                milliseconds: value.round(),
                              );
                            });
                          },
                    onChangeEnd: duration <= Duration.zero
                        ? null
                        : (value) {
                            unawaited(
                              _seekFromSlider(controller, value, duration),
                            );
                          },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '${_formatAudioDuration(displayPosition)} / '
                  '${_formatAudioDuration(duration)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: secondaryControlColor,
                  ),
                ),
                const Spacer(),
                if (widget.showFullScreenAction &&
                    widget.onOpenFullScreen != null)
                  IconButton(
                    onPressed: _openFullScreen,
                    icon: Icon(Icons.open_in_full_rounded, color: controlColor),
                  ),
                if (widget.showShareAction)
                  IconButton(
                    onPressed: () =>
                        _shareAttachment(context, ref, widget.attachment),
                    icon: Icon(Icons.ios_share_outlined, color: controlColor),
                    tooltip: context.strings.share,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildWebVideo(
    BuildContext context,
    String objectUrl,
    String viewType, {
    required bool muted,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 520.0;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        final maxVideoHeight = widget.fillAvailableHeight
            ? availableHeight
            : math.max(96.0, availableHeight - 56.0);
        final videoPane = SizedBox(
          height: maxVideoHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxVideoHeight,
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: buildWebVideoElementView(
                    viewType: viewType,
                    objectUrl: objectUrl,
                    autoplay: _webVideoAutoplay,
                    muted: muted,
                    fillAvailableHeight: widget.fillAvailableHeight,
                  ),
                ),
              ),
            ),
          ),
        );
        final controlColor = widget.fillAvailableHeight ? Colors.white : null;
        return Column(
          mainAxisSize: widget.fillAvailableHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (widget.fillAvailableHeight)
              Expanded(child: videoPane)
            else
              videoPane,
            if (!widget.fillAvailableHeight) const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: _toggleMuted,
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: controlColor,
                  ),
                  tooltip: _videoMuteTooltip(_muted),
                ),
                const Spacer(),
                if (widget.showFullScreenAction &&
                    widget.onOpenFullScreen != null)
                  IconButton(
                    onPressed: _openFullScreen,
                    icon: Icon(Icons.open_in_full_rounded, color: controlColor),
                  ),
                if (widget.showShareAction)
                  IconButton(
                    onPressed: () =>
                        _shareAttachment(context, ref, widget.attachment),
                    icon: Icon(Icons.ios_share_outlined, color: controlColor),
                    tooltip: context.strings.share,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeferredPreview(BuildContext context, {required bool loading}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 520.0;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        const controlsHeight = 96.0;
        final maxVideoHeight = math.max(96.0, availableHeight - controlsHeight);
        final controlsOnDark = widget.fillAvailableHeight;
        final controlColor = controlsOnDark ? Colors.white : null;
        final secondaryControlColor = controlsOnDark
            ? Colors.white70
            : _mutedTextColor(context);
        final previewBytes = _decodeVideoPreviewBytes();
        final playAction = loading
            ? null
            : () => unawaited(_load(playWhenLoaded: true));
        final videoPane = SizedBox(
          height: maxVideoHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxVideoHeight,
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: InkWell(
                      onTap: playAction,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (previewBytes != null)
                            Image.memory(
                              previewBytes,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.videocam_outlined,
                                  size: 56,
                                  color: Theme.of(context).colorScheme.primary,
                                );
                              },
                            )
                          else
                            Icon(
                              Icons.videocam_outlined,
                              size: 56,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.18),
                          ),
                          Center(
                            child: loading
                                ? const SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  )
                                : Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.56,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 38,
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
          ),
        );

        return Column(
          mainAxisSize: widget.fillAvailableHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (widget.fillAvailableHeight)
              Expanded(child: videoPane)
            else
              videoPane,
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: playAction,
                  icon: Icon(Icons.play_circle_outline, color: controlColor),
                ),
                Expanded(
                  child: Text(
                    loading && _playWhenLoaded
                        ? context.strings.localized(
                            en: 'Loading video...',
                            ja: '動画を読み込み中...',
                            zh: '正在加载视频...',
                            ko: '동영상을 불러오는 중...',
                            es: 'Cargando video...',
                            de: 'Video wird geladen...',
                          )
                        : context.strings.tapToPlayVideo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: secondaryControlColor,
                    ),
                  ),
                ),
                if (widget.showShareAction)
                  IconButton(
                    onPressed: () =>
                        _shareAttachment(context, ref, widget.attachment),
                    icon: Icon(Icons.ios_share_outlined, color: controlColor),
                    tooltip: context.strings.share,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Uint8List? _decodeVideoPreviewBytes() {
    final encoded = widget.attachment.previewBytesBase64;
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> _openFullScreen() async {
    final strings = context.strings;
    final sizeBytes = await _attachmentSizeFuture(ref, widget.attachment);
    if (!mounted) {
      return;
    }
    final sizeLabel = sizeBytes == null || sizeBytes <= 0
        ? null
        : strings.byteCount(sizeBytes);
    if (kIsWeb && _webObjectUrl != null) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.88),
        pageBuilder: (context, _, _) => _WebVideoLightboxDialog(
          attachment: widget.attachment,
          objectUrl: _webObjectUrl!,
          muted: _muted,
          sizeLabel: sizeLabel,
          onMutedChanged: _handleMutedChanged,
          onShare: widget.showShareAction
              ? () => _shareAttachment(context, ref, widget.attachment)
              : null,
        ),
        transitionBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      widget.onOpenFullScreen?.call();
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (context, _, _) => _VideoControllerLightboxDialog(
        attachment: widget.attachment,
        controller: controller,
        initialMuted: _muted,
        sizeLabel: sizeLabel,
        onMutedChanged: _handleMutedChanged,
        onShare: widget.showShareAction
            ? () => _shareAttachment(context, ref, widget.attachment)
            : null,
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
    if (mounted) {
      setState(() {
        _videoViewGeneration += 1;
        _wasPlaying = controller.value.isPlaying;
        _position = controller.value.position;
        _duration = controller.value.duration;
      });
    }
  }

  Future<void> _applyMutedState(VideoPlayerController controller) async {
    final desiredVolume = _muted ? 0.0 : 1.0;
    if ((controller.value.volume - desiredVolume).abs() < 0.01) {
      return;
    }
    await controller.setVolume(desiredVolume);
  }

  void _togglePlayback(VideoPlayerController controller) {
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      final duration = controller.value.duration;
      if (duration > Duration.zero &&
          controller.value.position >=
              duration - const Duration(milliseconds: 250)) {
        unawaited(
          controller.seekTo(Duration.zero).then((_) => controller.play()),
        );
      } else {
        unawaited(controller.play());
      }
    }
    setState(() {});
  }

  void _toggleMuted() {
    _handleMutedChanged(!_muted);
  }

  void _handleMutedChanged(bool muted) {
    if (kIsWeb && _webVideoViewType != null) {
      updateWebVideoElementMuted(_webVideoViewType!, muted);
    }
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.setVolume(muted ? 0.0 : 1.0));
    }
    if (!mounted) {
      _muted = muted;
      return;
    }
    setState(() {
      _muted = muted;
    });
  }

  Future<void> _seekFromSlider(
    VideoPlayerController controller,
    double value,
    Duration duration,
  ) async {
    final target = _clampMediaPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
    await controller.seekTo(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _position = target;
      _dragPosition = null;
    });
  }
}

Duration _clampMediaPosition(Duration value, Duration duration) {
  if (duration <= Duration.zero) {
    return Duration.zero;
  }
  if (value < Duration.zero) {
    return Duration.zero;
  }
  if (value > duration) {
    return duration;
  }
  return value;
}

String _mimeTypeForVideoAttachment(NoteAttachment attachment) {
  final label = attachment.label.toLowerCase();
  if (label.endsWith('.webm')) {
    return 'video/webm';
  }
  if (label.endsWith('.ogv') || label.endsWith('.ogg')) {
    return 'video/ogg';
  }
  if (label.endsWith('.mov')) {
    return 'video/quicktime';
  }
  if (label.endsWith('.m4v')) {
    return 'video/x-m4v';
  }
  return 'video/mp4';
}

Future<MediaImportResult> _showAudioRecordingDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showDialog<MediaImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AudioRecordingDialog(
      attachmentStore: ref.read(encryptedAttachmentStoreProvider),
    ),
  );
  return result ?? const MediaImportResult.cancelled();
}

class _RecordingFormat {
  const _RecordingFormat({
    required this.encoder,
    required this.extension,
    required this.mimeType,
  });

  final AudioEncoder encoder;
  final String extension;
  final String mimeType;
}

class _AudioRecordingDialog extends StatefulWidget {
  const _AudioRecordingDialog({required this.attachmentStore});

  final EncryptedAttachmentStore attachmentStore;

  @override
  State<_AudioRecordingDialog> createState() => _AudioRecordingDialogState();
}

class _AudioRecordingDialogState extends State<_AudioRecordingDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isRecording = false;
  bool _isBusy = false;
  String? _errorMessage;
  String? _fileName;
  _RecordingFormat? _format;
  StreamSubscription<Uint8List>? _webRecordingSubscription;
  final List<int> _webRecordingPcmBytes = <int>[];

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_webRecordingSubscription?.cancel());
    if (_isRecording) {
      unawaited(_recorder.cancel());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      final strings = context.strings;
      final hasPermission = await _recorder.hasPermission().timeout(
        kIsWeb ? const Duration(seconds: 30) : const Duration(seconds: 10),
        onTimeout: () =>
            throw TimeoutException(strings.microphonePermissionRequestTimedOut),
      );
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = kIsWeb
              ? '${strings.microphonePermissionNotGranted} ${strings.microphonePermissionBrowserHelp}'
              : strings.microphonePermissionNotGranted;
        });
        return;
      }

      final format = await _resolveRecordingFormat();
      debugPrint(
        'Audio recording start: encoder=${format.encoder.name}, '
        'extension=${format.extension}, web=$kIsWeb',
      );
      final timestamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final fileName = 'audio_note_$timestamp.${format.extension}';
      final outputPath = kIsWeb
          ? fileName
          : path.join((await getTemporaryDirectory()).path, fileName);

      if (kIsWeb) {
        _webRecordingPcmBytes.clear();
        final stream = await _recorder
            .startStream(_recordConfig(AudioEncoder.pcm16bits))
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () =>
                  throw TimeoutException(strings.microphoneStartTimedOut),
            );
        _webRecordingSubscription = stream.listen(_webRecordingPcmBytes.addAll);
      } else {
        await _recorder.start(_recordConfig(format.encoder), path: outputPath);
      }
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _elapsed += const Duration(seconds: 1);
          });
        }
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _format = format;
        _fileName = fileName;
        _elapsed = Duration.zero;
        _isRecording = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Audio recording failed: $error\n$stackTrace');
      if (kIsWeb) {
        unawaited(_webRecordingSubscription?.cancel());
        _webRecordingSubscription = null;
        unawaited(_recorder.cancel());
      }
      if (!mounted) {
        return;
      }
      final diagnostic = _recordingStartDiagnostic(error, context.strings);
      setState(() {
        _errorMessage = context.strings.audioRecordingStartFailed(diagnostic);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  String _recordingStartDiagnostic(Object error, AppStrings strings) {
    if (!kIsWeb) {
      return '';
    }
    if (error is TimeoutException && error.message != null) {
      return ' ${error.message}';
    }
    final message = error.toString().toLowerCase();
    if (message.contains('notallowed') ||
        message.contains('permission') ||
        message.contains('denied')) {
      return ' ${strings.microphonePermissionBrowserHelp}';
    }
    return '';
  }

  RecordConfig _recordConfig(AudioEncoder encoder) {
    return RecordConfig(
      encoder: encoder,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(
        service: AndroidService(
          title: context.strings.audioRecordingNotificationTitle,
          content: context.strings.audioRecordingNotificationContent,
        ),
      ),
      audioInterruption: AudioInterruptionMode.none,
    );
  }

  Future<void> _stopAndAttach() async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      _timer?.cancel();
      await _webRecordingSubscription?.cancel();
      _webRecordingSubscription = null;
      final recordedPath = await _recorder.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
      });
      final fileName = _fileName;
      final format = _format;
      if (fileName == null || format == null) {
        setState(() {
          _errorMessage = context.strings.audioRecordingSaveFailed;
        });
        return;
      }
      if (!kIsWeb && recordedPath == null) {
        setState(() {
          _errorMessage = context.strings.audioRecordingSaveFailed;
        });
        return;
      }
      if (kIsWeb && _webRecordingPcmBytes.isEmpty) {
        setState(() {
          _errorMessage = context.strings.audioRecordingEmpty;
        });
        return;
      }
      final file = kIsWeb
          ? XFile.fromData(
              Uint8List.fromList(
                _wavBytesFromPcm16(
                  _webRecordingPcmBytes,
                  sampleRate: 44100,
                  numChannels: 1,
                ),
              ),
              name: fileName,
              mimeType: format.mimeType,
            )
          : XFile(recordedPath!, name: fileName, mimeType: format.mimeType);
      final filePath = await widget.attachmentStore.storeAttachment(
        file,
        type: AttachmentType.audio,
      );
      if (!mounted) {
        return;
      }
      if (filePath == null) {
        setState(() {
          _errorMessage = context.strings.audioRecordingAttachFailed;
        });
        return;
      }
      Navigator.of(context).pop(
        MediaImportResult.success(
          NoteAttachment(
            type: AttachmentType.audio,
            label: fileName,
            filePath: filePath,
            durationMs: _elapsed.inMilliseconds,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = context.strings.audioRecordingStoreFailed;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_isRecording) {
      await _recorder.cancel();
    }
    if (mounted) {
      Navigator.of(context).pop(const MediaImportResult.cancelled());
    }
  }

  Future<_RecordingFormat> _resolveRecordingFormat() async {
    if (kIsWeb) {
      return const _RecordingFormat(
        encoder: AudioEncoder.wav,
        extension: 'wav',
        mimeType: 'audio/wav',
      );
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return const _RecordingFormat(
        encoder: AudioEncoder.aacLc,
        extension: 'm4a',
        mimeType: 'audio/mp4',
      );
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      return const _RecordingFormat(
        encoder: AudioEncoder.wav,
        extension: 'wav',
        mimeType: 'audio/wav',
      );
    }
    return const _RecordingFormat(
      encoder: AudioEncoder.aacLc,
      extension: 'm4a',
      mimeType: 'audio/mp4',
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.audioMemoRecordingTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isRecording
                  ? Icons.fiber_manual_record_rounded
                  : Icons.mic_none_rounded,
              size: 56,
              color: _isRecording
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              _formatRecordingDuration(_elapsed),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : _cancel,
          child: Text(strings.cancel),
        ),
        if (_isRecording)
          FilledButton.icon(
            onPressed: _isBusy ? null : _stopAndAttach,
            icon: const Icon(Icons.stop_rounded),
            label: Text(strings.stopAndAttachRecording),
          )
        else
          FilledButton.icon(
            onPressed: _isBusy ? null : _start,
            icon: const Icon(Icons.mic_rounded),
            label: Text(strings.startRecording),
          ),
      ],
    );
  }
}

List<int> _wavBytesFromPcm16(
  List<int> pcmBytes, {
  required int sampleRate,
  required int numChannels,
}) {
  final byteRate = sampleRate * numChannels * 2;
  final blockAlign = numChannels * 2;
  final dataLength = pcmBytes.length;
  final totalLength = 44 + dataLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.view(bytes.buffer);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i += 1) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, numChannels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  bytes.setRange(44, totalLength, pcmBytes);
  return bytes;
}

String _formatRecordingDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _AudioAttachmentViewer extends ConsumerStatefulWidget {
  const _AudioAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  ConsumerState<_AudioAttachmentViewer> createState() =>
      _AudioAttachmentViewerState();
}

class _AudioAttachmentViewerState
    extends ConsumerState<_AudioAttachmentViewer> {
  final AudioPlayer _player = AudioPlayer();
  String? _tempFilePath;
  bool _ready = false;
  String? _errorMessage;
  Duration? _dragPosition;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    final tempFilePath = _tempFilePath;
    if (tempFilePath != null) {
      unawaited(
        ref
            .read(encryptedAttachmentStoreProvider)
            .deleteMaterializedFile(tempFilePath),
      );
    }
    super.dispose();
  }

  Future<void> _load() async {
    final filePath = widget.attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage = context.strings.audioPlaybackFailed;
        });
      }
      return;
    }
    try {
      final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
      if (kIsWeb) {
        final bytes = await attachmentStore.readAttachment(
          filePath,
          type: widget.attachment.type,
        );
        if (!mounted) {
          return;
        }
        if (bytes == null || bytes.isEmpty) {
          setState(() {
            _errorMessage = context.strings.audioPlaybackFailed;
          });
          return;
        }
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.dataFromBytes(
              Uint8List.fromList(bytes),
              mimeType: _mimeTypeForAudioAttachment(widget.attachment),
            ),
          ),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _ready = true;
        });
        return;
      }

      final tempFilePath = await attachmentStore.materializeDecryptedFile(
        filePath,
        type: widget.attachment.type,
        preferredFileName: widget.attachment.label,
      );
      if (!mounted) {
        return;
      }
      if (tempFilePath == null) {
        setState(() {
          _errorMessage = context.strings.audioPlaybackFailed;
        });
        return;
      }
      await _player
          .setFilePath(tempFilePath)
          .timeout(const Duration(seconds: 15));
      setState(() {
        _tempFilePath = tempFilePath;
        _ready = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Audio playback load failed: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = context.strings.audioPlaybackFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(child: Text(errorMessage));
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final isPlaying = playerState?.playing ?? false;
        final isCompleted =
            playerState?.processingState == ProcessingState.completed;
        return StreamBuilder<Duration?>(
          stream: _player.durationStream,
          builder: (context, durationSnapshot) {
            final duration =
                durationSnapshot.data ?? _player.duration ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final boundedPosition =
                    position > duration && duration > Duration.zero
                    ? duration
                    : position;
                final displayPosition =
                    _dragPosition == null || duration == Duration.zero
                    ? boundedPosition
                    : _clampAudioPosition(_dragPosition!, duration);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.audiotrack_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: duration == Duration.zero
                            ? 0
                            : displayPosition.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble(),
                        max: duration == Duration.zero
                            ? 1
                            : duration.inMilliseconds.toDouble(),
                        onChanged: duration == Duration.zero
                            ? null
                            : (value) {
                                setState(() {
                                  _dragPosition = Duration(
                                    milliseconds: value.round(),
                                  );
                                });
                              },
                        onChangeEnd: duration == Duration.zero
                            ? null
                            : (value) {
                                unawaited(_seekFromSlider(value, duration));
                              },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatAudioDuration(displayPosition)),
                          Text(_formatAudioDuration(duration)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          if (isPlaying) {
                            await _player.pause();
                          } else {
                            if (isCompleted) {
                              await _player.seek(Duration.zero);
                            }
                            await _player.play();
                          }
                        },
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        label: Text(
                          isPlaying
                              ? context.strings.pauseAudio
                              : context.strings.playAudio,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _seekFromSlider(double value, Duration duration) async {
    final target = _clampAudioPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
    try {
      await _player.seek(target);
    } catch (error, stackTrace) {
      debugPrint('Audio seek failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = context.strings.audioPlaybackFailed;
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _dragPosition = null;
    });
  }
}

Duration _clampAudioPosition(Duration value, Duration duration) {
  if (duration <= Duration.zero) {
    return Duration.zero;
  }
  if (value < Duration.zero) {
    return Duration.zero;
  }
  if (value > duration) {
    return duration;
  }
  return value;
}

String _formatAudioDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String _mimeTypeForAudioAttachment(NoteAttachment attachment) {
  final label = attachment.label.toLowerCase();
  if (label.endsWith('.wav')) {
    return 'audio/wav';
  }
  if (label.endsWith('.m4a') || label.endsWith('.mp4')) {
    return 'audio/mp4';
  }
  if (label.endsWith('.webm')) {
    return 'audio/webm';
  }
  if (label.endsWith('.ogg') || label.endsWith('.opus')) {
    return 'audio/ogg';
  }
  return 'audio/mpeg';
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
