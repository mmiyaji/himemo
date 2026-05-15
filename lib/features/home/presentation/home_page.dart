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
