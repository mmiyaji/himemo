import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pinput/pinput.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/sync_bundle_preview.dart';
import '../domain/note_entry.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';

enum AppSection { notes, calendar, settings }

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  static const notesNavKey = Key('nav-notes');
  static const calendarNavKey = Key('nav-calendar');
  static const settingsNavKey = Key('nav-settings');
  static const addNoteKey = Key('add-note-button');

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 840;
    final section = _sectionForLocation(GoRouterState.of(context).uri.path);
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final flavor =
        FlavorConfig.instance.variables['flavor'] as String? ?? 'development';

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForSection(section)),
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
                    flavorName: flavor,
                    onSectionSelected: (target) =>
                        _goToSection(context, target),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  Expanded(child: child),
                ],
              )
            : child,
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: AppSection.values.indexOf(section),
              onDestinationSelected: (index) {
                _goToSection(context, AppSection.values[index]);
              },
              destinations: const [
                NavigationDestination(
                  key: notesNavKey,
                  icon: Icon(Icons.notes_outlined),
                  selectedIcon: Icon(Icons.notes_rounded),
                  label: 'Notes',
                ),
                NavigationDestination(
                  key: calendarNavKey,
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Calendar',
                ),
                NavigationDestination(
                  key: settingsNavKey,
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
      floatingActionButton: section == AppSection.notes
          ? FloatingActionButton.small(
              key: addNoteKey,
              onPressed: () => showNoteEditorSheet(context, ref),
              tooltip: 'Add note',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _goToSection(BuildContext context, AppSection section) {
    switch (section) {
      case AppSection.notes:
        context.go('/notes');
      case AppSection.calendar:
        context.go('/calendar');
      case AppSection.settings:
        context.go('/settings');
    }
  }

  String _titleForSection(AppSection section) {
    switch (section) {
      case AppSection.notes:
        return 'HiMemo';
      case AppSection.calendar:
        return 'Calendar';
      case AppSection.settings:
        return 'Settings';
    }
  }

  AppSection _sectionForLocation(String location) {
    if (location.startsWith('/calendar')) {
      return AppSection.calendar;
    }
    if (location.startsWith('/settings')) {
      return AppSection.settings;
    }
    return AppSection.notes;
  }
}

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String? _selectedNoteId;
  late final PageController _detailPageController;

  @override
  void initState() {
    super.initState();
    _detailPageController = PageController();
  }

  @override
  void dispose() {
    _detailPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width;
    final useSplitView = width >= 1180;
    final useCompactHeader = !useSplitView &&
        width < 720 &&
        screenSize.height > screenSize.width;
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final privateVaultUnlocked = ref.watch(
      privateVaultSessionControllerProvider,
    );
    final visibleNotes = ref.watch(visibleNotesProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);

    if (visibleNotes.isNotEmpty &&
        (_selectedNoteId == null ||
            visibleNotes.every((note) => note.id != _selectedNoteId))) {
      _selectedNoteId = visibleNotes.first.id;
    }

    final selectedIndex = _selectedNoteId == null
        ? -1
        : visibleNotes.indexWhere((note) => note.id == _selectedNoteId);

    if (useSplitView && selectedIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_detailPageController.hasClients) {
          return;
        }
        final currentPage = _detailPageController.page?.round();
        if (currentPage == selectedIndex) {
          return;
        }
        _detailPageController.jumpToPage(selectedIndex);
      });
    }

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
                selectedNoteId: _selectedNoteId,
                onNoteSelected: (note) => _openMobileNoteActions(
                  context,
                  note,
                  visibleNotes,
                ),
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (activeIdentity.id != 'daily') ...[
                _IdentityHeader(identity: activeIdentity),
                const SizedBox(height: 12),
              ],
              if (activeIdentity.id == 'private' && !privateVaultUnlocked) ...[
                const SizedBox(height: 12),
                const _PrivateVaultLockedNotice(),
              ],
              const _NotesToolbar(),
              const SizedBox(height: 16),
              if (visibleNotes.isEmpty)
                const _EmptyNotesState()
              else
                Container(
                  decoration: _sectionDecoration(context),
                  child: Column(
                    children: [
                      for (var i = 0; i < visibleNotes.length; i++) ...[
                        _NoteListTile(
                          note: visibleNotes[i],
                          vaultName: ref
                              .watch(vaultByIdProvider(visibleNotes[i].vaultId))
                              .name,
                          showVaultName: visibleVaults.length > 1,
                          selected: _selectedNoteId == visibleNotes[i].id,
                          onTap: () {
                            setState(() {
                              _selectedNoteId = visibleNotes[i].id;
                            });
                          },
                        ),
                        if (i != visibleNotes.length - 1)
                          Divider(
                            height: 1,
                            color: Theme.of(context).dividerColor,
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: visibleNotes.isEmpty
                ? const _EmptyNotesState()
                : _NoteDetailPager(
                    notes: visibleNotes,
                    selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                    controller: _detailPageController,
                    onPageChanged: (index) {
                      setState(() {
                        _selectedNoteId = visibleNotes[index].id;
                      });
                    },
                    onEdit: (note) =>
                        showNoteEditorSheet(context, ref, note: note),
                    onDelete: (note) => _deleteNote(context, note),
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
    final initialIndex = visibleNotes.indexWhere((entry) => entry.id == note.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: _NoteDetailPager(
              notes: visibleNotes,
              selectedIndex: initialIndex < 0 ? 0 : initialIndex,
              onPageChanged: (index) {
                setState(() {
                  _selectedNoteId = visibleNotes[index].id;
                });
              },
              onEdit: (selectedNote) async {
                Navigator.of(context).pop();
                await showNoteEditorSheet(context, ref, note: selectedNote);
              },
              onDelete: (selectedNote) async {
                Navigator.of(context).pop();
                await _deleteNote(context, selectedNote);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteNote(BuildContext context, NoteEntry note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete note'),
          content: Text('Delete "${note.title}" permanently from this device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('delete-note-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(notesControllerProvider.notifier).delete(note.id);
      if (_selectedNoteId == note.id) {
        setState(() {
          _selectedNoteId = null;
        });
      }
    }
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
    final notes = ref.watch(visibleNotesProvider);
    final noteDays = _sortedNoteDays(notes);
    final markedDays = noteDays.toSet();
    final sameDayNotes = notes
        .where((note) => _isSameDay(note.createdAt, _selectedDay))
        .toList(growable: false);
    final previousDay = _adjacentNoteDay(noteDays, _selectedDay, backwards: true);
    final nextDay = _adjacentNoteDay(noteDays, _selectedDay, backwards: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionIntro(
          title: 'Calendar',
          description:
              'Review notes grouped by day and keep diary entries anchored to dates.',
        ),
        const SizedBox(height: 16),
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
                    tooltip: 'Previous day with notes',
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${_selectedDay.year}/${_selectedDay.month.toString().padLeft(2, '0')}/${_selectedDay.day.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: nextDay == null
                        ? null
                        : () => _selectCalendarDay(nextDay),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Next day with notes',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (sameDayNotes.isEmpty)
                Text(
                  'No notes on this day yet.',
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

  List<DateTime> _sortedNoteDays(List<NoteEntry> notes) {
    final days = notes
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
                            tooltip: 'Previous day with notes',
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
                            tooltip: 'Next day with notes',
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
                                title: const Text('Delete note'),
                                content: Text(
                                  'Delete "${selectedNote.title}" permanently from this device?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
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

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
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
              tooltip: 'Previous month',
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(onPressed: onTodaySelected, child: const Text('Today')),
            IconButton(
              onPressed: onNextMonth,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next month',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final weekday in _weekdays)
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
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
  static const blueColorThemeKey = Key('color-theme-blue-option');
  static const greenColorThemeKey = Key('color-theme-green-option');
  static const orangeColorThemeKey = Key('color-theme-orange-option');
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

  Future<void> _switchIdentity(WidgetRef ref, String identityId) async {
    await ref.read(activeIdentityProvider.notifier).switchTo(identityId);
    if (identityId != 'private') {
      ref.read(privateVaultSessionControllerProvider.notifier).lock();
    }
  }

  Future<void> _showSetCoverKeyDialog(
      BuildContext context, WidgetRef ref) async {
    final secret = await _showSecretSetupDialog(
      context,
      title: 'Set cover key',
      label: 'Cover key',
      confirmLabel: 'Confirm cover key',
      helperText: 'Use this key to open the alternate everyday view.',
    );
    if (secret == null) {
      return;
    }
    await ref
        .read(coverModeSecretControllerProvider.notifier)
        .configure(secret);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cover key saved.')),
      );
    }
  }

  Future<void> _confirmResetCoverKey(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset cover key'),
        content: const Text(
          'This removes the configured cover key for alternate mode access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
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
    final secret = await _showSingleSecretPrompt(
      context,
      title: 'Enter special access key',
      label: 'Access key',
      helperText: 'A valid key switches the app into another mode.',
      actionLabel: 'Unlock mode',
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
        const SnackBar(content: Text('Private mode is now active.')),
      );
      return;
    }
    if (await ref
        .read(coverModeSecretControllerProvider.notifier)
        .verify(secret)) {
      await _switchIdentity(ref, 'cover');
      messenger.showSnackBar(
        const SnackBar(content: Text('Cover mode is now active.')),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('That access key did not match any mode.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIdentity = ref.watch(activeIdentityProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final colorTheme = ref.watch(appColorThemeControllerProvider);
    final appLockEnabled = ref.watch(appLockSettingsControllerProvider);
    final appLockRelockDelay = ref.watch(appLockRelockDelayControllerProvider);
    final appSessionUnlocked = ref.watch(appSessionUnlockControllerProvider);
    final deviceAuthState = ref.watch(deviceAuthControllerProvider);
    final pinLockState = ref.watch(appPinLockControllerProvider);
    final privateVaultConfigured = ref.watch(
      privateVaultSecretControllerProvider,
    );
    final coverModeConfigured = ref.watch(coverModeSecretControllerProvider);
    final privateVaultUnlocked = ref.watch(
      privateVaultSessionControllerProvider,
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
    final packageInfo = ref.watch(packageInfoProvider);
    final flavorName =
        FlavorConfig.instance.variables['flavor'] as String? ?? 'development';
    final displayName =
        FlavorConfig.instance.variables['displayName'] as String? ?? 'HiMemo';
    final noteCount = ref.watch(notesControllerProvider).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionIntro(
          title: 'Settings',
          description: 'Manage access, sync, and display policy.',
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Access modes',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Current mode'),
              subtitle: Text(
                activeIdentity == 'daily'
                    ? 'Normal memo mode'
                    : ref.watch(activeIdentityDataProvider).name,
              ),
            ),
            Text(
              'The app stays in normal memo mode by default. Enter a special access key only when you need another view.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => _showSpecialAccessKeyDialog(context, ref),
                  child: const Text('Enter special access key'),
                ),
                OutlinedButton(
                  onPressed: activeIdentity == 'daily'
                      ? null
                      : () => _switchIdentity(ref, 'daily'),
                  child: const Text('Return to normal mode'),
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
                    coverModeConfigured ? 'Change cover key' : 'Set cover key',
                  ),
                ),
                OutlinedButton(
                  onPressed: coverModeConfigured
                      ? () => _confirmResetCoverKey(context, ref)
                      : null,
                  child: const Text('Reset cover key'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'App unlock',
          children: [
            SwitchListTile.adaptive(
              key: appLockToggleKey,
              value: appLockEnabled,
              contentPadding: EdgeInsets.zero,
              title: kIsWeb
                  ? const Text('Require PIN on launch')
                  : const Text('Require device auth on launch'),
              subtitle: Text(
                kIsWeb
                    ? pinLockState.summary
                    : (deviceAuthState.isAvailable
                        ? 'Available: ${deviceAuthState.summary}'
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
                      title: 'Set unlock PIN',
                      confirmLabel: 'Save PIN',
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
                      .authenticate(
                        reason: 'Enable device authentication for HiMemo',
                      );
                  if (!authenticated) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Device authentication was not completed.',
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Session status'),
              subtitle: Text(
                appSessionUnlocked
                    ? 'Current session is unlocked.'
                    : (kIsWeb
                        ? 'Current session is locked until the correct PIN is entered.'
                        : 'Current session is locked until device authentication succeeds.'),
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
                              ? 'Change unlock PIN'
                              : 'Set unlock PIN',
                          confirmLabel: pinLockState.isConfigured
                              ? 'Update PIN'
                              : 'Save PIN',
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
                              content: Text(
                                pinLockState.isConfigured
                                    ? 'Unlock PIN updated.'
                                    : 'Unlock PIN configured.',
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        pinLockState.isConfigured ? 'Change PIN' : 'Set PIN',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: pinLockState.isConfigured
                          ? () async {
                              final shouldRemove = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Remove unlock PIN'),
                                  content: const Text(
                                    'Disable the web unlock PIN for this browser?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Remove'),
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
                                  .read(appLockSettingsControllerProvider
                                      .notifier)
                                  .setEnabled(false);
                            }
                          : null,
                      child: const Text('Remove PIN'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Web PIN lock is a browser-level access gate. It does not replace device-backed secure storage.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            const Text('Re-lock after app leaves the foreground'),
            const SizedBox(height: 8),
            _ThemeOptionTile(
              tileKey: appLockRelockImmediateKey,
              title: 'Immediately',
              subtitle: 'Lock the app as soon as it moves to the background.',
              selected: appLockRelockDelay == AppLockRelockDelay.immediate,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.immediate),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock30SecondsKey,
              title: 'After 30 seconds',
              subtitle: 'Allow quick app switching without immediate re-auth.',
              selected: appLockRelockDelay == AppLockRelockDelay.seconds30,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.seconds30),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock2MinutesKey,
              title: 'After 2 minutes',
              subtitle: 'Useful when capturing photos or audio between notes.',
              selected: appLockRelockDelay == AppLockRelockDelay.minutes2,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes2),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock10MinutesKey,
              title: 'After 10 minutes',
              subtitle: 'Keep the app open during longer editing sessions.',
              selected: appLockRelockDelay == AppLockRelockDelay.minutes10,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes10),
            ),
            SwitchListTile.adaptive(
              key: privateVaultLockOnAppLockKey,
              value: privateVaultLockOnAppLock,
              contentPadding: EdgeInsets.zero,
              title: const Text('Lock private vault when app locks'),
              subtitle: const Text(
                'Apply app re-lock to the private vault session too.',
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
                                  reason:
                                      'Unlock HiMemo with device authentication',
                                )
                            : null,
                    child: kIsWeb
                        ? const Text('PIN unlock on lock screen')
                        : const Text('Authenticate now'),
                  ),
                  OutlinedButton(
                    key: appLockLockNowKey,
                    onPressed: appLockEnabled
                        ? () => ref
                            .read(appSessionUnlockControllerProvider.notifier)
                            .lock()
                        : null,
                    child: const Text('Lock session now'),
                  ),
                  OutlinedButton(
                    onPressed: kIsWeb
                        ? null
                        : () => ref
                            .read(deviceAuthControllerProvider.notifier)
                            .refresh(),
                    child: kIsWeb
                        ? const Text('Web PIN active')
                        : const Text('Refresh availability'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Private vault',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Status'),
              subtitle: Text(
                privateVaultConfigured
                    ? (privateVaultUnlocked
                        ? 'Configured and unlocked for this session.'
                        : 'Configured and locked. A separate key is required.')
                    : 'Not configured yet. Set a separate key for the private vault.',
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
                    child: const Text('Set private key'),
                  ),
                if (privateVaultConfigured && !privateVaultUnlocked)
                  FilledButton(
                    key: privateVaultUnlockKey,
                    onPressed: () =>
                        _showUnlockPrivateVaultDialog(context, ref),
                    child: const Text('Unlock private vault'),
                  ),
                if (privateVaultUnlocked)
                  FilledButton.tonal(
                    key: privateVaultLockKey,
                    onPressed: () => ref
                        .read(privateVaultSessionControllerProvider.notifier)
                        .lock(),
                    child: const Text('Lock private vault'),
                  ),
                if (privateVaultConfigured)
                  OutlinedButton(
                    key: privateVaultResetKey,
                    onPressed: () => _confirmResetPrivateKey(context, ref),
                    child: const Text('Reset private key'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Sync target',
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
              title: const Text('Selected target'),
              subtitle: Text(_syncSubtitle(syncProvider)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Authentication'),
              subtitle: Text(_syncAuthSummary(syncProvider, syncAuthState)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pending sync queue'),
              subtitle: Text(
                syncQueueSummary.when(
                  data: (summary) {
                    if (!summary.hasPendingChanges) {
                      return 'No pending device changes.';
                    }
                    final timestamp = summary.lastQueuedAt;
                    final stampText = timestamp == null
                        ? 'queue ready'
                        : 'last queued ${_formatDateTime(timestamp)}';
                    return '${summary.totalChanges} changes pending (${summary.upserts} upserts, ${summary.deletes} deletes), $stampText';
                  },
                  loading: () => 'Checking pending changes...',
                  error: (_, _) => 'Unable to inspect the local sync queue.',
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remote bundle'),
              subtitle:
                  Text(_remoteBundleSummary(syncProvider, syncTransferState)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sync key fingerprint'),
              subtitle: Text(
                syncBundleFingerprint.when(
                  data: (value) => value,
                  loading: () => 'Preparing sync key...',
                  error: (_, _) => 'Unable to read the sync key fingerprint.',
                ),
              ),
            ),
            Wrap(
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
                      await Clipboard.setData(ClipboardData(text: backupCode));
                      if (!context.mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Sync key copied to clipboard.'),
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(content: Text('$error')),
                      );
                    }
                  },
                  child: const Text('Copy sync key'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final backupCode = await _showSyncKeyImportDialog(context);
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
                          content: Text(
                            'Sync key imported. Fingerprint: $fingerprint',
                          ),
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(content: Text('$error')),
                      );
                    }
                  },
                  child: const Text('Import sync key'),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Last sync activity'),
              subtitle: Text(
                syncBundleState.when(
                  data: (value) {
                    final entries = <String>[];
                    if (value.lastUploadedAt != null) {
                      entries.add(
                        'Last upload ${_formatDateTime(value.lastUploadedAt!)}',
                      );
                    }
                    if (value.lastAppliedAt != null) {
                      entries.add(
                        'Last apply ${_formatDateTime(value.lastAppliedAt!)}',
                      );
                    }
                    if (value.lastRemoteModifiedAt != null) {
                      entries.add(
                        'Remote bundle ${_formatDateTime(value.lastRemoteModifiedAt!)}',
                      );
                    }
                    if (entries.isEmpty) {
                      return 'No sync activity has been recorded on this device yet.';
                    }
                    return entries.join('\n');
                  },
                  loading: () => 'Reading sync activity...',
                  error: (_, _) => 'Unable to read local sync activity.',
                ),
              ),
            ),
            if (syncTransferState.localBundle != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Local bundle cache'),
                subtitle: Text(
                  'Stored at ${syncTransferState.localBundle!.reference}',
                ),
              ),
            _ThemeOptionTile(
              tileKey: syncOffKey,
              title: 'Off',
              subtitle: 'Keep data on this device only.',
              selected: syncProvider == SyncProvider.off,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.off),
            ),
            _ThemeOptionTile(
              tileKey: syncICloudKey,
              title: 'iCloud',
              subtitle: 'Apple-managed app data sync target.',
              selected: syncProvider == SyncProvider.iCloud,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.iCloud),
            ),
            _ThemeOptionTile(
              tileKey: syncGoogleDriveKey,
              title: 'Google Drive',
              subtitle: 'Google Drive app-data sync target.',
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
                        : () => ref
                            .read(syncAuthControllerProvider.notifier)
                            .connectSelected(),
                    child: Text(
                      syncAuthState.isAuthenticated ? 'Reconnect' : 'Connect',
                    ),
                  ),
                if (syncProvider != SyncProvider.off &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncDisconnectKey,
                    onPressed: () => ref
                        .read(syncAuthControllerProvider.notifier)
                        .disconnectSelected(),
                    child: const Text('Disconnect'),
                  ),
                OutlinedButton(
                  key: syncRefreshRemoteKey,
                  onPressed: syncTransferState.isBusy
                      ? null
                      : () async {
                          await ref
                              .read(syncTransferControllerProvider.notifier)
                              .refreshRemoteStatus();
                          if (!context.mounted) {
                            return;
                          }
                          final message =
                              ref.read(syncTransferControllerProvider).message;
                          if (message == null || message.isEmpty) {
                            return;
                          }
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        },
                  child: const Text('Refresh remote'),
                ),
                if (syncProvider == SyncProvider.googleDrive &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncUploadBundleKey,
                    onPressed: syncTransferState.isBusy ||
                            syncConflictWarning != null
                        ? null
                        : () async {
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
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          },
                    child: const Text('Upload bundle'),
                  ),
                if (syncProvider == SyncProvider.googleDrive &&
                    syncAuthState.isAuthenticated &&
                    syncConflictWarning != null)
                  FilledButton.tonal(
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            final shouldForce = await showDialog<bool>(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: const Text('Force upload?'),
                                      content: const Text(
                                        'A newer remote bundle was found while this device still has pending changes. Force upload will overwrite the remote backup with this device state.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(
                                            context,
                                          ).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.of(
                                            context,
                                          ).pop(true),
                                          child: const Text('Force upload'),
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
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          },
                    child: const Text('Force upload'),
                  ),
                if (syncProvider == SyncProvider.googleDrive &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final history = await ref
                                  .read(
                                    syncTransferControllerProvider.notifier,
                                  )
                                  .listRemoteBundleHistory();
                              if (!context.mounted) {
                                return;
                              }
                              if (history.isEmpty) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No remote bundle history is available.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final selected = await _showBundleHistoryDialog(
                                context,
                                history,
                              );
                              if (selected == null) {
                                return;
                              }
                              final preview = await ref
                                  .read(
                                    syncTransferControllerProvider.notifier,
                                  )
                                  .downloadBundlePreview(selected);
                              if (!context.mounted) {
                                return;
                              }
                              final shouldKeep = await _showBundlePreviewDialog(
                                    context,
                                    preview,
                                    confirmLabel: 'Keep for apply',
                                  ) ??
                                  false;
                              if (!shouldKeep || !context.mounted) {
                                return;
                              }
                              final message = ref
                                  .read(syncTransferControllerProvider)
                                  .message;
                              if (message != null && message.isNotEmpty) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              } else {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Selected bundle is ready for apply.',
                                    ),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(content: Text('$error')),
                              );
                            }
                          },
                    child: const Text('Bundle history'),
                  ),
                if (syncProvider == SyncProvider.googleDrive &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncDownloadBundleKey,
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            await ref
                                .read(syncTransferControllerProvider.notifier)
                                .downloadLatestBundle();
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(syncTransferControllerProvider)
                                .message;
                            if (message == null || message.isEmpty) {
                              return;
                            }
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          },
                    child: const Text('Download bundle'),
                  ),
                if (syncTransferState.localBundle != null)
                  OutlinedButton(
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final preview = await ref
                                  .read(
                                    syncTransferControllerProvider.notifier,
                                  )
                                  .previewDownloadedBundle();
                              if (!context.mounted) {
                                return;
                              }
                              await _showBundlePreviewDialog(
                                context,
                                preview,
                                confirmLabel: 'Close',
                              );
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(content: Text('$error')),
                              );
                            }
                          },
                    child: const Text('Review bundle'),
                  ),
                if (syncTransferState.localBundle != null)
                  OutlinedButton(
                    key: syncApplyBundleKey,
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final preview = await ref
                                  .read(
                                    syncTransferControllerProvider.notifier,
                                  )
                                  .previewDownloadedBundle();
                              if (!context.mounted) {
                                return;
                              }
                              final shouldApply =
                                  await _showBundlePreviewDialog(
                                        context,
                                        preview,
                                        confirmLabel: 'Apply bundle',
                                      ) ??
                                      false;
                              if (!shouldApply) {
                                return;
                              }
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(content: Text('$error')),
                              );
                              return;
                            }
                            await ref
                                .read(syncTransferControllerProvider.notifier)
                                .applyDownloadedBundle();
                            if (!context.mounted) {
                              return;
                            }
                            final message = ref
                                .read(syncTransferControllerProvider)
                                .message;
                            if (message == null || message.isEmpty) {
                              return;
                            }
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          },
                    child: const Text('Apply bundle'),
                  ),
                OutlinedButton(
                  onPressed: () async {
                    final snapshot = await ref
                        .read(syncEngineProvider)
                        .prepareSnapshot(ref.read(notesControllerProvider));
                    if (!context.mounted) {
                      return;
                    }
                    await showDialog<void>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Prepared sync snapshot'),
                          content: Text(
                            'Notes: ${snapshot.notes.length}\n'
                            'Attachments: ${snapshot.attachments.length}\n'
                            'Queue: ${snapshot.summary.totalChanges} pending\n'
                            'Device ID: ${snapshot.deviceId}',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Text('Inspect snapshot'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Storage',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Saved notes on this device'),
              subtitle: Text('$noteCount entries'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () {
                  ref.read(notesControllerProvider.notifier).seedIfEmpty();
                },
                child: const Text('Restore sample notes if empty'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Build flavor',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(displayName),
              subtitle: Text('Current flavor: $flavorName'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Display mode',
          children: [
            _ThemeOptionTile(
              tileKey: lightThemeKey,
              title: 'Light',
              subtitle: 'Keep the white memo-style interface.',
              selected: themeMode == ThemeMode.light,
              onTap: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .setMode(ThemeMode.light),
            ),
            _ThemeOptionTile(
              tileKey: systemThemeKey,
              title: 'System',
              subtitle: 'Follow the device setting.',
              selected: themeMode == ThemeMode.system,
              onTap: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .setMode(ThemeMode.system),
            ),
            _ThemeOptionTile(
              tileKey: darkThemeKey,
              title: 'Dark',
              subtitle: 'Use the higher-contrast dark theme explicitly.',
              selected: themeMode == ThemeMode.dark,
              onTap: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .setMode(ThemeMode.dark),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Color theme',
          children: [
            _ThemeOptionTile(
              tileKey: blueColorThemeKey,
              title: 'Blue',
              subtitle: 'Primary blue with calm light-blue support colors.',
              selected: colorTheme == AppColorTheme.blue,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.blue),
            ),
            _ThemeOptionTile(
              tileKey: greenColorThemeKey,
              title: 'Green',
              subtitle: 'Muted green palette for lower visual tension.',
              selected: colorTheme == AppColorTheme.green,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.green),
            ),
            _ThemeOptionTile(
              tileKey: orangeColorThemeKey,
              title: 'Orange',
              subtitle:
                  'Warm orange palette for highlighted actions and notes.',
              selected: colorTheme == AppColorTheme.orange,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.orange),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'About',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('App version'),
              subtitle: Text(
                packageInfo.when(
                  data: (info) => info.displayVersion,
                  loading: () => 'Reading app version...',
                  error: (_, _) => '1.0.0 (1)',
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('OSS licenses'),
              subtitle: const Text(
                'View bundled open-source software licenses.',
              ),
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

  String _syncSubtitle(SyncProvider provider) {
    switch (provider) {
      case SyncProvider.off:
        return 'Sync is disabled.';
      case SyncProvider.iCloud:
        return 'iCloud selected. Account wiring comes next.';
      case SyncProvider.googleDrive:
        return 'Google Drive selected. Account wiring comes next.';
    }
  }

  String _syncAuthSummary(SyncProvider provider, SyncAuthState authState) {
    if (provider == SyncProvider.off) {
      return 'No cloud account is connected.';
    }

    switch (authState.stage) {
      case SyncAuthStage.idle:
        return 'No account connected yet.';
      case SyncAuthStage.busy:
        return 'Waiting for authentication to complete...';
      case SyncAuthStage.authenticated:
        final identity =
            authState.email ?? authState.displayName ?? authState.userId;
        final suffix = authState.message == null ? '' : ' ${authState.message}';
        return identity == null
            ? 'Connected.$suffix'
            : 'Connected as $identity.$suffix';
      case SyncAuthStage.unsupported:
      case SyncAuthStage.error:
        return authState.message ?? 'Authentication is not available.';
    }
  }

  Future<void> _showSetPrivateKeyDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final secretController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Set private key'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: secretController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Private key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Confirm private key',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final secret = secretController.text.trim();
                    final confirm = confirmController.text.trim();
                    if (secret.length < 4) {
                      setState(() {
                        errorText = 'Use at least 4 characters.';
                      });
                      return;
                    }
                    if (secret != confirm) {
                      setState(() {
                        errorText = 'Keys do not match.';
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
                  child: const Text('Save'),
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
    final secretController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Unlock private vault'),
              content: TextField(
                controller: secretController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Private key',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final matched = await ref
                        .read(privateVaultSecretControllerProvider.notifier)
                        .verify(secretController.text.trim());
                    if (!matched) {
                      setState(() {
                        errorText = 'Private key is not correct.';
                      });
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Unlock'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset private key'),
          content: const Text(
            'This removes the configured private-vault key and locks the private vault immediately.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(privateVaultSecretControllerProvider.notifier).clear();
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.activeIdentity,
    required this.flavorName,
    required this.onSectionSelected,
  });

  final AppSection section;
  final UnlockIdentity activeIdentity;
  final String flavorName;
  final ValueChanged<AppSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 256,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HiMemo',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (activeIdentity.id != 'daily') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${activeIdentity.name} active',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        flavorName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _mutedTextColor(context),
                            ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                const SizedBox(height: 8),
                _SidebarItem(
                  icon: Icons.notes_outlined,
                  selectedIcon: Icons.notes_rounded,
                  label: 'Notes',
                  selected: section == AppSection.notes,
                  onTap: () => onSectionSelected(AppSection.notes),
                ),
                _SidebarItem(
                  icon: Icons.calendar_month_outlined,
                  selectedIcon: Icons.calendar_month_rounded,
                  label: 'Calendar',
                  selected: section == AppSection.calendar,
                  onTap: () => onSectionSelected(AppSection.calendar),
                ),
                _SidebarItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: 'Settings',
                  selected: section == AppSection.settings,
                  onTap: () => onSectionSelected(AppSection.settings),
                ),
              ],
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
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              'Private vault is locked. Unlock it from Settings to reveal hidden notes.',
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
  });

  final VaultBucket vault;
  final List<NoteEntry> notes;
  final String? selectedNoteId;
  final ValueChanged<NoteEntry> onNoteSelected;

  @override
  Widget build(BuildContext context) {
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
                Text(vault.name),
                const SizedBox(height: 4),
                Text(
                  vault.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedTextColor(context),
                      ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          for (var i = 0; i < notes.length; i++) ...[
            if (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i]))
              _NoteDayDivider(date: notes[i].createdAt),
            _NoteListTile(
              note: notes[i],
              vaultName: vault.name,
              showVaultName: false,
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
    final label =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      color: Theme.of(context).colorScheme.surface,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _mutedTextColor(context),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.vaultName,
    required this.showVaultName,
    required this.selected,
    required this.onTap,
  });

  final NoteEntry note;
  final String vaultName;
  final bool showVaultName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final changedAt = note.updatedAt ?? note.createdAt;
    final dateLabel =
        '${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;
    final bodyText = note.body.trim();
    final hasDistinctBody =
        bodyText.isNotEmpty && bodyText.replaceAll('\n', ' ').trim() != note.title.trim();

    return Material(
      color: selected ? _selectedSurfaceColor(context) : Colors.transparent,
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
                    child: Text(
                      note.title,
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
                Text(
                  note.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _strongMutedTextColor(context),
                      ),
                ),
              if (note.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0;
                        i < note.attachments.length && i < 3;
                        i++) ...[
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
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '+${note.attachments.length - 3}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
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
                            color: _mutedTextColor(context),
                          ),
                    ),
                  if (showVaultName) const Spacer() else const Spacer(),
                  Text(
                    isEdited ? 'Edited $dateLabel' : dateLabel,
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

class _NoteDetailPager extends ConsumerStatefulWidget {
  const _NoteDetailPager({
    required this.notes,
    required this.selectedIndex,
    required this.onPageChanged,
    required this.onEdit,
    required this.onDelete,
    this.controller,
  });

  final List<NoteEntry> notes;
  final int selectedIndex;
  final PageController? controller;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<NoteEntry> onEdit;
  final ValueChanged<NoteEntry> onDelete;

  @override
  ConsumerState<_NoteDetailPager> createState() => _NoteDetailPagerState();
}

class _NoteDetailPagerState extends ConsumerState<_NoteDetailPager> {
  PageController? _ownedController;

  PageController get _pageController =>
      widget.controller ??
      (_ownedController ??= PageController(initialPage: widget.selectedIndex));

  @override
  void didUpdateWidget(covariant _NoteDetailPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null &&
        oldWidget.selectedIndex != widget.selectedIndex &&
        _ownedController?.hasClients == true) {
      final currentPage = _ownedController!.page?.round();
      if (currentPage != widget.selectedIndex) {
        _ownedController!.jumpToPage(widget.selectedIndex);
      }
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                tooltip: 'Previous note',
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
                tooltip: 'Next note',
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
                  'Swipe left or right to move between notes.',
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
            onPageChanged: widget.onPageChanged,
            itemBuilder: (context, index) {
              final note = widget.notes[index];
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _NoteDetailPane(
                  note: note,
                  vaultName: ref.watch(vaultByIdProvider(note.vaultId)).name,
                  onEdit: () => widget.onEdit(note),
                  onDelete: () => widget.onDelete(note),
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
    required this.vaultName,
    this.onEdit,
    this.onDelete,
  });

  final NoteEntry note;
  final String vaultName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final createdLabel =
        '${note.createdAt.year}/${note.createdAt.month}/${note.createdAt.day} ${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';
    final changedAt = note.updatedAt ?? note.createdAt;
    final updatedLabel =
        '${changedAt.year}/${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;

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
                tooltip: 'Edit note',
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete note',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            isEdited ? 'Edited $updatedLabel' : createdLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
          if (isEdited)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Created $createdLabel · Revision ${note.revision}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
              ),
            ),
          const SizedBox(height: 20),
          ..._buildDetailBlocks(context, note),
          ],
        ),
      ),
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _strongMutedTextColor(context),
              ),
        ),
      ],
    );
  }
}

List<Widget> _buildDetailBlocks(BuildContext context, NoteEntry note) {
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
      Text(
        note.body,
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
          widgets.add(
            Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          );
        }
      case NoteBlockType.photo:
      case NoteBlockType.video:
      case NoteBlockType.audio:
        final attachment = block.attachment;
        if (attachment != null) {
          widgets.add(
            _EmbeddedAttachmentBlock(
              attachment: attachment,
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
    blocks.add(
      NoteBlock(
        type: NoteBlockType.paragraph,
        text: note.body,
      ),
    );
  }
  for (final attachment in note.attachments) {
    blocks.add(
      NoteBlock(
        type: switch (attachment.type) {
          AttachmentType.photo => NoteBlockType.photo,
          AttachmentType.video => NoteBlockType.video,
          AttachmentType.audio => NoteBlockType.audio,
        },
        attachment: attachment,
      ),
    );
  }
  return blocks;
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.tileKey,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Key tileKey;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

Future<void> showNoteEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  NoteEntry? note,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: _NoteEditorSheet(note: note),
        ),
      );
    },
  );
}

class _NotesToolbar extends ConsumerWidget {
  const _NotesToolbar({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const Key('notes-search-input'),
            initialValue: query,
            decoration: const InputDecoration(
              labelText: 'Search',
              hintText: 'Search notes, diary entries, and attachment labels',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: ref.read(searchQueryProvider.notifier).setQuery,
          ),
          if (!compact && ref.watch(activeIdentityProvider) != 'daily') ...[
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
        bodyText.isNotEmpty && bodyText.replaceAll('\n', ' ').trim() != note.title.trim();
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
                  for (var i = 0; i < note.attachments.length && i < 3; i++) ...[
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
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
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
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No matching notes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new memo or clear the current search filter to see saved entries.',
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
  const _NoteEditorSheet({this.note});

  final NoteEntry? note;

  @override
  ConsumerState<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends ConsumerState<_NoteEditorSheet> {
  late final TextEditingController _contentController;
  late DateTime _createdAt;
  late bool _isPinned;
  late NoteEditorMode _editorMode;
  late List<NoteAttachment> _attachments;
  late List<_RichBlockDraft> _richBlocks;
  late final Set<String> _initialAttachmentPaths;
  int? _activeRichParagraphIndex;
  String? _selectedVaultId;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: _composeEditorContent());
    _contentController.addListener(_handleTextChanged);
    _createdAt = widget.note?.createdAt ?? DateTime.now();
    _isPinned = widget.note?.isPinned ?? false;
    _editorMode = widget.note?.editorMode ??
        ((widget.note?.blocks.isNotEmpty ?? false)
            ? NoteEditorMode.rich
            : NoteEditorMode.rich);
    _attachments = [...?widget.note?.attachments];
    _richBlocks = _buildInitialRichBlocks();
    for (final block in _richBlocks) {
      _attachRichBlockListener(block);
    }
    _activeRichParagraphIndex = _richBlocks.indexWhere(
      (block) => block.type == NoteBlockType.paragraph,
    );
    _initialAttachmentPaths = _attachments
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    _selectedVaultId = widget.note?.vaultId ?? 'everyday';
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final attachment in _allCurrentAttachments) {
        final filePath = attachment.filePath;
        if (filePath == null || _initialAttachmentPaths.contains(filePath)) {
          continue;
        }
        unawaited(
          ref.read(encryptedAttachmentStoreProvider).deleteAttachment(filePath),
        );
      }
    }
    _contentController.removeListener(_handleTextChanged);
    _contentController.dispose();
    for (final block in _richBlocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
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

  void _requestParagraphFocus(_RichBlockDraft block, int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = block.controller;
      final focusNode = block.focusNode;
      if (controller == null || focusNode == null) {
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

  @override
  Widget build(BuildContext context) {
    final visibleVaults = ref.watch(visibleVaultsProvider);
    if (_selectedVaultId == null && visibleVaults.isNotEmpty) {
      _selectedVaultId = visibleVaults.first.id;
    }
    if (!visibleVaults.any((vault) => vault.id == _selectedVaultId) &&
        visibleVaults.isNotEmpty) {
      _selectedVaultId = visibleVaults.first.id;
    }

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
                child: Row(
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
              ),
            ),
            Text(
              widget.note == null ? 'New note' : 'Edit note',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  SegmentedButton<NoteEditorMode>(
                    segments: const [
                      ButtonSegment(
                        value: NoteEditorMode.quick,
                        label: Text('Quick memo'),
                        icon: Icon(Icons.notes_outlined),
                      ),
                      ButtonSegment(
                        value: NoteEditorMode.rich,
                        label: Text('Rich memo'),
                        icon: Icon(Icons.view_stream_outlined),
                      ),
                    ],
                    selected: {_editorMode},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _editorMode = selection.first;
                        if (_editorMode == NoteEditorMode.rich &&
                            _richBlocks.isEmpty) {
                          final draft = _RichBlockDraft.paragraph();
                          _attachRichBlockListener(draft);
                          _richBlocks = [draft];
                          _activeRichParagraphIndex = 0;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_editorMode == NoteEditorMode.quick) ...[
                    TextField(
                      key: const Key('note-content-input'),
                      controller: _contentController,
                      autofocus: widget.note == null,
                      minLines: 12,
                      maxLines: null,
                      decoration: const InputDecoration(
                        labelText: 'Memo',
                        hintText: 'Use the first line as the title',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
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
                          _RichAttachmentSection(
                            onSelected: _handleAttachmentAction,
                          ),
                          const SizedBox(height: 12),
                          _RichMemoEditor(
                            blocks: _richBlocks,
                            onRemoveBlock: _removeRichBlock,
                            onBackspaceAtParagraphStart:
                                _removeMediaBeforeParagraph,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    key: const Key('note-vault-select'),
                    initialValue: _selectedVaultId,
                    decoration: const InputDecoration(
                      labelText: 'Vault',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final vault in visibleVaults)
                        DropdownMenuItem(
                          value: vault.id,
                          child: Text(vault.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedVaultId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _isPinned,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pin this note'),
                    subtitle: const Text('Pinned notes stay near the top.'),
                    onChanged: (value) {
                      setState(() {
                        _isPinned = value;
                      });
                    },
                  ),
                  if (_editorMode == NoteEditorMode.quick)
                    _QuickAttachmentSection(
                      attachments: _attachments,
                      onSelected: _handleAttachmentAction,
                      onRemove: (index) {
                        final removed = _attachments[index];
                        setState(() {
                          _attachments.removeAt(index);
                        });
                        final filePath = removed.filePath;
                        if (filePath != null &&
                            !_initialAttachmentPaths.contains(filePath)) {
                          unawaited(
                            ref
                                .read(encryptedAttachmentStoreProvider)
                                .deleteAttachment(filePath),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('save-note-button'),
                  onPressed: _canSave ? _save : null,
                  child: Text(
                    widget.note == null ? 'Create note' : 'Save changes',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSave {
    final title = _editorMode == NoteEditorMode.quick
        ? _splitMemoContent(_contentController.text).title
        : _deriveRichTitle();
    return title.isNotEmpty && _selectedVaultId != null;
  }

  Future<void> _pickDateTime() async {
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
  }

  Future<void> _handleAttachmentAction(MediaImportAction action) async {
    final result =
        await ref.read(mediaImportServiceProvider).importAttachment(action);
    if (!mounted) {
      return;
    }
    final attachment = result.attachment;
    if (attachment == null) {
      final errorMessage = result.errorMessage;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
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
            nextBlocks.insert(insertionIndex, _RichBlockDraft.attachment(attachment));
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
      isPinned: _isPinned,
      revision: widget.note?.revision ?? 1,
      deviceId: widget.note?.deviceId,
      syncState: widget.note?.syncState ?? NoteSyncState.localOnly,
      editorMode: _editorMode,
    );
    await ref.read(notesControllerProvider.notifier).upsert(note);
    _saved = true;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _removeRichBlock(int index) {
    final block = _richBlocks[index];
    final attachment = block.attachment;
    if (attachment != null) {
      _removeAttachmentBlockAt(index);
      return;
    }
    block.dispose();
    setState(() {
      _richBlocks.removeAt(index);
      if (_richBlocks.where((candidate) => candidate.type == NoteBlockType.paragraph).isEmpty) {
        final draft = _RichBlockDraft.paragraph();
        _attachRichBlockListener(draft);
        _richBlocks.add(draft);
      }
      if (_activeRichParagraphIndex != null && _activeRichParagraphIndex! >= _richBlocks.length) {
        _activeRichParagraphIndex = _richBlocks.lastIndexWhere(
          (candidate) => candidate.type == NoteBlockType.paragraph,
        );
      }
    });
    final filePath = attachment?.filePath;
    if (filePath != null && !_initialAttachmentPaths.contains(filePath)) {
      unawaited(
        ref.read(encryptedAttachmentStoreProvider).deleteAttachment(filePath),
      );
    }
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
    if (!selection.isValid || !selection.isCollapsed || selection.baseOffset != 0) {
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
        final mergedText = switch ((leadingText.trim().isNotEmpty, trailingText.trim().isNotEmpty)) {
          (true, true) => '$leadingText\n\n$trailingText',
          (true, false) => leadingText,
          (false, true) => trailingText,
          (false, false) => '',
        };
        final focusBaseOffset = switch ((leadingText.trim().isNotEmpty, trailingText.trim().isNotEmpty)) {
          (true, true) => leadingText.length + 2,
          (true, false) => leadingText.length,
          (false, true) => 0,
          (false, false) => 0,
        };
        leadingController.text = mergedText;
        trailingParagraph.dispose();
        _richBlocks.removeAt(mediaIndex);

        if (paragraphToFocus == null || identical(paragraphToFocus, trailingParagraph)) {
          paragraphToFocus = leadingParagraph;
          focusOffset = focusBaseOffset + preferredFocusOffset;
        }
      }

      if (_richBlocks.where((candidate) => candidate.type == NoteBlockType.paragraph).isEmpty) {
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

    final filePath = attachment.filePath;
    if (filePath != null && !_initialAttachmentPaths.contains(filePath)) {
      unawaited(
        ref.read(encryptedAttachmentStoreProvider).deleteAttachment(filePath),
      );
    }
  }

  String _deriveRichTitle() {
    for (final block in _richBlocks) {
      final text = block.controller?.text.trim() ?? '';
      if (text.isNotEmpty) {
        return text.split('\n').first.trim();
      }
      final attachment = block.attachment;
      if (attachment != null) {
        return attachment.label;
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
          NoteBlock(
            type: block.type,
            attachment: block.attachment,
          ),
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

class _RichMemoEditor extends StatelessWidget {
  const _RichMemoEditor({
    required this.blocks,
    required this.onRemoveBlock,
    required this.onBackspaceAtParagraphStart,
  });

  final List<_RichBlockDraft> blocks;
  final ValueChanged<int> onRemoveBlock;
  final ValueChanged<int> onBackspaceAtParagraphStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          _RichBlockEditorTile(
            block: blocks[i],
            emphasizeInput: i == 0,
            onRemove: () => onRemoveBlock(i),
            onBackspaceAtStart: () => onBackspaceAtParagraphStart(i),
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
    this.emphasizeInput = false,
    required this.onRemove,
    required this.onBackspaceAtStart,
  });

  final _RichBlockDraft block;
  final bool emphasizeInput;
  final VoidCallback onRemove;
  final VoidCallback onBackspaceAtStart;

  @override
  Widget build(BuildContext context) {
    if (block.type == NoteBlockType.paragraph) {
      final paragraphText = block.controller?.text ?? '';
      final showPrompt = emphasizeInput && paragraphText.trim().isEmpty;
      return Container(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPrompt)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Start writing here',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _mutedTextColor(context),
                      ),
                ),
              ),
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
                decoration: const InputDecoration(
                  semanticCounterText: '',
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
        _AttachmentPreview(attachment: block.attachment!),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton.filledTonal(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Remove block',
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _QuickAttachmentSection extends StatelessWidget {
  const _QuickAttachmentSection({
    required this.attachments,
    required this.onSelected,
    required this.onRemove,
  });

  final List<NoteAttachment> attachments;
  final ValueChanged<MediaImportAction> onSelected;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Attachments',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              PopupMenuButton<MediaImportAction>(
                key: const Key('attachment-add-menu'),
                itemBuilder: (context) => [
                  if (!kIsWeb)
                    const PopupMenuItem(
                      value: MediaImportAction.takePhoto,
                      child: Text('Take photo'),
                    ),
                  const PopupMenuItem(
                    value: MediaImportAction.pickPhoto,
                    child: Text('Pick photo'),
                  ),
                  if (!kIsWeb)
                    const PopupMenuItem(
                      value: MediaImportAction.recordVideo,
                      child: Text('Record video'),
                    ),
                  const PopupMenuItem(
                    value: MediaImportAction.pickVideo,
                    child: Text('Pick video'),
                  ),
                  const PopupMenuItem(
                    value: MediaImportAction.pickAudio,
                    child: Text('Pick audio'),
                  ),
                ],
                onSelected: onSelected,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (attachments.isEmpty)
            Text(
              kIsWeb
                  ? 'Attach photos, videos, or audio files from this browser.'
                  : 'Attach photos, videos, or audio files from camera or device storage.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
            )
          else
            for (var i = 0; i < attachments.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EditableAttachmentTile(
                  attachment: attachments[i],
                  onRemove: () => onRemove(i),
                ),
              ),
        ],
      ),
    );
  }
}

class _RichAttachmentSection extends StatelessWidget {
  const _RichAttachmentSection({required this.onSelected});

  final ValueChanged<MediaImportAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _CompactMediaButton(
          icon: Icons.photo_outlined,
          label: 'Photo',
          onPressed: () => onSelected(MediaImportAction.pickPhoto),
        ),
        if (!kIsWeb)
          _CompactMediaButton(
            icon: Icons.photo_camera_outlined,
            label: 'Camera',
            onPressed: () => onSelected(MediaImportAction.takePhoto),
          ),
        _CompactMediaButton(
          icon: Icons.videocam_outlined,
          label: 'Video',
          onPressed: () => onSelected(MediaImportAction.pickVideo),
        ),
        if (!kIsWeb)
          _CompactMediaButton(
            icon: Icons.videocam_rounded,
            label: 'Record',
            onPressed: () => onSelected(MediaImportAction.recordVideo),
          ),
        _CompactMediaButton(
          icon: Icons.audiotrack_outlined,
          label: 'Audio',
          onPressed: () => onSelected(MediaImportAction.pickAudio),
        ),
      ],
    );
  }
}

class _CompactMediaButton extends StatelessWidget {
  const _CompactMediaButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _EditableAttachmentTile extends StatelessWidget {
  const _EditableAttachmentTile({
    required this.attachment,
    required this.onRemove,
  });

  final NoteAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _AttachmentListTile(attachment: attachment),
        Positioned(
          top: 8,
          right: 0,
          child: IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove attachment',
          ),
        ),
      ],
    );
  }
}

class _AttachmentListTile extends ConsumerWidget {
  const _AttachmentListTile({required this.attachment});

  final NoteAttachment attachment;

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
                        _attachmentDescription(attachment),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _mutedTextColor(context),
                            ),
                      ),
                    ],
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

class _EmbeddedAttachmentBlock extends ConsumerWidget {
  const _EmbeddedAttachmentBlock({
    required this.attachment,
    this.photoAttachments = const [],
    this.photoIndex,
  });

  final NoteAttachment attachment;
  final List<NoteAttachment> photoAttachments;
  final int? photoIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (attachment.type) {
      case AttachmentType.photo:
        return _EmbeddedPhotoAttachment(
          attachment: attachment,
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
    }
  }
}

class _EmbeddedPhotoAttachment extends ConsumerWidget {
  const _EmbeddedPhotoAttachment({
    required this.attachment,
    this.photoAttachments = const [],
    this.photoIndex,
  });

  final NoteAttachment attachment;
  final List<NoteAttachment> photoAttachments;
  final int? photoIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filePath = attachment.filePath;
    final previewBytesBase64 = attachment.previewBytesBase64;
    final imageBytesFuture = filePath != null && filePath.isNotEmpty
        ? ref
            .watch(encryptedAttachmentStoreProvider)
            .readAttachment(filePath, type: attachment.type)
        : Future<List<int>?>.value(
            previewBytesBase64 == null || previewBytesBase64.isEmpty
                ? null
                : base64Decode(previewBytesBase64),
          );

    return FutureBuilder<List<int>?>(
      future: imageBytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (bytes == null || bytes.isEmpty) {
          return const SizedBox(
            height: 180,
            child: Center(child: Text('Unable to load this image.')),
          );
        }
        return FutureBuilder<ui.Size>(
          future: _decodeImageSize(bytes),
          builder: (context, dimensionSnapshot) {
            final imageSize = dimensionSnapshot.data;
            if (imageSize == null) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                final displayWidth = math.min(maxWidth, imageSize.width);
                final displayHeight =
                    displayWidth * imageSize.height / imageSize.width;
                return InkWell(
                  onTap: () => _openAttachmentViewer(
                    context,
                    ref,
                    attachment,
                    photoAttachments: photoAttachments,
                    initialPhotoIndex: photoIndex,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: displayWidth,
                        height: displayHeight,
                        child: Image.memory(
                          Uint8List.fromList(bytes),
                          width: displayWidth,
                          height: displayHeight,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AttachmentPreview extends ConsumerWidget {
  const _AttachmentPreview({
    required this.attachment,
    this.size = 72,
  });

  final NoteAttachment attachment;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      future: ref
          .watch(encryptedAttachmentStoreProvider)
          .readAttachment(filePath, type: attachment.type),
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
  const _AttachmentImageBox({
    required this.bytes,
    this.size = 72,
  });

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
  const _AttachmentIconBox({
    required this.type,
    this.size = 72,
  });

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

String _attachmentDescription(NoteAttachment attachment) {
  switch (attachment.type) {
    case AttachmentType.photo:
      return attachment.filePath == null
          ? 'Photo placeholder'
          : 'Tap to view photo';
    case AttachmentType.video:
      return attachment.filePath == null
          ? 'Video placeholder'
          : 'Tap to play video';
    case AttachmentType.audio:
      return attachment.filePath == null
          ? 'Audio placeholder'
          : 'Tap to play audio';
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
  SyncProvider provider,
  SyncTransferState transferState,
) {
  if (provider != SyncProvider.googleDrive) {
    return 'Remote bundle transport is only wired for Google Drive right now.';
  }
  final remote = transferState.remoteStatus;
  if (remote == null) {
    return transferState.message ?? 'No remote bundle metadata loaded yet.';
  }
  final modifiedAt = remote.modifiedAt == null
      ? 'unknown time'
      : _formatDateTime(remote.modifiedAt!);
  final sizeLabel =
      remote.sizeBytes == null ? 'size unknown' : '${remote.sizeBytes} bytes';
  final noteCount = remote.noteCount == null ? '?' : '${remote.noteCount}';
  final attachmentCount =
      remote.attachmentCount == null ? '?' : '${remote.attachmentCount}';
  return 'Last bundle: $modifiedAt, $sizeLabel, $noteCount notes, $attachmentCount attachments.';
}

Future<bool?> _showBundlePreviewDialog(
  BuildContext context,
  SyncBundlePreview preview, {
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Bundle review'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notes in bundle: ${preview.noteCount}'),
                Text('Attachments in bundle: ${preview.attachmentCount}'),
                Text('Adds: ${preview.addedCount}'),
                Text('Updates: ${preview.updatedCount}'),
                Text('Removals on this device: ${preview.removedCount}'),
                if (preview.privateVaultNoteCount > 0)
                  Text(
                    'Private vault notes affected: ${preview.privateVaultNoteCount}',
                  ),
                if (preview.deviceId != null && preview.deviceId!.isNotEmpty)
                  Text('Remote device: ${preview.deviceId}'),
                if (preview.exportedAt != null)
                  Text('Exported at: ${_formatDateTime(preview.exportedAt!)}'),
                if (preview.sampleTitles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Bundle sample: ${preview.sampleTitles.join(', ')}'),
                ],
                _PreviewTitlesSection(
                  title: 'Added notes',
                  titles: preview.addedTitles,
                ),
                _PreviewTitlesSection(
                  title: 'Updated notes',
                  titles: preview.updatedTitles,
                ),
                _PreviewTitlesSection(
                  title: 'Removed locally after apply',
                  titles: preview.removedTitles,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
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
  const _PreviewTitlesSection({
    required this.title,
    required this.titles,
  });

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
  return showDialog<RemoteSyncBundleStatus>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Remote bundle history'),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = history[index];
              final modifiedAt = entry.modifiedAt == null
                  ? 'Unknown time'
                  : _formatDateTime(entry.modifiedAt!);
              final counts =
                  '${entry.noteCount ?? '?'} notes, ${entry.attachmentCount ?? '?'} attachments';
              final device = entry.deviceId == null || entry.deviceId!.isEmpty
                  ? 'Unknown device'
                  : entry.deviceId!;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(modifiedAt),
                subtitle: Text(
                  '${entry.fileName}\n$counts\n$device',
                ),
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
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<String?> _showSyncKeyImportDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Import sync key'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Paste himemo-sync-key-v1:...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Import'),
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
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.length < 4) {
                    setState(() {
                      errorText = 'Use at least 4 characters.';
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
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final secret = secretController.text.trim();
                  final confirm = confirmController.text.trim();
                  if (secret.length < 4) {
                    setState(() {
                      errorText = 'Use at least 4 characters.';
                    });
                    return;
                  }
                  if (secret != confirm) {
                    setState(() {
                      errorText = 'Keys do not match.';
                    });
                    return;
                  }
                  Navigator.of(context).pop(secret);
                },
                child: const Text('Save'),
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
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Replace sync key'),
        content: Text(
          'Current fingerprint: $currentFingerprint\n'
          'Imported fingerprint: $incomingFingerprint\n\n'
          'Replacing the sync key can make existing remote bundles unreadable on this device until the original key is restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace key'),
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
    builder: (context) => _PinSetupDialog(
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

Future<void> _openAttachmentViewer(
  BuildContext context,
  WidgetRef ref,
  NoteAttachment attachment, {
  List<NoteAttachment> photoAttachments = const [],
  int? initialPhotoIndex,
}
) async {
  if (attachment.type == AttachmentType.photo) {
    final attachments = photoAttachments.isEmpty ? [attachment] : photoAttachments;
    final fallbackIndex = attachments.indexOf(attachment);
    final resolvedIndex = initialPhotoIndex != null &&
            initialPhotoIndex >= 0 &&
            initialPhotoIndex < attachments.length
        ? initialPhotoIndex
        : (fallbackIndex >= 0 ? fallbackIndex : 0);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close image viewer',
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
  const _PinSetupDialog({
    required this.title,
    required this.confirmLabel,
  });

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
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use a 4 digit PIN for this browser.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _PinEntryField(
              controller: _pinController,
              label: 'PIN',
            ),
            const SizedBox(height: 12),
            _PinEntryField(
              controller: _confirmController,
              label: 'Confirm PIN',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  void _submit() {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length != 4) {
      setState(() {
        _errorText = 'PIN must be exactly 4 digits.';
      });
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      setState(() {
        _errorText = 'PIN must contain digits only.';
      });
      return;
    }
    if (pin != confirm) {
      setState(() {
        _errorText = 'PIN confirmation did not match.';
      });
      return;
    }
    Navigator.of(context).pop(pin);
  }
}

class _PinEntryField extends StatelessWidget {
  const _PinEntryField({
    required this.controller,
    required this.label,
  });

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
          _attachmentDescription(attachment),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: switch (attachment.type) {
            AttachmentType.photo =>
              _PhotoAttachmentViewer(attachment: attachment),
            AttachmentType.video =>
              _VideoAttachmentViewer(attachment: attachment),
            AttachmentType.audio =>
              _AudioAttachmentViewer(attachment: attachment),
          },
        ),
      ],
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
    final filePath = _attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Text(
            'No image is stored for this attachment.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FutureBuilder<List<int>?>(
          future: ref
              .watch(encryptedAttachmentStoreProvider)
              .readAttachment(filePath, type: _attachment.type),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (bytes == null || bytes.isEmpty) {
              return const Center(
                child: Text(
                  'Unable to decrypt this image.',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }

            return FutureBuilder<ui.Size>(
              future: _decodeImageSize(bytes),
              builder: (context, dimensionSnapshot) {
                final imageSize = dimensionSnapshot.data;
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
                    final viewportHeight = constraints.maxHeight -
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
                              child: GestureDetector(
                                onTap: () {},
                                onDoubleTap: () => _toggleActualSize(maxScale),
                                child: SizedBox(
                                  width: displayedWidth,
                                  height: displayedHeight,
                                  child: InteractiveViewer(
                                    transformationController:
                                        _transformationController,
                                    minScale: 1,
                                    maxScale: maxScale,
                                    panEnabled: true,
                                    clipBehavior: Clip.hardEdge,
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
                                tooltip: 'Previous image',
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
                                tooltip: 'Next image',
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
    final targetScale = (currentScale * factor).clamp(1.0, maxScale);
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
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
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
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleEdgeToEdge;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
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
            tooltip: 'Close',
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
            tooltip: 'Previous image',
          ),
          IconButton(
            onPressed: canMoveNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
            tooltip: 'Next image',
          ),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded, color: Colors.white),
            tooltip: 'Zoom out',
          ),
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            tooltip: 'Zoom in',
          ),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
            tooltip: 'Fit to screen',
          ),
          IconButton(
            onPressed: onToggleEdgeToEdge,
            icon: Icon(
              edgeToEdge
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white,
            ),
            tooltip: edgeToEdge ? 'Restore frame' : 'Maximize',
          ),
          IconButton(
            onPressed: onShare,
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            tooltip: 'Share',
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

class _PhotoAttachmentViewer extends ConsumerWidget {
  const _PhotoAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filePath = attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      return const Center(
          child: Text('No image is stored for this attachment.'));
    }
    return FutureBuilder<List<int>?>(
      future: ref
          .watch(encryptedAttachmentStoreProvider)
          .readAttachment(filePath, type: attachment.type),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (bytes == null || bytes.isEmpty) {
          return const Center(child: Text('Unable to decrypt this image.'));
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
        ref.read(encryptedAttachmentStoreProvider).deleteMaterializedFile(
              tempFilePath,
            ),
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
      return const Center(child: Text('Video preview is not enabled on web.'));
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
        ref.read(encryptedAttachmentStoreProvider).deleteMaterializedFile(
              tempFilePath,
            ),
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
    await _player.setFilePath(tempFilePath);
    setState(() {
      _tempFilePath = tempFilePath;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Center(child: Text('Audio playback is not enabled on web.'));
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPlaying ? Icons.graphic_eq_rounded : Icons.audiotrack_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                if (isPlaying) {
                  await _player.pause();
                } else {
                  await _player.play();
                }
              },
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(isPlaying ? 'Pause audio' : 'Play audio'),
            ),
          ],
        );
      },
    );
  }
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
  }
}
