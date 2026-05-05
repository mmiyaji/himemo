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
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:just_audio/just_audio.dart';
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
import '../../sync/data/sync_bundle_preview.dart';
import '../domain/note_entry.dart';
import '../domain/note_tags.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';

const _appStoreId = String.fromEnvironment('HIMEMO_APP_STORE_ID');
const _androidStorePackageName = 'org.ruhenheim.himemo';
const _buildDateIso = String.fromEnvironment('HIMEMO_BUILD_DATE');

enum AppSection { notes, calendar, insights, settings }

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

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 840;
    final section = _sectionForLocation(GoRouterState.of(context).uri.path);
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final activePrivateProfileLabel = ref.watch(
      activePrivateProfileLabelProvider,
    );
    final adminMode = ref.watch(adminModeSessionControllerProvider);
    final privateProfileActive =
        !adminMode && activePrivateProfileLabel != null;
    final privateProfileActiveColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const _AppBrandTitle(),
        actions: [
          if (privateProfileActive)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(180, width * 0.34),
              ),
              child: Text(
                activePrivateProfileLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: privateProfileActiveColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          IconButton(
            key: AppShell.privateProfileAccessKey,
            tooltip: adminMode
                ? (context.strings.text('home.admin.mode.active'))
                : (activePrivateProfileLabel != null
                      ? context.strings.viewingPrivateProfile(
                          activePrivateProfileLabel,
                        )
                      : (context.strings.text('home.unlock.private.profile'))),
            onPressed: () => _showProfileAccessDialog(context, ref),
            icon: Icon(
              adminMode
                  ? Icons.admin_panel_settings_rounded
                  : activePrivateProfileLabel != null
                  ? Icons.lock_open_rounded
                  : Icons.lock_rounded,
              color: privateProfileActive ? privateProfileActiveColor : null,
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
                    onToggleCollapsed: () {
                      setState(() {
                        _sidebarCollapsed = !_sidebarCollapsed;
                      });
                    },
                    onSectionSelected: (target) =>
                        _goToSection(context, ref, target),
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
          section == AppSection.notes || section == AppSection.calendar
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
    if (currentSection == AppSection.notes && section != AppSection.notes) {
      ref.read(selectedNoteIdProvider.notifier).select(null);
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
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
    final effectiveSelectedNoteId =
        selectedNoteId != null &&
            visibleNotes.any((note) => note.id == selectedNoteId)
        ? selectedNoteId
        : null;

    final selectedIndex = effectiveSelectedNoteId == null
        ? -1
        : visibleNotes.indexWhere((note) => note.id == effectiveSelectedNoteId);

    if (!useSplitView) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (activeIdentity.id != 'daily') ...[
            _IdentityHeader(identity: activeIdentity),
            const SizedBox(height: 12),
          ],
          if (activeIdentity.id == 'private' && !privateVaultUnlocked) ...[
            const SizedBox(height: 12),
            const _PrivateVaultLockedNotice(),
          ],
          _NotesToolbar(compact: useCompactHeader),
          const SizedBox(height: 16),
          if (visibleNotes.isEmpty)
            const _EmptyNotesState()
          else
            for (final vault in visibleVaults) ...[
              _VaultSectionCard(
                vault: vault,
                notes: ref.watch(notesForVaultProvider(vault.id)),
                selectedNoteId: effectiveSelectedNoteId,
                density: listDensity,
                query: query,
                onNoteSelected: (note) =>
                    _openMobileNoteActions(context, note, visibleNotes),
              ),
              const SizedBox(height: 16),
            ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 5,
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
            onNoteSelected: (note) {
              _debugNotePerf('select split-list ${_notePerfLabel(note)}');
              ref.read(selectedNoteIdProvider.notifier).select(note.id);
            },
          ),
        ),
        VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        Expanded(
          flex: 6,
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
  }

  Future<void> _openMobileNoteActions(
    BuildContext context,
    NoteEntry note,
    List<NoteEntry> visibleNotes,
  ) async {
    _debugNotePerf('open mobile detail ${_notePerfLabel(note)}');
    final initialIndex = visibleNotes.indexWhere(
      (entry) => entry.id == note.id,
    );
    final controller = Scaffold.of(context).showBottomSheet((context) {
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
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
                Navigator.of(context).pop();
                await showNoteEditorSheet(context, ref, note: selectedNote);
              },
              onDelete: (selectedNote) async {
                Navigator.of(context).pop();
                await _deleteNote(context, selectedNote);
              },
              onTagTap: (tag) {
                Navigator.of(context).pop();
                _applyTagFilter(context, tag);
              },
            ),
          ),
        ),
      );
    }, showDragHandle: true);
    await controller.closed;
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
  DateTime _selectedDay = DateTime.now();
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final notes = ref.watch(visibleNotesProvider);
    final noteDays = _sortedNoteDays(notes);
    final markedDays = noteDays.toSet();
    final sameDayNotes = notes
        .where((note) => _isSameDay(note.createdAt, _selectedDay))
        .toList(growable: false);
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
              });
            },
            onDateSelected: (date) {
              setState(() {
                _selectedDay = date;
                _visibleMonth = DateTime(date.year, date.month);
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
                for (var i = 0; i < sameDayNotes.length; i++) ...[
                  _CalendarNoteRow(
                    note: sameDayNotes[i],
                    vaultName: ref
                        .watch(vaultByIdProvider(sameDayNotes[i].vaultId))
                        .name,
                    onTap: () => _openCalendarNoteDetails(
                      context,
                      notes,
                      _selectedDay,
                      i,
                    ),
                  ),
                  if (i != sameDayNotes.length - 1)
                    Divider(height: 24, color: Theme.of(context).dividerColor),
                ],
            ],
          ),
        ),
      ],
    );
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
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

  List<DateTime> _sortedNoteDays(List<NoteEntry> notes) {
    final days =
        notes
            .map(
              (note) => DateTime(
                note.createdAt.year,
                note.createdAt.month,
                note.createdAt.day,
              ),
            )
            .toSet()
            .toList()
          ..sort();
    return days;
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
    });
  }

  Future<void> _openCalendarNoteDetails(
    BuildContext context,
    List<NoteEntry> allNotes,
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
            final noteDays = _sortedNoteDays(allNotes);
            final dayNotes = allNotes
                .where((note) => _isSameDay(note.createdAt, selectedDay))
                .toList(growable: false);
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

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final notes = ref.watch(visibleNotesProvider);
    final summary = _buildInsightsSummary(context, notes);

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
            buckets: _buildMonthlyBuckets(context, notes),
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
            buckets: _buildRecentDayBuckets(context, notes),
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
            buckets: _buildWeekdayHourBuckets(notes),
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
            buckets: _buildAttachmentBuckets(context, notes),
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

_InsightsSummary _buildInsightsSummary(
  BuildContext context,
  List<NoteEntry> notes,
) {
  final strings = context.strings;
  final now = DateTime.now();
  final thisMonthCount = notes
      .where(
        (note) =>
            note.createdAt.year == now.year &&
            note.createdAt.month == now.month,
      )
      .length;
  final totalCharacters = notes.fold<int>(
    0,
    (sum, note) => sum + note.body.trim().length,
  );
  final totalAttachments = notes.fold<int>(
    0,
    (sum, note) => sum + note.attachments.length,
  );
  final activeDays =
      notes
          .map(
            (note) => DateTime(
              note.createdAt.year,
              note.createdAt.month,
              note.createdAt.day,
            ),
          )
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));
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
  final bestDay = _buildRecentDayBuckets(context, notes, count: 31)
      .fold<_InsightBucket?>(
        null,
        (best, bucket) =>
            best == null || bucket.value > best.value ? bucket : best,
      );
  final bestHour = _buildHourBuckets(notes).fold<_InsightBucket?>(
    null,
    (best, bucket) => best == null || bucket.value > best.value ? bucket : best,
  );
  final previousMonth = DateTime(now.year, now.month - 1);
  final previousMonthCount = notes
      .where(
        (note) =>
            note.createdAt.year == previousMonth.year &&
            note.createdAt.month == previousMonth.month,
      )
      .length;
  final monthlyDelta = thisMonthCount - previousMonthCount;
  final message = bestDay == null || bestDay.value == 0
      ? strings.text('home.insights.summary.empty')
      : strings.text('home.insights.summary.active', {
          'thisMonthCount': thisMonthCount,
          'bestDayLabel': bestDay.label,
        });
  return _InsightsSummary(
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
  );
}

List<_InsightBucket> _buildMonthlyBuckets(
  BuildContext context,
  List<NoteEntry> notes, {
  int count = 6,
}) {
  final strings = context.strings;
  final now = DateTime.now();
  final buckets = <_InsightBucket>[];
  for (var i = count - 1; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    final value = notes
        .where(
          (note) =>
              note.createdAt.year == month.year &&
              note.createdAt.month == month.month,
        )
        .length;
    buckets.add(
      _InsightBucket(
        label: strings.monthBucketLabel(month.month),
        value: value,
      ),
    );
  }
  return buckets;
}

List<_InsightBucket> _buildRecentDayBuckets(
  BuildContext context,
  List<NoteEntry> notes, {
  int count = 14,
}) {
  final now = DateTime.now();
  final buckets = <_InsightBucket>[];
  for (var i = count - 1; i >= 0; i--) {
    final day = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: i));
    final value = notes
        .where((note) => _isSameCalendarDay(note.createdAt, day))
        .length;
    buckets.add(_InsightBucket(label: '${day.month}/${day.day}', value: value));
  }
  return buckets;
}

List<_WeekdayHourBucket> _buildWeekdayHourBuckets(List<NoteEntry> notes) {
  return [
    for (var startHour = 0; startHour < 24; startHour += 3)
      for (var weekday = 1; weekday <= 7; weekday++)
        _WeekdayHourBucket(
          weekday: weekday,
          startHour: startHour,
          value: notes
              .where(
                (note) =>
                    note.createdAt.weekday == weekday &&
                    note.createdAt.hour >= startHour &&
                    note.createdAt.hour < startHour + 3,
              )
              .length,
        ),
  ];
}

List<_InsightBucket> _buildAttachmentBuckets(
  BuildContext context,
  List<NoteEntry> notes,
) {
  final strings = context.strings;
  int countFor(AttachmentType type) => notes.fold<int>(
    0,
    (sum, note) =>
        sum +
        note.attachments.where((attachment) => attachment.type == type).length,
  );
  return [
    _InsightBucket(
      label: strings.text('home.photo'),
      value: countFor(AttachmentType.photo),
    ),
    _InsightBucket(
      label: strings.text('home.video'),
      value: countFor(AttachmentType.video),
    ),
    _InsightBucket(
      label: strings.text('home.audio'),
      value: countFor(AttachmentType.audio),
    ),
  ];
}

List<_InsightBucket> _buildHourBuckets(List<NoteEntry> notes) {
  return [
    for (var hour = 0; hour < 24; hour += 4)
      _InsightBucket(
        label:
            '${hour.toString().padLeft(2, '0')}-${(hour + 3).toString().padLeft(2, '0')}',
        value: notes
            .where(
              (note) =>
                  note.createdAt.hour >= hour && note.createdAt.hour < hour + 4,
            )
            .length,
      ),
  ];
}

bool _isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
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
    final appearanceSummary = strings.appearanceSummary(
      language: _localeSettingLabel(context, localeSetting),
      theme: _themeModeLabel(context, themeMode),
      font: _fontFamilyLabel(context, fontFamily),
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
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(strings.text('home.filters')),
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
                          child: Text(strings.text('home.import.recovery.key')),
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
                                          .read(syncTransferControllerProvider)
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
                                          .read(syncTransferControllerProvider)
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
                                    strings.text('home.prepared.sync.snapshot'),
                                  ),
                                  content: Text(
                                    strings.syncSnapshotSummary(
                                      notes: snapshot.notes.length,
                                      attachments: snapshot.attachments.length,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (syncProvider != SyncProvider.off)
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
          initialValue: fontFamily,
          isExpanded: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            helperText: strings.appFontDesc,
            prefixIcon: const Icon(Icons.text_fields_rounded),
          ),
          items: [
            DropdownMenuItem(
              value: AppFontFamily.system,
              child: Text(strings.fontSystem),
            ),
            DropdownMenuItem(
              value: AppFontFamily.gothic,
              child: Text(strings.fontGothic),
            ),
            DropdownMenuItem(
              value: AppFontFamily.uiGothic,
              child: Text(strings.fontUiGothic),
            ),
            DropdownMenuItem(
              value: AppFontFamily.kakuGothic,
              child: Text(strings.fontKakuGothic),
            ),
            DropdownMenuItem(
              value: AppFontFamily.mincho,
              child: Text(strings.fontMincho),
            ),
            DropdownMenuItem(
              value: AppFontFamily.uiMincho,
              child: Text(strings.fontUiMincho),
            ),
            DropdownMenuItem(
              value: AppFontFamily.rounded,
              child: Text(strings.fontRounded),
            ),
            DropdownMenuItem(
              value: AppFontFamily.zenRounded,
              child: Text(strings.fontZenRounded),
            ),
            DropdownMenuItem(
              value: AppFontFamily.casual,
              child: Text(strings.fontCasual),
            ),
            DropdownMenuItem(
              value: AppFontFamily.monospace,
              child: Text(strings.fontMonospace),
            ),
          ],
          onChanged: (value) {
            if (value == null || value == fontFamily) {
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
        return authState.message ??
            (strings.text('home.authentication.is.not.available'));
    }
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
    required this.onToggleCollapsed,
    required this.onSectionSelected,
  });

  final AppSection section;
  final UnlockIdentity activeIdentity;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<AppSection> onSectionSelected;

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
                  onTap: () => onSectionSelected(AppSection.notes),
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

class _VaultSectionCard extends StatelessWidget {
  const _VaultSectionCard({
    required this.vault,
    required this.notes,
    required this.selectedNoteId,
    required this.onNoteSelected,
    required this.density,
    required this.query,
  });

  final VaultBucket vault;
  final List<NoteEntry> notes;
  final String? selectedNoteId;
  final ValueChanged<NoteEntry> onNoteSelected;
  final NotesListDensity density;
  final String query;

  @override
  Widget build(BuildContext context) {
    final vaultLabel = _vaultDisplayName(context, vault);
    if (notes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: _sectionDecoration(context),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vaultLabel),
                  if (vault.id != 'everyday' &&
                      _vaultDisplayDescription(context, vault).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _vaultDisplayDescription(context, vault),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedTextColor(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            for (var i = 0; i < notes.length; i++) ...[
              if (density != NotesListDensity.compact &&
                  (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i])))
                _NoteDayDivider(date: notes[i].createdAt),
              _NoteListTile(
                note: notes[i],
                vaultName: vaultLabel,
                showVaultName: false,
                density: density,
                query: query,
                selected: notes[i].id == selectedNoteId,
                onTap: () => onNoteSelected(notes[i]),
              ),
              if (i != notes.length - 1)
                Divider(height: 1, color: Theme.of(context).dividerColor),
            ],
          ],
        ),
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

String _vaultDisplayDescription(BuildContext context, VaultBucket vault) {
  if (vault.description == 'Unlocked private notes' ||
      vault.description == '__unlocked_private_notes__') {
    return context.strings.unlockedPrivateNotes;
  }
  if (vault.description == 'Unlocked notes' ||
      vault.description == '__unlocked_notes__') {
    return context.strings.unlockedNotes;
  }
  return vault.description;
}

bool _isSameNoteDay(NoteEntry left, NoteEntry right) {
  return left.createdAt.year == right.createdAt.year &&
      left.createdAt.month == right.createdAt.month &&
      left.createdAt.day == right.createdAt.day;
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
    final bodyText = note.body.trim();
    final compactPreview = _normalizeCompactPreview(note.body);
    final tags = note.normalizedTags;
    final previewFacts = _notePreviewFacts(note);
    final hasDistinctBody =
        bodyText.isNotEmpty &&
        bodyText.replaceAll('\n', ' ').trim() != note.title.trim();
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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      : note.body,
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
                  if (showVaultName && !isPrivateNote)
                    Text(
                      vaultName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedTextColor(context),
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

  String _normalizeCompactPreview(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
  }
}

class _NotePreviewFact {
  const _NotePreviewFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
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
      padding: const EdgeInsets.all(16),
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
          _SplitNoteDividerRow() => _DecoratedSplitNoteRow(
            position: row.position,
            child: Divider(height: 1, color: Theme.of(context).dividerColor),
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
    if (density != NotesListDensity.compact && i != notes.length - 1) {
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
    this.onTagTap,
  });

  final List<NoteEntry> notes;
  final int selectedIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<NoteEntry> onEdit;
  final ValueChanged<NoteEntry> onDelete;
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
    final buildWatch = Stopwatch()..start();
    final createdLabel =
        '${note.createdAt.year}/${note.createdAt.month}/${note.createdAt.day} ${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';
    final changedAt = note.updatedAt ?? note.createdAt;
    final updatedLabel =
        '${changedAt.year}/${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;
    final tags = note.normalizedTags;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      buildWatch.stop();
      _debugNotePerf(
        'detail pane frame ${buildWatch.elapsedMicroseconds / 1000}ms ${_notePerfLabel(note)} tags=${tags.length}',
      );
    });

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Text(note.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              isEdited ? strings.editedAt(updatedLabel) : createdLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
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
            ..._buildDetailBlocks(context, note, mediaActive: isActive),
          ],
        ),
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
    _disposeRecognizers();
    final text = widget.text;
    final style = widget.style;
    final matches = _urlPattern.allMatches(text).toList(growable: false);
    if (matches.isEmpty) {
      return SelectableText(text, style: style);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }

      final rawMatch = match.group(0)!;
      final trimmed = _trimTrailingUrlPunctuation(rawMatch);
      final trailing = rawMatch.substring(trimmed.length);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openMemoLink(context, trimmed);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: trimmed, style: linkStyle, recognizer: recognizer),
      );
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
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

List<Widget> _buildDetailBlocks(
  BuildContext context,
  NoteEntry note, {
  required bool mediaActive,
}) {
  final blocks = note.blocks.isNotEmpty
      ? note.blocks
      : _legacyBlocksFromNote(note);
  final photoAttachments = blocks
      .where((block) => block.type == NoteBlockType.photo)
      .map((block) => block.attachment)
      .whereType<NoteAttachment>()
      .toList(growable: false);
  if (blocks.isEmpty) {
    return [
      _LinkifiedMemoText(
        text: note.body,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ];
  }

  final widgets = <Widget>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    switch (block.type) {
      case NoteBlockType.paragraph:
        final text = block.text?.trim() ?? '';
        if (text.isNotEmpty) {
          final location = _tryParseLocationMemo(text);
          widgets.add(
            location == null
                ? _LinkifiedMemoText(
                    text: text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  )
                : _LocationMemoCard(
                    location: location,
                    strings: context.strings,
                    width: double.infinity,
                  ),
          );
        }
      case NoteBlockType.photo:
      case NoteBlockType.video:
      case NoteBlockType.audio:
      case NoteBlockType.file:
        final attachment = block.attachment;
        if (attachment != null) {
          widgets.add(
            _EmbeddedAttachmentBlock(
              attachment: attachment,
              mediaActive: mediaActive,
              photoAttachments: photoAttachments,
              photoIndex: attachment.type == AttachmentType.photo
                  ? photoAttachments.indexOf(attachment)
                  : null,
            ),
          );
        }
    }
    if (i != blocks.length - 1) {
      widgets.add(const SizedBox(height: 16));
    }
  }
  return widgets;
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
    return Semantics(
      label: semanticLabel,
      child: Container(
        decoration: _sectionDecoration(context),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            children: children,
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.48,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return _ExtendedColorThemeSheetBody(
          current: current,
          themes: themes,
          titleFor: titleFor,
          subtitleFor: subtitleFor,
          sampleColorFor: sampleColorFor,
          scrollController: scrollController,
        );
      },
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
    required this.scrollController,
  });

  final AppColorTheme current;
  final List<AppColorTheme> themes;
  final String Function(AppColorTheme theme) titleFor;
  final String Function(AppColorTheme theme) subtitleFor;
  final Color Function(AppColorTheme theme) sampleColorFor;
  final ScrollController scrollController;

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
                  controller: scrollController,
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
          ),
        ),
      );
    },
  );
}

class _NotesToolbar extends ConsumerStatefulWidget {
  const _NotesToolbar({this.compact = false});

  final bool compact;

  @override
  ConsumerState<_NotesToolbar> createState() => _NotesToolbarState();
}

class _NotesToolbarState extends ConsumerState<_NotesToolbar> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final query = ref.watch(searchQueryProvider);
    final filters = ref.watch(searchFiltersControllerProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final tagSuggestions = ref.watch(visibleTagSuggestionsProvider);
    final hasAdvancedFilters = !filters.isDefault;
    final listDensity = ref.watch(notesListDensityControllerProvider);
    final privateModeActive = ref.watch(privacyScreenActiveProvider);
    final availableWidth = MediaQuery.sizeOf(context).width;
    final compactToolbarButtons = widget.compact || availableWidth < 560;
    final activeFilterCount =
        (filters.pinnedOnly ? 1 : 0) +
        (filters.withMediaOnly ? 1 : 0) +
        (filters.vaultId != null ? 1 : 0) +
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
                  initialValue: query,
                  decoration: InputDecoration(
                    labelText: strings.search,
                    hintText: strings.text(
                      'home.search.notes.diary.entries.and.attachment.labels',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: ref.read(searchQueryProvider.notifier).setQuery,
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
                  onTap: () {
                    setState(() {
                      _showAdvanced = !_showAdvanced;
                    });
                  },
                  child: Container(
                    height: 48,
                    width: compactToolbarButtons ? 48 : null,
                    constraints: BoxConstraints(
                      minWidth: compactToolbarButtons ? 48 : 84,
                    ),
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(
                      horizontal: compactToolbarButtons ? 0 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: _showAdvanced || hasAdvancedFilters
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
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '$activeFilterCount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.tune_rounded, size: 20),
                                    const SizedBox(width: 6),
                                    Text(
                                      strings.text('home.filters'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                  ],
                                ),
                              ),
                              if (activeFilterCount > 0)
                                Positioned(
                                  top: 6,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '$activeFilterCount',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
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
          if (!_showAdvanced && filters.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in filters.tags)
                  InputChip(
                    label: Text('#$tag'),
                    onDeleted: () => ref
                        .read(searchFiltersControllerProvider.notifier)
                        .removeTag(tag),
                  ),
              ],
            ),
          ],
          if (_showAdvanced) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('home.filters'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: filters.pinnedOnly,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(strings.text('home.pinned.only')),
                    onChanged: (value) => ref
                        .read(searchFiltersControllerProvider.notifier)
                        .setPinnedOnly(value ?? false),
                  ),
                  CheckboxListTile(
                    value: filters.withMediaOnly,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(strings.text('home.with.media')),
                    onChanged: (value) => ref
                        .read(searchFiltersControllerProvider.notifier)
                        .setWithMediaOnly(value ?? false),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(filters.vaultId ?? 'all-vaults'),
                    initialValue: filters.vaultId,
                    decoration: InputDecoration(
                      labelText: strings.text('home.vault'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(strings.text('home.all.visible.vaults')),
                      ),
                      for (final vault in visibleVaults)
                        DropdownMenuItem<String?>(
                          value: vault.id,
                          child: Text(_vaultDisplayName(context, vault)),
                        ),
                    ],
                    onChanged: ref
                        .read(searchFiltersControllerProvider.notifier)
                        .setVault,
                  ),
                  const SizedBox(height: 12),
                  _TagAutocompleteField(
                    key: const Key('search-tag-input'),
                    suggestions: tagSuggestions,
                    label: strings.text('home.filter.by.tag'),
                    hintText: strings.text('home.add.tags.to.narrow.the.list'),
                    existingTags: filters.tags,
                    onTagSelected: ref
                        .read(searchFiltersControllerProvider.notifier)
                        .addTag,
                  ),
                  if (filters.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in filters.tags)
                          InputChip(
                            label: Text('#$tag'),
                            onDeleted: () => ref
                                .read(searchFiltersControllerProvider.notifier)
                                .removeTag(tag),
                          ),
                      ],
                    ),
                  ],
                  if (hasAdvancedFilters) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: ref
                            .read(searchFiltersControllerProvider.notifier)
                            .reset,
                        child: Text(strings.text('home.reset.filters')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
  });

  final List<String> suggestions;
  final String label;
  final String hintText;
  final List<String> existingTags;
  final ValueChanged<String> onTagSelected;

  @override
  State<_TagAutocompleteField> createState() => _TagAutocompleteFieldState();
}

class _TagAutocompleteFieldState extends State<_TagAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitTag(String raw) {
    final normalized = normalizeNoteTag(raw);
    if (normalized.isEmpty) {
      return;
    }
    final existingKeys = widget.existingTags.map(canonicalizeNoteTag).toSet();
    if (existingKeys.contains(canonicalizeNoteTag(normalized))) {
      _controller.clear();
      return;
    }
    widget.onTagSelected(normalized);
    _controller.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final existingKeys = widget.existingTags
            .map(canonicalizeNoteTag)
            .toSet();
        final seenKeys = <String>{};
        final filteredSuggestions = <String>[
          for (final tag in widget.suggestions)
            if (!existingKeys.contains(canonicalizeNoteTag(tag)) &&
                seenKeys.add(canonicalizeNoteTag(tag)))
              tag,
        ];
        final input = canonicalizeNoteTag(value.text);
        if (input.isEmpty) {
          return filteredSuggestions.take(8);
        }
        return filteredSuggestions
            .where((tag) => canonicalizeNoteTag(tag).contains(input))
            .take(8);
      },
      displayStringForOption: (option) => option,
      onSelected: _submitTag,
      fieldViewBuilder:
          (context, textEditingController, focusNode, onSubmitted) {
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hintText,
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.sell_outlined),
              ),
              onFieldSubmitted: _submitTag,
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        final matches = options.toList(growable: false);
        if (matches.isEmpty) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 240),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                children: [
                  for (final option in matches)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.sell_outlined, size: 18),
                      title: Text(option),
                      onTap: () => onSelected(option),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
    final bodyText = note.body.trim();
    final hasDistinctBody =
        bodyText.isNotEmpty &&
        bodyText.replaceAll('\n', ' ').trim() != note.title.trim();
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
                note.body,
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
  const _NoteEditorSheet({this.note, this.initialCreatedAt});

  final NoteEntry? note;
  final DateTime? initialCreatedAt;

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
  final Set<String> _pendingAttachmentDeletes = <String>{};
  int? _activeRichParagraphIndex;
  String? _selectedVaultId;
  bool _saved = false;
  bool _draftLoaded = false;
  bool _editorDisposed = false;
  Timer? _draftSaveTimer;

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
    _attachments = [...?widget.note?.attachments];
    _tags = [...?widget.note?.tags];
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
    setState(() {
      _createdAt = draft.createdAt;
      _isPinned = draft.isPinned;
      _editorMode = draft.editorMode;
      _selectedVaultId = draft.vaultId;
      _tags = [...draft.tags];
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
        onPressed: () {
          ref.read(noteEditorDraftStoreProvider).clear();
        },
      ),
    );
  }

  void _scheduleDraftPersist() {
    _updateCanSubmit();
    if (widget.note != null) {
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
      ref
          .read(noteEditorDraftStoreProvider)
          .save(
            NoteEditorDraftSnapshot(
              createdAt: _createdAt,
              isPinned: _isPinned,
              editorMode: _editorMode,
              vaultId: vaultId,
              tags: _tags,
              quickContent: _contentController.text,
              quickAttachments: _attachments,
              richBlocks: _richBlocksToNoteBlocks(),
            ),
          );
    });
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
    if (_selectedVaultId == 'everyday' &&
        widget.note != null &&
        widget.note!.vaultId != 'everyday' &&
        privateTargets.any((vault) => vault.id == widget.note!.vaultId)) {
      _selectedVaultId = widget.note!.vaultId;
    }
    final isPrivateSelection = _selectedVaultId != 'everyday';

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
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
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
                          PopupMenuButton<NoteEditorMode>(
                            tooltip: _editorMode == NoteEditorMode.quick
                                ? strings.quickMemo
                                : strings.richMemo,
                            icon: Icon(
                              _editorMode == NoteEditorMode.quick
                                  ? Icons.notes_outlined
                                  : Icons.view_stream_outlined,
                              color: _mutedTextColor(context),
                            ),
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
                              PopupMenuItem(
                                value: MediaImportAction.addLocation,
                                child: _MediaMenuEntry(
                                  icon: Icons.my_location_outlined,
                                  label: strings.addCurrentLocation,
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
                    ),
                  ],
                ),
              ),
            ),
            Text(
              widget.note == null ? strings.newNote : strings.editNote,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (_editorMode == NoteEditorMode.quick) ...[
                    TextField(
                      key: const Key('note-content-input'),
                      controller: _contentController,
                      focusNode: _quickContentFocusNode,
                      autofocus: widget.note == null,
                      minLines: 12,
                      maxLines: null,
                      decoration: InputDecoration(
                        labelText: strings.memoLabel,
                        hintText: strings.memoFirstLineHint,
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
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
        margin: useFloating
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
      await _handleLocationAction();
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

  Future<void> _handleLocationAction() async {
    final strings = context.strings;
    try {
      final locationServiceEnabled =
          kIsWeb || await Geolocator.isLocationServiceEnabled();
      if (!locationServiceEnabled) {
        if (!mounted) {
          return;
        }
        _showEditorSnackBar(content: Text(strings.locationServicesOff));
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
        _showEditorSnackBar(content: Text(strings.locationPermissionRequired));
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
      _insertLocationText(
        _formatLocationMemo(position, strings, estimatedAddress: address),
      );
      _showEditorSnackBar(content: Text(strings.currentLocationAdded));
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showEditorSnackBar(content: Text(strings.currentLocationUnavailable));
    }
  }

  void _insertLocationText(String locationText) {
    setState(() {
      if (_editorMode == NoteEditorMode.quick) {
        final text = _contentController.text;
        final selection = _contentController.selection;
        final insertionOffset = selection.isValid
            ? selection.baseOffset.clamp(0, text.length)
            : text.length;
        final prefix = insertionOffset > 0 && !text.endsWith('\n')
            ? '\n\n'
            : '';
        final suffix = insertionOffset < text.length ? '\n\n' : '';
        final nextText = text.replaceRange(
          insertionOffset,
          insertionOffset,
          '$prefix$locationText$suffix',
        );
        final nextOffset =
            insertionOffset + prefix.length + locationText.length;
        _contentController.text = nextText;
        _contentController.selection = TextSelection.collapsed(
          offset: nextOffset,
        );
        return;
      }

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
        if (text.trim().isEmpty) {
          controller.text = locationText;
          final trailingParagraph = _RichBlockDraft.paragraph();
          _attachRichBlockListener(trailingParagraph);
          nextBlocks.insert(insertionIndex + 1, trailingParagraph);
          paragraphToFocus = trailingParagraph;
        } else {
          final beforeText = text.substring(0, cursorOffset);
          final afterText = text.substring(cursorOffset);
          current.dispose();
          nextBlocks.removeAt(insertionIndex);

          final replacement = <_RichBlockDraft>[];
          if (beforeText.trim().isNotEmpty) {
            final beforeParagraph = _RichBlockDraft.paragraph(beforeText);
            _attachRichBlockListener(beforeParagraph);
            replacement.add(beforeParagraph);
          }

          final locationParagraph = _RichBlockDraft.paragraph(locationText);
          _attachRichBlockListener(locationParagraph);
          replacement.add(locationParagraph);

          final afterParagraph = _RichBlockDraft.paragraph(afterText);
          _attachRichBlockListener(afterParagraph);
          replacement.add(afterParagraph);

          nextBlocks.insertAll(insertionIndex, replacement);
          paragraphToFocus = afterParagraph;
        }
      } else {
        final paragraph = _RichBlockDraft.paragraph(locationText);
        _attachRichBlockListener(paragraph);
        final trailingParagraph = _RichBlockDraft.paragraph();
        _attachRichBlockListener(trailingParagraph);
        nextBlocks.insertAll(insertionIndex, [paragraph, trailingParagraph]);
        paragraphToFocus = trailingParagraph;
      }

      _richBlocks = nextBlocks;
      _activeRichParagraphIndex = _richBlocks.indexOf(paragraphToFocus);
      _requestParagraphFocus(paragraphToFocus, focusOffset);
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
    );
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    for (final filePath in _pendingAttachmentDeletes) {
      await attachmentStore.deleteAttachment(filePath);
    }
    _pendingAttachmentDeletes.clear();
    await ref
        .read(lastNoteEditorSettingsControllerProvider.notifier)
        .remember(mode: _editorMode, vaultId: _selectedVaultId!);
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

String _formatLocationMemo(
  Position position,
  AppStrings strings, {
  String? estimatedAddress,
}) {
  final latitude = position.latitude.toStringAsFixed(6);
  final longitude = position.longitude.toStringAsFixed(6);
  final accuracy = position.accuracy.isFinite
      ? '${position.accuracy.round()}m'
      : '-';
  final mapUrl = 'https://maps.google.com/?q=$latitude,$longitude';
  return strings.locationMemo(
    latitude: latitude,
    longitude: longitude,
    accuracy: accuracy,
    mapUrl: mapUrl,
    estimatedAddress: estimatedAddress,
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

_LocationMemoData? _tryParseLocationMemo(String text) {
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
                decoration: InputDecoration(
                  semanticCounterText: '',
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

class _QuickAttachmentSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          if (attachments.isEmpty)
            Text(
              kIsWeb ? strings.attachFromBrowser : strings.attachFromDevice,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            )
          else
            for (var i = 0; i < attachments.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EditableAttachmentTile(
                  attachment: attachments[i],
                  onRemove: () => onRemove(i),
                  onMovePrevious: i > 0 ? () => onMove(i, -1) : null,
                  onMoveNext: i < attachments.length - 1
                      ? () => onMove(i, 1)
                      : null,
                ),
              ),
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

  @override
  void didUpdateWidget(covariant _AttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.filePath != widget.attachment.filePath ||
        oldWidget.attachment.type != widget.attachment.type ||
        oldWidget.attachment.previewBytesBase64 !=
            widget.attachment.previewBytesBase64) {
      _bytesFuture = null;
      _futureFilePath = null;
    }
  }

  Future<List<int>?> _attachmentBytesFuture(String filePath) {
    if (_bytesFuture != null && _futureFilePath == filePath) {
      return _bytesFuture!;
    }
    _futureFilePath = filePath;
    return _bytesFuture = ref
        .read(encryptedAttachmentStoreProvider)
        .readAttachment(filePath, type: widget.attachment.type);
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
      return _AttachmentImageBox(
        bytes: base64Decode(previewBytesBase64),
        size: size,
      );
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
        return _AttachmentImageBox(bytes: bytes, size: size);
      },
    );
  }
}

class _AttachmentImageBox extends StatelessWidget {
  const _AttachmentImageBox({required this.bytes, this.size = 72});

  final List<int> bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        Uint8List.fromList(bytes),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
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
      future: _readPhotoAttachmentBytes(ref, attachment),
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
