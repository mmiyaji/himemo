import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;

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
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pinput/pinput.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_strings.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/google_sign_in_initializer.dart';
import '../../sync/data/sync_bundle_preview.dart';
import '../../sync/presentation/google_sign_in_web_button.dart';
import '../domain/note_entry.dart';
import '../domain/note_tags.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';

const _appStoreId = String.fromEnvironment('HIMEMO_APP_STORE_ID');
const _androidStorePackageName = 'org.ruhenheim.himemo';
const _buildDateIso = String.fromEnvironment('HIMEMO_BUILD_DATE');

enum AppSection { notes, calendar, insights, settings }

final _noteOverlaySheetDepth = ValueNotifier<int>(0);

void _pushNoteOverlaySheet() {
  _noteOverlaySheetDepth.value = _noteOverlaySheetDepth.value + 1;
}

void _popNoteOverlaySheet() {
  if (_noteOverlaySheetDepth.value > 0) {
    _noteOverlaySheetDepth.value = _noteOverlaySheetDepth.value - 1;
  }
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
  bool _sidebarCollapsed = false;
  AppSection? _lastObservedSection;
  bool _noteOverlayWasOpen = false;
  DateTime? _suppressProfileAccessUntil;

  @override
  void initState() {
    super.initState();
    _noteOverlaySheetDepth.addListener(_handleNoteOverlayChanged);
  }

  @override
  void dispose() {
    _noteOverlaySheetDepth.removeListener(_handleNoteOverlayChanged);
    super.dispose();
  }

  void _handleNoteOverlayChanged() {
    final noteOverlayOpen = _noteOverlaySheetDepth.value > 0;
    if (_noteOverlayWasOpen && !noteOverlayOpen) {
      _suppressProfileAccessUntil = DateTime.now().add(
        const Duration(milliseconds: 450),
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
    final noteOverlayOpen = _noteOverlaySheetDepth.value > 0;
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final activePrivateProfileLabel = ref.watch(
      activePrivateProfileLabelProvider,
    );
    final adminMode = ref.watch(adminModeSessionControllerProvider);
    final profileUnlocking = ref.watch(
      privateProfileUnlockControllerProvider.select((value) => value.isLoading),
    );
    final privateProfileActive =
        !adminMode && activePrivateProfileLabel != null;
    final privateProfileActiveColor = Theme.of(context).colorScheme.primary;
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
    final effectiveProfileAccessTooltip = profileUnlocking
        ? profileAccessBusyTooltip
        : profileAccessTooltip;

    return Scaffold(
      appBar: AppBar(
        title: const _AppBrandTitle(),
        actions: [
          if (privateProfileActive)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(220, width * 0.42),
                ),
                child: Tooltip(
                  message: profileUnlocking
                      ? profileAccessBusyTooltip
                      : context.strings.viewingPrivateProfile(
                          activePrivateProfileLabel,
                        ),
                  child: Material(
                    color: privateProfileActiveColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      key: AppShell.privateProfileAccessKey,
                      borderRadius: BorderRadius.circular(999),
                      onTap: noteOverlayOpen || profileUnlocking
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
                              Icon(
                                Icons.lock_open_rounded,
                                size: 20,
                                color: privateProfileActiveColor,
                              ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                activePrivateProfileLabel,
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
                      enabled: !noteOverlayOpen && !profileUnlocking,
                      label: effectiveProfileAccessTooltip,
                      onTap: noteOverlayOpen || profileUnlocking
                          ? null
                          : () => _handleProfileAccessTap(context, ref),
                      child: Material(
                        type: MaterialType.transparency,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: AppShell.privateProfileAccessKey,
                          customBorder: const CircleBorder(),
                          onTap: noteOverlayOpen || profileUnlocking
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
                                : Icon(
                                    adminMode
                                        ? Icons.admin_panel_settings_rounded
                                        : activePrivateProfileLabel != null
                                        ? Icons.lock_open_rounded
                                        : Icons.lock_rounded,
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
          : NavigationBar(
              selectedIndex: AppSection.values.indexOf(section),
              onDestinationSelected: (index) {
                _goToSection(context, ref, AppSection.values[index]);
              },
              destinations: [
                NavigationDestination(
                  key: AppShell.notesNavKey,
                  icon: const Icon(Icons.notes_outlined),
                  selectedIcon: const Icon(Icons.notes_rounded),
                  label: strings.notes,
                ),
                NavigationDestination(
                  key: AppShell.calendarNavKey,
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month_rounded),
                  label: strings.calendar,
                ),
                NavigationDestination(
                  key: AppShell.insightsNavKey,
                  icon: const Icon(Icons.insert_chart_outlined_rounded),
                  selectedIcon: const Icon(Icons.insert_chart_rounded),
                  label: strings.insights,
                ),
                NavigationDestination(
                  key: AppShell.settingsNavKey,
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings_rounded),
                  label: strings.settings,
                ),
              ],
            ),
      floatingActionButton:
          !noteOverlayOpen &&
              (section == AppSection.notes || section == AppSection.calendar)
          ? FloatingActionButton.small(
              key: AppShell.addNoteKey,
              onPressed: () => showNoteEditorSheet(context, ref),
              tooltip: context.strings.addNote,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _goToSection(BuildContext context, WidgetRef ref, AppSection section) {
    final currentSection = _sectionForLocation(
      GoRouterState.of(context).uri.path,
    );
    if (currentSection != section) {
      _dismissOpenSheet(context);
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
      _dismissOpenSheet(context);
    });
  }

  void _dismissOpenSheet(BuildContext context) {
    if (_noteOverlaySheetDepth.value <= 0) {
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
    if (location.startsWith('/settings')) {
      return AppSection.settings;
    }
    return AppSection.notes;
  }
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
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'HiMemo',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
    final query = ref.watch(searchQueryProvider).trim();
    final selectedNoteId = ref.watch(selectedNoteIdProvider);

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
        query: query,
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
                query: query,
                onAddNote: () => showNoteEditorSheet(context, ref),
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
    _pushNoteOverlaySheet();
    try {
      await showModalBottomSheet<void>(
        context: hostContext,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.86,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
            ),
          );
        },
      );
    } finally {
      _popNoteOverlaySheet();
    }
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
      showDragHandle: true,
      builder: (context) {
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
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: FractionallySizedBox(
                  heightFactor: 0.9,
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
                      const SizedBox(height: 8),
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

class _InsightBarChart extends StatelessWidget {
  const _InsightBarChart({required this.buckets, required this.valueSuffix});

  final List<_InsightBucket> buckets;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
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
                          '${bucket.value}$valueSuffix',
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
    final createdAt = note.createdAt;
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

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const appLockToggleKey = Key('app-lock-toggle');
  static const appLockRelockImmediateKey = Key('app-lock-relock-immediate');
  static const appLockRelock30SecondsKey = Key('app-lock-relock-30-seconds');
  static const appLockRelock2MinutesKey = Key('app-lock-relock-2-minutes');
  static const appLockRelock10MinutesKey = Key('app-lock-relock-10-minutes');
  static const privateVaultLockOnAppLockKey = Key(
    'private-vault-lock-on-app-lock',
  );
  static const appLockAuthenticateKey = Key('app-lock-authenticate');
  static const appLockLockNowKey = Key('app-lock-lock-now');
  static const lightThemeKey = Key('theme-light-option');
  static const systemThemeKey = Key('theme-system-option');
  static const darkThemeKey = Key('theme-dark-option');
  static const localeDropdownKey = Key('locale-dropdown');
  static const fontDropdownKey = Key('font-dropdown');
  static const localeSystemKey = Key('locale-system-option');
  static const createDemoNotesKey = Key('create-demo-notes-button');
  static const deleteDemoNotesKey = Key('delete-demo-notes-button');
  static const localeJapaneseKey = Key('locale-japanese-option');
  static const localeEnglishKey = Key('locale-english-option');
  static const localeChineseKey = Key('locale-chinese-option');
  static const localeKoreanKey = Key('locale-korean-option');
  static const localeSpanishKey = Key('locale-spanish-option');
  static const localeGermanKey = Key('locale-german-option');
  static const memoQuickDefaultKey = Key('memo-default-quick-option');
  static const memoRichDefaultKey = Key('memo-default-rich-option');
  static const memoStandardListKey = Key('memo-standard-list-option');
  static const memoCompactListKey = Key('memo-compact-list-option');
  static const memoAutoLocationKey = Key('memo-auto-location-toggle');
  static const konjyoColorThemeKey = Key('color-theme-konjyo-option');
  static const moegiColorThemeKey = Key('color-theme-moegi-option');
  static const yamabukiColorThemeKey = Key('color-theme-yamabuki-option');
  static const syncOffKey = Key('sync-off-option');
  static const syncICloudKey = Key('sync-icloud-option');
  static const syncGoogleDriveKey = Key('sync-google-drive-option');
  static const syncConnectKey = Key('sync-connect-button');
  static const syncDisconnectKey = Key('sync-disconnect-button');
  static const syncRefreshRemoteKey = Key('sync-refresh-remote-button');
  static const syncUploadBundleKey = Key('sync-upload-bundle-button');
  static const syncDownloadBundleKey = Key('sync-download-bundle-button');
  static const syncApplyBundleKey = Key('sync-apply-bundle-button');
  static const privateVaultSetKey = Key('private-vault-set-key');
  static const privateVaultUnlockKey = Key('private-vault-unlock-key');
  static const privateVaultLockKey = Key('private-vault-lock-key');
  static const privateVaultResetKey = Key('private-vault-reset-key');
  static const privateProfileAddKey = Key('private-profile-add-key');
  static const privateProfileAdminModeKey = Key(
    'private-profile-admin-mode-key',
  );
  static const privateProfileNameInputKey = Key('private-profile-name-input');
  static const privateProfilePasswordInputKey = Key(
    'private-profile-password-input',
  );
  static const privateProfileConfirmInputKey = Key(
    'private-profile-confirm-input',
  );
  static const privateProfileSubmitKey = Key('private-profile-submit');
  static const privateProfileExitAdminModeKey = Key(
    'private-profile-exit-admin-mode',
  );

  Future<void> _switchIdentity(WidgetRef ref, String identityId) async {
    await ref.read(activeIdentityProvider.notifier).switchTo(identityId);
    if (identityId != 'private') {
      ref.read(privateVaultSessionControllerProvider.notifier).lock();
    }
  }

  Future<void> _showSetCoverKeyDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secret = await _showSecretSetupDialog(
      context,
      title: strings.setAlternateProfilePassword,
      label: strings.text('home.alternate.profile.password'),
      confirmLabel: strings.text('home.confirm.alternate.profile.password'),
      helperText: strings.text(
        'home.use.this.password.to.switch.to.a.different.everyday.prof',
      ),
    );
    if (secret == null) {
      return;
    }
    await ref
        .read(coverModeSecretControllerProvider.notifier)
        .configure(secret);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(strings.text('home.alternate.profile.password.saved')),
        ),
      );
    }
  }

  Future<void> _confirmResetCoverKey(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.resetAlternateProfilePassword),
        content: Text(
          strings.text(
            'home.this.removes.the.configured.password.for.the.alternate.p',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text('home.reset')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(coverModeSecretControllerProvider.notifier).clear();
    if (ref.read(activeIdentityProvider) == 'cover') {
      await _switchIdentity(ref, 'daily');
    }
  }

  Future<void> _showSpecialAccessKeyDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secret = await _showSingleSecretPrompt(
      context,
      title: strings.text('home.enter.special.access.key'),
      label: strings.accessKey,
      helperText: strings.specialAccessKeyHelp,
      actionLabel: strings.unlockMode,
    );
    if (secret == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (await ref
        .read(privateVaultSecretControllerProvider.notifier)
        .verify(secret)) {
      await _switchIdentity(ref, 'private');
      messenger.showSnackBar(
        SnackBar(showCloseIcon: true, content: Text(strings.privateModeActive)),
      );
      return;
    }
    if (await ref
        .read(coverModeSecretControllerProvider.notifier)
        .verify(secret)) {
      await _switchIdentity(ref, 'cover');
      messenger.showSnackBar(
        SnackBar(showCloseIcon: true, content: Text(strings.coverModeActive)),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text(strings.accessKeyNoMatch)),
    );
  }

  Future<void> _showAddPrivateProfileDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.text('home.add.private.profile')),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: privateProfileNameInputKey,
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: strings.text('home.profile.name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: privateProfilePasswordInputKey,
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: strings.text('home.profile.password.2'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.isEmpty)
                      ? (strings.text('home.enter.a.password.2'))
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: privateProfileConfirmInputKey,
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: strings.text('home.confirm.password'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value != passwordController.text) {
                      return strings.text('home.passwords.do.not.match');
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: privateProfileSubmitKey,
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: Text(strings.text('home.add')),
          ),
        ],
      ),
    );
    if (submitted != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
        passwordController.dispose();
        confirmController.dispose();
      });
      return;
    }
    final profileName = nameController.text;
    final profilePassword = passwordController.text;
    final error = await ref
        .read(privateMemoProfilesControllerProvider.notifier)
        .addProfile(name: profileName, password: profilePassword);
    if (error == null) {
      await ref
          .read(privateProfileUnlockControllerProvider.notifier)
          .unlockWithPassword(profilePassword);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      passwordController.dispose();
      confirmController.dispose();
    });
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

  Future<void> _enterAdminMode(BuildContext context, WidgetRef ref) async {
    final strings = context.strings;
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.text(
              'home.admin.mode.is.not.available.in.this.environment',
            ),
          ),
        ),
      );
      return;
    }
    final authenticated = await ref
        .read(deviceAuthControllerProvider.notifier)
        .authenticate(reason: 'Enter admin mode to manage private profiles');
    if (!authenticated || !context.mounted) {
      return;
    }
    ref.read(adminModeSessionControllerProvider.notifier).unlock();
    ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.text(
            'home.admin.mode.unlocked.profile.names.and.vault.ids.remain.h',
          ),
        ),
      ),
    );
  }

  Future<void> _showChangeCurrentProfilePasswordDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final unlockedVaultId = ref.read(unlockedPrivateProfileVaultIdProvider);
    if (unlockedVaultId == null ||
        !unlockedVaultId.startsWith(customPrivateVaultPrefix)) {
      return;
    }
    final profileId = unlockedVaultId.substring(
      customPrivateVaultPrefix.length,
    );
    final password = await _showSecretSetupDialog(
      context,
      title: strings.text('home.change.current.profile.password'),
      label: strings.text('home.new.password'),
      confirmLabel: strings.text('home.confirm.new.password'),
      helperText: strings.text(
        'home.update.the.password.used.to.unlock.this.profile',
      ),
    );
    if (password == null) {
      return;
    }
    await ref
        .read(privateMemoProfilesControllerProvider.notifier)
        .updateProfilePassword(id: profileId, password: password);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(strings.text('home.profile.password.updated')),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final activeIdentity = ref.watch(activeIdentityProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final activeColorTheme = ref.watch(effectiveAppColorThemeProvider);
    final activeColorThemeScope = ref.watch(activeColorThemeScopeProvider);
    final colorThemeSettingsScope = ref.watch(colorThemeSettingsScopeProvider);
    final defaultColorTheme = ref.watch(appColorThemeControllerProvider);
    final profileColorThemes = ref.watch(profileColorThemeControllerProvider);
    final fontFamily = ref.watch(appFontFamilyControllerProvider);
    final localeSetting = ref.watch(appLocaleControllerProvider);
    final appLockEnabled = ref.watch(appLockSettingsControllerProvider);
    final appLockRelockDelay = ref.watch(appLockRelockDelayControllerProvider);
    final appSessionUnlocked = ref.watch(appSessionUnlockControllerProvider);
    final lastNoteEditorSettings = ref.watch(
      lastNoteEditorSettingsControllerProvider,
    );
    final notesListDensity = ref.watch(notesListDensityControllerProvider);
    final widgetQuickCaptureEnabled = ref.watch(
      widgetQuickCaptureSettingsControllerProvider,
    );
    final deviceAuthState = ref.watch(deviceAuthControllerProvider);
    final pinLockState = ref.watch(appPinLockControllerProvider);
    final privateVaultConfigured = ref.watch(
      privateVaultSecretControllerProvider,
    );
    final coverModeConfigured = ref.watch(coverModeSecretControllerProvider);
    final privateVaultUnlocked = ref.watch(
      privateVaultSessionControllerProvider,
    );
    final adminMode = ref.watch(adminModeSessionControllerProvider);
    final unlockedPrivateProfileVaultId = ref.watch(
      unlockedPrivateProfileVaultIdProvider,
    );
    final activePrivateProfileLabel = ref.watch(
      activePrivateProfileLabelProvider,
    );
    final privateVaultLockOnAppLock = ref.watch(
      privateVaultLockOnAppLockControllerProvider,
    );
    final syncProvider = ref.watch(syncProviderControllerProvider);
    final syncAuthState = ref.watch(selectedSyncAuthStateProvider);
    final syncQueueSummary = ref.watch(syncQueueSummaryProvider);
    final syncTransferState = ref.watch(syncTransferControllerProvider);
    final syncBundleFingerprint = ref.watch(syncBundleFingerprintProvider);
    final syncBundleState = ref.watch(syncBundleStateProvider);
    final syncConflictWarning = ref.watch(syncConflictWarningProvider);
    final inAppUpdateState = ref.watch(inAppUpdateControllerProvider);
    final packageInfo = ref.watch(packageInfoProvider);
    final storageUsageSummary = ref.watch(storageUsageSummaryProvider);
    const showLegacyAccessSettings = bool.fromEnvironment(
      'HIMEMO_SHOW_LEGACY_ACCESS_SETTINGS',
    );
    const showLegacyPrivateVaultSettings = bool.fromEnvironment(
      'HIMEMO_SHOW_LEGACY_PRIVATE_VAULT_SETTINGS',
    );
    final flavorName =
        FlavorConfig.instance.variables['flavor'] as String? ?? 'development';
    final showFlavorInfo = flavorName != 'production';
    final displayName =
        FlavorConfig.instance.variables['displayName'] as String? ?? 'HiMemo';
    final visibleStorageVaultIds = {
      'everyday',
      if (unlockedPrivateProfileVaultId != null) unlockedPrivateProfileVaultId,
    };
    final currentNotes = ref.watch(notesControllerProvider);
    final noteCount = currentNotes
        .where(
          (note) =>
              note.deletedAt == null &&
              visibleStorageVaultIds.contains(note.vaultId),
        )
        .length;
    final demoNoteCount = currentNotes
        .where(
          (note) =>
              note.deletedAt == null &&
              (note.deviceId == 'seeded-device' || note.id.startsWith('seed-')),
        )
        .length;
    final currentModeLabel = activeIdentity == 'daily'
        ? (strings.text('home.normal.memo.mode'))
        : ref.watch(activeIdentityDataProvider).name;
    final lockSummary = !appLockEnabled
        ? (strings.text(
            'home.off.turning.this.on.asks.for.a.password.or.device.authen',
          ))
        : (appSessionUnlocked
              ? (strings.text('home.on.this.session.is.unlocked'))
              : (strings.text('home.on.this.session.is.locked')));
    final syncSummary = syncProvider == SyncProvider.off
        ? (strings.text('home.device.only.storage'))
        : _syncAuthSummary(context, syncProvider, syncAuthState);
    final memoEditorModeLabel =
        lastNoteEditorSettings.mode == NoteEditorMode.quick
        ? strings.quickMemo
        : strings.richMemo;
    final memoListDensityLabel = notesListDensity == NotesListDensity.compact
        ? strings.text('home.compact.list')
        : strings.text('home.standard.list');
    final memoLocationLabel = lastNoteEditorSettings.captureLocation
        ? strings.text('home.enabled')
        : strings.text('home.disabled');
    final memoSettingsSummary = strings.localized(
      en: '$memoEditorModeLabel / $memoListDensityLabel / Location: $memoLocationLabel',
      ja: '$memoEditorModeLabel / $memoListDensityLabel / 現在地: $memoLocationLabel',
      zh: '$memoEditorModeLabel / $memoListDensityLabel / 位置：$memoLocationLabel',
      ko: '$memoEditorModeLabel / $memoListDensityLabel / 위치: $memoLocationLabel',
      es: '$memoEditorModeLabel / $memoListDensityLabel / Ubicación: $memoLocationLabel',
      de: '$memoEditorModeLabel / $memoListDensityLabel / Standort: $memoLocationLabel',
    );
    final effectiveFontFamily = _availableFontFamilies.contains(fontFamily)
        ? fontFamily
        : AppFontFamily.system;
    final appearanceSummary = strings.appearanceSummary(
      language: _localeSettingLabel(context, localeSetting),
      theme: _themeModeLabel(context, themeMode),
      font: _fontFamilyLabel(context, effectiveFontFamily),
      color: _colorThemeLabel(context, activeColorTheme),
    );
    final colorThemeTargets = [
      _ColorThemeScopeOption(
        scope: defaultColorThemeScope,
        label: strings.text('home.normal.memo.mode'),
      ),
      if (unlockedPrivateProfileVaultId != null &&
          activeColorThemeScope != defaultColorThemeScope)
        _ColorThemeScopeOption(
          scope: activeColorThemeScope,
          label:
              activePrivateProfileLabel ?? strings.text('home.private.profile'),
        ),
    ];
    final resolvedColorThemeScope =
        colorThemeTargets.any(
          (target) => target.scope == colorThemeSettingsScope,
        )
        ? colorThemeSettingsScope
        : (colorThemeTargets.any(
                (target) => target.scope == activeColorThemeScope,
              )
              ? activeColorThemeScope
              : defaultColorThemeScope);
    final colorThemeTargetLabel = colorThemeTargets
        .firstWhere(
          (target) => target.scope == resolvedColorThemeScope,
          orElse: () => colorThemeTargets.first,
        )
        .label;
    final selectedColorTheme = resolvedColorThemeScope == defaultColorThemeScope
        ? defaultColorTheme
        : (profileColorThemes[resolvedColorThemeScope] ?? defaultColorTheme);
    final aboutVersion = packageInfo.when(
      data: (info) => info.displayVersion,
      loading: strings.readingVersion,
      error: (_, _) => '1.0.0 (1)',
    );
    final appUpdatesSupported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final appUpdatesDescription = appUpdatesSupported
        ? strings.appUpdatesDesc
        : _appUpdatesUnavailableDescription(strings);
    final inAppUpdateSummary = switch (inAppUpdateState.stage) {
      InAppUpdateStage.checking => strings.updateStatusChecking,
      InAppUpdateStage.ready => strings.updateStatusAvailable,
      InAppUpdateStage.completed =>
        inAppUpdateState.status?.updateAvailable == true
            ? strings.updateStatusStarted
            : strings.updateStatusUpToDate,
      InAppUpdateStage.unsupported => appUpdatesDescription,
      InAppUpdateStage.error =>
        inAppUpdateState.message ?? strings.updateStatusUnsupported,
      _ =>
        inAppUpdateState.status?.updateAvailable == true
            ? strings.updateStatusAvailable
            : appUpdatesDescription,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsOverviewCard(
          items: [
            _SettingsOverviewItem(
              label: strings.text('home.mode'),
              value: currentModeLabel,
              assetPath: 'assets/settings/access.svg',
            ),
            _SettingsOverviewItem(
              label: strings.text('home.unlock'),
              value: appLockEnabled
                  ? (strings.text('home.enabled'))
                  : (strings.text('home.disabled')),
              assetPath: 'assets/settings/security.svg',
            ),
            _SettingsOverviewItem(
              label: strings.syncLabel,
              value: syncProvider == SyncProvider.off
                  ? (strings.text('home.off'))
                  : (strings.text('home.configured')),
              assetPath: 'assets/settings/sync.svg',
            ),
            _SettingsOverviewItem(
              label: strings.text('home.theme'),
              value: _themeModeLabel(context, themeMode),
              assetPath: 'assets/settings/appearance.svg',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildAppearanceSettingsGroup(
          context: context,
          ref: ref,
          strings: strings,
          localeSetting: localeSetting,
          themeMode: themeMode,
          fontFamily: fontFamily,
          colorTheme: selectedColorTheme,
          colorThemeScope: resolvedColorThemeScope,
          colorThemeTargets: colorThemeTargets,
          colorThemeTargetLabel: colorThemeTargetLabel,
          appearanceSummary: appearanceSummary,
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.localized(
            en: 'Memo settings',
            ja: 'メモ設定',
            zh: '备忘录设置',
            ko: '메모 설정',
            es: 'Ajustes de notas',
            de: 'Notiz-Einstellungen',
          ),
          summary: memoSettingsSummary,
          assetPath: 'assets/settings/appearance.svg',
          semanticLabel: 'settings-memo',
          children: [
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'Default input',
                ja: '入力の既定',
                zh: '默认输入',
                ko: '기본 입력',
                es: 'Entrada predeterminada',
                de: 'Standardeingabe',
              ),
            ),
            _ThemeOptionTile(
              tileKey: memoQuickDefaultKey,
              title: strings.quickMemo,
              subtitle: strings.localized(
                en: 'Start new notes with the simple first-line memo editor.',
                ja: '新規メモを1行目タイトルのシンプル入力で開始します。',
                zh: '新建备忘录时使用首行作为标题的简单输入。',
                ko: '새 메모를 첫 줄 제목 방식의 간단 입력으로 시작합니다.',
                es: 'Inicia las notas nuevas con el editor simple de primera línea.',
                de: 'Neue Notizen starten mit dem einfachen Editor, bei dem die erste Zeile der Titel ist.',
              ),
              selected: lastNoteEditorSettings.mode == NoteEditorMode.quick,
              onTap: () => ref
                  .read(lastNoteEditorSettingsControllerProvider.notifier)
                  .remember(
                    mode: NoteEditorMode.quick,
                    vaultId: lastNoteEditorSettings.vaultId,
                    captureLocation: lastNoteEditorSettings.captureLocation,
                  ),
            ),
            _ThemeOptionTile(
              tileKey: memoRichDefaultKey,
              title: strings.richMemo,
              subtitle: strings.localized(
                en: 'Start new notes with block-style text and media editing.',
                ja: '新規メモを本文ブロックとメディアを扱える入力で開始します。',
                zh: '新建备忘录时使用支持文本块和媒体的编辑器。',
                ko: '새 메모를 텍스트 블록과 미디어 편집으로 시작합니다.',
                es: 'Inicia las notas nuevas con edición por bloques de texto y medios.',
                de: 'Neue Notizen starten mit blockbasierter Text- und Medienbearbeitung.',
              ),
              selected: lastNoteEditorSettings.mode == NoteEditorMode.rich,
              onTap: () => ref
                  .read(lastNoteEditorSettingsControllerProvider.notifier)
                  .remember(
                    mode: NoteEditorMode.rich,
                    vaultId: lastNoteEditorSettings.vaultId,
                    captureLocation: lastNoteEditorSettings.captureLocation,
                  ),
            ),
            const SizedBox(height: 8),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'List display',
                ja: '一覧表示',
                zh: '列表显示',
                ko: '목록 표시',
                es: 'Vista de lista',
                de: 'Listenansicht',
              ),
            ),
            _ThemeOptionTile(
              tileKey: memoStandardListKey,
              title: strings.text('home.standard.list'),
              subtitle: strings.localized(
                en: 'Show two-line previews and more context in the note list.',
                ja: 'ノート一覧に2行プレビューを表示し、内容を把握しやすくします。',
                zh: '在列表中显示两行预览，便于查看内容。',
                ko: '목록에 두 줄 미리보기를 표시해 내용을 더 쉽게 확인합니다.',
                es: 'Muestra vistas previas de dos líneas y más contexto en la lista.',
                de: 'Zeigt zweizeilige Vorschauen und mehr Kontext in der Notizliste.',
              ),
              selected: notesListDensity == NotesListDensity.standard,
              onTap: () => ref
                  .read(notesListDensityControllerProvider.notifier)
                  .setDensity(NotesListDensity.standard),
            ),
            _ThemeOptionTile(
              tileKey: memoCompactListKey,
              title: strings.text('home.compact.list'),
              subtitle: strings.localized(
                en: 'Fit more notes on screen with a denser one-line list.',
                ja: '1行中心の密な一覧にして、画面に多くのメモを表示します。',
                zh: '使用更紧凑的单行列表，在屏幕上显示更多备忘录。',
                ko: '한 줄 중심의 촘촘한 목록으로 더 많은 메모를 표시합니다.',
                es: 'Muestra más notas en pantalla con una lista densa de una línea.',
                de: 'Zeigt mehr Notizen auf dem Bildschirm mit einer dichteren einzeiligen Liste.',
              ),
              selected: notesListDensity == NotesListDensity.compact,
              onTap: () => ref
                  .read(notesListDensityControllerProvider.notifier)
                  .setDensity(NotesListDensity.compact),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: memoAutoLocationKey,
              value: lastNoteEditorSettings.captureLocation,
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.localized(
                  en: 'Add current location to new notes',
                  ja: '新規メモに現在地を自動付与',
                  zh: '为新建备忘录自动添加当前位置',
                  ko: '새 메모에 현재 위치 자동 추가',
                  es: 'Añadir ubicación actual a notas nuevas',
                  de: 'Aktuellen Standort zu neuen Notizen hinzufügen',
                ),
              ),
              subtitle: Text(
                strings.localized(
                  en: 'When enabled, new notes try to capture location metadata when the editor opens.',
                  ja: 'オンにすると、新規メモ作成画面を開いたときに位置情報を取得します。',
                  zh: '开启后，打开新建编辑器时会尝试获取位置元数据。',
                  ko: '켜면 새 메모 편집기를 열 때 위치 메타데이터를 가져옵니다.',
                  es: 'Al activarlo, las notas nuevas intentan capturar metadatos de ubicación al abrir el editor.',
                  de: 'Wenn aktiviert, erfassen neue Notizen beim Öffnen des Editors Standortmetadaten.',
                ),
              ),
              onChanged: (enabled) => ref
                  .read(lastNoteEditorSettingsControllerProvider.notifier)
                  .setCaptureLocation(enabled),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.privateProfilesSettingsTitle,
          summary: adminMode
              ? strings.privateProfilesSettingsAdminSummary
              : (activePrivateProfileLabel != null
                    ? strings.privateProfilesSettingsActiveSummary(
                        activePrivateProfileLabel,
                      )
                    : strings.privateProfilesSettingsDefaultSummary),
          assetPath: 'assets/settings/security.svg',
          children: [
            Text(
              strings.privateProfilesSettingsBody,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  key: privateProfileAddKey,
                  onPressed: () => _showAddPrivateProfileDialog(context, ref),
                  child: Text(strings.addPrivateProfile),
                ),
                FilledButton.tonal(
                  key: privateProfileAdminModeKey,
                  onPressed: adminMode
                      ? null
                      : () => _enterAdminMode(context, ref),
                  child: Text(
                    adminMode
                        ? strings.adminModeActiveLabel
                        : strings.enterAdminModeLabel,
                  ),
                ),
                if (adminMode)
                  OutlinedButton(
                    key: privateProfileExitAdminModeKey,
                    onPressed: () => ref
                        .read(adminModeSessionControllerProvider.notifier)
                        .lock(),
                    child: Text(strings.exitAdminModeLabel),
                  ),
                if (unlockedPrivateProfileVaultId != null &&
                    unlockedPrivateProfileVaultId.startsWith(
                      customPrivateVaultPrefix,
                    ))
                  OutlinedButton(
                    onPressed: () =>
                        _showChangeCurrentProfilePasswordDialog(context, ref),
                    child: Text(
                      strings.text('home.change.current.profile.password.2'),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (kDebugMode && showLegacyAccessSettings)
          _SettingsGroup(
            title: strings.text('home.access.modes'),
            summary: strings.accessModeSummary(currentModeLabel),
            assetPath: 'assets/settings/access.svg',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.text('home.current.mode')),
                subtitle: Text(
                  activeIdentity == 'daily'
                      ? (strings.text('home.normal.memo.mode'))
                      : ref.watch(activeIdentityDataProvider).name,
                ),
              ),
              Text(
                strings.text(
                  'home.the.app.stays.in.normal.memo.mode.by.default.enter.a.spe',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 12),
              if (syncProvider != SyncProvider.iCloud)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () =>
                          _showSpecialAccessKeyDialog(context, ref),
                      child: Text(
                        strings.text('home.enter.special.access.key'),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: activeIdentity == 'daily'
                          ? null
                          : () => _switchIdentity(ref, 'daily'),
                      child: Text(strings.text('home.return.to.normal.mode')),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _showSetCoverKeyDialog(context, ref),
                    child: Text(
                      coverModeConfigured
                          ? strings.changeAlternateProfilePassword
                          : strings.setAlternateProfilePassword,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: coverModeConfigured
                        ? () => _confirmResetCoverKey(context, ref)
                        : null,
                    child: Text(strings.resetAlternateProfilePassword),
                  ),
                ],
              ),
            ],
          ),
        if (kDebugMode && showLegacyAccessSettings) const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.app.security'),
          summary: lockSummary,
          assetPath: 'assets/settings/security.svg',
          children: [
            SwitchListTile.adaptive(
              key: appLockToggleKey,
              value: appLockEnabled,
              contentPadding: EdgeInsets.zero,
              title: kIsWeb
                  ? Text(strings.text('home.require.pin.on.launch'))
                  : Text(strings.text('home.require.device.auth.on.launch')),
              subtitle: Text(
                kIsWeb
                    ? strings.webPinProtectionSummary(
                        strings.pinLockSummary(
                          isConfigured: pinLockState.isConfigured,
                          lastError: pinLockState.lastError,
                        ),
                      )
                    : (deviceAuthState.isAvailable
                          ? strings.deviceAuthProtectionSummary(
                              deviceAuthState.summary,
                            )
                          : deviceAuthState.summary),
              ),
              onChanged: (value) async {
                if (!value) {
                  await ref
                      .read(appLockSettingsControllerProvider.notifier)
                      .setEnabled(false);
                  ref
                      .read(appSessionUnlockControllerProvider.notifier)
                      .unlock();
                  return;
                }

                if (kIsWeb) {
                  if (!pinLockState.isConfigured) {
                    final configured = await _showPinSetupDialog(
                      context,
                      title: strings.text('home.set.unlock.pin'),
                      confirmLabel: strings.text('home.save.pin'),
                    );
                    if (configured == null) {
                      return;
                    }
                    await ref
                        .read(appPinLockControllerProvider.notifier)
                        .configure(configured);
                  }
                } else {
                  final authenticated = await ref
                      .read(deviceAuthControllerProvider.notifier)
                      .authenticate(reason: strings.enableDeviceAuthReason);
                  if (!authenticated) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          showCloseIcon: true,
                          content: Text(
                            strings.text(
                              'home.device.authentication.was.not.completed.so.launch.protec',
                            ),
                          ),
                        ),
                      );
                    }
                    return;
                  }
                }

                await ref
                    .read(appLockSettingsControllerProvider.notifier)
                    .setEnabled(true);
              },
            ),
            if (syncProvider == SyncProvider.iCloud)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  strings.text(
                    'home.when.icloud.sync.is.selected.this.key.is.shared.automati',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.session.status')),
              subtitle: Text(
                appSessionUnlocked
                    ? (strings.text('home.this.session.is.currently.unlocked'))
                    : (kIsWeb
                          ? (strings.text(
                              'home.this.browser.stays.locked.until.the.correct.pin.is.enter',
                            ))
                          : (strings.text(
                              'home.this.session.stays.locked.until.device.authentication.su',
                            ))),
              ),
            ),
            if (kIsWeb) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () async {
                        final pin = await _showPinSetupDialog(
                          context,
                          title: pinLockState.isConfigured
                              ? (strings.text('home.change.unlock.pin'))
                              : (strings.text('home.set.unlock.pin.2')),
                          confirmLabel: pinLockState.isConfigured
                              ? (strings.text('home.update.pin'))
                              : (strings.text('home.save.pin')),
                        );
                        if (pin == null) {
                          return;
                        }
                        await ref
                            .read(appPinLockControllerProvider.notifier)
                            .configure(pin);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              showCloseIcon: true,
                              content: Text(
                                pinLockState.isConfigured
                                    ? (strings.text('home.unlock.pin.updated'))
                                    : (strings.text(
                                        'home.unlock.pin.configured',
                                      )),
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        pinLockState.isConfigured
                            ? (strings.text('home.change.pin'))
                            : (strings.text('home.set.pin')),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: pinLockState.isConfigured
                          ? () async {
                              final shouldRemove = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    strings.text('home.remove.unlock.pin'),
                                  ),
                                  content: Text(
                                    strings.text(
                                      'home.remove.the.web.unlock.pin.for.this.browser.and.turn.off',
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
                                      child: Text(strings.text('home.remove')),
                                    ),
                                  ],
                                ),
                              );
                              if (shouldRemove != true) {
                                return;
                              }
                              await ref
                                  .read(appPinLockControllerProvider.notifier)
                                  .clear();
                              await ref
                                  .read(
                                    appLockSettingsControllerProvider.notifier,
                                  )
                                  .setEnabled(false);
                            }
                          : null,
                      child: Text(strings.text('home.remove.pin')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.text(
                  'home.web.pin.is.a.browser.level.access.gate.it.does.not.repla',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (showLegacyAccessSettings) ...[
              SwitchListTile.adaptive(
                value: widgetQuickCaptureEnabled,
                contentPadding: EdgeInsets.zero,
                title: Text(strings.homeWidgetQuickCapture),
                subtitle: Text(
                  !kIsWeb &&
                          (defaultTargetPlatform == TargetPlatform.android ||
                              defaultTargetPlatform == TargetPlatform.iOS)
                      ? strings.homeWidgetQuickCaptureDesc
                      : strings.homeWidgetQuickCaptureMobileOnly,
                ),
                onChanged:
                    !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS)
                    ? (value) => ref
                          .read(
                            widgetQuickCaptureSettingsControllerProvider
                                .notifier,
                          )
                          .setEnabled(value)
                    : null,
              ),
              Text(
                strings.text(
                  'home.quick.widget.capture.only.writes.plain.text.into.notes.i',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Text(strings.text('home.re.lock.after.app.leaves.the.foreground')),
            const SizedBox(height: 8),
            _ThemeOptionTile(
              tileKey: appLockRelockImmediateKey,
              title: strings.text('home.immediately'),
              subtitle: strings.text(
                'home.lock.the.app.as.soon.as.it.moves.to.the.background',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.immediate,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.immediate),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock30SecondsKey,
              title: strings.text('home.after.30.seconds'),
              subtitle: strings.text(
                'home.allow.quick.app.switching.without.immediate.re.auth',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.seconds30,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.seconds30),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock2MinutesKey,
              title: strings.text('home.after.2.minutes'),
              subtitle: strings.text(
                'home.useful.when.capturing.photos.or.audio.between.notes',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.minutes2,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes2),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock10MinutesKey,
              title: strings.text('home.after.10.minutes'),
              subtitle: strings.text(
                'home.keep.the.app.open.during.longer.editing.sessions',
              ),
              selected: appLockRelockDelay == AppLockRelockDelay.minutes10,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes10),
            ),
            if (showLegacyPrivateVaultSettings)
              SwitchListTile.adaptive(
                key: privateVaultLockOnAppLockKey,
                value: privateVaultLockOnAppLock,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  strings.text('home.lock.legacy.private.area.when.app.locks'),
                ),
                subtitle: Text(
                  strings.text(
                    'home.normally.this.locks.whenever.the.app.locks',
                  ),
                ),
                onChanged: (value) => ref
                    .read(privateVaultLockOnAppLockControllerProvider.notifier)
                    .setEnabled(value),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    key: appLockAuthenticateKey,
                    onPressed: kIsWeb
                        ? null
                        : deviceAuthState.isAvailable
                        ? () => ref
                              .read(deviceAuthControllerProvider.notifier)
                              .authenticate(
                                reason: strings.unlockWithDeviceAuthReason,
                              )
                        : null,
                    child: kIsWeb
                        ? Text(strings.text('home.pin.unlock.on.lock.screen'))
                        : Text(strings.text('home.authenticate.now')),
                  ),
                  OutlinedButton(
                    key: appLockLockNowKey,
                    onPressed: appLockEnabled
                        ? () {
                            ref
                                .read(
                                  appSessionUnlockControllerProvider.notifier,
                                )
                                .lock();
                            ref
                                .read(
                                  privateVaultSessionControllerProvider
                                      .notifier,
                                )
                                .lock();
                            ref
                                .read(
                                  unlockedPrivateProfileVaultIdProvider
                                      .notifier,
                                )
                                .lock();
                            ref
                                .read(
                                  adminModeSessionControllerProvider.notifier,
                                )
                                .lock();
                          }
                        : null,
                    child: Text(strings.text('home.lock.session.now')),
                  ),
                  OutlinedButton(
                    onPressed: kIsWeb
                        ? null
                        : () => ref
                              .read(deviceAuthControllerProvider.notifier)
                              .refresh(),
                    child: kIsWeb
                        ? Text(strings.text('home.web.pin.active'))
                        : Text(strings.text('home.refresh.availability')),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.external.quick.memo'),
          summary: widgetQuickCaptureEnabled
              ? (strings.text(
                  'home.widget.quick.writes.are.allowed.while.the.app.is.locked',
                ))
              : (strings.text('home.widget.quick.writes.are.off')),
          assetPath: 'assets/settings/storage.svg',
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.text('home.allow.widget.writes.while.locked'),
              ),
              subtitle: Text(
                strings.text(
                  'home.only.the.submitted.text.is.saved.existing.notes.and.lock',
                ),
              ),
              value: widgetQuickCaptureEnabled,
              onChanged: (value) => ref
                  .read(widgetQuickCaptureSettingsControllerProvider.notifier)
                  .setEnabled(value),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.write.target')),
              subtitle: Text(strings.notes),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (kDebugMode && showLegacyPrivateVaultSettings)
          _SettingsGroup(
            title: strings.text('home.private.vault'),
            summary: privateVaultConfigured
                ? (privateVaultUnlocked
                      ? (strings.text('home.configured.and.currently.unlocked'))
                      : (strings.text('home.configured.and.locked')))
                : (strings.text('home.no.private.vault.key.has.been.set.yet')),
            assetPath: 'assets/settings/security.svg',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.text('home.status')),
                subtitle: Text(
                  privateVaultConfigured
                      ? (privateVaultUnlocked
                            ? (strings.text(
                                'home.configured.and.unlocked.for.this.session',
                              ))
                            : (strings.text(
                                'home.configured.and.locked.a.separate.key.is.required',
                              )))
                      : (strings.text(
                          'home.not.configured.yet.set.a.separate.key.for.the.private.va',
                        )),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!privateVaultConfigured)
                    FilledButton(
                      key: privateVaultSetKey,
                      onPressed: () => _showSetPrivateKeyDialog(context, ref),
                      child: Text(strings.text('home.set.private.key')),
                    ),
                  if (privateVaultConfigured && !privateVaultUnlocked)
                    FilledButton(
                      key: privateVaultUnlockKey,
                      onPressed: () =>
                          _showUnlockPrivateVaultDialog(context, ref),
                      child: Text(strings.text('home.unlock.private.vault')),
                    ),
                  if (privateVaultUnlocked)
                    FilledButton.tonal(
                      key: privateVaultLockKey,
                      onPressed: () => ref
                          .read(privateVaultSessionControllerProvider.notifier)
                          .lock(),
                      child: Text(strings.text('home.lock.private.vault')),
                    ),
                  if (privateVaultConfigured)
                    OutlinedButton(
                      key: privateVaultResetKey,
                      onPressed: () => _confirmResetPrivateKey(context, ref),
                      child: Text(strings.text('home.reset.private.key')),
                    ),
                ],
              ),
            ],
          ),
        if (kDebugMode && showLegacyPrivateVaultSettings)
          const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.backup.and.sync'),
          summary: syncSummary,
          assetPath: 'assets/settings/sync.svg',
          children: [
            if (syncConflictWarning != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                child: Text(
                  syncConflictWarning,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'Remote backup',
                ja: 'リモートバックアップ',
                zh: '远程备份',
                ko: '원격 백업',
                es: 'Copia remota',
                de: 'Remote-Backup',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.selected.target')),
              subtitle: Text(_syncSubtitle(context, syncProvider)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_syncStatusTitle(context, syncProvider)),
              subtitle: Text(
                _syncAuthSummary(context, syncProvider, syncAuthState),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: Text(strings.syncDetailsTitle),
                  subtitle: Text(strings.syncDetailsSummary),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.pending.sync.queue')),
                      subtitle: Text(
                        syncQueueSummary.when(
                          data: (summary) {
                            if (!summary.hasPendingChanges) {
                              return strings.text(
                                'home.no.pending.device.changes',
                              );
                            }
                            final timestamp = summary.lastQueuedAt;
                            final stampText = timestamp == null
                                ? (strings.text('home.queue.ready'))
                                : strings.lastQueuedAt(
                                    _formatDateTime(timestamp),
                                  );
                            return strings.pendingSyncSummary(
                              total: summary.totalChanges,
                              upserts: summary.upserts,
                              deletes: summary.deletes,
                              stamp: stampText,
                            );
                          },
                          loading: () =>
                              strings.text('home.checking.pending.changes'),
                          error: (_, _) => strings.text(
                            'home.unable.to.inspect.the.local.sync.queue',
                          ),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.remote.bundle')),
                      subtitle: Text(
                        _remoteBundleSummary(
                          strings,
                          syncProvider,
                          syncTransferState,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.text('home.cloud.recovery.key.fingerprint'),
                      ),
                      subtitle: Text(
                        syncBundleFingerprint.when(
                          data: (value) => value,
                          loading: () =>
                              strings.text('home.preparing.cloud.recovery.key'),
                          error: (_, _) => strings.text(
                            'home.unable.to.read.the.cloud.recovery.key.fingerprint',
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final backupCode = await ref
                                    .read(syncBundleKeyServiceProvider)
                                    .exportBackupCode();
                                await Clipboard.setData(
                                  ClipboardData(text: backupCode),
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text(
                                      strings.text(
                                        'home.cloud.recovery.key.copied.to.clipboard',
                                      ),
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text('$error'),
                                  ),
                                );
                              }
                            },
                            child: Text(strings.text('home.copy.recovery.key')),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              final backupCode = await _showSyncKeyImportDialog(
                                context,
                              );
                              if (!context.mounted || backupCode == null) {
                                return;
                              }
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final currentFingerprint = await ref
                                    .read(syncBundleKeyServiceProvider)
                                    .fingerprint();
                                if (!context.mounted) {
                                  return;
                                }
                                final incomingFingerprint = ref
                                    .read(syncBundleKeyServiceProvider)
                                    .previewBackupCodeFingerprint(backupCode);
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
                                    .importBackupCode(backupCode);
                                ref.invalidate(syncBundleFingerprintProvider);
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text(
                                      strings.recoveryKeyImported(fingerprint),
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text('$error'),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              strings.text('home.import.recovery.key'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.last.sync.activity')),
                      subtitle: Text(
                        syncBundleState.when(
                          data: (value) {
                            final entries = <String>[];
                            if (value.lastUploadedAt != null) {
                              entries.add(
                                strings.lastUploadAt(
                                  _formatDateTime(value.lastUploadedAt!),
                                ),
                              );
                            }
                            if (value.lastAppliedAt != null) {
                              entries.add(
                                strings.lastApplyAt(
                                  _formatDateTime(value.lastAppliedAt!),
                                ),
                              );
                            }
                            if (value.lastRemoteModifiedAt != null) {
                              entries.add(
                                strings.remoteBundleAt(
                                  _formatDateTime(value.lastRemoteModifiedAt!),
                                ),
                              );
                            }
                            if (entries.isEmpty) {
                              return strings.text(
                                'home.no.sync.activity.has.been.recorded.on.this.device.yet',
                              );
                            }
                            return entries.join('\n');
                          },
                          loading: () =>
                              strings.text('home.reading.sync.activity'),
                          error: (_, _) => strings.text(
                            'home.unable.to.read.local.sync.activity',
                          ),
                        ),
                      ),
                    ),
                    if (syncTransferState.localBundle != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.text('home.local.bundle.cache')),
                        subtitle: Text(
                          strings.localBundleStoredAt(
                            syncTransferState.localBundle!.reference,
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated)
                            OutlinedButton(
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final history = await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .listRemoteBundleHistory();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        if (history.isEmpty) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              showCloseIcon: true,
                                              content: Text(
                                                strings.text(
                                                  'home.no.remote.bundle.history.is.available',
                                                ),
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        await _showBundleHistoryDialog(
                                          context,
                                          history,
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.bundle.history')),
                            ),
                          if (syncProvider != SyncProvider.off &&
                              syncAuthState.isAuthenticated)
                            OutlinedButton(
                              key: syncDownloadBundleKey,
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .downloadLatestBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final message = ref
                                            .read(
                                              syncTransferControllerProvider,
                                            )
                                            .message;
                                        if (message != null &&
                                            message.isNotEmpty) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              showCloseIcon: true,
                                              content: Text(message),
                                            ),
                                          );
                                        }
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.download.bundle')),
                            ),
                          if (syncTransferState.localBundle != null)
                            OutlinedButton(
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final preview = await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .previewDownloadedBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        await _showBundlePreviewDialog(
                                          context,
                                          preview,
                                          confirmLabel: strings.close,
                                        );
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.review.bundle')),
                            ),
                          if (syncTransferState.localBundle != null)
                            OutlinedButton(
                              key: syncApplyBundleKey,
                              onPressed: syncTransferState.isBusy
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        final preview = await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .previewDownloadedBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final shouldApply =
                                            await _showBundlePreviewDialog(
                                              context,
                                              preview,
                                              confirmLabel: strings.text(
                                                'home.apply.bundle',
                                              ),
                                            ) ??
                                            false;
                                        if (!shouldApply) {
                                          return;
                                        }
                                        await ref
                                            .read(
                                              syncTransferControllerProvider
                                                  .notifier,
                                            )
                                            .applyDownloadedBundle();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        final message = ref
                                            .read(
                                              syncTransferControllerProvider,
                                            )
                                            .message;
                                        if (message != null &&
                                            message.isNotEmpty) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              showCloseIcon: true,
                                              content: Text(message),
                                            ),
                                          );
                                        }
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        messenger.showSnackBar(
                                          SnackBar(
                                            showCloseIcon: true,
                                            content: Text('$error'),
                                          ),
                                        );
                                      }
                                    },
                              child: Text(strings.text('home.apply.bundle')),
                            ),
                          OutlinedButton(
                            onPressed: () async {
                              final snapshot = await ref
                                  .read(syncEngineProvider)
                                  .prepareSnapshot(
                                    ref.read(notesControllerProvider),
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              await showDialog<void>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: Text(
                                      strings.text(
                                        'home.prepared.sync.snapshot',
                                      ),
                                    ),
                                    content: Text(
                                      strings.syncSnapshotSummary(
                                        notes: snapshot.notes.length,
                                        attachments:
                                            snapshot.attachments.length,
                                        pending: snapshot.summary.totalChanges,
                                        deviceId: snapshot.deviceId,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: Text(strings.close),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            child: Text(strings.text('home.inspect.snapshot')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _ThemeOptionTile(
              tileKey: syncOffKey,
              title: strings.text('home.off'),
              subtitle: strings.text('home.keep.data.on.this.device.only'),
              selected: syncProvider == SyncProvider.off,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.off),
            ),
            if (isICloudSyncSupported)
              _ThemeOptionTile(
                tileKey: syncICloudKey,
                title: 'iCloud',
                subtitle: strings.text(
                  'home.use.this.device.s.icloud.as.the.sync.target.no.himemo.lo',
                ),
                selected: syncProvider == SyncProvider.iCloud,
                onTap: () => ref
                    .read(syncProviderControllerProvider.notifier)
                    .setProvider(SyncProvider.iCloud),
              ),
            _ThemeOptionTile(
              tileKey: syncGoogleDriveKey,
              title: 'Google Drive',
              subtitle: strings.text('home.google.drive.app.data.sync.target'),
              selected: syncProvider == SyncProvider.googleDrive,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.googleDrive),
            ),
            if (kIsWeb &&
                syncProvider == SyncProvider.googleDrive &&
                !syncAuthState.isAuthenticated)
              const _GoogleDriveWebSignInPanel(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (syncProvider != SyncProvider.off &&
                    !(kIsWeb && syncProvider == SyncProvider.googleDrive))
                  FilledButton(
                    key: syncConnectKey,
                    onPressed: syncAuthState.stage == SyncAuthStage.busy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref
                                  .read(syncAuthControllerProvider.notifier)
                                  .connectSelected();
                              if (!context.mounted) {
                                return;
                              }
                              final message = ref
                                  .read(
                                    syncAuthControllerProvider,
                                  )[syncProvider]
                                  ?.message;
                              if (message != null && message.isNotEmpty) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    showCloseIcon: true,
                                    content: Text(message),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text('$error'),
                                ),
                              );
                            }
                          },
                    child: Text(
                      syncAuthState.isAuthenticated
                          ? _syncReconnectLabel(context, syncProvider)
                          : _syncConnectLabel(context, syncProvider),
                    ),
                  ),
                if (syncProvider != SyncProvider.off &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncDisconnectKey,
                    onPressed: () => ref
                        .read(syncAuthControllerProvider.notifier)
                        .disconnectSelected(),
                    child: Text(_syncDisconnectLabel(context, syncProvider)),
                  ),
                OutlinedButton(
                  key: syncRefreshRemoteKey,
                  onPressed: syncTransferState.isBusy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(syncTransferControllerProvider.notifier)
                                .refreshRemoteStatus();
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(syncTransferControllerProvider)
                                .message;
                            if (message == null || message.isEmpty) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(message),
                              ),
                            );
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text('$error'),
                              ),
                            );
                          }
                        },
                  child: Text(strings.text('home.refresh.remote')),
                ),
                if (syncProvider != SyncProvider.off &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncUploadBundleKey,
                    onPressed:
                        syncTransferState.isBusy || syncConflictWarning != null
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref
                                  .read(syncTransferControllerProvider.notifier)
                                  .uploadCurrentBundle();
                              if (!context.mounted) {
                                return;
                              }
                              final message = ref
                                  .read(syncTransferControllerProvider)
                                  .message;
                              if (message == null || message.isEmpty) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text(message),
                                ),
                              );
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text('$error'),
                                ),
                              );
                            }
                          },
                    child: Text(strings.text('home.upload.bundle')),
                  ),
                if (syncProvider != SyncProvider.off &&
                    syncAuthState.isAuthenticated &&
                    syncConflictWarning != null)
                  FilledButton.tonal(
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final shouldForce =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: Text(
                                        strings.text('home.force.upload.2'),
                                      ),
                                      content: Text(
                                        strings.text(
                                          'home.a.newer.remote.bundle.was.found.while.this.device.still',
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
                                          child: Text(
                                            strings.text('home.force.upload'),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ) ??
                                false;
                            if (!shouldForce) {
                              return;
                            }
                            await ref
                                .read(syncTransferControllerProvider.notifier)
                                .uploadCurrentBundle(force: true);
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(syncTransferControllerProvider)
                                .message;
                            if (message == null || message.isEmpty) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(message),
                              ),
                            );
                          },
                    child: Text(strings.text('home.force.upload')),
                  ),
              ],
            ),
            _SettingsSectionLabel(
              label: strings.localized(
                en: 'File backup',
                ja: 'ファイルバックアップ',
                zh: '文件备份',
                ko: '파일 백업',
                es: 'Copia en archivo',
                de: 'Datei-Backup',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: noteCount == 0
                        ? null
                        : () => _exportLocalArchive(context, ref),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      strings.localized(
                        en: 'File export',
                        ja: 'ファイルエクスポート',
                        zh: '文件导出',
                        ko: '파일 내보내기',
                        es: 'Exportar archivo',
                        de: 'Datei exportieren',
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _importLocalArchive(context, ref),
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      strings.localized(
                        en: 'File import',
                        ja: 'ファイルインポート',
                        zh: '文件导入',
                        ko: '파일 가져오기',
                        es: 'Importar archivo',
                        de: 'Datei importieren',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.text('home.storage'),
          summary: strings.noteCountSummary(noteCount),
          assetPath: 'assets/settings/storage.svg',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.text('home.saved.notes.on.this.device')),
              subtitle: Text(strings.entriesCount(noteCount)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.localized(
                  en: 'Storage size',
                  ja: '保存サイズ',
                  zh: '存储大小',
                  ko: '저장 크기',
                  es: 'Tamaño guardado',
                  de: 'Speichergröße',
                ),
              ),
              subtitle: Text(
                storageUsageSummary.when(
                  data: (summary) => strings.localized(
                    en: '${strings.byteCount(summary.totalBytes)} total / notes ${strings.byteCount(summary.notePayloadBytes)} / attachments ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    ja: '合計 ${strings.byteCount(summary.totalBytes)} / ノート ${strings.byteCount(summary.notePayloadBytes)} / 添付 ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    zh: '合计 ${strings.byteCount(summary.totalBytes)} / 笔记 ${strings.byteCount(summary.notePayloadBytes)} / 附件 ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    ko: '합계 ${strings.byteCount(summary.totalBytes)} / 노트 ${strings.byteCount(summary.notePayloadBytes)} / 첨부 ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    es: '${strings.byteCount(summary.totalBytes)} en total / notas ${strings.byteCount(summary.notePayloadBytes)} / adjuntos ${strings.byteCount(summary.attachmentPayloadBytes)}',
                    de: '${strings.byteCount(summary.totalBytes)} gesamt / Notizen ${strings.byteCount(summary.notePayloadBytes)} / Anhänge ${strings.byteCount(summary.attachmentPayloadBytes)}',
                  ),
                  loading: () => strings.localized(
                    en: 'Calculating...',
                    ja: '計算中...',
                    zh: '正在计算...',
                    ko: '계산 중...',
                    es: 'Calculando...',
                    de: 'Wird berechnet...',
                  ),
                  error: (_, _) => strings.localized(
                    en: 'Unable to calculate storage size.',
                    ja: '保存サイズを計算できませんでした。',
                    zh: '无法计算存储大小。',
                    ko: '저장 크기를 계산할 수 없습니다.',
                    es: 'No se pudo calcular el tamaño guardado.',
                    de: 'Speichergröße konnte nicht berechnet werden.',
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: createDemoNotesKey,
                    onPressed: () async {
                      final createdCount = await ref
                          .read(notesControllerProvider.notifier)
                          .createDemoNotes();
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          showCloseIcon: true,
                          content: Text(
                            createdCount == 0
                                ? strings.noDemoNotesToCreate
                                : strings.demoNotesCreated(createdCount),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: Text(strings.createDemoNotes),
                  ),
                  OutlinedButton.icon(
                    key: deleteDemoNotesKey,
                    onPressed: demoNoteCount == 0
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) {
                                return AlertDialog(
                                  title: Text(strings.deleteDemoNotesTitle),
                                  content: Text(
                                    strings.deleteDemoNotesBody(demoNoteCount),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(
                                        dialogContext,
                                      ).pop(false),
                                      child: Text(strings.text('home.cancel')),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                      child: Text(strings.delete),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirmed != true) {
                              return;
                            }
                            final deletedCount = await ref
                                .read(notesControllerProvider.notifier)
                                .deleteDemoNotes();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(
                                  strings.demoNotesDeleted(deletedCount),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(strings.deleteDemoNotes),
                  ),
                  OutlinedButton.icon(
                    onPressed: noteCount == 0
                        ? null
                        : () async {
                            final confirmed = await _confirmStorageReset(
                              context,
                              noteCount,
                            );
                            if (confirmed != true) {
                              return;
                            }
                            final deletedCount = await ref
                                .read(notesControllerProvider.notifier)
                                .resetLocalStorage();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(
                                  strings.localized(
                                    en: 'Initialized local storage. Deleted $deletedCount notes.',
                                    ja: '\u30b9\u30c8\u30ec\u30fc\u30b8\u3092\u521d\u671f\u5316\u3057\u307e\u3057\u305f\u3002$deletedCount \u4ef6\u306e\u30ce\u30fc\u30c8\u3092\u524a\u9664\u3057\u307e\u3057\u305f\u3002',
                                    zh: '\u5df2\u521d\u59cb\u5316\u672c\u5730\u5b58\u50a8\u3002\u5220\u9664\u4e86 $deletedCount \u6761\u7b14\u8bb0\u3002',
                                    ko: '\ub85c\uceec \uc800\uc7a5\uc18c\ub97c \ucd08\uae30\ud654\ud588\uc2b5\ub2c8\ub2e4. \uba54\ubaa8 $deletedCount\uac1c\ub97c \uc0ad\uc81c\ud588\uc2b5\ub2c8\ub2e4.',
                                    es: 'Se inicializo el almacenamiento local. Se eliminaron $deletedCount notas.',
                                    de: 'Lokaler Speicher initialisiert. $deletedCount Notizen wurden geloescht.',
                                  ),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(
                      strings.localized(
                        en: 'Initialize storage',
                        ja: '\u30b9\u30c8\u30ec\u30fc\u30b8\u3092\u521d\u671f\u5316',
                        zh: '\u521d\u59cb\u5316\u5b58\u50a8',
                        ko: '\uc800\uc7a5\uc18c \ucd08\uae30\ud654',
                        es: 'Inicializar almacenamiento',
                        de: 'Speicher initialisieren',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.about,
          summary: showFlavorInfo
              ? '$aboutVersion / $displayName'
              : aboutVersion,
          assetPath: 'assets/settings/about.svg',
          children: [
            if (showFlavorInfo)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(displayName),
                subtitle: Text(strings.currentFlavor(flavorName)),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.appVersion),
              subtitle: Text(
                packageInfo.when(
                  data: (info) =>
                      _versionWithBuildDate(strings, info.displayVersion),
                  loading: strings.readingVersion,
                  error: (_, _) => _versionWithBuildDate(strings, '1.0.0 (1)'),
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.appUpdates),
              subtitle: Text(
                inAppUpdateState.status == null
                    ? appUpdatesDescription
                    : [
                        inAppUpdateSummary,
                        if (inAppUpdateState.status?.availableVersionCode !=
                            null)
                          strings.updateVersionLabel(
                            inAppUpdateState.status?.availableVersionCode,
                          ),
                        if (inAppUpdateState.status?.updatePriority != null)
                          strings.updatePriorityLabel(
                            inAppUpdateState.status?.updatePriority,
                          ),
                        if (inAppUpdateState.status?.installStatus ==
                            InstallStatus.downloaded)
                          strings.updateFlexibleReady,
                      ].join('\n'),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: inAppUpdateState.isBusy
                      ? null
                      : () async {
                          if (!appUpdatesSupported) {
                            await _openStoreListingOrExplain(context, strings);
                            return;
                          }
                          await ref
                              .read(inAppUpdateControllerProvider.notifier)
                              .check();
                          if (!context.mounted) {
                            return;
                          }
                          final message = ref
                              .read(inAppUpdateControllerProvider)
                              .message;
                          if (message != null && message.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                showCloseIcon: true,
                                content: Text(message),
                              ),
                            );
                          }
                        },
                  child: Text(strings.checkForUpdates),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openStoreReviewOrExplain(context, strings),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: Text(strings.writeStoreReview),
                ),
                if (inAppUpdateState.status?.updateAvailable == true &&
                    inAppUpdateState.status?.installStatus !=
                        InstallStatus.downloaded)
                  FilledButton(
                    onPressed: inAppUpdateState.isBusy
                        ? null
                        : () async {
                            await ref
                                .read(inAppUpdateControllerProvider.notifier)
                                .startPreferredUpdate();
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(inAppUpdateControllerProvider)
                                .message;
                            if (message != null && message.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text(message),
                                ),
                              );
                            }
                          },
                    child: Text(strings.startUpdate),
                  ),
                if (inAppUpdateState.status?.installStatus ==
                    InstallStatus.downloaded)
                  FilledButton.tonal(
                    onPressed: inAppUpdateState.isBusy
                        ? null
                        : () async {
                            await ref
                                .read(inAppUpdateControllerProvider.notifier)
                                .completeFlexibleUpdate();
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(inAppUpdateControllerProvider)
                                .message;
                            if (message != null && message.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  showCloseIcon: true,
                                  content: Text(message),
                                ),
                              );
                            }
                          },
                    child: Text(strings.completeUpdateInstall),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.ossLicenses),
              subtitle: Text(strings.ossLicensesDesc),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () {
                final info = packageInfo.asData?.value;
                showLicensePage(
                  context: context,
                  applicationName: info?.appName ?? 'HiMemo',
                  applicationVersion: info?.displayVersion ?? '1.0.0 (1)',
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppearanceSettingsGroup({
    required BuildContext context,
    required WidgetRef ref,
    required AppStrings strings,
    required AppLocaleSetting localeSetting,
    required ThemeMode themeMode,
    required AppFontFamily fontFamily,
    required AppColorTheme colorTheme,
    required String colorThemeScope,
    required List<_ColorThemeScopeOption> colorThemeTargets,
    required String colorThemeTargetLabel,
    required String appearanceSummary,
  }) {
    final effectiveFontFamily = _availableFontFamilies.contains(fontFamily)
        ? fontFamily
        : AppFontFamily.system;
    return _SettingsGroup(
      title: strings.appearanceWithControls,
      summary: appearanceSummary,
      assetPath: 'assets/settings/appearance.svg',
      semanticLabel: 'settings-appearance',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            strings.language,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        DropdownButtonFormField<AppLocaleSetting>(
          key: SettingsScreen.localeDropdownKey,
          initialValue: localeSetting,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: strings.languageSystemDesc,
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.translate_rounded),
          ),
          items: [
            DropdownMenuItem(
              key: SettingsScreen.localeSystemKey,
              value: AppLocaleSetting.system,
              child: Text(strings.languageSystemOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeJapaneseKey,
              value: AppLocaleSetting.japanese,
              child: Text(strings.languageJapaneseOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeEnglishKey,
              value: AppLocaleSetting.english,
              child: Text(strings.languageEnglishOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeChineseKey,
              value: AppLocaleSetting.chinese,
              child: Text(strings.languageChineseOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeKoreanKey,
              value: AppLocaleSetting.korean,
              child: Text(strings.languageKoreanOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeSpanishKey,
              value: AppLocaleSetting.spanish,
              child: Text(strings.languageSpanishOption),
            ),
            DropdownMenuItem(
              key: SettingsScreen.localeGermanKey,
              value: AppLocaleSetting.german,
              child: Text(strings.languageGermanOption),
            ),
          ],
          onChanged: (value) {
            if (value == null || value == localeSetting) {
              return;
            }
            ref.read(appLocaleControllerProvider.notifier).setLocale(value);
          },
        ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            strings.appFont,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        DropdownButtonFormField<AppFontFamily>(
          key: SettingsScreen.fontDropdownKey,
          initialValue: effectiveFontFamily,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: strings.appFontDesc,
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.text_fields_rounded),
          ),
          items: _availableFontFamilies
              .map(
                (font) => DropdownMenuItem(
                  value: font,
                  child: Text(_fontFamilyLabel(context, font)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null || value == effectiveFontFamily) {
              return;
            }
            ref.read(appFontFamilyControllerProvider.notifier).setFont(value);
          },
        ),
        const Divider(height: 24),
        _ThemeOptionTile(
          tileKey: lightThemeKey,
          title: strings.themeLight,
          subtitle: strings.lightDesc,
          selected: themeMode == ThemeMode.light,
          onTap: () => ref
              .read(themeModeControllerProvider.notifier)
              .setMode(ThemeMode.light),
        ),
        _ThemeOptionTile(
          tileKey: systemThemeKey,
          title: strings.themeSystem,
          subtitle: strings.systemDesc,
          selected: themeMode == ThemeMode.system,
          onTap: () => ref
              .read(themeModeControllerProvider.notifier)
              .setMode(ThemeMode.system),
        ),
        _ThemeOptionTile(
          tileKey: darkThemeKey,
          title: strings.themeDark,
          subtitle: strings.darkDesc,
          selected: themeMode == ThemeMode.dark,
          onTap: () => ref
              .read(themeModeControllerProvider.notifier)
              .setMode(ThemeMode.dark),
        ),
        const Divider(height: 24),
        if (colorThemeTargets.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: colorThemeScope,
            isExpanded: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: strings.accentColor,
              prefixIcon: const Icon(Icons.palette_outlined),
            ),
            items: [
              for (final target in colorThemeTargets)
                DropdownMenuItem(
                  value: target.scope,
                  child: Text(target.label),
                ),
            ],
            onChanged: (value) {
              if (value == null || value == colorThemeScope) {
                return;
              }
              ref.read(colorThemeSettingsScopeProvider.notifier).select(value);
            },
          ),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${strings.accentColor} ($colorThemeTargetLabel)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                strings.accentColorJapanesePaletteDesc,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ],
          ),
        ),
        _ColorThemePicker(
          current: colorTheme,
          basicThemes: const [
            AppColorTheme.konjyo,
            AppColorTheme.moegi,
            AppColorTheme.yamabuki,
            AppColorTheme.kurenai,
            AppColorTheme.sakura,
          ],
          extendedThemes: const [
            AppColorTheme.konjyo,
            AppColorTheme.ai,
            AppColorTheme.ruri,
            AppColorTheme.hanada,
            AppColorTheme.chigusa,
            AppColorTheme.asagi,
            AppColorTheme.sora,
            AppColorTheme.tokiwa,
            AppColorTheme.seiheki,
            AppColorTheme.wakatake,
            AppColorTheme.moegi,
            AppColorTheme.byakuroku,
            AppColorTheme.rikyucha,
            AppColorTheme.kurumi,
            AppColorTheme.yamabuki,
            AppColorTheme.nanohana,
            AppColorTheme.enji,
            AppColorTheme.akane,
            AppColorTheme.kurenai,
            AppColorTheme.haizakura,
            AppColorTheme.sakura,
            AppColorTheme.sumi,
            AppColorTheme.ginnezumi,
            AppColorTheme.shironeri,
            AppColorTheme.gofun,
            AppColorTheme.kikyo,
            AppColorTheme.edomurasaki,
            AppColorTheme.sumire,
            AppColorTheme.fuji,
            AppColorTheme.shion,
          ],
          titleFor: (theme) => _colorThemeLabel(context, theme),
          subtitleFor: (theme) => _colorThemeDescription(context, theme),
          sampleColorFor: _themeSampleColor,
          onSelect: (theme) =>
              _setColorThemeForScope(ref, colorThemeScope, theme),
        ),
      ],
    );
  }

  String _syncStatusTitle(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.icloud.availability');
    }
    return strings.text('home.authentication');
  }

  String _syncConnectLabel(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.check.icloud');
    }
    return strings.text('home.connect');
  }

  String _syncReconnectLabel(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.check.again');
    }
    return strings.text('home.reconnect');
  }

  String _syncDisconnectLabel(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      return strings.text('home.stop.using.icloud');
    }
    return strings.text('home.disconnect');
  }

  String _syncSubtitle(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    switch (provider) {
      case SyncProvider.off:
        return strings.text('home.sync.is.disabled');
      case SyncProvider.iCloud:
        return strings.text(
          'home.icloud.selected.the.app.checks.this.device.s.icloud.avai',
        );
      case SyncProvider.googleDrive:
        return strings.text(
          'home.google.drive.selected.authorize.access.to.drive.app.data',
        );
    }
  }

  String syncSubtitleLegacy(BuildContext context, SyncProvider provider) {
    return _syncSubtitle(context, provider);
  }

  String _syncAuthSummary(
    BuildContext context,
    SyncProvider provider,
    SyncAuthState authState,
  ) {
    final strings = context.strings;
    if (provider == SyncProvider.iCloud) {
      switch (authState.stage) {
        case SyncAuthStage.idle:
          return strings.text(
            'home.this.device.s.icloud.availability.has.not.been.checked.y',
          );
        case SyncAuthStage.busy:
          return strings.text(
            'home.checking.this.device.s.icloud.availability',
          );
        case SyncAuthStage.authenticated:
          return strings.text(
            'home.this.device.can.use.icloud.as.the.himemo.sync.target',
          );
        case SyncAuthStage.unsupported:
        case SyncAuthStage.error:
          return authState.message ??
              (strings.text(
                'home.icloud.sync.is.not.available.on.this.device',
              ));
      }
    }
    if (provider == SyncProvider.off) {
      return strings.text('home.no.cloud.account.is.connected');
    }

    switch (authState.stage) {
      case SyncAuthStage.idle:
        return strings.text('home.no.account.connected.yet');
      case SyncAuthStage.busy:
        return strings.text('home.waiting.for.authentication.to.complete');
      case SyncAuthStage.authenticated:
        final identity =
            authState.email ?? authState.displayName ?? authState.userId;
        final suffix = authState.message == null ? '' : ' ${authState.message}';
        return identity == null
            ? strings.syncConnected(suffix: suffix)
            : strings.syncConnected(identity: identity, suffix: suffix);
      case SyncAuthStage.unsupported:
      case SyncAuthStage.error:
        if (provider == SyncProvider.googleDrive &&
            _isGoogleDriveWebSignInUnavailable(authState.message)) {
          return strings.googleDriveWebSignInUnavailable;
        }
        return authState.message ??
            (strings.text('home.authentication.is.not.available'));
    }
  }

  bool _isGoogleDriveWebSignInUnavailable(String? message) {
    return message != null &&
        message.contains(
          'Google Drive sync on web requires the Google Sign-In SDK button flow',
        );
  }

  String syncAuthSummaryLegacy(
    BuildContext context,
    SyncProvider provider,
    SyncAuthState authState,
  ) {
    final strings = context.strings;
    if (provider == SyncProvider.off) {
      return strings.text('home.no.cloud.account.is.connected.2');
    }

    switch (authState.stage) {
      case SyncAuthStage.idle:
        return strings.text('home.no.account.connected.yet.2');
      case SyncAuthStage.busy:
        return strings.text('home.waiting.for.authentication.to.complete.2');
      case SyncAuthStage.authenticated:
        final identity =
            authState.email ?? authState.displayName ?? authState.userId;
        final suffix = authState.message == null ? '' : ' ${authState.message}';
        return identity == null
            ? strings.syncConnectedLegacy(suffix: suffix)
            : strings.syncConnectedLegacy(identity: identity, suffix: suffix);
      case SyncAuthStage.unsupported:
      case SyncAuthStage.error:
        return authState.message ??
            (strings.text('home.authentication.is.not.available.2'));
    }
  }

  Future<void> _showSetPrivateKeyDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secretController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(strings.setPrivateKey),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: secretController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: strings.privateKey,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: strings.confirmPrivateKey(strings.privateKey),
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () async {
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
                    await ref
                        .read(privateVaultSecretControllerProvider.notifier)
                        .configure(secret);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
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

  Future<void> _showUnlockPrivateVaultDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final secretController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(strings.unlockPrivateVault),
              content: TextField(
                controller: secretController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: strings.privateKey,
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final matched = await ref
                        .read(privateVaultSecretControllerProvider.notifier)
                        .verify(secretController.text.trim());
                    if (!matched) {
                      setState(() {
                        errorText = strings.privateKeyIncorrect;
                      });
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(strings.unlock),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmResetPrivateKey(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.resetPrivateKey),
          content: Text(strings.resetPrivateKeyBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.reset),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(privateVaultSecretControllerProvider.notifier).clear();
    }
  }

  Future<bool?> _confirmStorageReset(BuildContext context, int noteCount) {
    final strings = context.strings;
    var agreed = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                strings.localized(
                  en: 'Initialize storage',
                  ja: '\u30b9\u30c8\u30ec\u30fc\u30b8\u3092\u521d\u671f\u5316',
                  zh: '\u521d\u59cb\u5316\u5b58\u50a8',
                  ko: '\uc800\uc7a5\uc18c \ucd08\uae30\ud654',
                  es: 'Inicializar almacenamiento',
                  de: 'Speicher initialisieren',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.localized(
                      en: 'This deletes all notes and attachments saved on this device. This action cannot be undone.',
                      ja: '\u3053\u306e\u7aef\u672b\u306b\u4fdd\u5b58\u3055\u308c\u3066\u3044\u308b\u3059\u3079\u3066\u306e\u30ce\u30fc\u30c8\u3068\u6dfb\u4ed8\u30d5\u30a1\u30a4\u30eb\u3092\u524a\u9664\u3057\u307e\u3059\u3002\u3053\u306e\u64cd\u4f5c\u306f\u5143\u306b\u623b\u305b\u307e\u305b\u3093\u3002',
                      zh: '\u8fd9\u5c06\u5220\u9664\u6b64\u8bbe\u5907\u4e0a\u4fdd\u5b58\u7684\u6240\u6709\u7b14\u8bb0\u548c\u9644\u4ef6\u3002\u6b64\u64cd\u4f5c\u65e0\u6cd5\u64a4\u9500\u3002',
                      ko: '\uc774 \uae30\uae30\uc5d0 \uc800\uc7a5\ub41c \ubaa8\ub4e0 \uba54\ubaa8\uc640 \ucca8\ubd80 \ud30c\uc77c\uc744 \uc0ad\uc81c\ud569\ub2c8\ub2e4. \uc774 \uc791\uc5c5\uc740 \ub418\ub3cc\ub9b4 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.',
                      es: 'Esto elimina todas las notas y adjuntos guardados en este dispositivo. Esta accion no se puede deshacer.',
                      de: 'Dies loescht alle Notizen und Anhaenge auf diesem Geraet. Diese Aktion kann nicht rueckgaengig gemacht werden.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.localized(
                      en: 'Notes to delete: $noteCount',
                      ja: '\u524a\u9664\u5bfe\u8c61\u306e\u30ce\u30fc\u30c8: $noteCount \u4ef6',
                      zh: '\u8981\u5220\u9664\u7684\u7b14\u8bb0\uff1a$noteCount',
                      ko: '\uc0ad\uc81c\ud560 \uba54\ubaa8: $noteCount\uac1c',
                      es: 'Notas a eliminar: $noteCount',
                      de: 'Zu loeschende Notizen: $noteCount',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: agreed,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      strings.localized(
                        en: 'I understand that the data will be deleted.',
                        ja: '\u30c7\u30fc\u30bf\u304c\u524a\u9664\u3055\u308c\u308b\u3053\u3068\u306b\u540c\u610f\u3057\u307e\u3059\u3002',
                        zh: '\u6211\u7406\u89e3\u5e76\u540c\u610f\u6570\u636e\u5c06\u88ab\u5220\u9664\u3002',
                        ko: '\ub370\uc774\ud130\uac00 \uc0ad\uc81c\ub428\uc744 \uc774\ud574\ud558\uace0 \ub3d9\uc758\ud569\ub2c8\ub2e4.',
                        es: 'Entiendo que los datos se eliminaran.',
                        de: 'Ich verstehe, dass die Daten geloescht werden.',
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        agreed = value ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: agreed
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: Text(strings.delete),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const _availableFontFamilies = <AppFontFamily>[
    ...iOSFriendlyAppFontFamilies,
  ];

  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    final strings = context.strings;
    return switch (mode) {
      ThemeMode.light => strings.themeLight,
      ThemeMode.system => strings.themeSystem,
      ThemeMode.dark => strings.themeDark,
    };
  }

  String _fontFamilyLabel(BuildContext context, AppFontFamily fontFamily) {
    final strings = context.strings;
    return switch (fontFamily) {
      AppFontFamily.system => strings.fontSystem,
      AppFontFamily.gothic => strings.fontGothic,
      AppFontFamily.uiGothic => strings.fontUiGothic,
      AppFontFamily.kakuGothic => strings.fontKakuGothic,
      AppFontFamily.mincho => strings.fontMincho,
      AppFontFamily.uiMincho => strings.fontUiMincho,
      AppFontFamily.rounded => strings.fontRounded,
      AppFontFamily.zenRounded => strings.fontZenRounded,
      AppFontFamily.casual => strings.fontCasual,
      AppFontFamily.monospace => strings.fontMonospace,
    };
  }

  String _localeSettingLabel(BuildContext context, AppLocaleSetting setting) {
    final strings = context.strings;
    return switch (setting) {
      AppLocaleSetting.system => strings.languageSystemOption,
      AppLocaleSetting.japanese => strings.languageJapaneseOption,
      AppLocaleSetting.english => strings.languageEnglishOption,
      AppLocaleSetting.chinese => strings.languageChineseOption,
      AppLocaleSetting.korean => strings.languageKoreanOption,
      AppLocaleSetting.spanish => strings.languageSpanishOption,
      AppLocaleSetting.german => strings.languageGermanOption,
    };
  }

  String _colorThemeLabel(BuildContext context, AppColorTheme theme) {
    final strings = context.strings;
    return switch (theme) {
      AppColorTheme.konjyo => strings.colorKonjyo,
      AppColorTheme.moegi => strings.colorMoegi,
      AppColorTheme.yamabuki => strings.colorYamabuki,
      AppColorTheme.ginnezumi => strings.colorGinnezumi,
      AppColorTheme.seiheki => strings.colorSeiheki,
      AppColorTheme.kurenai => strings.colorKurenai,
      AppColorTheme.sakura => strings.colorSakura,
      AppColorTheme.fuji => strings.colorFuji,
      AppColorTheme.ai => strings.colorAi,
      AppColorTheme.kurumi => strings.colorKurumi,
      AppColorTheme.chigusa => strings.colorChigusa,
      AppColorTheme.sumire => strings.colorSumire,
      AppColorTheme.sumi => strings.colorSumi,
      AppColorTheme.shironeri => strings.colorShironeri,
      AppColorTheme.gofun => strings.colorGofun,
      AppColorTheme.enji => strings.colorEnji,
      AppColorTheme.hanada => strings.colorHanada,
      AppColorTheme.sora => strings.colorSora,
      AppColorTheme.ruri => strings.colorRuri,
      AppColorTheme.asagi => strings.colorAsagi,
      AppColorTheme.wakatake => strings.colorWakatake,
      AppColorTheme.tokiwa => strings.colorTokiwa,
      AppColorTheme.byakuroku => strings.colorByakuroku,
      AppColorTheme.nanohana => strings.colorNanohana,
      AppColorTheme.haizakura => strings.colorHaizakura,
      AppColorTheme.akane => strings.colorAkane,
      AppColorTheme.kikyo => strings.colorKikyo,
      AppColorTheme.edomurasaki => strings.colorEdomurasaki,
      AppColorTheme.shion => strings.colorShion,
      AppColorTheme.rikyucha => strings.colorRikyucha,
    };
  }

  String _colorThemeDescription(BuildContext context, AppColorTheme theme) {
    final strings = context.strings;
    return switch (theme) {
      AppColorTheme.konjyo => strings.colorKonjyoDesc,
      AppColorTheme.moegi => strings.colorMoegiDesc,
      AppColorTheme.yamabuki => strings.colorYamabukiDesc,
      AppColorTheme.ginnezumi => strings.colorGinnezumiDesc,
      AppColorTheme.seiheki => strings.colorSeihekiDesc,
      AppColorTheme.kurenai => strings.colorKurenaiDesc,
      AppColorTheme.sakura => strings.colorSakuraDesc,
      AppColorTheme.fuji => strings.colorFujiDesc,
      AppColorTheme.ai => strings.colorAiDesc,
      AppColorTheme.kurumi => strings.colorKurumiDesc,
      AppColorTheme.chigusa => strings.colorChigusaDesc,
      AppColorTheme.sumire => strings.colorSumireDesc,
      AppColorTheme.sumi => strings.colorSumiDesc,
      AppColorTheme.shironeri => strings.colorShironeriDesc,
      AppColorTheme.gofun => strings.colorGofunDesc,
      AppColorTheme.enji => strings.colorEnjiDesc,
      AppColorTheme.hanada => strings.colorHanadaDesc,
      AppColorTheme.sora => strings.colorSoraDesc,
      AppColorTheme.ruri => strings.colorRuriDesc,
      AppColorTheme.asagi => strings.colorAsagiDesc,
      AppColorTheme.wakatake => strings.colorWakatakeDesc,
      AppColorTheme.tokiwa => strings.colorTokiwaDesc,
      AppColorTheme.byakuroku => strings.colorByakurokuDesc,
      AppColorTheme.nanohana => strings.colorNanohanaDesc,
      AppColorTheme.haizakura => strings.colorHaizakuraDesc,
      AppColorTheme.akane => strings.colorAkaneDesc,
      AppColorTheme.kikyo => strings.colorKikyoDesc,
      AppColorTheme.edomurasaki => strings.colorEdomurasakiDesc,
      AppColorTheme.shion => strings.colorShionDesc,
      AppColorTheme.rikyucha => strings.colorRikyuchaDesc,
    };
  }

  Future<void> _setColorThemeForScope(
    WidgetRef ref,
    String scope,
    AppColorTheme theme,
  ) {
    if (scope == defaultColorThemeScope) {
      return ref.read(appColorThemeControllerProvider.notifier).setTheme(theme);
    }
    return ref
        .read(profileColorThemeControllerProvider.notifier)
        .setTheme(scope, theme);
  }

  Color _themeSampleColor(AppColorTheme theme) {
    return switch (theme) {
      AppColorTheme.konjyo => const Color(0xFF113285),
      AppColorTheme.moegi => const Color(0xFF7BA23F),
      AppColorTheme.yamabuki => const Color(0xFFFFB11B),
      AppColorTheme.ginnezumi => const Color(0xFF91989F),
      AppColorTheme.seiheki => const Color(0xFF268785),
      AppColorTheme.kurenai => const Color(0xFFCB1B45),
      AppColorTheme.sakura => const Color(0xFFFEDFE1),
      AppColorTheme.fuji => const Color(0xFF8B81C3),
      AppColorTheme.ai => const Color(0xFF0F4C81),
      AppColorTheme.kurumi => const Color(0xFF947A6D),
      AppColorTheme.chigusa => const Color(0xFF3A8FB7),
      AppColorTheme.sumire => const Color(0xFF66327C),
      AppColorTheme.sumi => const Color(0xFF1C1C1C),
      AppColorTheme.shironeri => const Color(0xFFF3F3F2),
      AppColorTheme.gofun => const Color(0xFFFFFBF0),
      AppColorTheme.enji => const Color(0xFF9F353A),
      AppColorTheme.hanada => const Color(0xFF006284),
      AppColorTheme.sora => const Color(0xFF58B2DC),
      AppColorTheme.ruri => const Color(0xFF005CAF),
      AppColorTheme.asagi => const Color(0xFF33A6B8),
      AppColorTheme.wakatake => const Color(0xFF5DAC81),
      AppColorTheme.tokiwa => const Color(0xFF1B813E),
      AppColorTheme.byakuroku => const Color(0xFFA8D8B9),
      AppColorTheme.nanohana => const Color(0xFFFFEC47),
      AppColorTheme.haizakura => const Color(0xFFD7C4BB),
      AppColorTheme.akane => const Color(0xFFB7282E),
      AppColorTheme.kikyo => const Color(0xFF6A4C9C),
      AppColorTheme.edomurasaki => const Color(0xFF77428D),
      AppColorTheme.shion => const Color(0xFF8F77B5),
      AppColorTheme.rikyucha => const Color(0xFF897D55),
    };
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

bool _isSameNoteDay(NoteEntry left, NoteEntry right) {
  return left.createdAt.year == right.createdAt.year &&
      left.createdAt.month == right.createdAt.month &&
      left.createdAt.day == right.createdAt.day;
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
    required this.query,
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
  final String query;
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
    return ListView.builder(
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
  }
}

List<_MobileNoteRow> _buildMobileNoteRows({
  required UnlockIdentity activeIdentity,
  required bool showPrivateVaultNotice,
  required bool compactHeader,
  required List<NoteEntry> notes,
  required NotesListDensity density,
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
        (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i]))) {
      noteRows.add(_MobileDayRow(notes[i].createdAt));
    }
    noteRows.add(_MobileTileRow(notes[i]));
    if (density != NotesListDensity.compact &&
        i != notes.length - 1 &&
        _isSameNoteDay(notes[i], notes[i + 1])) {
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
    required this.query,
    required this.selected,
    required this.onTap,
  });

  final NoteEntry note;
  final String vaultName;
  final bool showVaultName;
  final NotesListDensity density;
  final String query;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isPrivateNote = isPrivateVaultId(note.vaultId);
    final changedAt = note.updatedAt ?? note.createdAt;
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
    final hasDistinctBody =
        bodyPreview.isNotEmpty && bodyPreview != note.title.trim();
    final showAttachmentPreviews =
        density != NotesListDensity.compact && !isPrivateNote;
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
              if (previewFacts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final fact in previewFacts.take(3))
                      _NotePreviewFactChip(fact: fact),
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
                        child: _AttachmentPreview(
                          attachment: note.attachments[i],
                          size: thumbnailSize,
                        ),
                      ),
                    ],
                    if (note.attachments.length > maxThumbs) ...[
                      Container(
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
    required this.query,
    required this.onAddNote,
    required this.onNoteSelected,
  });

  final UnlockIdentity activeIdentity;
  final bool showPrivateVaultNotice;
  final List<NoteEntry> notes;
  final String? selectedNoteId;
  final Map<String, String> vaultNameById;
  final bool showVaultName;
  final NotesListDensity density;
  final String query;
  final VoidCallback onAddNote;
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
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
  }
}

List<_SplitNoteRow> _buildSplitNoteRows({
  required UnlockIdentity activeIdentity,
  required bool showPrivateVaultNotice,
  required List<NoteEntry> notes,
  required NotesListDensity density,
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
        (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i]))) {
      noteRows.add(_SplitNoteDayRow(notes[i].createdAt));
    }
    noteRows.add(_SplitNoteTileRow(notes[i]));
    if (density != NotesListDensity.compact &&
        i != notes.length - 1 &&
        _isSameNoteDay(notes[i], notes[i + 1])) {
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
  late final PageController _pageController;
  int? _programmaticPageTarget;

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

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canMovePrevious = widget.selectedIndex > 0;
    final canMoveNext = widget.selectedIndex < widget.notes.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
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
              const SizedBox(width: 8),
              Text(
                '${widget.selectedIndex + 1} / ${widget.notes.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.text(
                    'home.swipe.left.or.right.to.move.between.notes',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: strings.close,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
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
        ),
      ],
    );
  }
}

class _NoteDetailPane extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final strings = context.strings;
    final createdLabel =
        '${note.createdAt.year}/${note.createdAt.month}/${note.createdAt.day} ${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';
    final changedAt = note.updatedAt ?? note.createdAt;
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

class _SettingsOverviewItem {
  const _SettingsOverviewItem({
    required this.label,
    required this.value,
    required this.assetPath,
  });

  final String label;
  final String value;
  final String assetPath;
}

class _ColorThemeScopeOption {
  const _ColorThemeScopeOption({required this.scope, required this.label});

  final String scope;
  final String label;
}

class _SettingsOverviewCard extends StatelessWidget {
  const _SettingsOverviewCard({required this.items});

  final List<_SettingsOverviewItem> items;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedTextColor(context);
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final width = constraints.maxWidth;
          final columns = width >= 720 ? 4 : (width >= 320 ? 2 : 1);
          final itemWidth = (width - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final item in items)
                SizedBox(
                  width: itemWidth,
                  child: Row(
                    children: [
                      _SettingsSectionIcon(assetPath: item.assetPath),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: Theme.of(
                                context,
                              ).textTheme.labelMedium?.copyWith(color: muted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.value,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.summary,
    required this.assetPath,
    required this.children,
    this.semanticLabel,
  });

  final String title;
  final String summary;
  final String assetPath;
  final List<Widget> children;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(6);
    return Semantics(
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: borderRadius,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                maintainState: true,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                leading: _SettingsSectionIcon(assetPath: assetPath),
                title: Text(title, style: theme.textTheme.titleMedium),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: borderRadius,
                ),
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: _mutedTextColor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionIcon extends StatelessWidget {
  const _SettingsSectionIcon({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SvgPicture.asset(
        assetPath,
        colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
      ),
    );
  }
}

class _ColorThemePicker extends StatefulWidget {
  const _ColorThemePicker({
    required this.current,
    required this.basicThemes,
    required this.extendedThemes,
    required this.titleFor,
    required this.subtitleFor,
    required this.sampleColorFor,
    required this.onSelect,
  });

  final AppColorTheme current;
  final List<AppColorTheme> basicThemes;
  final List<AppColorTheme> extendedThemes;
  final String Function(AppColorTheme theme) titleFor;
  final String Function(AppColorTheme theme) subtitleFor;
  final Color Function(AppColorTheme theme) sampleColorFor;
  final ValueChanged<AppColorTheme> onSelect;

  @override
  State<_ColorThemePicker> createState() => _ColorThemePickerState();
}

class _ColorThemePickerState extends State<_ColorThemePicker> {
  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final extendedSelected = widget.extendedThemes.contains(widget.current);
    final basicSelected = widget.basicThemes.contains(widget.current);
    final themes = [
      ...widget.basicThemes,
      if (extendedSelected && !basicSelected) widget.current,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final theme in themes)
          _ThemeOptionTile(
            title: widget.titleFor(theme),
            subtitle: widget.subtitleFor(theme),
            sampleColor: widget.sampleColorFor(theme),
            selected: widget.current == theme,
            onTap: () => widget.onSelect(theme),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showExtendedThemeDialog(context),
            icon: const Icon(Icons.palette_outlined),
            label: Text(
              strings.extendedThemesWithCount(widget.extendedThemes.length),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showExtendedThemeDialog(BuildContext context) async {
    final selected = await showModalBottomSheet<AppColorTheme>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return _ExtendedColorThemeSheet(
          current: widget.current,
          themes: widget.extendedThemes,
          titleFor: widget.titleFor,
          subtitleFor: widget.subtitleFor,
          sampleColorFor: widget.sampleColorFor,
        );
      },
    );
    if (selected != null) {
      widget.onSelect(selected);
    }
  }
}

class _ExtendedColorThemeSheet extends StatelessWidget {
  const _ExtendedColorThemeSheet({
    required this.current,
    required this.themes,
    required this.titleFor,
    required this.subtitleFor,
    required this.sampleColorFor,
  });

  final AppColorTheme current;
  final List<AppColorTheme> themes;
  final String Function(AppColorTheme theme) titleFor;
  final String Function(AppColorTheme theme) subtitleFor;
  final Color Function(AppColorTheme theme) sampleColorFor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: _ExtendedColorThemeSheetBody(
        current: current,
        themes: themes,
        titleFor: titleFor,
        subtitleFor: subtitleFor,
        sampleColorFor: sampleColorFor,
      ),
    );
  }
}

class _ExtendedColorThemeSheetBody extends StatelessWidget {
  const _ExtendedColorThemeSheetBody({
    required this.current,
    required this.themes,
    required this.titleFor,
    required this.subtitleFor,
    required this.sampleColorFor,
  });

  final AppColorTheme current;
  final List<AppColorTheme> themes;
  final String Function(AppColorTheme theme) titleFor;
  final String Function(AppColorTheme theme) subtitleFor;
  final Color Function(AppColorTheme theme) sampleColorFor;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final grouped = <String, List<AppColorTheme>>{};
    for (final theme in themes) {
      grouped.putIfAbsent(_categoryFor(context, theme), () => []).add(theme);
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              strings.extendedThemes,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720
                    ? 3
                    : constraints.maxWidth >= 460
                    ? 2
                    : 1;
                return CustomScrollView(
                  slivers: [
                    for (final entry in grouped.entries) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text(
                            entry.key,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          itemCount: entry.value.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: columns == 1 ? 3.7 : 2.5,
                              ),
                          itemBuilder: (context, index) {
                            final theme = entry.value[index];
                            return _ColorThemeCard(
                              title: titleFor(theme),
                              subtitle: subtitleFor(theme),
                              sampleColor: sampleColorFor(theme),
                              selected: current == theme,
                              onTap: () => Navigator.of(context).pop(theme),
                            );
                          },
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _categoryFor(BuildContext context, AppColorTheme theme) {
    final strings = context.strings;
    return switch (theme) {
      AppColorTheme.ai ||
      AppColorTheme.chigusa ||
      AppColorTheme.konjyo ||
      AppColorTheme.hanada ||
      AppColorTheme.sora ||
      AppColorTheme.ruri ||
      AppColorTheme.asagi => strings.themeCategoryBlueGreen,
      AppColorTheme.fuji ||
      AppColorTheme.sumire ||
      AppColorTheme.kikyo ||
      AppColorTheme.edomurasaki ||
      AppColorTheme.shion => strings.themeCategoryPurple,
      AppColorTheme.moegi ||
      AppColorTheme.seiheki ||
      AppColorTheme.wakatake ||
      AppColorTheme.tokiwa ||
      AppColorTheme.byakuroku => strings.themeCategoryGreenYellow,
      AppColorTheme.yamabuki ||
      AppColorTheme.nanohana ||
      AppColorTheme.kurumi ||
      AppColorTheme.rikyucha => strings.themeCategoryEarth,
      AppColorTheme.kurenai ||
      AppColorTheme.sakura ||
      AppColorTheme.enji ||
      AppColorTheme.haizakura ||
      AppColorTheme.akane => strings.themeCategoryRedPink,
      AppColorTheme.sumi ||
      AppColorTheme.ginnezumi ||
      AppColorTheme.shironeri ||
      AppColorTheme.gofun => strings.themeCategoryNeutral,
    };
  }
}

class _ColorThemeCard extends StatelessWidget {
  const _ColorThemeCard({
    required this.title,
    required this.subtitle,
    required this.sampleColor,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color sampleColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: colorScheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: sampleColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, color: colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    this.tileKey,
    required this.title,
    required this.subtitle,
    this.sampleColor,
    required this.selected,
    required this.onTap,
  });

  final Key? tileKey;
  final String title;
  final String subtitle;
  final Color? sampleColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sampleColor = this.sampleColor;
    return ListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: sampleColor == null
          ? Text(title)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                const SizedBox(height: 4),
                Container(
                  width: 44,
                  height: 3,
                  decoration: BoxDecoration(
                    color: sampleColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

Future<void> showNoteEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  NoteEntry? note,
  DateTime? initialCreatedAt,
}) async {
  _pushNoteOverlaySheet();
  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  final initialTags = note == null
      ? ref.read(searchFiltersControllerProvider).tags
      : const <String>[];
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return FractionallySizedBox(
          heightFactor: bottomInset > 0 ? 1 : 0.92,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: _NoteEditorSheet(
              note: note,
              initialCreatedAt: initialCreatedAt,
              initialTags: initialTags,
            ),
          ),
        );
      },
    );
  } finally {
    scaffoldMessenger?.hideCurrentSnackBar();
    _popNoteOverlaySheet();
  }
}

class _NotesToolbar extends ConsumerStatefulWidget {
  const _NotesToolbar({this.compact = false});

  final bool compact;

  @override
  ConsumerState<_NotesToolbar> createState() => _NotesToolbarState();
}

class _NotesToolbarState extends ConsumerState<_NotesToolbar> {
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  late String _lastAppliedSearchQuery;

  @override
  void initState() {
    super.initState();
    _lastAppliedSearchQuery = ref.read(searchQueryProvider);
    _searchController = TextEditingController(text: _lastAppliedSearchQuery);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final query = ref.watch(searchQueryProvider);
    _syncExternalSearchQuery(query);
    final filters = ref.watch(searchFiltersControllerProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final tagSummaries = ref.watch(visibleTagSummariesProvider);
    final visibleVaultIds = {for (final vault in visibleVaults) vault.id};
    final hasArchivedNotes = ref
        .watch(notesControllerProvider)
        .any(
          (note) =>
              note.deletedAt == null &&
              note.archivedAt != null &&
              visibleVaultIds.contains(note.vaultId),
        );
    final hasAdvancedFilters = !filters.isDefault;
    final listDensity = ref.watch(notesListDensityControllerProvider);
    final privateModeActive = ref.watch(privacyScreenActiveProvider);
    final availableWidth = MediaQuery.sizeOf(context).width;
    final compactToolbarButtons = widget.compact || availableWidth < 560;
    final activeFilterCount =
        (filters.pinnedOnly ? 1 : 0) +
        (filters.attachmentFilters.isNotEmpty ? 1 : 0) +
        (filters.archivedOnly || filters.includeArchived ? 1 : 0) +
        (filters.requireAllTags && filters.tags.length > 1 ? 1 : 0) +
        (filters.dateRange != SearchDateRange.all ? 1 : 0) +
        (filters.vaultId != null ? 1 : 0) +
        (filters.year != null ? 1 : 0) +
        filters.tags.length;

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('notes-search-input'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: strings.search,
                    hintText: strings.text(
                      'home.search.notes.diary.entries.and.attachment.labels',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _scheduleSearchQuery,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<NotesListDensity>(
                tooltip: strings.text('home.list.layout'),
                onSelected: ref
                    .read(notesListDensityControllerProvider.notifier)
                    .setDensity,
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: NotesListDensity.standard,
                    checked: listDensity == NotesListDensity.standard,
                    child: Text(strings.text('home.standard.list')),
                  ),
                  CheckedPopupMenuItem(
                    value: NotesListDensity.compact,
                    checked: listDensity == NotesListDensity.compact,
                    child: Text(strings.text('home.compact.list')),
                  ),
                ],
                child: Semantics(
                  button: true,
                  label: strings.text('home.list.layout'),
                  child: Tooltip(
                    message: strings.text('home.list.layout'),
                    child: Container(
                      height: 48,
                      width: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.view_agenda_outlined, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: strings.text('home.filters'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openAdvancedFiltersSheet(
                    context,
                    hasArchivedNotes: hasArchivedNotes,
                  ),
                  child: Container(
                    height: 48,
                    width: compactToolbarButtons ? 48 : null,
                    constraints: BoxConstraints(
                      minWidth: compactToolbarButtons
                          ? 48
                          : activeFilterCount > 0
                          ? 110
                          : 84,
                    ),
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(
                      horizontal: compactToolbarButtons ? 0 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: hasAdvancedFilters
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: compactToolbarButtons
                        ? Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.tune_rounded, size: 20),
                              if (activeFilterCount > 0)
                                Positioned(
                                  top: -5,
                                  right: -5,
                                  child: _FilterCountBadge(
                                    count: activeFilterCount,
                                  ),
                                ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tune_rounded, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                strings.text('home.filters'),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              if (activeFilterCount > 0) ...[
                                const SizedBox(width: 8),
                                _FilterCountBadge(count: activeFilterCount),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (privateModeActive) ...[
            const SizedBox(height: 8),
            Text(
              strings.text(
                'home.search.terms.are.cleared.when.private.mode.closes',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
          ],
          if (tagSummaries.isNotEmpty) ...[
            const SizedBox(height: 10),
            _QuickTagStrip(
              summaries: tagSummaries,
              activeTags: filters.tags,
              onTagSelected: (tag) {
                final notifier = ref.read(
                  searchFiltersControllerProvider.notifier,
                );
                final selected = filters.tags
                    .map(canonicalizeNoteTag)
                    .contains(canonicalizeNoteTag(tag));
                if (selected) {
                  notifier.removeTag(tag);
                } else {
                  notifier.addTag(tag);
                }
                ref.read(searchQueryProvider.notifier).setQuery('');
                ref.read(selectedNoteIdProvider.notifier).select(null);
              },
            ),
          ],
          if (filters.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (filters.requireAllTags && filters.tags.length > 1)
                  InputChip(
                    label: Text(
                      strings.localized(
                        en: 'All tags',
                        ja: 'タグ: すべて',
                        zh: '所有标签',
                        ko: '모든 태그',
                        es: 'Todas las etiquetas',
                        de: 'Alle Tags',
                      ),
                    ),
                    onDeleted: () => ref
                        .read(searchFiltersControllerProvider.notifier)
                        .setRequireAllTags(false),
                  ),
              ],
            ),
          ],
          ..._buildDetailedFilterRows(context, strings, filters, visibleVaults),
          if (!widget.compact &&
              ref.watch(activeIdentityProvider) != 'daily') ...[
            const SizedBox(height: 12),
            _InfoChip(
              icon: Icons.lock_outline_rounded,
              text: ref.watch(activeIdentityDataProvider).lockLabel,
            ),
          ],
        ],
      ),
    );
  }

  void _syncExternalSearchQuery(String query) {
    if (query == _lastAppliedSearchQuery || query == _searchController.text) {
      return;
    }
    _searchDebounce?.cancel();
    _lastAppliedSearchQuery = query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchController.text == query) {
        return;
      }
      _searchController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    });
  }

  void _scheduleSearchQuery(String value) {
    _searchDebounce?.cancel();
    if (value.isEmpty) {
      _applySearchQuery(value);
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 260),
      () => _applySearchQuery(_searchController.text),
    );
  }

  void _applySearchQuery(String value) {
    if (!mounted || value == _lastAppliedSearchQuery) {
      return;
    }
    _lastAppliedSearchQuery = value;
    ref.read(searchQueryProvider.notifier).setQuery(value);
  }

  List<Widget> _buildDetailedFilterRows(
    BuildContext context,
    AppStrings strings,
    SearchFilters filters,
    List<VaultBucket> visibleVaults,
  ) {
    final notifier = ref.read(searchFiltersControllerProvider.notifier);
    final chips = <Widget>[];

    if (filters.pinnedOnly) {
      chips.add(
        _filterSummaryChip(
          context,
          label: strings.text('home.pinned.only'),
          onDeleted: () => notifier.setPinnedOnly(false),
        ),
      );
    }
    if (filters.attachmentFilters.isNotEmpty) {
      chips.add(
        _filterSummaryChip(
          context,
          label: _attachmentFilterSummaryLabel(
            strings,
            filters.attachmentFilters,
          ),
          onDeleted: () =>
              notifier.setAttachmentFilter(SearchAttachmentFilter.all),
        ),
      );
    }
    if (filters.archivedOnly) {
      chips.add(
        _filterSummaryChip(
          context,
          label: strings.localized(
            en: 'Archive',
            ja: 'アーカイブ',
            zh: '归档',
            ko: '아카이브',
            es: 'Archivo',
            de: 'Archiv',
          ),
          onDeleted: () => notifier.setArchivedOnly(false),
        ),
      );
    }
    if (filters.includeArchived) {
      chips.add(
        _filterSummaryChip(
          context,
          label: strings.localized(
            en: 'Normal + archive',
            ja: '通常 + アーカイブ',
            zh: '普通 + 归档',
            ko: '일반 + 아카이브',
            es: 'Normal + archivo',
            de: 'Normal + Archiv',
          ),
          onDeleted: () => notifier.setIncludeArchived(false),
        ),
      );
    }
    if (filters.dateRange != SearchDateRange.all) {
      chips.add(
        _filterSummaryChip(
          context,
          label:
              '${_dateRangeLabel(strings, filters.dateRange)} / ${_dateFieldLabel(strings, filters.dateField)}',
          onDeleted: () => notifier.setDateRange(SearchDateRange.all),
        ),
      );
    }
    if (filters.vaultId != null) {
      chips.add(
        _filterSummaryChip(
          context,
          label: _selectedVaultLabel(context, visibleVaults, filters.vaultId!),
          onDeleted: () => notifier.setVault(null),
        ),
      );
    }
    if (filters.year != null) {
      chips.add(
        _filterSummaryChip(
          context,
          label: '${filters.year}',
          onDeleted: () => notifier.setYear(null),
        ),
      );
    }

    if (chips.isEmpty) {
      return const [];
    }
    return [
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: chips),
    ];
  }

  Widget _filterSummaryChip(
    BuildContext context, {
    required String label,
    required VoidCallback onDeleted,
  }) {
    return InputChip(
      label: Text(label),
      avatar: const Icon(Icons.filter_alt_outlined, size: 16),
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
  }

  String _selectedVaultLabel(
    BuildContext context,
    List<VaultBucket> visibleVaults,
    String vaultId,
  ) {
    for (final vault in visibleVaults) {
      if (vault.id == vaultId) {
        return _vaultDisplayName(context, vault);
      }
    }
    return vaultId;
  }

  String _dateRangeLabel(AppStrings strings, SearchDateRange range) {
    return switch (range) {
      SearchDateRange.all => strings.localized(
        en: 'All dates',
        ja: '\u3059\u3079\u3066\u306e\u671f\u9593',
        zh: '\u6240\u6709\u65e5\u671f',
        ko: '\ubaa8\ub4e0 \uae30\uac04',
        es: 'Todas las fechas',
        de: 'Alle Daten',
      ),
      SearchDateRange.last7Days => strings.localized(
        en: 'Last 7 days',
        ja: '\u76f4\u8fd17\u65e5',
        zh: '\u6700\u8fd1 7 \u5929',
        ko: '\ucd5c\uadfc 7\uc77c',
        es: 'Ultimos 7 dias',
        de: 'Letzte 7 Tage',
      ),
      SearchDateRange.last30Days => strings.localized(
        en: 'Last 30 days',
        ja: '\u76f4\u8fd130\u65e5',
        zh: '\u6700\u8fd1 30 \u5929',
        ko: '\ucd5c\uadfc 30\uc77c',
        es: 'Ultimos 30 dias',
        de: 'Letzte 30 Tage',
      ),
      SearchDateRange.thisMonth => strings.localized(
        en: 'This month',
        ja: '\u4eca\u6708',
        zh: '\u672c\u6708',
        ko: '\uc774\ubc88 \ub2ec',
        es: 'Este mes',
        de: 'Dieser Monat',
      ),
    };
  }

  String _dateFieldLabel(AppStrings strings, SearchDateField field) {
    return switch (field) {
      SearchDateField.createdAt => strings.localized(
        en: 'Created date',
        ja: '\u4f5c\u6210\u65e5',
        zh: '\u521b\u5efa\u65e5\u671f',
        ko: '\uc791\uc131\uc77c',
        es: 'Fecha de creacion',
        de: 'Erstellt am',
      ),
      SearchDateField.updatedAt => strings.localized(
        en: 'Updated date',
        ja: '\u66f4\u65b0\u65e5',
        zh: '\u66f4\u65b0\u65e5\u671f',
        ko: '\uc218\uc815\uc77c',
        es: 'Fecha de actualizacion',
        de: 'Geandert am',
      ),
    };
  }

  String _attachmentFilterLabel(
    AppStrings strings,
    SearchAttachmentFilter filter,
  ) {
    return switch (filter) {
      SearchAttachmentFilter.all => strings.localized(
        en: 'All attachments',
        ja: '\u3059\u3079\u3066',
        zh: '\u5168\u90e8',
        ko: '\ubaa8\ub450',
        es: 'Todos',
        de: 'Alle',
      ),
      SearchAttachmentFilter.any => strings.text('home.with.media'),
      SearchAttachmentFilter.photo => strings.localized(
        en: 'Images',
        ja: '\u753b\u50cf',
        zh: '\u56fe\u50cf',
        ko: '\uc774\ubbf8\uc9c0',
        es: 'Imagenes',
        de: 'Bilder',
      ),
      SearchAttachmentFilter.video => strings.localized(
        en: 'Videos',
        ja: '\u52d5\u753b',
        zh: '\u89c6\u9891',
        ko: '\ub3d9\uc601\uc0c1',
        es: 'Videos',
        de: 'Videos',
      ),
      SearchAttachmentFilter.audio => strings.localized(
        en: 'Audio',
        ja: '\u97f3\u58f0',
        zh: '\u97f3\u9891',
        ko: '\uc624\ub514\uc624',
        es: 'Audio',
        de: 'Audio',
      ),
      SearchAttachmentFilter.location => strings.localized(
        en: 'Location',
        ja: '\u4f4d\u7f6e\u60c5\u5831',
        zh: '\u4f4d\u7f6e\u4fe1\u606f',
        ko: '\uc704\uce58 \uc815\ubcf4',
        es: 'Ubicacion',
        de: 'Standort',
      ),
    };
  }

  String _attachmentFilterSummaryLabel(
    AppStrings strings,
    List<SearchAttachmentFilter> filters,
  ) {
    if (filters.isEmpty) {
      return _attachmentFilterLabel(strings, SearchAttachmentFilter.all);
    }
    if (filters.contains(SearchAttachmentFilter.any)) {
      return _attachmentFilterLabel(strings, SearchAttachmentFilter.any);
    }
    return filters
        .map((filter) => _attachmentFilterLabel(strings, filter))
        .join(' / ');
  }

  void _openAdvancedFiltersSheet(
    BuildContext context, {
    required bool hasArchivedNotes,
  }) {
    _pushNoteOverlaySheet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final strings = sheetContext.strings;
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.92;
        return Consumer(
          builder: (context, ref, _) {
            final filters = ref.watch(searchFiltersControllerProvider);
            final notifier = ref.read(searchFiltersControllerProvider.notifier);
            final visibleVaults = ref.watch(visibleVaultsProvider);
            final canFilterVaults = visibleVaults.length > 1;
            if (!canFilterVaults && filters.vaultId != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  notifier.setVault(null);
                }
              });
            }
            final years = ref.watch(visibleNoteYearsProvider);
            final suggestions = ref.watch(visibleTagSuggestionsProvider);
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.text('home.filters'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (!filters.isDefault)
                            TextButton(
                              onPressed: notifier.reset,
                              child: Text(strings.text('home.reset.filters')),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: filters.pinnedOnly,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: Text(strings.text('home.pinned.only')),
                        onChanged: (value) =>
                            notifier.setPinnedOnly(value ?? false),
                      ),
                      _AttachmentSearchFilterControls(
                        filters: filters.attachmentFilters,
                        onHasAttachmentsChanged: (enabled) =>
                            notifier.setAttachmentFilter(
                              enabled
                                  ? SearchAttachmentFilter.any
                                  : SearchAttachmentFilter.all,
                            ),
                        onFilterToggled: notifier.toggleAttachmentFilter,
                      ),
                      const SizedBox(height: 12),
                      _TagAutocompleteField(
                        key: const Key('search-tag-input-sheet'),
                        suggestions: suggestions,
                        label: strings.text('home.filter.by.tag'),
                        hintText: strings.text(
                          'home.add.tags.to.narrow.the.list',
                        ),
                        existingTags: filters.tags,
                        onTagSelected: notifier.addTag,
                        showSubmitAction: true,
                      ),
                      if (filters.tags.length > 1) ...[
                        const SizedBox(height: 10),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text(
                                strings.localized(
                                  en: 'Any tag',
                                  ja: 'いずれかのタグ',
                                  zh: '任一标签',
                                  ko: '태그 중 하나',
                                  es: 'Cualquier etiqueta',
                                  de: 'Ein beliebiger Tag',
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text(
                                strings.localized(
                                  en: 'All tags',
                                  ja: 'すべてのタグ',
                                  zh: '所有标签',
                                  ko: '모든 태그',
                                  es: 'Todas las etiquetas',
                                  de: 'Alle Tags',
                                ),
                              ),
                            ),
                          ],
                          selected: {filters.requireAllTags},
                          onSelectionChanged: (selection) =>
                              notifier.setRequireAllTags(selection.single),
                        ),
                      ],
                      if (filters.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in filters.tags)
                              InputChip(
                                label: Text('#$tag'),
                                onDeleted: () => notifier.removeTag(tag),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<SearchDateRange>(
                        initialValue: filters.dateRange,
                        decoration: InputDecoration(
                          labelText: strings.localized(
                            en: 'Period',
                            ja: '\u671f\u9593',
                            zh: '\u671f\u95f4',
                            ko: '\uae30\uac04',
                            es: 'Periodo',
                            de: 'Zeitraum',
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final range in SearchDateRange.values)
                            DropdownMenuItem(
                              value: range,
                              child: Text(_dateRangeLabel(strings, range)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            notifier.setDateRange(value);
                          }
                        },
                      ),
                      if (filters.dateRange != SearchDateRange.all) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<SearchDateField>(
                          initialValue: filters.dateField,
                          decoration: InputDecoration(
                            labelText: strings.localized(
                              en: 'Date target',
                              ja: '\u65e5\u4ed8\u5bfe\u8c61',
                              zh: '\u65e5\u671f\u5bf9\u8c61',
                              ko: '\ub0a0\uc9dc \uae30\uc900',
                              es: 'Fecha objetivo',
                              de: 'Datumsfeld',
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final field in SearchDateField.values)
                              DropdownMenuItem(
                                value: field,
                                child: Text(_dateFieldLabel(strings, field)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              notifier.setDateField(value);
                            }
                          },
                        ),
                      ],
                      if (hasArchivedNotes ||
                          filters.archivedOnly ||
                          filters.includeArchived) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: filters.archivedOnly
                              ? 1
                              : (filters.includeArchived ? 2 : 0),
                          decoration: InputDecoration(
                            labelText: strings.localized(
                              en: 'Target',
                              ja: '\u5bfe\u8c61',
                              zh: '\u5bf9\u8c61',
                              ko: '\ub300\uc0c1',
                              es: 'Objetivo',
                              de: 'Ziel',
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 0,
                              child: Text(
                                strings.localized(
                                  en: 'Normal notes',
                                  ja: '\u901a\u5e38\u30ce\u30fc\u30c8',
                                  zh: '\u666e\u901a\u7b14\u8bb0',
                                  ko: '\uc77c\ubc18 \uba54\ubaa8',
                                  es: 'Notas normales',
                                  de: 'Normale Notizen',
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text(
                                strings.localized(
                                  en: 'Archive only',
                                  ja: '\u30a2\u30fc\u30ab\u30a4\u30d6\u306e\u307f',
                                  zh: '\u4ec5\u5f52\u6863',
                                  ko: '\uc544\uce74\uc774\ube0c\ub9cc',
                                  es: 'Solo archivo',
                                  de: 'Nur Archiv',
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text(
                                strings.localized(
                                  en: 'Normal + archive',
                                  ja: '\u901a\u5e38 + \u30a2\u30fc\u30ab\u30a4\u30d6',
                                  zh: '\u666e\u901a + \u5f52\u6863',
                                  ko: '\uc77c\ubc18 + \uc544\uce74\uc774\ube0c',
                                  es: 'Normal + archivo',
                                  de: 'Normal + Archiv',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == 1) {
                              notifier.setArchivedOnly(true);
                            } else if (value == 2) {
                              notifier.setIncludeArchived(true);
                            } else {
                              notifier
                                ..setArchivedOnly(false)
                                ..setIncludeArchived(false);
                            }
                          },
                        ),
                      ],
                      if (canFilterVaults) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          key: ValueKey(filters.vaultId ?? 'all-vaults-sheet'),
                          initialValue: filters.vaultId,
                          decoration: InputDecoration(
                            labelText: strings.text('home.vault'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                strings.text('home.all.visible.vaults'),
                              ),
                            ),
                            for (final vault in visibleVaults)
                              DropdownMenuItem<String?>(
                                value: vault.id,
                                child: Text(_vaultDisplayName(context, vault)),
                              ),
                          ],
                          onChanged: notifier.setVault,
                        ),
                      ],
                      if (years.length > 1) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          key: ValueKey(filters.year ?? 'all-years-sheet'),
                          initialValue: filters.year,
                          decoration: InputDecoration(
                            labelText: strings.text('home.year.partition'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem<int?>(
                              value: null,
                              child: Text(strings.text('home.all.years')),
                            ),
                            for (final year in years)
                              DropdownMenuItem<int?>(
                                value: year,
                                child: Text('$year'),
                              ),
                          ],
                          onChanged: notifier.setYear,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(strings.close),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_popNoteOverlaySheet);
  }
}

class _QuickTagStrip extends StatelessWidget {
  const _QuickTagStrip({
    required this.summaries,
    required this.activeTags,
    required this.onTagSelected,
  });

  final List<VisibleTagSummary> summaries;
  final List<String> activeTags;
  final ValueChanged<String> onTagSelected;

  @override
  Widget build(BuildContext context) {
    final activeKeys = activeTags.map(canonicalizeNoteTag).toSet();
    final visibleSummaries = summaries.take(10).toList(growable: false);
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: ScrollConfiguration(
        behavior: const _HorizontalMouseDragScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          itemCount: visibleSummaries.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final summary = visibleSummaries[index];
            return Center(
              child: _QuickTagChip(
                summary: summary,
                selected: activeKeys.contains(
                  canonicalizeNoteTag(summary.name),
                ),
                onTap: () => onTagSelected(summary.name),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HorizontalMouseDragScrollBehavior extends MaterialScrollBehavior {
  const _HorizontalMouseDragScrollBehavior();

  @override
  Set<ui.PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    ui.PointerDeviceKind.mouse,
  };
}

class _QuickTagChip extends StatelessWidget {
  const _QuickTagChip({
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
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: selected ? colorScheme.onPrimaryContainer : null,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return Tooltip(
      message: '#${summary.name}',
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? colorScheme.primary : theme.dividerColor,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tag_rounded,
                  size: 15,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${summary.name} (${summary.count})',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: labelStyle,
                  strutStyle: labelStyle == null
                      ? null
                      : StrutStyle.fromTextStyle(
                          labelStyle,
                          forceStrutHeight: true,
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

class _AttachmentSearchFilterControls extends StatelessWidget {
  const _AttachmentSearchFilterControls({
    required this.filters,
    required this.onHasAttachmentsChanged,
    required this.onFilterToggled,
  });

  final List<SearchAttachmentFilter> filters;
  final ValueChanged<bool> onHasAttachmentsChanged;
  final ValueChanged<SearchAttachmentFilter> onFilterToggled;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final hasAttachmentFilter = filters.isNotEmpty;
    final selectedFilters = filters.isEmpty
        ? const <SearchAttachmentFilter>[SearchAttachmentFilter.any]
        : filters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: hasAttachmentFilter,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(
            strings.localized(
              en: 'Has attachments',
              ja: '\u6dfb\u4ed8\u3042\u308a',
              zh: '\u6709\u9644\u4ef6',
              ko: '\ucca8\ubd80 \uc788\uc74c',
              es: 'Con adjuntos',
              de: 'Mit Anhangen',
            ),
          ),
          onChanged: (value) => onHasAttachmentsChanged(value == true),
        ),
        if (hasAttachmentFilter) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const [
                SearchAttachmentFilter.any,
                SearchAttachmentFilter.photo,
                SearchAttachmentFilter.video,
                SearchAttachmentFilter.audio,
                SearchAttachmentFilter.location,
              ])
                ChoiceChip(
                  avatar: Icon(_attachmentSearchFilterIcon(option), size: 18),
                  label: Text(_attachmentSearchFilterLabel(strings, option)),
                  selected: selectedFilters.contains(option),
                  onSelected: (_) => onFilterToggled(option),
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _attachmentSearchFilterLabel(
  AppStrings strings,
  SearchAttachmentFilter filter,
) {
  return switch (filter) {
    SearchAttachmentFilter.all => strings.localized(
      en: 'All attachments',
      ja: '\u3059\u3079\u3066',
      zh: '\u5168\u90e8',
      ko: '\ubaa8\ub450',
      es: 'Todos',
      de: 'Alle',
    ),
    SearchAttachmentFilter.any => strings.localized(
      en: 'Any',
      ja: '\u3059\u3079\u3066',
      zh: '\u5168\u90e8',
      ko: '\ubaa8\ub450',
      es: 'Cualquiera',
      de: 'Alle',
    ),
    SearchAttachmentFilter.photo => strings.localized(
      en: 'Images',
      ja: '\u753b\u50cf',
      zh: '\u56fe\u50cf',
      ko: '\uc774\ubbf8\uc9c0',
      es: 'Imagenes',
      de: 'Bilder',
    ),
    SearchAttachmentFilter.video => strings.localized(
      en: 'Videos',
      ja: '\u52d5\u753b',
      zh: '\u89c6\u9891',
      ko: '\ub3d9\uc601\uc0c1',
      es: 'Videos',
      de: 'Videos',
    ),
    SearchAttachmentFilter.audio => strings.localized(
      en: 'Audio',
      ja: '\u97f3\u58f0',
      zh: '\u97f3\u9891',
      ko: '\uc624\ub514\uc624',
      es: 'Audio',
      de: 'Audio',
    ),
    SearchAttachmentFilter.location => strings.localized(
      en: 'Location',
      ja: '\u4f4d\u7f6e\u60c5\u5831',
      zh: '\u4f4d\u7f6e\u4fe1\u606f',
      ko: '\uc704\uce58 \uc815\ubcf4',
      es: 'Ubicacion',
      de: 'Standort',
    ),
  };
}

IconData _attachmentSearchFilterIcon(SearchAttachmentFilter filter) {
  return switch (filter) {
    SearchAttachmentFilter.all => Icons.attach_file_rounded,
    SearchAttachmentFilter.any => Icons.attach_file_rounded,
    SearchAttachmentFilter.photo => Icons.image_outlined,
    SearchAttachmentFilter.video => Icons.movie_outlined,
    SearchAttachmentFilter.audio => Icons.mic_none_rounded,
    SearchAttachmentFilter.location => Icons.location_on_outlined,
  };
}

class _FilterCountBadge extends StatelessWidget {
  const _FilterCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 20,
      constraints: const BoxConstraints(minWidth: 20),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.surface, width: 1.5),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 16), label: Text(text));
  }
}

class _NoteTagChip extends StatelessWidget {
  const _NoteTagChip({required this.tag, this.onTap, this.compact = false});

  final String tag;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = '#$tag';
    final chipLabel = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall,
    );
    if (onTap == null) {
      return Chip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        side: BorderSide(color: Theme.of(context).dividerColor),
        label: chipLabel,
      );
    }
    return ActionChip(
      label: chipLabel,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
  }
}

class _TagAutocompleteField extends StatefulWidget {
  const _TagAutocompleteField({
    super.key,
    required this.suggestions,
    required this.label,
    required this.hintText,
    required this.existingTags,
    required this.onTagSelected,
    this.showSubmitAction = false,
  });

  final List<String> suggestions;
  final String label;
  final String hintText;
  final List<String> existingTags;
  final ValueChanged<String> onTagSelected;
  final bool showSubmitAction;

  @override
  State<_TagAutocompleteField> createState() => _TagAutocompleteFieldState();
}

class _TagAutocompleteFieldState extends State<_TagAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late Set<String> _existingTagKeys;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
    _existingTagKeys = _currentExistingTagKeys();
  }

  @override
  void didUpdateWidget(covariant _TagAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKeys = _currentExistingTagKeys();
    if (_setEquals(_existingTagKeys, nextKeys)) {
      return;
    }
    _existingTagKeys = nextKeys;
    final currentTag = canonicalizeNoteTag(_controller.text);
    if (currentTag.isNotEmpty && nextKeys.contains(currentTag)) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    setState(() {});
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _submitTag(String raw) {
    final normalized = normalizeNoteTag(raw);
    if (normalized.isEmpty) {
      return;
    }
    final existingKeys = _currentExistingTagKeys();
    if (existingKeys.contains(canonicalizeNoteTag(normalized))) {
      _controller.clear();
      return;
    }
    widget.onTagSelected(normalized);
    _controller.clear();
  }

  bool get _canSubmitCurrentText {
    final normalized = normalizeNoteTag(_controller.text);
    return normalized.isNotEmpty &&
        !_currentExistingTagKeys().contains(canonicalizeNoteTag(normalized));
  }

  Set<String> _currentExistingTagKeys() {
    return widget.existingTags
        .map(canonicalizeNoteTag)
        .where((tag) => tag.isNotEmpty)
        .toSet();
  }

  bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    return left.containsAll(right);
  }

  List<String> _matchingSuggestions() {
    final existingKeys = _currentExistingTagKeys();
    final seenKeys = <String>{};
    final input = canonicalizeNoteTag(_controller.text);
    final matches = <String>[];
    for (final tag in widget.suggestions) {
      final key = canonicalizeNoteTag(tag);
      if (key.isEmpty || existingKeys.contains(key) || !seenKeys.add(key)) {
        continue;
      }
      if (input.isNotEmpty && !key.contains(input)) {
        continue;
      }
      matches.add(tag);
      if (matches.length == 8) {
        break;
      }
    }
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final matches = _focusNode.hasFocus
        ? _matchingSuggestions()
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(Icons.sell_outlined),
            suffixIcon: widget.showSubmitAction && _canSubmitCurrentText
                ? IconButton(
                    tooltip: MaterialLocalizations.of(context).okButtonLabel,
                    icon: const Icon(Icons.check_rounded),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _submitTag(_controller.text),
                  )
                : null,
          ),
          onFieldSubmitted: _submitTag,
        ),
        if (matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  children: [
                    for (final option in matches)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.sell_outlined, size: 18),
                        title: Text(option),
                        onTap: () {
                          _submitTag(option);
                          _focusNode.requestFocus();
                        },
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

class _CalendarNoteRow extends StatelessWidget {
  const _CalendarNoteRow({
    required this.note,
    required this.vaultName,
    required this.onTap,
  });

  final NoteEntry note;
  final String vaultName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bodyPreview = _normalizePreviewText(note.body, maxChars: 320);
    final hasDistinctBody =
        bodyPreview.isNotEmpty && bodyPreview != note.title.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _mutedTextColor(context),
                ),
              ],
            ),
            if (hasDistinctBody) ...[
              const SizedBox(height: 4),
              Text(
                bodyPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _strongMutedTextColor(context),
                ),
              ),
            ],
            if (note.attachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (
                    var i = 0;
                    i < note.attachments.length && i < 3;
                    i++
                  ) ...[
                    Padding(
                      padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                      child: _AttachmentPreview(
                        attachment: note.attachments[i],
                        size: 56,
                      ),
                    ),
                  ],
                  if (note.attachments.length > 3) ...[
                    Container(
                      width: 56,
                      height: 56,
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
                        '+${note.attachments.length - 3}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              vaultName,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDayNotesList extends ConsumerWidget {
  const _CalendarDayNotesList({
    required this.notes,
    required this.itemCount,
    required this.expanded,
    required this.onTap,
  });

  final List<NoteEntry> notes;
  final int itemCount;
  final bool expanded;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dividerColor = Theme.of(context).dividerColor;
    final cappedItemCount = itemCount.clamp(0, notes.length);

    Widget buildRow(int index) {
      final note = notes[index];
      return _CalendarNoteRow(
        note: note,
        vaultName: ref.watch(vaultByIdProvider(note.vaultId)).name,
        onTap: () => onTap(index),
      );
    }

    if (!expanded) {
      return Column(
        children: [
          for (var index = 0; index < cappedItemCount; index++) ...[
            buildRow(index),
            if (index != cappedItemCount - 1)
              Divider(height: 24, color: dividerColor),
          ],
        ],
      );
    }

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final listHeight = math.min(560.0, math.max(280.0, viewportHeight * 0.55));
    return SizedBox(
      height: listHeight,
      child: ListView.separated(
        primary: false,
        itemCount: cappedItemCount,
        separatorBuilder: (context, index) =>
            Divider(height: 24, color: dividerColor),
        itemBuilder: (context, index) => buildRow(index),
      ),
    );
  }
}

class _EmptyNotesState extends StatelessWidget {
  const _EmptyNotesState();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.emptyNotesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.emptyNotesBody,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
          ),
        ],
      ),
    );
  }
}

class _EmptyNoteSelectionState extends StatelessWidget {
  const _EmptyNoteSelectionState();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('home.select.a.note'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.text('home.pick.a.note.from.the.list.to.preview.it.here'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
          ),
        ],
      ),
    );
  }
}

class _RichBlockDraft {
  _RichBlockDraft.paragraph([String text = ''])
    : type = NoteBlockType.paragraph,
      controller = TextEditingController(text: text),
      focusNode = FocusNode(),
      attachment = null;

  _RichBlockDraft.attachment(NoteAttachment value)
    : type = switch (value.type) {
        AttachmentType.photo => NoteBlockType.photo,
        AttachmentType.video => NoteBlockType.video,
        AttachmentType.audio => NoteBlockType.audio,
        AttachmentType.file => NoteBlockType.file,
      },
      controller = null,
      focusNode = null,
      attachment = value;

  final NoteBlockType type;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final NoteAttachment? attachment;

  void dispose() {
    controller?.dispose();
    focusNode?.dispose();
  }
}

class _NoteEditorSheet extends ConsumerStatefulWidget {
  const _NoteEditorSheet({
    this.note,
    this.initialCreatedAt,
    this.initialTags = const <String>[],
  });

  final NoteEntry? note;
  final DateTime? initialCreatedAt;
  final List<String> initialTags;

  @override
  ConsumerState<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends ConsumerState<_NoteEditorSheet> {
  late final TextEditingController _contentController;
  late final FocusNode _quickContentFocusNode;
  late final NoteEditorDraftStore _draftStore;
  late final EncryptedAttachmentStore _attachmentStore;
  late DateTime _createdAt;
  late bool _isPinned;
  late NoteEditorMode _editorMode;
  late List<NoteAttachment> _attachments;
  late List<String> _tags;
  late List<_RichBlockDraft> _richBlocks;
  late final Set<String> _initialAttachmentPaths;
  late final ValueNotifier<bool> _canSubmitNotifier;
  late bool _captureLocationEnabled;
  final Set<String> _pendingAttachmentDeletes = <String>{};
  int? _activeRichParagraphIndex;
  String? _selectedVaultId;
  NoteLocation? _location;
  bool _locationBusy = false;
  bool _saved = false;
  bool _draftLoaded = false;
  bool _editorDisposed = false;
  Timer? _draftSaveTimer;
  bool _discardingDraft = false;
  bool _draftRestoreSnackBarActive = false;

  @override
  void initState() {
    super.initState();
    _draftStore = ref.read(noteEditorDraftStoreProvider);
    _attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    final lastSettings = ref.read(lastNoteEditorSettingsControllerProvider);
    _contentController = TextEditingController(text: _composeEditorContent());
    _canSubmitNotifier = ValueNotifier<bool>(false);
    _quickContentFocusNode = FocusNode();
    _contentController.addListener(_handleTextChanged);
    _createdAt =
        widget.note?.createdAt ?? widget.initialCreatedAt ?? DateTime.now();
    _isPinned = widget.note?.isPinned ?? false;
    _editorMode =
        widget.note?.editorMode ??
        ((widget.note?.blocks.isNotEmpty ?? false)
            ? NoteEditorMode.rich
            : lastSettings.mode);
    _captureLocationEnabled =
        widget.note == null && lastSettings.captureLocation;
    _location = widget.note?.location;
    _attachments = [...?widget.note?.attachments];
    _tags = widget.note == null
        ? dedupeNoteTags(widget.initialTags).toList(growable: true)
        : [...?widget.note?.tags];
    _richBlocks = _buildInitialRichBlocks();
    for (final block in _richBlocks) {
      _attachRichBlockListener(block);
    }
    _activeRichParagraphIndex = _richBlocks.indexWhere(
      (block) => block.type == NoteBlockType.paragraph,
    );
    _updateCanSubmit();
    _initialAttachmentPaths = _attachments
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    _selectedVaultId = widget.note?.vaultId ?? _initialNewNoteVaultId();
    _scheduleInitialEditorFocus();
    if (widget.note == null) {
      unawaited(_restoreDraftIfAny());
      if (_captureLocationEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _location == null) {
            unawaited(_captureCurrentLocationForNote(showErrors: false));
          }
        });
      }
    }
  }

  String _initialNewNoteVaultId() {
    final unlockedVaultId = ref.read(unlockedPrivateProfileVaultIdProvider);
    if (unlockedVaultId != null) {
      return unlockedVaultId;
    }
    return ref.read(lastNoteEditorSettingsControllerProvider).vaultId;
  }

  VaultBucket _privateTargetFor(
    String vaultId,
    List<PrivateMemoProfile> privateProfiles,
  ) {
    if (vaultId == legacyPrivateVaultId) {
      return VaultBucket(
        id: legacyPrivateVaultId,
        name: context.strings.text('home.private.profile'),
        description: context.strings.unlockedPrivateNotes,
      );
    }
    for (final profile in privateProfiles) {
      if (profile.vaultId == vaultId) {
        return VaultBucket(
          id: profile.vaultId,
          name: profile.name,
          description: context.strings.unlockedPrivateNotes,
        );
      }
    }
    return VaultBucket(
      id: vaultId,
      name: context.strings.text('home.private.profile'),
      description: context.strings.unlockedPrivateNotes,
    );
  }

  @override
  void dispose() {
    _editorDisposed = true;
    _draftSaveTimer?.cancel();
    if (_draftRestoreSnackBarActive) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
    final shouldKeepDraft = !_saved && widget.note == null && _hasDraftContent;
    if (shouldKeepDraft && _selectedVaultId != null) {
      unawaited(
        _draftStore.save(
          NoteEditorDraftSnapshot(
            createdAt: _createdAt,
            isPinned: _isPinned,
            editorMode: _editorMode,
            vaultId: _selectedVaultId!,
            tags: _tags,
            quickContent: _contentController.text,
            quickAttachments: _attachments,
            richBlocks: _richBlocksToNoteBlocks(),
            location: _location,
          ),
        ),
      );
    } else if (!_saved && widget.note == null) {
      unawaited(_draftStore.clear());
    }
    if (!_saved) {
      for (final filePath in _pendingAttachmentDeletes) {
        unawaited(_attachmentStore.deleteAttachment(filePath));
      }
      if (!shouldKeepDraft) {
        for (final attachment in _allCurrentAttachments) {
          final filePath = attachment.filePath;
          if (filePath == null || _initialAttachmentPaths.contains(filePath)) {
            continue;
          }
          unawaited(_attachmentStore.deleteAttachment(filePath));
        }
      }
    }
    _contentController.removeListener(_handleTextChanged);
    _contentController.dispose();
    _quickContentFocusNode.dispose();
    _canSubmitNotifier.dispose();
    for (final block in _richBlocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _handleTextChanged() {
    _scheduleDraftPersist();
    _updateCanSubmit();
  }

  void _updateCanSubmit() {
    if (_editorDisposed) {
      return;
    }
    final next = _hasSubmitContent;
    if (_canSubmitNotifier.value != next) {
      _canSubmitNotifier.value = next;
    }
  }

  String _composeEditorContent() {
    final title = widget.note?.title.trim() ?? '';
    final body = widget.note?.body.trim() ?? '';
    if (title.isEmpty) {
      return body;
    }
    if (body.isEmpty) {
      return title;
    }
    return '$title\n$body';
  }

  List<_RichBlockDraft> _buildInitialRichBlocks() {
    final sourceBlocks = widget.note?.blocks.isNotEmpty == true
        ? widget.note!.blocks
        : _legacyBlocksFromNote(
            widget.note ??
                NoteEntry(
                  id: 'draft',
                  vaultId: 'everyday',
                  title: '',
                  body: _composeEditorContent(),
                  createdAt: DateTime.now(),
                  attachments: [...?widget.note?.attachments],
                ),
          );
    final drafts = <_RichBlockDraft>[];
    for (final block in sourceBlocks) {
      switch (block.type) {
        case NoteBlockType.paragraph:
          drafts.add(_RichBlockDraft.paragraph(block.text ?? ''));
        case NoteBlockType.photo:
        case NoteBlockType.video:
        case NoteBlockType.audio:
        case NoteBlockType.file:
          if (block.attachment != null) {
            drafts.add(_RichBlockDraft.attachment(block.attachment!));
          }
      }
    }
    if (drafts.isEmpty) {
      drafts.add(_RichBlockDraft.paragraph());
    }
    return drafts;
  }

  List<_RichBlockDraft> _buildRichBlocksFromQuickMemo() {
    final content = _contentController.text.trim();
    final drafts = <_RichBlockDraft>[];
    if (content.isNotEmpty) {
      drafts.add(_RichBlockDraft.paragraph(content));
    }
    for (final attachment in _attachments) {
      drafts.add(_RichBlockDraft.attachment(attachment));
    }
    if (drafts.isEmpty || drafts.last.type != NoteBlockType.paragraph) {
      drafts.add(_RichBlockDraft.paragraph());
    }
    return drafts;
  }

  void _replaceRichBlocks(List<_RichBlockDraft> nextBlocks) {
    for (final block in _richBlocks) {
      block.dispose();
    }
    _richBlocks = nextBlocks.isEmpty
        ? [_RichBlockDraft.paragraph()]
        : nextBlocks;
    for (final block in _richBlocks) {
      _attachRichBlockListener(block);
    }
    _activeRichParagraphIndex = _richBlocks.indexWhere(
      (block) => block.type == NoteBlockType.paragraph,
    );
  }

  void _attachRichBlockListener(_RichBlockDraft block) {
    block.controller?.addListener(_handleTextChanged);
    block.focusNode?.addListener(() {
      if (!mounted || !(block.focusNode?.hasFocus ?? false)) {
        return;
      }
      final index = _richBlocks.indexOf(block);
      if (index == -1 || _activeRichParagraphIndex == index) {
        return;
      }
      setState(() {
        _activeRichParagraphIndex = index;
      });
    });
  }

  Future<void> _restoreDraftIfAny() async {
    if (_draftLoaded) {
      return;
    }
    _draftLoaded = true;
    final draft = await ref.read(noteEditorDraftStoreProvider).load();
    if (!mounted || draft == null) {
      return;
    }
    if (!_draftHasContent(draft)) {
      await ref.read(noteEditorDraftStoreProvider).clear();
      return;
    }
    setState(() {
      _createdAt = draft.createdAt;
      _isPinned = draft.isPinned;
      _editorMode = draft.editorMode;
      _selectedVaultId = draft.vaultId;
      _tags = [...draft.tags];
      _location = draft.location;
      _contentController.text = draft.quickContent;
      _attachments = [...draft.quickAttachments];
      for (final block in _richBlocks) {
        block.dispose();
      }
      _richBlocks = [
        for (final block in draft.richBlocks)
          if (block.type == NoteBlockType.paragraph)
            _RichBlockDraft.paragraph(block.text ?? '')
          else if (block.attachment != null)
            _RichBlockDraft.attachment(block.attachment!),
      ];
      if (_richBlocks.isEmpty) {
        _richBlocks = [_RichBlockDraft.paragraph()];
      }
      for (final block in _richBlocks) {
        _attachRichBlockListener(block);
      }
      _activeRichParagraphIndex = _richBlocks.indexWhere(
        (block) => block.type == NoteBlockType.paragraph,
      );
    });
    if (!mounted) {
      return;
    }
    _scheduleInitialEditorFocus();
    _showEditorSnackBar(
      content: Text(context.strings.draftRestored),
      action: SnackBarAction(
        label: context.strings.discardDraft,
        onPressed: _discardRestoredDraft,
      ),
    );
    _draftRestoreSnackBarActive = true;
  }

  void _discardRestoredDraft() {
    if (!mounted || _editorDisposed) {
      return;
    }
    _discardingDraft = true;
    _draftSaveTimer?.cancel();
    unawaited(ref.read(noteEditorDraftStoreProvider).clear());
    for (final attachment in _allCurrentAttachments) {
      final filePath = attachment.filePath;
      if (filePath == null || _initialAttachmentPaths.contains(filePath)) {
        continue;
      }
      unawaited(_attachmentStore.deleteAttachment(filePath));
    }
    setState(() {
      _createdAt = DateTime.now();
      _isPinned = false;
      _tags = [];
      _attachments = [];
      _contentController.clear();
      _replaceRichBlocks([_RichBlockDraft.paragraph()]);
    });
    _discardingDraft = false;
    _draftRestoreSnackBarActive = false;
    _updateCanSubmit();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _scheduleInitialEditorFocus();
  }

  void _scheduleDraftPersist() {
    _updateCanSubmit();
    if (widget.note != null || _discardingDraft) {
      return;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _editorDisposed) {
        return;
      }
      final vaultId = _selectedVaultId;
      if (vaultId == null) {
        return;
      }
      final snapshot = NoteEditorDraftSnapshot(
        createdAt: _createdAt,
        isPinned: _isPinned,
        editorMode: _editorMode,
        vaultId: vaultId,
        tags: _tags,
        quickContent: _contentController.text,
        quickAttachments: _attachments,
        richBlocks: _richBlocksToNoteBlocks(),
        location: _location,
      );
      if (!_draftHasContent(snapshot)) {
        unawaited(ref.read(noteEditorDraftStoreProvider).clear());
        return;
      }
      ref.read(noteEditorDraftStoreProvider).save(snapshot);
    });
  }

  bool _draftHasContent(NoteEditorDraftSnapshot draft) {
    if (draft.quickContent.trim().isNotEmpty ||
        draft.quickAttachments.isNotEmpty) {
      return true;
    }
    for (final block in draft.richBlocks) {
      if ((block.text ?? '').trim().isNotEmpty || block.attachment != null) {
        return true;
      }
    }
    return false;
  }

  int _resolveRichInsertionIndex() {
    final activeIndex = _activeRichParagraphIndex;
    if (activeIndex != null &&
        activeIndex >= 0 &&
        activeIndex < _richBlocks.length &&
        _richBlocks[activeIndex].type == NoteBlockType.paragraph) {
      return activeIndex;
    }
    final lastParagraphIndex = _richBlocks.lastIndexWhere(
      (block) => block.type == NoteBlockType.paragraph,
    );
    return lastParagraphIndex == -1 ? _richBlocks.length : lastParagraphIndex;
  }

  void _scheduleInitialEditorFocus() {
    if (!mounted || _editorDisposed || widget.note != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editorDisposed) {
        return;
      }
      if (_editorMode == NoteEditorMode.quick) {
        if (!_quickContentFocusNode.canRequestFocus) {
          return;
        }
        _quickContentFocusNode.requestFocus();
        final textLength = _contentController.text.length;
        _contentController.selection = TextSelection.collapsed(
          offset: textLength,
        );
        return;
      }
      final paragraphIndex = _richBlocks.indexWhere(
        (block) => block.type == NoteBlockType.paragraph,
      );
      if (paragraphIndex == -1) {
        return;
      }
      final paragraphToFocus = _richBlocks[paragraphIndex];
      _requestParagraphFocus(
        paragraphToFocus,
        paragraphToFocus.controller?.text.length ?? 0,
      );
    });
  }

  void _requestParagraphFocus(_RichBlockDraft block, int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editorDisposed || !_richBlocks.contains(block)) {
        return;
      }
      final controller = block.controller;
      final focusNode = block.focusNode;
      if (controller == null ||
          focusNode == null ||
          !focusNode.canRequestFocus) {
        return;
      }
      focusNode.requestFocus();
      final clampedOffset = offset.clamp(0, controller.text.length);
      controller.selection = TextSelection.collapsed(offset: clampedOffset);
    });
  }

  List<NoteAttachment> get _allCurrentAttachments {
    if (_editorMode == NoteEditorMode.quick) {
      return _attachments;
    }
    return [
      for (final block in _richBlocks)
        if (block.attachment != null) block.attachment!,
    ];
  }

  String _deriveRichPlainText() {
    return _richBlocks
        .map((block) => block.controller?.text.trim())
        .whereType<String>()
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  void _switchEditorMode(NoteEditorMode nextMode) {
    if (nextMode == _editorMode) {
      return;
    }
    _RichBlockDraft? paragraphToFocus;
    setState(() {
      final previousMode = _editorMode;
      if (previousMode == NoteEditorMode.quick &&
          nextMode == NoteEditorMode.rich) {
        _replaceRichBlocks(_buildRichBlocksFromQuickMemo());
        final paragraphIndex = _activeRichParagraphIndex;
        if (paragraphIndex != null &&
            paragraphIndex >= 0 &&
            paragraphIndex < _richBlocks.length) {
          paragraphToFocus = _richBlocks[paragraphIndex];
        }
      } else if (previousMode == NoteEditorMode.rich &&
          nextMode == NoteEditorMode.quick) {
        _contentController.text = _deriveRichPlainText();
        _attachments = _allCurrentAttachments;
      }
      _editorMode = nextMode;
    });
    if (nextMode == NoteEditorMode.quick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _quickContentFocusNode.requestFocus();
        final textLength = _contentController.text.length;
        _contentController.selection = TextSelection.collapsed(
          offset: textLength,
        );
      });
    } else if (paragraphToFocus != null) {
      _requestParagraphFocus(
        paragraphToFocus!,
        paragraphToFocus!.controller?.text.length ?? 0,
      );
    }
    _scheduleDraftPersist();
  }

  bool get _hasDraftContent {
    if (_editorMode == NoteEditorMode.quick) {
      final content = _splitMemoContent(_contentController.text);
      return content.title.isNotEmpty ||
          content.body.isNotEmpty ||
          _attachments.isNotEmpty ||
          _tags.isNotEmpty ||
          _isPinned;
    }
    return _deriveRichTitle().isNotEmpty ||
        _deriveRichBody().isNotEmpty ||
        _allCurrentAttachments.isNotEmpty ||
        _tags.isNotEmpty ||
        _isPinned;
  }

  void _queueAttachmentDelete(NoteAttachment attachment) {
    final filePath = attachment.filePath;
    if (filePath == null || _initialAttachmentPaths.contains(filePath)) {
      return;
    }
    _pendingAttachmentDeletes.add(filePath);
  }

  void _cancelAttachmentDelete(NoteAttachment attachment) {
    final filePath = attachment.filePath;
    if (filePath == null) {
      return;
    }
    _pendingAttachmentDeletes.remove(filePath);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final privateProfiles = ref.watch(privateMemoProfilesControllerProvider);
    final accessiblePrivateVaultIds = ref.watch(
      accessiblePrivateVaultIdsProvider,
    );
    final adminMode = ref.watch(adminModeSessionControllerProvider);
    final privateTargets = <VaultBucket>[
      for (final vaultId in accessiblePrivateVaultIds)
        _privateTargetFor(vaultId, privateProfiles),
    ];
    final hasPrivateTargets = privateTargets.isNotEmpty;
    _selectedVaultId ??= widget.note?.vaultId ?? 'everyday';
    if (_selectedVaultId != 'everyday' &&
        !privateTargets.any((vault) => vault.id == _selectedVaultId)) {
      _selectedVaultId = 'everyday';
    }
    final isPrivateSelection = _selectedVaultId != 'everyday';
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _pickDateTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_createdAt.year}/${_createdAt.month.toString().padLeft(2, '0')}/${_createdAt.day.toString().padLeft(2, '0')} ${_createdAt.hour.toString().padLeft(2, '0')}:${_createdAt.minute.toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: _mutedTextColor(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        PopupMenuButton<NoteEditorMode>(
                          tooltip: _editorMode == NoteEditorMode.quick
                              ? strings.quickMemo
                              : strings.richMemo,
                          offset: const Offset(0, 8),
                          onSelected: _switchEditorMode,
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: NoteEditorMode.quick,
                              child: _MediaMenuEntry(
                                icon: _editorMode == NoteEditorMode.quick
                                    ? Icons.check_rounded
                                    : Icons.notes_outlined,
                                label: strings.quickMemo,
                              ),
                            ),
                            PopupMenuItem(
                              value: NoteEditorMode.rich,
                              child: _MediaMenuEntry(
                                icon: _editorMode == NoteEditorMode.rich
                                    ? Icons.check_rounded
                                    : Icons.view_stream_outlined,
                                label: strings.richMemo,
                              ),
                            ),
                          ],
                          child: _EditorModeButton(
                            mode: _editorMode,
                            strings: strings,
                          ),
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: strings.pinThisNote,
                              onPressed: () {
                                setState(() {
                                  _isPinned = !_isPinned;
                                });
                                _scheduleDraftPersist();
                              },
                              icon: Icon(
                                _isPinned
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                color: _isPinned
                                    ? Theme.of(context).colorScheme.primary
                                    : _mutedTextColor(context),
                              ),
                            ),
                            IconButton(
                              tooltip: _captureLocationEnabled
                                  ? strings.currentLocationLabel
                                  : strings.addCurrentLocation,
                              onPressed: _locationBusy
                                  ? null
                                  : _toggleLocationCapture,
                              icon: _locationBusy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _location != null
                                          ? Icons.my_location_rounded
                                          : Icons.my_location_outlined,
                                      color:
                                          _captureLocationEnabled ||
                                              _location != null
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : _mutedTextColor(context),
                                    ),
                            ),
                            PopupMenuButton<MediaImportAction>(
                              key: const Key('note-capture-media-menu'),
                              tooltip: strings.captureMedia,
                              icon: Icon(
                                Icons.photo_camera_outlined,
                                color: _mutedTextColor(context),
                              ),
                              onSelected: _handleAttachmentAction,
                              itemBuilder: (context) => [
                                if (!kIsWeb)
                                  PopupMenuItem(
                                    value: MediaImportAction.takePhoto,
                                    child: _MediaMenuEntry(
                                      icon: Icons.photo_camera_outlined,
                                      label: strings.takePhoto,
                                    ),
                                  ),
                                if (!kIsWeb)
                                  PopupMenuItem(
                                    value: MediaImportAction.recordVideo,
                                    child: _MediaMenuEntry(
                                      icon: Icons.videocam_outlined,
                                      label: strings.recordVideo,
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: MediaImportAction.recordAudio,
                                  child: _MediaMenuEntry(
                                    icon: Icons.mic_none_rounded,
                                    label: strings.recordAudio,
                                  ),
                                ),
                              ],
                            ),
                            PopupMenuButton<MediaImportAction>(
                              key: const Key('note-import-file-menu'),
                              tooltip: strings.importFiles,
                              icon: Icon(
                                Icons.folder_open_outlined,
                                color: _mutedTextColor(context),
                              ),
                              onSelected: _handleAttachmentAction,
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: MediaImportAction.pickPhoto,
                                  child: _MediaMenuEntry(
                                    icon: Icons.photo_library_outlined,
                                    label: strings.pickPhoto,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: MediaImportAction.pickVideo,
                                  child: _MediaMenuEntry(
                                    icon: Icons.video_library_outlined,
                                    label: strings.pickVideo,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: MediaImportAction.pickAudio,
                                  child: _MediaMenuEntry(
                                    icon: Icons.graphic_eq_rounded,
                                    label: strings.pickAudio,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: MediaImportAction.pickFile,
                                  child: _MediaMenuEntry(
                                    icon: Icons.insert_drive_file_outlined,
                                    label: strings.pickFile,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  top: keyboardVisible ? 12 : 0,
                  bottom: keyboardVisible ? 120 : 96,
                ),
                children: [
                  if (_editorMode == NoteEditorMode.quick) ...[
                    Container(
                      decoration: _sectionDecoration(context),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.memoLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('note-content-input'),
                            controller: _contentController,
                            focusNode: _quickContentFocusNode,
                            autofocus: widget.note == null,
                            minLines: 10,
                            maxLines: null,
                            scrollPadding: const EdgeInsets.only(
                              top: 96,
                              left: 20,
                              right: 20,
                              bottom: 96,
                            ),
                            decoration: InputDecoration(
                              labelText: strings.memoLabel,
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.never,
                              hintText: strings.memoFirstLineHint,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Container(
                      decoration: _sectionDecoration(context),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.memoLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          _RichMemoEditor(
                            blocks: _richBlocks,
                            strings: strings,
                            onRemoveBlock: _removeRichBlock,
                            onBackspaceAtParagraphStart:
                                _removeMediaBeforeParagraph,
                            onMoveBlock: _moveRichBlock,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_editorMode == NoteEditorMode.quick)
                    _QuickAttachmentSection(
                      strings: strings,
                      attachments: _attachments,
                      onRemove: _removeQuickAttachmentAt,
                      onMove: _moveQuickAttachment,
                    ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: _sectionDecoration(context),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text('home.tags'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        _TagAutocompleteField(
                          key: const Key('note-tag-input'),
                          suggestions: ref.watch(visibleTagSuggestionsProvider),
                          label: strings.text('home.add.a.tag'),
                          hintText: strings.text(
                            'home.type.a.tag.and.press.enter',
                          ),
                          existingTags: _tags,
                          showSubmitAction: true,
                          onTagSelected: (tag) {
                            setState(() {
                              _tags = dedupeNoteTags([..._tags, tag]);
                            });
                            _scheduleDraftPersist();
                          },
                        ),
                        if (_tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final tag in _tags)
                                InputChip(
                                  label: Text('#$tag'),
                                  onDeleted: () {
                                    setState(() {
                                      _tags = _tags
                                          .where(
                                            (entry) =>
                                                canonicalizeNoteTag(entry) !=
                                                canonicalizeNoteTag(tag),
                                          )
                                          .toList(growable: false);
                                    });
                                    _scheduleDraftPersist();
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasPrivateTargets)
                    SwitchListTile.adaptive(
                      key: const Key('note-save-private-toggle'),
                      value: isPrivateSelection,
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.save.to.private.profile')),
                      subtitle: Text(
                        adminMode
                            ? (strings.text(
                                'home.choose.which.private.profile.to.save.into.while.in.admin',
                              ))
                            : (strings.text(
                                'home.save.into.the.currently.unlocked.private.profile',
                              )),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _selectedVaultId = value
                              ? (privateTargets.isEmpty
                                    ? 'everyday'
                                    : privateTargets.first.id)
                              : 'everyday';
                        });
                        _scheduleDraftPersist();
                      },
                    ),
                  if (isPrivateSelection &&
                      adminMode &&
                      privateTargets.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DropdownButtonFormField<String>(
                        key: const Key('note-private-profile-select'),
                        initialValue: _selectedVaultId,
                        decoration: InputDecoration(
                          labelText: strings.text('home.private.profile'),
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final vault in privateTargets)
                            DropdownMenuItem(
                              value: vault.id,
                              child: Text(_vaultDisplayName(context, vault)),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedVaultId = value;
                          });
                          _scheduleDraftPersist();
                        },
                      ),
                    ),
                  if (_location != null) ...[
                    const SizedBox(height: 12),
                    _EditableLocationSection(
                      location: _location!,
                      strings: strings,
                      onEdit: _editLocation,
                      onRemove: () {
                        setState(() {
                          _location = null;
                          _captureLocationEnabled = false;
                        });
                        unawaited(
                          ref
                              .read(
                                lastNoteEditorSettingsControllerProvider
                                    .notifier,
                              )
                              .setCaptureLocation(false),
                        );
                        _scheduleDraftPersist();
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: _canSubmitNotifier,
                  builder: (context, canSubmit, _) {
                    return FilledButton(
                      key: const Key('save-note-button'),
                      onPressed: canSubmit && _selectedVaultId != null
                          ? _save
                          : null,
                      child: Text(
                        widget.note == null
                            ? strings.createNote
                            : strings.saveChanges,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasSubmitContent {
    final hasText = _editorMode == NoteEditorMode.quick
        ? (() {
            final content = _splitMemoContent(_contentController.text);
            return content.title.isNotEmpty || content.body.isNotEmpty;
          })()
        : _deriveRichTitle().isNotEmpty || _deriveRichBody().isNotEmpty;
    final hasAttachments = _allCurrentAttachments.isNotEmpty;
    return hasText || hasAttachments;
  }

  bool get _canSave {
    return _hasSubmitContent && _selectedVaultId != null;
  }

  void _showEditorSnackBar({required Widget content, SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final availableWidth = mediaQuery.size.width - 32;
    final snackBarWidth = availableWidth <= 420
        ? null
        : math.min(420.0, availableWidth);
    final useFloating =
        mediaQuery.size.width >= 520 &&
        mediaQuery.size.height - bottomInset >= 720;
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: content,
        action: action,
        behavior: useFloating
            ? SnackBarBehavior.floating
            : SnackBarBehavior.fixed,
        width: useFloating ? snackBarWidth : null,
        margin: useFloating && snackBarWidth == null
            ? EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16)
            : null,
        duration: action == null
            ? const Duration(seconds: 2)
            : const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final previous = _createdAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (pickedTime == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _createdAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
    _scheduleDraftPersist();
    if (!mounted) {
      return;
    }
    _showEditorSnackBar(
      content: Text(context.strings.dateTimeUpdated),
      action: SnackBarAction(
        label: context.strings.undo,
        onPressed: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _createdAt = previous;
          });
          _scheduleDraftPersist();
        },
      ),
    );
  }

  Future<void> _handleAttachmentAction(MediaImportAction action) async {
    if (action == MediaImportAction.addLocation) {
      await _toggleLocationCapture();
      return;
    }
    final MediaImportResult result;
    if (action == MediaImportAction.recordAudio) {
      // ignore: use_build_context_synchronously
      result = await _showAudioRecordingDialog(context, ref);
    } else {
      final mediaImportService = ref.read(mediaImportServiceProvider);
      result = await mediaImportService.importAttachment(action);
    }
    if (!mounted) {
      return;
    }
    final attachment = result.attachment;
    if (attachment == null) {
      final errorMessage = result.errorMessage;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        _showEditorSnackBar(content: Text(errorMessage));
      }
      return;
    }
    setState(() {
      if (_editorMode == NoteEditorMode.quick) {
        _attachments = [..._attachments, attachment];
      } else {
        final insertionIndex = _resolveRichInsertionIndex();
        final nextBlocks = [..._richBlocks];
        late final _RichBlockDraft paragraphToFocus;
        var focusOffset = 0;

        if (insertionIndex < nextBlocks.length &&
            nextBlocks[insertionIndex].type == NoteBlockType.paragraph) {
          final current = nextBlocks[insertionIndex];
          final controller = current.controller!;
          final text = controller.text;
          final selection = controller.selection;
          final cursorOffset = selection.isValid
              ? selection.baseOffset.clamp(0, text.length)
              : text.length;

          if (text.trim().isNotEmpty) {
            final beforeText = text.substring(0, cursorOffset);
            final afterText = text.substring(cursorOffset);
            current.dispose();
            nextBlocks.removeAt(insertionIndex);

            final replacement = <_RichBlockDraft>[];
            if (beforeText.isNotEmpty) {
              final beforeParagraph = _RichBlockDraft.paragraph(beforeText);
              _attachRichBlockListener(beforeParagraph);
              replacement.add(beforeParagraph);
            }

            replacement.add(_RichBlockDraft.attachment(attachment));

            final afterParagraph = _RichBlockDraft.paragraph(afterText);
            _attachRichBlockListener(afterParagraph);
            replacement.add(afterParagraph);

            nextBlocks.insertAll(insertionIndex, replacement);
            paragraphToFocus = afterParagraph;
            focusOffset = 0;
          } else {
            nextBlocks.insert(
              insertionIndex,
              _RichBlockDraft.attachment(attachment),
            );
            paragraphToFocus = current;
            focusOffset = 0;
          }
        } else {
          final trailingParagraph = _RichBlockDraft.paragraph();
          _attachRichBlockListener(trailingParagraph);
          nextBlocks.insertAll(insertionIndex, [
            _RichBlockDraft.attachment(attachment),
            trailingParagraph,
          ]);
          paragraphToFocus = trailingParagraph;
          focusOffset = 0;
        }

        _richBlocks = nextBlocks;
        _activeRichParagraphIndex = _richBlocks.indexOf(paragraphToFocus);
        _requestParagraphFocus(paragraphToFocus, focusOffset);
      }
    });
    _cancelAttachmentDelete(attachment);
    _scheduleDraftPersist();
  }

  Future<void> _toggleLocationCapture() async {
    final nextEnabled = !_captureLocationEnabled;
    setState(() {
      _captureLocationEnabled = nextEnabled;
      if (!nextEnabled) {
        _location = null;
      }
    });
    await ref
        .read(lastNoteEditorSettingsControllerProvider.notifier)
        .setCaptureLocation(nextEnabled);
    _scheduleDraftPersist();
    if (nextEnabled) {
      await _captureCurrentLocationForNote(showErrors: true);
    }
  }

  Future<void> _captureCurrentLocationForNote({
    required bool showErrors,
  }) async {
    if (_locationBusy) {
      return;
    }
    final strings = context.strings;
    setState(() {
      _locationBusy = true;
    });
    try {
      final locationServiceEnabled =
          kIsWeb || await Geolocator.isLocationServiceEnabled();
      if (!locationServiceEnabled) {
        if (!mounted) {
          return;
        }
        if (showErrors) {
          _showEditorSnackBar(content: Text(strings.locationServicesOff));
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        if (showErrors) {
          _showEditorSnackBar(
            content: Text(strings.locationPermissionRequired),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) {
        return;
      }
      final address = await _resolveLocationAddress(position);
      if (!mounted) {
        return;
      }
      setState(() {
        _location = _noteLocationFromPosition(position, address: address);
      });
      _scheduleDraftPersist();
      if (showErrors) {
        _showEditorSnackBar(content: Text(strings.currentLocationAdded));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (showErrors) {
        _showEditorSnackBar(content: Text(strings.currentLocationUnavailable));
      }
    } finally {
      if (mounted) {
        setState(() {
          _locationBusy = false;
        });
      }
    }
  }

  Future<void> _editLocation() async {
    final current = _location;
    if (current == null) {
      return;
    }
    final edited = await _showLocationEditDialog(context, current);
    if (edited == null || !mounted) {
      return;
    }
    setState(() {
      _location = edited;
    });
    _scheduleDraftPersist();
  }

  Future<void> _save() async {
    if (!_canSave) {
      return;
    }
    final content = _editorMode == NoteEditorMode.quick
        ? _splitMemoContent(_contentController.text)
        : (title: _deriveRichTitle(), body: _deriveRichBody());
    final blocks = _editorMode == NoteEditorMode.quick
        ? const <NoteBlock>[]
        : _richBlocksToNoteBlocks();
    final note = NoteEntry(
      id: widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      vaultId: _selectedVaultId!,
      title: content.title,
      body: content.body,
      createdAt: _createdAt,
      updatedAt: widget.note == null ? _createdAt : DateTime.now(),
      attachments: _editorMode == NoteEditorMode.quick
          ? _attachments
          : _richBlocks
                .map((block) => block.attachment)
                .whereType<NoteAttachment>()
                .toList(growable: false),
      blocks: blocks,
      tags: dedupeNoteTags(_tags),
      isPinned: _isPinned,
      revision: widget.note?.revision ?? 1,
      deviceId: widget.note?.deviceId,
      syncState: widget.note?.syncState ?? NoteSyncState.localOnly,
      editorMode: _editorMode,
      location: _location,
    );
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    for (final filePath in _pendingAttachmentDeletes) {
      await attachmentStore.deleteAttachment(filePath);
    }
    _pendingAttachmentDeletes.clear();
    await ref
        .read(lastNoteEditorSettingsControllerProvider.notifier)
        .remember(
          mode: _editorMode,
          vaultId: _selectedVaultId!,
          captureLocation: _captureLocationEnabled,
        );
    await ref.read(notesControllerProvider.notifier).upsert(note);
    if (widget.note == null) {
      await ref.read(noteEditorDraftStoreProvider).clear();
    }
    _saved = true;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _removeRichBlock(int index) {
    final block = _richBlocks[index];
    if (block.attachment != null) {
      _removeAttachmentBlockAt(index);
      return;
    }
    block.dispose();
    setState(() {
      _richBlocks.removeAt(index);
      if (_richBlocks
          .where((candidate) => candidate.type == NoteBlockType.paragraph)
          .isEmpty) {
        final draft = _RichBlockDraft.paragraph();
        _attachRichBlockListener(draft);
        _richBlocks.add(draft);
      }
      if (_activeRichParagraphIndex != null &&
          _activeRichParagraphIndex! >= _richBlocks.length) {
        _activeRichParagraphIndex = _richBlocks.lastIndexWhere(
          (candidate) => candidate.type == NoteBlockType.paragraph,
        );
      }
    });
    _scheduleDraftPersist();
  }

  void _moveRichBlock(int index, int delta) {
    final targetIndex = index + delta;
    if (index < 0 ||
        index >= _richBlocks.length ||
        targetIndex < 0 ||
        targetIndex >= _richBlocks.length) {
      return;
    }
    setState(() {
      final next = [..._richBlocks];
      final block = next.removeAt(index);
      next.insert(targetIndex, block);
      _richBlocks = next;
      if (block.type == NoteBlockType.paragraph) {
        _activeRichParagraphIndex = targetIndex;
      }
    });
    _scheduleDraftPersist();
  }

  void _removeQuickAttachmentAt(int index) {
    final removed = _attachments[index];
    setState(() {
      _attachments.removeAt(index);
    });
    _queueAttachmentDelete(removed);
    _scheduleDraftPersist();
    if (!mounted) {
      return;
    }
    _showEditorSnackBar(
      content: Text(context.strings.attachmentRemoved(removed.label)),
      action: SnackBarAction(
        label: context.strings.undo,
        onPressed: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _attachments.insert(index.clamp(0, _attachments.length), removed);
          });
          _cancelAttachmentDelete(removed);
          _scheduleDraftPersist();
        },
      ),
    );
  }

  void _moveQuickAttachment(int index, int delta) {
    final target = index + delta;
    if (index < 0 ||
        index >= _attachments.length ||
        target < 0 ||
        target >= _attachments.length) {
      return;
    }
    setState(() {
      final next = [..._attachments];
      final attachment = next.removeAt(index);
      next.insert(target, attachment);
      _attachments = next;
    });
    _scheduleDraftPersist();
  }

  void _removeMediaBeforeParagraph(int paragraphIndex) {
    if (paragraphIndex <= 0 || paragraphIndex >= _richBlocks.length) {
      return;
    }
    final paragraph = _richBlocks[paragraphIndex];
    final controller = paragraph.controller;
    if (paragraph.type != NoteBlockType.paragraph || controller == null) {
      return;
    }
    final selection = controller.selection;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        selection.baseOffset != 0) {
      return;
    }

    final previousIndex = paragraphIndex - 1;
    final previousBlock = _richBlocks[previousIndex];
    final attachment = previousBlock.attachment;
    if (attachment == null) {
      return;
    }
    _removeAttachmentBlockAt(
      previousIndex,
      preferredFocusParagraph: paragraph,
      preferredFocusOffset: 0,
    );
  }

  void _removeAttachmentBlockAt(
    int mediaIndex, {
    _RichBlockDraft? preferredFocusParagraph,
    int preferredFocusOffset = 0,
  }) {
    if (mediaIndex < 0 || mediaIndex >= _richBlocks.length) {
      return;
    }
    final removedBlock = _richBlocks[mediaIndex];
    final attachment = removedBlock.attachment;
    if (attachment == null) {
      return;
    }

    _RichBlockDraft? paragraphToFocus = preferredFocusParagraph;
    var focusOffset = preferredFocusOffset;

    setState(() {
      _richBlocks.removeAt(mediaIndex);

      if (mediaIndex - 1 >= 0 &&
          mediaIndex < _richBlocks.length &&
          _richBlocks[mediaIndex - 1].type == NoteBlockType.paragraph &&
          _richBlocks[mediaIndex].type == NoteBlockType.paragraph) {
        final leadingParagraph = _richBlocks[mediaIndex - 1];
        final trailingParagraph = _richBlocks[mediaIndex];
        final leadingController = leadingParagraph.controller!;
        final trailingController = trailingParagraph.controller!;
        final leadingText = leadingController.text;
        final trailingText = trailingController.text;
        final mergedText = switch ((
          leadingText.trim().isNotEmpty,
          trailingText.trim().isNotEmpty,
        )) {
          (true, true) => '$leadingText\n\n$trailingText',
          (true, false) => leadingText,
          (false, true) => trailingText,
          (false, false) => '',
        };
        final focusBaseOffset = switch ((
          leadingText.trim().isNotEmpty,
          trailingText.trim().isNotEmpty,
        )) {
          (true, true) => leadingText.length + 2,
          (true, false) => leadingText.length,
          (false, true) => 0,
          (false, false) => 0,
        };
        leadingController.text = mergedText;
        trailingParagraph.dispose();
        _richBlocks.removeAt(mediaIndex);

        if (paragraphToFocus == null ||
            identical(paragraphToFocus, trailingParagraph)) {
          paragraphToFocus = leadingParagraph;
          focusOffset = focusBaseOffset + preferredFocusOffset;
        }
      }

      if (_richBlocks
          .where((candidate) => candidate.type == NoteBlockType.paragraph)
          .isEmpty) {
        final draft = _RichBlockDraft.paragraph();
        _attachRichBlockListener(draft);
        _richBlocks.add(draft);
        paragraphToFocus ??= draft;
      }

      if (paragraphToFocus != null) {
        _activeRichParagraphIndex = _richBlocks.indexOf(paragraphToFocus!);
      } else if (_activeRichParagraphIndex != null &&
          _activeRichParagraphIndex! >= _richBlocks.length) {
        _activeRichParagraphIndex = _richBlocks.lastIndexWhere(
          (candidate) => candidate.type == NoteBlockType.paragraph,
        );
      }
    });

    if (paragraphToFocus != null) {
      _requestParagraphFocus(paragraphToFocus!, focusOffset);
    }
    _scheduleDraftPersist();

    if (mounted) {
      final restoreIndex = mediaIndex.clamp(0, _richBlocks.length);
      _showEditorSnackBar(
        content: Text(context.strings.attachmentRemoved(attachment.label)),
        action: SnackBarAction(
          label: context.strings.undo,
          onPressed: () {
            if (!mounted) {
              return;
            }
            setState(() {
              _richBlocks.insert(
                restoreIndex,
                _RichBlockDraft.attachment(attachment),
              );
            });
            _cancelAttachmentDelete(attachment);
            _scheduleDraftPersist();
          },
        ),
      );
    }
    _queueAttachmentDelete(attachment);
  }

  String _deriveRichTitle() {
    for (final block in _richBlocks) {
      final text = block.controller?.text.trim() ?? '';
      if (text.isNotEmpty) {
        return text.split('\n').first.trim();
      }
    }
    return '';
  }

  String _deriveRichBody() {
    return _richBlocks
        .map((block) => block.controller?.text.trim())
        .whereType<String>()
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  List<NoteBlock> _richBlocksToNoteBlocks() {
    return [
      for (final block in _richBlocks)
        if (block.type == NoteBlockType.paragraph)
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: block.controller?.text ?? '',
          )
        else if (block.attachment != null)
          NoteBlock(type: block.type, attachment: block.attachment),
    ];
  }
}

({String title, String body}) _splitMemoContent(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) {
    return (title: '', body: '');
  }

  final lines = normalized.split('\n');
  final title = lines.first.trim();
  final body = lines.skip(1).join('\n').trim();
  return (title: title, body: body);
}

Future<String?> _resolveLocationAddress(Position position) async {
  if (kIsWeb) {
    return null;
  }
  try {
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 5));
    if (placemarks.isEmpty) {
      return null;
    }
    return _formatPlacemarkAddress(placemarks.first);
  } catch (_) {
    return null;
  }
}

String? _formatPlacemarkAddress(Placemark placemark) {
  final streetParts = [placemark.street, placemark.subLocality]
      .whereType<String>()
      .map((part) => part.trim())
      .where((part) {
        return part.isNotEmpty;
      })
      .toList(growable: false);

  final parts =
      [
            if (streetParts.isNotEmpty) streetParts.join(' '),
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country,
          ]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) {
            return part.isNotEmpty;
          })
          .toList(growable: false);

  final deduped = <String>[];
  for (final part in parts) {
    if (!deduped.contains(part)) {
      deduped.add(part);
    }
  }
  return deduped.isEmpty ? null : deduped.join(', ');
}

NoteLocation _noteLocationFromPosition(Position position, {String? address}) {
  return NoteLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
    address: address,
    capturedAt: DateTime.now(),
  );
}

class _LocationMemoData {
  const _LocationMemoData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.mapUrl,
    this.address,
  });

  final String latitude;
  final String longitude;
  final String accuracy;
  final String mapUrl;
  final String? address;
}

_LocationMemoData _locationMemoDataFromMetadata(NoteLocation location) {
  final latitude = location.latitude.toStringAsFixed(6);
  final longitude = location.longitude.toStringAsFixed(6);
  return _LocationMemoData(
    latitude: latitude,
    longitude: longitude,
    accuracy: location.accuracyMeters == null
        ? '-'
        : '${location.accuracyMeters!.round()}m',
    mapUrl: 'https://maps.google.com/?q=$latitude,$longitude',
    address: location.address,
  );
}

_LocationMemoData? _tryParseLocationMemo(String text) {
  final leadingText = text.trimLeft().toLowerCase();
  if (!leadingText.startsWith('迴ｾ蝨ｨ蝨ｰ') &&
      !leadingText.startsWith('current location')) {
    return null;
  }
  final normalized = text.replaceAll('\r\n', '\n').trim();
  final lines = normalized
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 4) {
    return null;
  }
  final heading = lines.first.toLowerCase();
  if (heading != '現在地' && heading != 'current location') {
    return null;
  }

  final urlMatch = RegExp(
    r'https://maps\.google\.com/\?q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
  ).firstMatch(normalized);
  if (urlMatch == null) {
    return null;
  }

  String valueAfterColon(String label) {
    final line = lines.firstWhere(
      (candidate) => candidate.toLowerCase().startsWith(label.toLowerCase()),
      orElse: () => '',
    );
    final colonIndex = line.indexOf(':');
    return colonIndex < 0 ? '' : line.substring(colonIndex + 1).trim();
  }

  final latitude = valueAfterColon('緯度').isNotEmpty
      ? valueAfterColon('緯度')
      : valueAfterColon('Latitude');
  final longitude = valueAfterColon('経度').isNotEmpty
      ? valueAfterColon('経度')
      : valueAfterColon('Longitude');
  var accuracy = valueAfterColon('精度').isNotEmpty
      ? valueAfterColon('精度')
      : valueAfterColon('Accuracy');
  accuracy = accuracy
      .replaceFirst(RegExp(r'^約\s*'), '')
      .replaceFirst(RegExp(r'^about\s+', caseSensitive: false), '');
  final address = valueAfterColon('推定住所').isNotEmpty
      ? valueAfterColon('推定住所')
      : valueAfterColon('Estimated address');

  return _LocationMemoData(
    latitude: latitude.isEmpty ? urlMatch.group(1)! : latitude,
    longitude: longitude.isEmpty ? urlMatch.group(2)! : longitude,
    accuracy: accuracy.isEmpty ? '-' : accuracy,
    mapUrl: urlMatch.group(0)!,
    address: address.isEmpty ? null : address,
  );
}

Future<void> _openLocationMap(
  BuildContext context,
  _LocationMemoData location,
) async {
  final uri = Uri.tryParse(location.mapUrl);
  if (uri != null) {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        return;
      }
    } catch (_) {
      // Fall through to the visible failure message below.
    }
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(showCloseIcon: true, content: Text(context.strings.mapOpenFailed)),
  );
}

class _EditableLocationSection extends StatelessWidget {
  const _EditableLocationSection({
    required this.location,
    required this.strings,
    required this.onEdit,
    required this.onRemove,
  });

  final NoteLocation location;
  final AppStrings strings;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final data = _locationMemoDataFromMetadata(location);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final address = data.address?.trim();
    final subtitle = address == null || address.isEmpty
        ? '${strings.latitudeLabel}: ${data.latitude}, '
              '${strings.longitudeLabel}: ${data.longitude}'
        : address;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.my_location_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.currentLocationLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.editNote,
                onPressed: onEdit,
                icon: const Icon(Icons.map_outlined),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.removeBlock,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationSearchResult {
  const _LocationSearchResult({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

Future<List<_LocationSearchResult>> _searchLocationCandidates(
  String query,
) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'jsonv2',
    'limit': '5',
    'q': trimmed,
  });
  final response = await http
      .get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'HiMemo/1.0 (mail@ruhenheim.org)',
        },
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('Location search failed: ${response.statusCode}');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! List) {
    return const [];
  }
  return [
    for (final entry in decoded)
      if (entry is Map)
        if (double.tryParse('${entry['lat']}') case final latitude?)
          if (double.tryParse('${entry['lon']}') case final longitude?)
            _LocationSearchResult(
              label: '${entry['display_name'] ?? ''}'.trim(),
              latitude: latitude,
              longitude: longitude,
            ),
  ].where((entry) => entry.label.isNotEmpty).toList(growable: false);
}

Future<String?> _reverseSearchLocationAddress(LatLng point) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': point.latitude.toStringAsFixed(7),
      'lon': point.longitude.toStringAsFixed(7),
      'zoom': '18',
      'addressdetails': '1',
    });
    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'HiMemo/1.0 (mail@ruhenheim.org)',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return null;
    }
    final displayName = '${decoded['display_name'] ?? ''}'.trim();
    return displayName.isEmpty ? null : displayName;
  } catch (_) {
    return null;
  }
}

Future<NoteLocation?> _showLocationEditDialog(
  BuildContext context,
  NoteLocation location,
) {
  return showDialog<NoteLocation>(
    context: context,
    builder: (dialogContext) => _LocationEditDialog(location: location),
  );
}

class _LocationEditDialog extends StatefulWidget {
  const _LocationEditDialog({required this.location});

  final NoteLocation location;

  @override
  State<_LocationEditDialog> createState() => _LocationEditDialogState();
}

class _LocationEditDialogState extends State<_LocationEditDialog> {
  late final TextEditingController _accuracyController;
  late final TextEditingController _addressController;
  late final TextEditingController _searchController;
  late final MapController _mapController;
  late LatLng _selectedPoint;
  double _selectedZoom = 15;
  bool _isSearching = false;
  bool _isResolvingAddress = false;
  String? _errorText;
  Timer? _reverseAddressDebounce;
  LatLng? _lastReverseAddressPoint;
  int _reverseAddressRequestId = 0;
  List<_LocationSearchResult> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _accuracyController = TextEditingController(
      text: widget.location.accuracyMeters == null
          ? ''
          : widget.location.accuracyMeters!.round().toString(),
    );
    _addressController = TextEditingController(
      text: widget.location.address ?? '',
    );
    _searchController = TextEditingController();
    _mapController = MapController();
    _selectedPoint = LatLng(
      widget.location.latitude,
      widget.location.longitude,
    );
  }

  @override
  void dispose() {
    _reverseAddressDebounce?.cancel();
    _accuracyController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(AppStrings strings) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _errorText = null;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _errorText = null;
    });
    try {
      final results = await _searchLocationCandidates(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _errorText = results.isEmpty
            ? strings.localized(
                en: 'No matching places were found.',
                ja: '一致する地点が見つかりませんでした。',
                zh: '未找到匹配的地点。',
                ko: '일치하는 장소를 찾을 수 없습니다.',
                es: 'No se encontraron lugares coincidentes.',
                de: 'Keine passenden Orte gefunden.',
              )
            : null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSearching = false;
        _errorText = strings.localized(
          en: 'Location search failed. Try again later.',
          ja: '地点検索に失敗しました。時間をおいて再試行してください。',
          zh: '地点搜索失败。请稍后重试。',
          ko: '장소 검색에 실패했습니다. 나중에 다시 시도하세요.',
          es: 'La búsqueda de ubicación falló. Inténtalo más tarde.',
          de: 'Standortsuche fehlgeschlagen. Versuche es später erneut.',
        );
      });
    }
  }

  void _selectSearchResult(_LocationSearchResult result) {
    final point = LatLng(result.latitude, result.longitude);
    _reverseAddressDebounce?.cancel();
    setState(() {
      _selectedPoint = point;
      _lastReverseAddressPoint = point;
      _addressController.text = result.label;
      _searchResults = const [];
      _isResolvingAddress = false;
      _errorText = null;
    });
    _mapController.move(point, 15);
  }

  void _scheduleReverseAddressUpdate() {
    _reverseAddressDebounce?.cancel();
    final point = _selectedPoint;
    final previous = _lastReverseAddressPoint;
    if (previous != null &&
        (previous.latitude - point.latitude).abs() < 0.00008 &&
        (previous.longitude - point.longitude).abs() < 0.00008) {
      return;
    }
    _reverseAddressDebounce = Timer(const Duration(milliseconds: 850), () {
      _resolveAddressForPoint(point);
    });
  }

  Future<void> _resolveAddressForPoint(LatLng point) async {
    final requestId = ++_reverseAddressRequestId;
    if (mounted) {
      setState(() {
        _isResolvingAddress = true;
      });
    }
    final address = await _reverseSearchLocationAddress(point);
    if (!mounted || requestId != _reverseAddressRequestId) {
      return;
    }
    setState(() {
      _lastReverseAddressPoint = point;
      _isResolvingAddress = false;
      if (address != null) {
        _addressController.text = address;
      }
    });
  }

  void _save() {
    Navigator.of(context).pop(
      NoteLocation(
        latitude: _selectedPoint.latitude,
        longitude: _selectedPoint.longitude,
        accuracyMeters: double.tryParse(_accuracyController.text.trim()),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        capturedAt: widget.location.capturedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(strings.currentLocationLabel),
      content: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width - 48, 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.localized(
                  en: 'Move the map so the pin points to the note location.',
                  ja: 'ピンがメモの地点を指すように地図を移動してください。',
                  zh: '移动地图，让图钉指向笔记位置。',
                  ko: '핀이 메모 위치를 가리키도록 지도를 이동하세요.',
                  es: 'Mueve el mapa para que el pin señale la ubicación de la nota.',
                  de: 'Verschiebe die Karte, damit die Markierung auf den Notizort zeigt.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: strings.localized(
                          en: 'Search place',
                          ja: '地点を検索',
                          zh: '搜索地点',
                          ko: '장소 검색',
                          es: 'Buscar lugar',
                          de: 'Ort suchen',
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                      onSubmitted: (_) => _runSearch(strings),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: strings.localized(
                      en: 'Search',
                      ja: '検索',
                      zh: '搜索',
                      ko: '검색',
                      es: 'Buscar',
                      de: 'Suchen',
                    ),
                    onPressed: _isSearching ? null : () => _runSearch(strings),
                    icon: _isSearching
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                  ),
                ],
              ),
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final result in _searchResults)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            result.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSearchResult(result),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 280,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _selectedPoint,
                          initialZoom: _selectedZoom,
                          onPositionChanged: (camera, hasGesture) {
                            _selectedPoint = camera.center;
                            _selectedZoom = camera.zoom;
                            if (hasGesture) {
                              _scheduleReverseAddressUpdate();
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'org.ruhenheim.himemo',
                          ),
                        ],
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 42,
                            color: colorScheme.primary,
                            shadows: [
                              Shadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              '© OpenStreetMap © CARTO',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: strings.estimatedAddressLabel,
                  suffixIcon: _isResolvingAddress
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _accuracyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.locationAccuracyLabel,
                  suffixText: 'm',
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(_errorText!, style: TextStyle(color: colorScheme.error)),
              ],
              const SizedBox(height: 8),
              Text(
                '${strings.latitudeLabel}: ${_selectedPoint.latitude.toStringAsFixed(6)}\n'
                '${strings.longitudeLabel}: ${_selectedPoint.longitude.toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        TextButton.icon(
          onPressed: () => _openLocationMap(
            context,
            _locationMemoDataFromMetadata(widget.location),
          ),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(strings.openMap),
        ),
        FilledButton(onPressed: _save, child: Text(strings.save)),
      ],
    );
  }
}

class _LocationMemoCard extends StatelessWidget {
  const _LocationMemoCard({
    required this.location,
    required this.strings,
    this.width,
  });

  final _LocationMemoData location;
  final AppStrings strings;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderColor = theme.dividerColor.withValues(alpha: 0.8);
    final muted = _mutedTextColor(context);

    return Container(
      width: width,
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.10),
                      scheme.surface,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LocationMapPatternPainter(
                      lineColor: scheme.primary.withValues(alpha: 0.18),
                      accentColor: scheme.tertiary.withValues(alpha: 0.20),
                    ),
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: scheme.onPrimary,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.currentLocationLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (location.address case final address?) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.estimatedAddressLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              address,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _LocationValue(
                      label: strings.latitudeLabel,
                      value: location.latitude,
                    ),
                    _LocationValue(
                      label: strings.longitudeLabel,
                      value: location.longitude,
                    ),
                    _LocationValue(
                      label: strings.locationAccuracyLabel,
                      value: location.accuracy,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openLocationMap(context, location),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: Text(strings.openMap),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: location.mapUrl),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            showCloseIcon: true,
                            content: Text(strings.mapLinkCopied),
                          ),
                        );
                      },
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(strings.copyMapLink),
                      style: TextButton.styleFrom(
                        foregroundColor: muted,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationValue extends StatelessWidget {
  const _LocationValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: _mutedTextColor(context),
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationMapPatternPainter extends CustomPainter {
  const _LocationMapPatternPainter({
    required this.lineColor,
    required this.accentColor,
  });

  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final accentPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final route = Path()
      ..moveTo(size.width * 0.08, size.height * 0.76)
      ..cubicTo(
        size.width * 0.26,
        size.height * 0.24,
        size.width * 0.42,
        size.height * 0.92,
        size.width * 0.62,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.74,
        size.height * 0.12,
        size.width * 0.86,
        size.height * 0.18,
        size.width * 0.94,
        size.height * 0.08,
      );
    canvas.drawPath(route, accentPaint);

    for (final x in <double>[0.20, 0.48, 0.76]) {
      canvas.drawLine(
        Offset(size.width * x, 0),
        Offset(size.width * (x - 0.16), size.height),
        linePaint,
      );
    }
    for (final y in <double>[0.28, 0.62]) {
      canvas.drawLine(
        Offset(0, size.height * y),
        Offset(size.width, size.height * (y + 0.12)),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LocationMapPatternPainter oldDelegate) {
    return lineColor != oldDelegate.lineColor ||
        accentColor != oldDelegate.accentColor;
  }
}

class _RichMemoEditor extends StatelessWidget {
  const _RichMemoEditor({
    required this.blocks,
    required this.strings,
    required this.onRemoveBlock,
    required this.onBackspaceAtParagraphStart,
    required this.onMoveBlock,
  });

  final List<_RichBlockDraft> blocks;
  final AppStrings strings;
  final ValueChanged<int> onRemoveBlock;
  final ValueChanged<int> onBackspaceAtParagraphStart;
  final void Function(int index, int delta) onMoveBlock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          _RichBlockEditorTile(
            block: blocks[i],
            strings: strings,
            emphasizeInput: i == 0,
            onRemove: () => onRemoveBlock(i),
            onBackspaceAtStart: () => onBackspaceAtParagraphStart(i),
            onMovePrevious: () => onMoveBlock(i, -1),
            onMoveNext: () => onMoveBlock(i, 1),
            canMovePrevious: i > 0,
            canMoveNext: i < blocks.length - 1,
          ),
          if (i != blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RichBlockEditorTile extends StatelessWidget {
  const _RichBlockEditorTile({
    required this.block,
    required this.strings,
    this.emphasizeInput = false,
    required this.onRemove,
    required this.onBackspaceAtStart,
    required this.onMovePrevious,
    required this.onMoveNext,
    required this.canMovePrevious,
    required this.canMoveNext,
  });

  final _RichBlockDraft block;
  final AppStrings strings;
  final bool emphasizeInput;
  final VoidCallback onRemove;
  final VoidCallback onBackspaceAtStart;
  final VoidCallback onMovePrevious;
  final VoidCallback onMoveNext;
  final bool canMovePrevious;
  final bool canMoveNext;

  @override
  Widget build(BuildContext context) {
    if (block.type == NoteBlockType.paragraph) {
      final paragraphText = block.controller?.text ?? '';
      final location = _tryParseLocationMemo(paragraphText);
      if (location != null) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Stack(
                children: [
                  _LocationMemoCard(location: location, strings: strings),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filledTonal(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: strings.removeBlock,
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _CompactMediaActionRail(
              canMovePrevious: canMovePrevious,
              canMoveNext: canMoveNext,
              onMovePrevious: onMovePrevious,
              onMoveNext: onMoveNext,
            ),
          ],
        );
      }
      final showPrompt = emphasizeInput && paragraphText.trim().isEmpty;
      return Container(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Focus(
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent ||
                    event.logicalKey != LogicalKeyboardKey.backspace) {
                  return KeyEventResult.ignored;
                }
                final controller = block.controller;
                final selection = controller?.selection;
                if (controller == null ||
                    selection == null ||
                    !selection.isValid ||
                    !selection.isCollapsed ||
                    selection.baseOffset != 0) {
                  return KeyEventResult.ignored;
                }
                onBackspaceAtStart();
                return KeyEventResult.handled;
              },
              child: TextField(
                controller: block.controller,
                focusNode: block.focusNode,
                minLines: 1,
                maxLines: null,
                scrollPadding: const EdgeInsets.only(
                  top: 96,
                  left: 20,
                  right: 20,
                  bottom: 96,
                ),
                decoration: InputDecoration(
                  semanticCounterText: '',
                  labelText: strings.memoLabel,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  hintText: showPrompt ? strings.startWritingHere : null,
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        _AttachmentListTile(
          attachment: block.attachment!,
          showShareAction: false,
          trailingActionWidth: 88,
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton.filledTonal(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: strings.removeBlock,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
              const SizedBox(width: 6),
              _CompactMediaActionRail(
                canMovePrevious: canMovePrevious,
                canMoveNext: canMoveNext,
                onMovePrevious: onMovePrevious,
                onMoveNext: onMoveNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorModeButton extends StatelessWidget {
  const _EditorModeButton({required this.mode, required this.strings});

  final NoteEditorMode mode;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRich = mode == NoteEditorMode.rich;
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRich ? Icons.view_stream_outlined : Icons.notes_outlined,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isRich ? strings.richMemo : strings.quickMemo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.expand_more_rounded, size: 18, color: colorScheme.primary),
        ],
      ),
    );
  }
}

class _MediaMenuEntry extends StatelessWidget {
  const _MediaMenuEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _CompactMediaActionRail extends StatelessWidget {
  const _CompactMediaActionRail({
    required this.canMovePrevious,
    required this.canMoveNext,
    required this.onMovePrevious,
    required this.onMoveNext,
  });

  final bool canMovePrevious;
  final bool canMoveNext;
  final VoidCallback? onMovePrevious;
  final VoidCallback? onMoveNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderColor = theme.dividerColor.withValues(alpha: 0.7);
    return Container(
      width: 36,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CompactMediaIconButton(
            onPressed: canMovePrevious ? onMovePrevious : null,
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: context.strings.moveEarlier,
          ),
          Divider(height: 1, thickness: 1, color: borderColor),
          _CompactMediaIconButton(
            onPressed: canMoveNext ? onMoveNext : null,
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: context.strings.moveLater,
          ),
        ],
      ),
    );
  }
}

class _CompactMediaIconButton extends StatelessWidget {
  const _CompactMediaIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final color = _mutedTextColor(context);
    return IconButton(
      onPressed: onPressed,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      splashRadius: 18,
      tooltip: tooltip,
      color: onPressed == null ? color.withValues(alpha: 0.35) : color,
      icon: Icon(icon),
    );
  }
}

class _QuickAttachmentSection extends StatefulWidget {
  const _QuickAttachmentSection({
    required this.strings,
    required this.attachments,
    required this.onRemove,
    required this.onMove,
  });

  final AppStrings strings;
  final List<NoteAttachment> attachments;
  final ValueChanged<int> onRemove;
  final void Function(int index, int delta) onMove;

  @override
  State<_QuickAttachmentSection> createState() =>
      _QuickAttachmentSectionState();
}

class _QuickAttachmentSectionState extends State<_QuickAttachmentSection> {
  static const _collapsedAttachmentLimit = 8;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final attachments = widget.attachments;
    final shouldCollapse = attachments.length > _collapsedAttachmentLimit;
    final visibleCount = shouldCollapse && !_expanded
        ? _collapsedAttachmentLimit
        : attachments.length;

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.attachments,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.localized(
              en: 'Use the camera or folder icons in the top right to add media.',
              ja: '右上のカメラ・フォルダアイコンからメディアを追加できます。',
              zh: '可通过右上角的相机或文件夹图标添加媒体。',
              ko: '오른쪽 위의 카메라・폴더 아이콘에서 미디어를 추가할 수 있습니다.',
              es: 'Usa los iconos de cámara o carpeta arriba a la derecha para añadir medios.',
              de: 'Über die Kamera- oder Ordner-Symbole oben rechts kannst du Medien hinzufügen.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < visibleCount; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EditableAttachmentTile(
                  attachment: attachments[i],
                  onRemove: () => widget.onRemove(i),
                  onMovePrevious: i > 0 ? () => widget.onMove(i, -1) : null,
                  onMoveNext: i < attachments.length - 1
                      ? () => widget.onMove(i, 1)
                      : null,
                ),
              ),
            if (shouldCollapse)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(
                    _expanded
                        ? strings.localized(
                            en: 'Show fewer attachments',
                            ja: '添付を少なく表示',
                            zh: '显示较少附件',
                            ko: '첨부 파일 적게 표시',
                            es: 'Mostrar menos adjuntos',
                            de: 'Weniger Anhaenge anzeigen',
                          )
                        : strings.localized(
                            en: 'Show all ${attachments.length} attachments',
                            ja: '${attachments.length}件の添付をすべて表示',
                            zh: '显示全部 ${attachments.length} 个附件',
                            ko: '첨부 파일 ${attachments.length}개 모두 표시',
                            es: 'Mostrar los ${attachments.length} adjuntos',
                            de: 'Alle ${attachments.length} Anhaenge anzeigen',
                          ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EditableAttachmentTile extends StatelessWidget {
  const _EditableAttachmentTile({
    required this.attachment,
    required this.onRemove,
    this.onMovePrevious,
    this.onMoveNext,
  });

  final NoteAttachment attachment;
  final VoidCallback onRemove;
  final VoidCallback? onMovePrevious;
  final VoidCallback? onMoveNext;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _AttachmentListTile(
          attachment: attachment,
          showShareAction: false,
          trailingActionWidth: 144,
        ),
        Positioned(
          top: 8,
          right: 0,
          child: Row(
            children: [
              IconButton(
                onPressed: onMovePrevious,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: context.strings.moveEarlier,
              ),
              IconButton(
                onPressed: onMoveNext,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: context.strings.moveLater,
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
                tooltip: context.strings.removeBlock,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttachmentListTile extends ConsumerWidget {
  const _AttachmentListTile({
    required this.attachment,
    this.showShareAction = true,
    this.trailingActionWidth = 0,
  });

  final NoteAttachment attachment;
  final bool showShareAction;
  final double trailingActionWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: _sectionDecoration(context),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openAttachmentViewer(context, ref, attachment),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AttachmentPreview(attachment: attachment),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _attachmentDescription(context, attachment),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _mutedTextColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showShareAction)
                  IconButton(
                    onPressed: () => _shareAttachment(context, ref, attachment),
                    icon: const Icon(Icons.share_outlined),
                    tooltip: context.strings.share,
                  )
                else if (trailingActionWidth > 0)
                  SizedBox(width: trailingActionWidth),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _shareAttachment(
  BuildContext context,
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final strings = context.strings;
  final filePath = attachment.filePath;
  if (filePath == null || filePath.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(strings.unableToShareAttachment),
      ),
    );
    return;
  }

  final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
  if (kIsWeb) {
    final bytes = await attachmentStore.readAttachment(
      filePath,
      type: attachment.type,
    );
    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            content: Text(strings.unableToDecryptAttachment),
          ),
        );
      }
      return;
    }
    await Share.shareXFiles([
      XFile.fromData(Uint8List.fromList(bytes), name: attachment.label),
    ], text: attachment.label);
    return;
  }

  final tempFilePath = await attachmentStore.materializeDecryptedFile(
    filePath,
    type: attachment.type,
    preferredFileName: attachment.label,
  );
  if (tempFilePath == null || tempFilePath.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(strings.unableToDecryptAttachment),
        ),
      );
    }
    return;
  }
  try {
    await Share.shareXFiles([XFile(tempFilePath)], text: attachment.label);
  } finally {
    await attachmentStore.deleteMaterializedFile(tempFilePath);
  }
}

class _EmbeddedAttachmentBlock extends ConsumerWidget {
  const _EmbeddedAttachmentBlock({
    required this.attachment,
    required this.mediaActive,
    this.photoAttachments = const [],
    this.photoIndex,
  });

  final NoteAttachment attachment;
  final bool mediaActive;
  final List<NoteAttachment> photoAttachments;
  final int? photoIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (attachment.type) {
      case AttachmentType.photo:
        return _EmbeddedPhotoAttachment(
          attachment: attachment,
          mediaActive: mediaActive,
          photoAttachments: photoAttachments,
          photoIndex: photoIndex,
        );
      case AttachmentType.video:
        return SizedBox(
          height: 260,
          child: _VideoAttachmentViewer(attachment: attachment),
        );
      case AttachmentType.audio:
        return SizedBox(
          height: 180,
          child: _AudioAttachmentViewer(attachment: attachment),
        );
      case AttachmentType.file:
        return _EmbeddedFileAttachment(attachment: attachment);
    }
  }
}

class _EmbeddedFileAttachment extends ConsumerWidget {
  const _EmbeddedFileAttachment({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AttachmentListTile(attachment: attachment);
  }
}

class _EmbeddedPhotoAttachment extends ConsumerStatefulWidget {
  const _EmbeddedPhotoAttachment({
    required this.attachment,
    required this.mediaActive,
    this.photoAttachments = const [],
    this.photoIndex,
  });

  final NoteAttachment attachment;
  final bool mediaActive;
  final List<NoteAttachment> photoAttachments;
  final int? photoIndex;

  @override
  ConsumerState<_EmbeddedPhotoAttachment> createState() =>
      _EmbeddedPhotoAttachmentState();
}

class _EmbeddedPhotoAttachmentState
    extends ConsumerState<_EmbeddedPhotoAttachment> {
  Future<List<int>?>? _imageBytesFuture;

  @override
  void didUpdateWidget(covariant _EmbeddedPhotoAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attachmentCacheKey(oldWidget.attachment) !=
        _attachmentCacheKey(widget.attachment)) {
      _imageBytesFuture = null;
    }
  }

  Future<List<int>?> _ensureImageBytesFuture() {
    return _imageBytesFuture ??= _readPhotoAttachmentBytesWithPerf(
      ref,
      widget.attachment,
      source: 'detail',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.mediaActive) {
      return _InactivePhotoAttachmentPreview(label: widget.attachment.label);
    }
    return FutureBuilder<List<int>?>(
      future: _ensureImageBytesFuture(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (bytes == null || bytes.isEmpty) {
          return SizedBox(
            height: 180,
            child: Center(child: Text(context.strings.unableToLoadImage)),
          );
        }
        return InkWell(
          onTap: () => _openAttachmentViewer(
            context,
            ref,
            widget.attachment,
            photoAttachments: widget.photoAttachments,
            initialPhotoIndex: widget.photoIndex,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InactivePhotoAttachmentPreview extends StatelessWidget {
  const _InactivePhotoAttachmentPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Icon(
        Icons.image_outlined,
        color: _mutedTextColor(context),
        semanticLabel: label,
      ),
    );
  }
}

class _AttachmentPreview extends ConsumerStatefulWidget {
  const _AttachmentPreview({required this.attachment, this.size = 72});

  final NoteAttachment attachment;
  final double size;

  @override
  ConsumerState<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends ConsumerState<_AttachmentPreview> {
  Future<List<int>?>? _bytesFuture;
  String? _futureFilePath;
  Uint8List? _previewBytes;
  String? _previewBytesBase64;

  @override
  void didUpdateWidget(covariant _AttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.filePath != widget.attachment.filePath ||
        oldWidget.attachment.type != widget.attachment.type ||
        oldWidget.attachment.previewBytesBase64 !=
            widget.attachment.previewBytesBase64) {
      _bytesFuture = null;
      _futureFilePath = null;
      _previewBytes = null;
      _previewBytesBase64 = null;
    }
  }

  Future<List<int>?> _attachmentBytesFuture(String filePath) {
    if (_bytesFuture != null && _futureFilePath == filePath) {
      return _bytesFuture!;
    }
    _futureFilePath = filePath;
    return _bytesFuture = _readPhotoAttachmentBytesWithPerf(
      ref,
      widget.attachment,
      source: 'attachment preview',
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final size = widget.size;
    if (attachment.type != AttachmentType.photo) {
      return _AttachmentIconBox(type: attachment.type, size: size);
    }

    final previewBytesBase64 = attachment.previewBytesBase64;
    if (previewBytesBase64 != null && previewBytesBase64.isNotEmpty) {
      return _AttachmentImageBox(bytes: _decodePreviewBytes(), size: size);
    }

    final filePath = attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      return _AttachmentIconBox(type: attachment.type, size: size);
    }

    return FutureBuilder<List<int>?>(
      future: _attachmentBytesFuture(filePath),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _AttachmentIconBox(type: attachment.type, size: size);
        }
        return _AttachmentImageBox(
          bytes: Uint8List.fromList(bytes),
          size: size,
        );
      },
    );
  }

  Uint8List _decodePreviewBytes() {
    final encoded = widget.attachment.previewBytesBase64!;
    if (_previewBytes != null && _previewBytesBase64 == encoded) {
      return _previewBytes!;
    }
    _previewBytesBase64 = encoded;
    return _previewBytes = base64Decode(encoded);
  }
}

class _AttachmentImageBox extends StatelessWidget {
  const _AttachmentImageBox({required this.bytes, this.size = 72});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imageCacheSize = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 4096);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: imageCacheSize,
        cacheHeight: imageCacheSize,
      ),
    );
  }
}

class _AttachmentIconBox extends StatelessWidget {
  const _AttachmentIconBox({required this.type, this.size = 72});

  final AttachmentType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _iconForAttachment(type),
        size: size * 0.42,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

String _attachmentDescription(BuildContext context, NoteAttachment attachment) {
  final strings = context.strings;
  switch (attachment.type) {
    case AttachmentType.photo:
      return attachment.filePath == null
          ? strings.photoPlaceholder
          : strings.tapToViewPhoto;
    case AttachmentType.video:
      return attachment.filePath == null
          ? strings.videoPlaceholder
          : strings.tapToPlayVideo;
    case AttachmentType.audio:
      return attachment.filePath == null
          ? strings.audioPlaceholder
          : strings.tapToPlayAudio;
    case AttachmentType.file:
      return attachment.filePath == null
          ? strings.filePlaceholder
          : strings.tapToOpenFile;
  }
}

String _formatDateTime(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$year/$month/$day $hour:$minute';
}

String _remoteBundleSummary(
  AppStrings strings,
  SyncProvider provider,
  SyncTransferState transferState,
) {
  if (provider == SyncProvider.off) {
    return strings.text('home.remote.bundle.storage.is.not.configured.yet');
  }
  if (provider == SyncProvider.iCloud && transferState.remoteStatus == null) {
    return transferState.message ??
        (strings.text('home.no.icloud.bundle.metadata.loaded.yet'));
  }
  if (provider != SyncProvider.googleDrive && provider != SyncProvider.iCloud) {
    return strings.text('home.remote.bundle.transport.is.not.available.yet');
  }
  if (provider == SyncProvider.off) {
    return strings.text('home.remote.bundle.storage.is.not.configured.yet.2');
  }
  if (provider == SyncProvider.iCloud && transferState.remoteStatus == null) {
    return transferState.message ??
        (strings.text('home.no.icloud.bundle.metadata.loaded.yet.2'));
  }
  if (provider != SyncProvider.googleDrive && provider != SyncProvider.iCloud) {
    return strings.text(
      'home.remote.bundle.transport.is.only.wired.for.google.drive.r',
    );
  }
  final remote = transferState.remoteStatus;
  if (remote == null) {
    return transferState.message ??
        (strings.text('home.no.remote.bundle.metadata.loaded.yet'));
  }
  final modifiedAt = remote.modifiedAt == null
      ? (strings.text('home.unknown.time'))
      : _formatDateTime(remote.modifiedAt!);
  final sizeLabel = remote.sizeBytes == null
      ? (strings.text('home.size.unknown'))
      : strings.byteCount(remote.sizeBytes!);
  final noteCount = remote.noteCount == null ? '?' : '${remote.noteCount}';
  final attachmentCount = remote.attachmentCount == null
      ? '?'
      : '${remote.attachmentCount}';
  return strings.remoteBundleSummary(
    modifiedAt: modifiedAt,
    sizeLabel: sizeLabel,
    noteCount: noteCount,
    attachmentCount: attachmentCount,
  );
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

void _showStoreFeedback(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
}

enum _LocalArchiveExportKind { passwordProtectedZip, plainZip }

class _LocalArchiveExportOptions {
  const _LocalArchiveExportOptions({required this.kind, this.password});

  final _LocalArchiveExportKind kind;
  final String? password;
}

Future<void> _exportLocalArchive(BuildContext context, WidgetRef ref) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final options = await _showLocalArchiveExportDialog(context);
    if (options == null || !context.mounted) {
      return;
    }
    final archive = await ref
        .read(syncTransferControllerProvider.notifier)
        .exportLocalArchive(password: options.password);
    if (!context.mounted) {
      return;
    }
    final savedPath = await FilePicker.platform.saveFile(
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
      await Share.shareXFiles([
        XFile.fromData(
          archive.bytes,
          name: archive.fileName,
          mimeType: 'application/zip',
        ),
      ], text: 'HiMemo ZIP archive');
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
    final picked = await FilePicker.platform.pickFiles(
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
                      _formatDateTime(preview.exportedAt!),
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
                  : _formatDateTime(entry.modifiedAt!);
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
      pageBuilder: (context, _, __) => _PhotoLightboxDialog(
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

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(context).pop(),
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
                                child: GestureDetector(
                                  onTap: () {},
                                  onDoubleTap: () =>
                                      _toggleActualSize(maxScale),
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
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
    await Share.shareXFiles(
      [
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
    );
  }
}

class _LightboxTopBar extends StatelessWidget {
  const _LightboxTopBar({
    required this.attachment,
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
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              attachment.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: canMovePrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
            tooltip: strings.previousImage,
          ),
          IconButton(
            onPressed: canMoveNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
            tooltip: strings.nextImage,
          ),
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
  }
}

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
) {
  final filePath = attachment.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    return ref
        .read(encryptedAttachmentStoreProvider)
        .readAttachment(filePath, type: attachment.type);
  }
  final previewBytesBase64 = attachment.previewBytesBase64;
  if (previewBytesBase64 == null || previewBytesBase64.isEmpty) {
    return Future<List<int>?>.value(null);
  }
  return Future<List<int>?>.value(base64Decode(previewBytesBase64));
}

Future<List<int>?> _readPhotoAttachmentDetailBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) {
  final previewBytesBase64 = attachment.previewBytesBase64;
  if (previewBytesBase64 != null && previewBytesBase64.isNotEmpty) {
    return Future<List<int>?>.value(base64Decode(previewBytesBase64));
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
            child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain),
          ),
        );
      },
    );
  }
}

class _VideoAttachmentViewer extends ConsumerStatefulWidget {
  const _VideoAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  ConsumerState<_VideoAttachmentViewer> createState() =>
      _VideoAttachmentViewerState();
}

class _VideoAttachmentViewerState
    extends ConsumerState<_VideoAttachmentViewer> {
  VideoPlayerController? _controller;
  String? _tempFilePath;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
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
    if (filePath == null || filePath.isEmpty || kIsWeb) {
      return;
    }
    final tempFilePath = await ref
        .read(encryptedAttachmentStoreProvider)
        .materializeDecryptedFile(
          filePath,
          type: widget.attachment.type,
          preferredFileName: widget.attachment.label,
        );
    if (!mounted || tempFilePath == null) {
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.file(tempFilePath));
    await controller.initialize();
    setState(() {
      _tempFilePath = tempFilePath;
      _controller = controller;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Center(child: Text(context.strings.videoPreviewUnavailableWeb));
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
                setState(() {});
              },
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
              ),
            ),
            Expanded(
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ],
    );
  }
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
