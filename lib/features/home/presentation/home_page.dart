import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pinput/pinput.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_strings.dart';
import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/sync_bundle_preview.dart';
import '../domain/note_entry.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';

enum AppSection { notes, calendar, insights, settings }

class _NoteTemplate {
  const _NoteTemplate({
    required this.id,
    required this.label,
    required this.quickContent,
    required this.richBlocks,
  });

  final String id;
  final String label;
  final String quickContent;
  final List<NoteBlock> richBlocks;
}

const _noteTemplates = <_NoteTemplate>[
  _NoteTemplate(
    id: 'diary',
    label: 'Diary',
    quickContent: 'Today\n\nWhat happened today?\nHow did it feel?',
    richBlocks: [
      NoteBlock(type: NoteBlockType.paragraph, text: 'Today'),
      NoteBlock(
        type: NoteBlockType.paragraph,
        text: 'What happened today?\nHow did it feel?',
      ),
    ],
  ),
  _NoteTemplate(
    id: 'shopping',
    label: 'Shopping',
    quickContent: 'Shopping list\n\n- Milk\n- Eggs\n- Fruit',
    richBlocks: [
      NoteBlock(type: NoteBlockType.paragraph, text: 'Shopping list'),
      NoteBlock(type: NoteBlockType.paragraph, text: '- Milk\n- Eggs\n- Fruit'),
    ],
  ),
  _NoteTemplate(
    id: 'meeting',
    label: 'Meeting',
    quickContent: 'Meeting notes\n\nAgenda\n\nDecisions\n\nNext actions',
    richBlocks: [
      NoteBlock(type: NoteBlockType.paragraph, text: 'Meeting notes'),
      NoteBlock(
        type: NoteBlockType.paragraph,
        text: 'Agenda\n\nDecisions\n\nNext actions',
      ),
    ],
  ),
  _NoteTemplate(
    id: 'travel',
    label: 'Travel',
    quickContent: 'Trip log\n\nPlace\n\nWhat stood out?',
    richBlocks: [
      NoteBlock(type: NoteBlockType.paragraph, text: 'Trip log'),
      NoteBlock(
        type: NoteBlockType.paragraph,
        text: 'Place\n\nWhat stood out?',
      ),
    ],
  ),
];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  static const notesNavKey = Key('nav-notes');
  static const calendarNavKey = Key('nav-calendar');
  static const insightsNavKey = Key('nav-insights');
  static const settingsNavKey = Key('nav-settings');
  static const addNoteKey = Key('add-note-button');

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 840;
    final section = _sectionForLocation(GoRouterState.of(context).uri.path);
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final flavor =
        FlavorConfig.instance.variables['flavor'] as String? ?? 'development';

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForSection(context, section)),
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
              destinations: [
                NavigationDestination(
                  key: notesNavKey,
                  icon: const Icon(Icons.notes_outlined),
                  selectedIcon: const Icon(Icons.notes_rounded),
                  label: strings.notes,
                ),
                NavigationDestination(
                  key: calendarNavKey,
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month_rounded),
                  label: strings.calendar,
                ),
                NavigationDestination(
                  key: insightsNavKey,
                  icon: const Icon(Icons.insert_chart_outlined_rounded),
                  selectedIcon: const Icon(Icons.insert_chart_rounded),
                  label: strings.insights,
                ),
                NavigationDestination(
                  key: settingsNavKey,
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings_rounded),
                  label: strings.settings,
                ),
              ],
            ),
      floatingActionButton: section == AppSection.notes
          ? FloatingActionButton.small(
              key: addNoteKey,
              onPressed: () => showNoteEditorSheet(context, ref),
              tooltip: context.strings.addNote,
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
      case AppSection.insights:
        context.go('/insights');
      case AppSection.settings:
        context.go('/settings');
    }
  }

  String _titleForSection(BuildContext context, AppSection section) {
    final strings = context.strings;
    switch (section) {
      case AppSection.notes:
        return strings.appTitle;
      case AppSection.calendar:
        return strings.calendar;
      case AppSection.insights:
        return strings.insights;
      case AppSection.settings:
        return strings.settings;
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
    final useCompactHeader =
        !useSplitView && width < 720 && screenSize.height > screenSize.width;
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final privateVaultUnlocked = ref.watch(
      privateVaultSessionControllerProvider,
    );
    final visibleNotes = ref.watch(visibleNotesProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final listDensity = ref.watch(notesListDensityControllerProvider);
    final query = ref.watch(searchQueryProvider).trim();

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
                        if (i == 0 ||
                            !_isSameNoteDay(
                              visibleNotes[i - 1],
                              visibleNotes[i],
                            ))
                          _NoteDayDivider(date: visibleNotes[i].createdAt),
                        _NoteListTile(
                          note: visibleNotes[i],
                          vaultName: ref
                              .watch(vaultByIdProvider(visibleNotes[i].vaultId))
                              .name,
                          showVaultName: visibleVaults.length > 1,
                          density: listDensity,
                          query: query,
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
    final initialIndex = visibleNotes.indexWhere(
      (entry) => entry.id == note.id,
    );
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
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${note.title}" deleted'),
          action: SnackBarAction(
            label: 'Undo',
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
        _SectionIntro(
          title: strings.calendar,
          description: strings.isJapanese
              ? '日付ごとにノートを振り返り、日記を日付にひも付けて見返します。'
              : 'Review notes grouped by day and keep diary entries anchored to dates.',
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
                    tooltip: strings.isJapanese
                        ? '前の記録がある日'
                        : 'Previous day with notes',
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
                    tooltip: strings.isJapanese
                        ? '次の記録がある日'
                        : 'Next day with notes',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (sameDayNotes.isEmpty)
                Text(
                  strings.isJapanese
                      ? 'この日にはまだノートがありません。'
                      : 'No notes on this day yet.',
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
                            tooltip: strings.isJapanese
                                ? '前の記録がある日'
                                : 'Previous day with notes',
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
                            tooltip: strings.isJapanese
                                ? '次の記録がある日'
                                : 'Next day with notes',
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
                                title: Text(
                                  strings.isJapanese
                                      ? 'ノートを削除'
                                      : 'Delete note',
                                ),
                                content: Text(
                                  strings.isJapanese
                                      ? '「${selectedNote.title}」をこの端末から完全に削除しますか？'
                                      : 'Delete "${selectedNote.title}" permanently from this device?',
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
                                      strings.isJapanese ? '削除' : 'Delete',
                                    ),
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
    final weekdays = strings.isJapanese
        ? const ['月', '火', '水', '木', '金', '土', '日']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
              tooltip: strings.isJapanese ? '前の月' : 'Previous month',
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: onTodaySelected,
              child: Text(strings.today),
            ),
            IconButton(
              onPressed: onNextMonth,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: strings.isJapanese ? '次の月' : 'Next month',
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
                strings.isJapanese ? '記録のまとめ' : 'Writing activity',
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
          title: strings.isJapanese ? '月ごとのノート数' : 'Monthly notes',
          description: strings.isJapanese
              ? '最近6か月のノート件数'
              : 'Notes created over the last 6 months.',
          child: _InsightBarChart(
            buckets: _buildMonthlyBuckets(context, notes),
            valueSuffix: strings.isJapanese ? '件' : ' notes',
          ),
        ),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.isJapanese ? '直近の日別推移' : 'Recent days',
          description: strings.isJapanese
              ? '直近14日の日別ノート件数'
              : 'Daily note count over the last 14 days.',
          child: _InsightBarChart(
            buckets: _buildRecentDayBuckets(context, notes),
            valueSuffix: strings.isJapanese ? '件' : ' notes',
            compactLabels: true,
          ),
        ),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.isJapanese ? '曜日ごとの傾向' : 'Weekday rhythm',
          description: strings.isJapanese
              ? 'どの曜日に書いているか'
              : 'See which weekdays you write on most.',
          child: _InsightBarChart(
            buckets: _buildWeekdayBuckets(context, notes),
            valueSuffix: strings.isJapanese ? '件' : ' notes',
          ),
        ),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.isJapanese ? '添付メディア' : 'Attachments',
          description: strings.isJapanese
              ? '写真・動画・音声の使用数'
              : 'How often photos, videos, and audio are used.',
          child: _InsightBarChart(
            buckets: _buildAttachmentBuckets(context, notes),
            valueSuffix: strings.isJapanese ? '件' : ' items',
          ),
        ),
        const SizedBox(height: 16),
        _InsightChartSection(
          title: strings.isJapanese ? '記録しやすい時間帯' : 'Writing hours',
          description: strings.isJapanese
              ? '書きやすい時間帯を見ます。'
              : 'Find the hours when writing comes naturally.',
          child: _InsightBarChart(
            buckets: _buildHourBuckets(notes),
            valueSuffix: strings.isJapanese ? '件' : ' notes',
            compactLabels: true,
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
            label: strings.isJapanese ? '連続記録' : 'Current streak',
            value: '${summary.currentStreak}',
            helper: strings.isJapanese ? '日' : 'days',
          ),
          _InsightKpiTile(
            label: strings.isJapanese ? '今月' : 'This month',
            value: '${summary.thisMonthCount}',
            helper: strings.isJapanese ? '件' : 'notes',
          ),
          _InsightKpiTile(
            label: strings.isJapanese ? '文字数' : 'Characters',
            value: '${summary.totalCharacters}',
            helper: strings.isJapanese ? '累計' : 'total',
          ),
          _InsightKpiTile(
            label: strings.isJapanese ? '添付数' : 'Attachments',
            value: '${summary.totalAttachments}',
            helper: strings.isJapanese ? '件' : 'items',
          ),
          _InsightKpiTile(
            label: strings.isJapanese ? '最も書いた日' : 'Best day',
            value: summary.bestDayLabel,
            helper: strings.isJapanese
                ? '${summary.bestDayValue}件'
                : '${summary.bestDayValue} notes',
          ),
          _InsightKpiTile(
            label: strings.isJapanese ? '記録しやすい時間' : 'Best hour',
            value: summary.bestHourLabel,
            helper: strings.isJapanese ? 'ピーク' : 'peak time',
          ),
          _InsightKpiTile(
            label: strings.isJapanese ? '前月比' : 'Monthly trend',
            value: summary.monthlyDeltaLabel,
            helper: strings.isJapanese ? '先月比' : 'vs last month',
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
      width: 220,
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
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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
  const _InsightBarChart({
    required this.buckets,
    required this.valueSuffix,
    this.compactLabels = false,
  });

  final List<_InsightBucket> buckets;
  final String valueSuffix;
  final bool compactLabels;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    if (buckets.isEmpty) {
      return Text(
        strings.isJapanese ? 'まだデータがありません。' : 'No data yet.',
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
                          maxLines: compactLabels ? 1 : 2,
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

class _InsightBucket {
  const _InsightBucket({required this.label, required this.value});

  final String label;
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
      ? '書いた量がここにたまります。まずは数日続けてみると変化が見えます。'
      : '今月は $thisMonthCount 件、最も書いた日は ${bestDay.label} です。連続記録を保つと積み上がりが見えやすくなります。';
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
        label: strings.isJapanese ? '${month.month}月' : '${month.month}',
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

List<_InsightBucket> _buildWeekdayBuckets(
  BuildContext context,
  List<NoteEntry> notes,
) {
  final strings = context.strings;
  const enLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const jaLabels = ['月', '火', '水', '木', '金', '土', '日'];
  return [
    for (var i = 1; i <= 7; i++)
      _InsightBucket(
        label: strings.isJapanese ? jaLabels[i - 1] : enLabels[i - 1],
        value: notes.where((note) => note.createdAt.weekday == i).length,
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
      label: strings.isJapanese ? '写真' : 'Photo',
      value: countFor(AttachmentType.photo),
    ),
    _InsightBucket(
      label: strings.isJapanese ? '動画' : 'Video',
      value: countFor(AttachmentType.video),
    ),
    _InsightBucket(
      label: strings.isJapanese ? '音声' : 'Audio',
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
    BuildContext context,
    WidgetRef ref,
  ) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cover key saved.')));
    }
  }

  Future<void> _confirmResetCoverKey(
    BuildContext context,
    WidgetRef ref,
  ) async {
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
    final strings = context.strings;
    final activeIdentity = ref.watch(activeIdentityProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final colorTheme = ref.watch(appColorThemeControllerProvider);
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
    final currentModeLabel = activeIdentity == 'daily'
        ? (strings.isJapanese ? '通常メモモード' : 'Normal memo mode')
        : ref.watch(activeIdentityDataProvider).name;
    final lockSummary = !appLockEnabled
        ? (strings.isJapanese
              ? '起動時の保護はオフです。'
              : 'Launch protection is off.')
        : (appSessionUnlocked
              ? (strings.isJapanese
                    ? '起動時の保護はオンです。このセッションでは解除されています。'
                    : 'Launch protection is on. This session is unlocked.')
              : (strings.isJapanese
                    ? '起動時の保護はオンです。現在はロック中です。'
                    : 'Launch protection is on. This session is locked.'));
    final syncSummary = syncProvider == SyncProvider.off
        ? (strings.isJapanese ? 'この端末のみ' : 'Device-only storage')
        : _syncAuthSummary(context, syncProvider, syncAuthState);
    final appearanceSummary =
        '${_localeSettingLabel(context, localeSetting)} / ${_themeModeLabel(context, themeMode)} / ${_colorThemeLabel(context, colorTheme)}';
    final aboutVersion = packageInfo.when(
      data: (info) => info.displayVersion,
      loading: strings.readingVersion,
      error: (_, _) => '1.0.0 (1)',
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionIntro(
          title: strings.settings,
          description: strings.isJapanese
              ? 'アクセス、同期、表示ポリシーを管理します。'
              : 'Manage access, sync, and display policy.',
        ),
        const SizedBox(height: 16),
        _SettingsOverviewCard(
          items: [
            _SettingsOverviewItem(
              label: strings.isJapanese ? 'モード' : 'Mode',
              value: currentModeLabel,
              assetPath: 'assets/settings/access.svg',
            ),
            _SettingsOverviewItem(
              label: strings.isJapanese ? 'ロック' : 'Unlock',
              value: appLockEnabled
                  ? (strings.isJapanese ? '有効' : 'Enabled')
                  : (strings.isJapanese ? '無効' : 'Disabled'),
              assetPath: 'assets/settings/security.svg',
            ),
            _SettingsOverviewItem(
              label: 'Sync',
              value: syncProvider == SyncProvider.off
                  ? (strings.isJapanese ? 'オフ' : 'Off')
                  : (strings.isJapanese ? '設定済み' : 'Configured'),
              assetPath: 'assets/settings/sync.svg',
            ),
            _SettingsOverviewItem(
              label: strings.isJapanese ? 'テーマ' : 'Theme',
              value: _themeModeLabel(context, themeMode),
              assetPath: 'assets/settings/appearance.svg',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.isJapanese ? 'アクセスモード' : 'Access modes',
          summary:
              strings.isJapanese
                  ? '$currentModeLabel。別の表示が必要なときだけ特別キーを使います。'
                  : '$currentModeLabel. Special keys are used only when another view is needed.',
          assetPath: 'assets/settings/access.svg',
          initiallyExpanded: true,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.isJapanese ? '現在のモード' : 'Current mode'),
              subtitle: Text(
                activeIdentity == 'daily'
                    ? (strings.isJapanese ? '通常メモモード' : 'Normal memo mode')
                    : ref.watch(activeIdentityDataProvider).name,
              ),
            ),
            Text(
              strings.isJapanese
                  ? '通常はそのまま通常メモモードで使います。別の表示が必要なときだけ特別なアクセスキーを入力します。'
                  : 'The app stays in normal memo mode by default. Enter a special access key only when you need another view.',
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
                  onPressed: () => _showSpecialAccessKeyDialog(context, ref),
                  child: Text(
                    strings.isJapanese
                        ? '特別なアクセスキーを入力'
                        : 'Enter special access key',
                  ),
                ),
                OutlinedButton(
                  onPressed: activeIdentity == 'daily'
                      ? null
                      : () => _switchIdentity(ref, 'daily'),
                  child: Text(
                    strings.isJapanese
                        ? '通常モードに戻す'
                        : 'Return to normal mode',
                  ),
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
                        ? (strings.isJapanese ? 'カバーキーを変更' : 'Change cover key')
                        : (strings.isJapanese ? 'カバーキーを設定' : 'Set cover key'),
                  ),
                ),
                OutlinedButton(
                  onPressed: coverModeConfigured
                      ? () => _confirmResetCoverKey(context, ref)
                      : null,
                  child: Text(
                    strings.isJapanese ? 'カバーキーをリセット' : 'Reset cover key',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.isJapanese ? 'アプリ保護' : 'App security',
          summary: lockSummary,
          assetPath: 'assets/settings/security.svg',
          initiallyExpanded: true,
          children: [
            SwitchListTile.adaptive(
              key: appLockToggleKey,
              value: appLockEnabled,
              contentPadding: EdgeInsets.zero,
              title: kIsWeb
                  ? Text(
                      strings.isJapanese
                          ? '起動時に PIN を要求'
                          : 'Require PIN on launch',
                    )
                  : Text(
                      strings.isJapanese
                          ? '起動時に端末認証を要求'
                          : 'Require device auth on launch',
                    ),
              subtitle: Text(
                kIsWeb
                    ? (strings.isJapanese
                          ? 'このブラウザでは 4 桁の PIN でメモ画面を保護します。${pinLockState.localizedSummary(isJapanese: true)}'
                          : 'Protect this browser session with a 4 digit PIN. ${pinLockState.localizedSummary(isJapanese: false)}')
                    : (deviceAuthState.isAvailable
                          ? (strings.isJapanese
                                ? 'この端末の生体認証や画面ロックで保護します。利用状況: ${deviceAuthState.summary}'
                                : 'Protect the app with device authentication. Availability: ${deviceAuthState.summary}')
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
                      title: strings.isJapanese ? '解除用 PIN を設定' : 'Set unlock PIN',
                      confirmLabel: strings.isJapanese ? 'PIN を保存' : 'Save PIN',
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
                        SnackBar(
                          content: Text(
                            strings.isJapanese
                                ? '端末認証が完了しなかったため、アプリ保護はオンになりませんでした。'
                                : 'Device authentication was not completed, so launch protection stayed off.',
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
              title: Text(strings.isJapanese ? 'セッション状態' : 'Session status'),
              subtitle: Text(
                appSessionUnlocked
                    ? (strings.isJapanese
                          ? 'このセッションではメモを開ける状態です。'
                          : 'This session is currently unlocked.')
                    : (kIsWeb
                          ? (strings.isJapanese
                                ? '正しい PIN を入力するまで、このブラウザではメモを開けません。'
                                : 'This browser stays locked until the correct PIN is entered.')
                          : (strings.isJapanese
                                ? '端末認証が成功するまで、このセッションはロックされたままです。'
                                : 'This session stays locked until device authentication succeeds.')),
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
                              ? (strings.isJapanese ? '解除用 PIN を変更' : 'Change unlock PIN')
                              : (strings.isJapanese ? '解除用 PIN を設定' : 'Set unlock PIN'),
                          confirmLabel: pinLockState.isConfigured
                              ? (strings.isJapanese ? 'PIN を更新' : 'Update PIN')
                              : (strings.isJapanese ? 'PIN を保存' : 'Save PIN'),
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
                                    ? (strings.isJapanese ? '解除用 PIN を更新しました。' : 'Unlock PIN updated.')
                                    : (strings.isJapanese ? '解除用 PIN を設定しました。' : 'Unlock PIN configured.'),
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        pinLockState.isConfigured
                            ? (strings.isJapanese ? 'PIN を変更' : 'Change PIN')
                            : (strings.isJapanese ? 'PIN を設定' : 'Set PIN'),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: pinLockState.isConfigured
                          ? () async {
                              final shouldRemove = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    strings.isJapanese
                                        ? '解除用 PIN を削除'
                                        : 'Remove unlock PIN',
                                  ),
                                  content: Text(
                                    strings.isJapanese
                                        ? 'このブラウザで使っている Web 用 PIN を削除し、起動時の PIN 保護もオフにしますか。'
                                        : 'Remove the web unlock PIN for this browser and turn off launch PIN protection?',
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
                                        strings.isJapanese ? '削除' : 'Remove',
                                      ),
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
                      child: Text(
                        strings.isJapanese ? 'PIN を削除' : 'Remove PIN',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.isJapanese
                    ? 'Web 用 PIN は、このブラウザでメモ画面を開きにくくするための保護です。端末の安全領域や生体認証の代わりにはなりません。'
                    : 'Web PIN is a browser-level access gate. It does not replace device-backed secure storage or biometrics.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
            ],
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
                          widgetQuickCaptureSettingsControllerProvider.notifier,
                        )
                        .setEnabled(value)
                  : null,
            ),
            Text(
              strings.isJapanese
                  ? 'クイックキャプチャは Daily Notes に平文テキストだけを書き込みます。既存ノートや private vault の内容は開きません。'
                  : 'Quick widget capture only writes plain text into Daily Notes. It never opens existing notes or private vault content.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 4),
            Text(
              strings.isJapanese
                  ? 'アプリが前面から外れた後に再ロック'
                  : 'Re-lock after app leaves the foreground',
            ),
            const SizedBox(height: 8),
            _ThemeOptionTile(
              tileKey: appLockRelockImmediateKey,
              title: strings.isJapanese ? 'すぐに' : 'Immediately',
              subtitle: strings.isJapanese
                  ? 'バックグラウンドに移動したらすぐロックします。'
                  : 'Lock the app as soon as it moves to the background.',
              selected: appLockRelockDelay == AppLockRelockDelay.immediate,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.immediate),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock30SecondsKey,
              title: strings.isJapanese ? '30秒後' : 'After 30 seconds',
              subtitle: strings.isJapanese
                  ? 'すぐ戻るときは再認証なしで切り替えられます。'
                  : 'Allow quick app switching without immediate re-auth.',
              selected: appLockRelockDelay == AppLockRelockDelay.seconds30,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.seconds30),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock2MinutesKey,
              title: strings.isJapanese ? '2分後' : 'After 2 minutes',
              subtitle: strings.isJapanese
                  ? 'ノート間で写真や音声を扱うときに向いています。'
                  : 'Useful when capturing photos or audio between notes.',
              selected: appLockRelockDelay == AppLockRelockDelay.minutes2,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes2),
            ),
            _ThemeOptionTile(
              tileKey: appLockRelock10MinutesKey,
              title: strings.isJapanese ? '10分後' : 'After 10 minutes',
              subtitle: strings.isJapanese
                  ? '長めの編集中でも開いたままにできます。'
                  : 'Keep the app open during longer editing sessions.',
              selected: appLockRelockDelay == AppLockRelockDelay.minutes10,
              onTap: () => ref
                  .read(appLockRelockDelayControllerProvider.notifier)
                  .setDelay(AppLockRelockDelay.minutes10),
            ),
            SwitchListTile.adaptive(
              key: privateVaultLockOnAppLockKey,
              value: privateVaultLockOnAppLock,
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.isJapanese
                    ? 'アプリロック時に private vault もロック'
                    : 'Lock private vault when app locks',
              ),
              subtitle: Text(
                strings.isJapanese
                    ? 'アプリの再ロックを private vault のセッションにも適用します。'
                    : 'Apply app re-lock to the private vault session too.',
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
                        ? Text(
                            strings.isJapanese
                                ? 'ロック画面で PIN 解除'
                                : 'PIN unlock on lock screen',
                          )
                        : Text(
                            strings.isJapanese
                                ? '今すぐ認証'
                                : 'Authenticate now',
                          ),
                  ),
                  OutlinedButton(
                    key: appLockLockNowKey,
                    onPressed: appLockEnabled
                        ? () => ref
                              .read(appSessionUnlockControllerProvider.notifier)
                              .lock()
                        : null,
                    child: Text(
                      strings.isJapanese
                          ? '今すぐセッションをロック'
                          : 'Lock session now',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: kIsWeb
                        ? null
                        : () => ref
                              .read(deviceAuthControllerProvider.notifier)
                              .refresh(),
                    child: kIsWeb
                        ? Text(
                            strings.isJapanese
                                ? 'Web PIN 利用中'
                                : 'Web PIN active',
                          )
                        : Text(
                            strings.isJapanese
                                ? '利用可否を更新'
                                : 'Refresh availability',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.isJapanese ? 'Private vault' : 'Private vault',
          summary: privateVaultConfigured
              ? (privateVaultUnlocked
                    ? (strings.isJapanese
                          ? '設定済みで現在は解除中です。'
                          : 'Configured and currently unlocked.')
                    : (strings.isJapanese
                          ? '設定済みでロック中です。'
                          : 'Configured and locked.'))
              : (strings.isJapanese
                    ? 'まだ private vault のキーが設定されていません。'
                    : 'No private vault key has been set yet.'),
          assetPath: 'assets/settings/security.svg',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.isJapanese ? '状態' : 'Status'),
              subtitle: Text(
                privateVaultConfigured
                    ? (privateVaultUnlocked
                          ? (strings.isJapanese
                                ? 'このセッションでは解除されています。'
                                : 'Configured and unlocked for this session.')
                          : (strings.isJapanese
                                ? '設定済みでロック中です。別のキーが必要です。'
                                : 'Configured and locked. A separate key is required.'))
                    : (strings.isJapanese
                          ? '未設定です。private vault 用の別キーを設定してください。'
                          : 'Not configured yet. Set a separate key for the private vault.'),
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
                    child: Text(
                      strings.isJapanese
                          ? 'プライベートキーを設定'
                          : 'Set private key',
                    ),
                  ),
                if (privateVaultConfigured && !privateVaultUnlocked)
                  FilledButton(
                    key: privateVaultUnlockKey,
                    onPressed: () =>
                        _showUnlockPrivateVaultDialog(context, ref),
                    child: Text(
                      strings.isJapanese
                          ? 'Private vault を解除'
                          : 'Unlock private vault',
                    ),
                  ),
                if (privateVaultUnlocked)
                  FilledButton.tonal(
                    key: privateVaultLockKey,
                    onPressed: () => ref
                        .read(privateVaultSessionControllerProvider.notifier)
                        .lock(),
                    child: Text(
                      strings.isJapanese
                          ? 'Private vault をロック'
                          : 'Lock private vault',
                    ),
                  ),
                if (privateVaultConfigured)
                  OutlinedButton(
                    key: privateVaultResetKey,
                    onPressed: () => _confirmResetPrivateKey(context, ref),
                    child: Text(
                      strings.isJapanese
                          ? 'プライベートキーをリセット'
                          : 'Reset private key',
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.isJapanese ? 'バックアップと同期' : 'Backup and sync',
          summary: syncSummary,
          assetPath: 'assets/settings/sync.svg',
          initiallyExpanded: true,
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
              title: Text(strings.isJapanese ? '選択中の同期先' : 'Selected target'),
              subtitle: Text(_syncSubtitle(context, syncProvider)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.isJapanese ? '認証' : 'Authentication'),
              subtitle: Text(_syncAuthSummary(context, syncProvider, syncAuthState)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.isJapanese ? '保留中の同期キュー' : 'Pending sync queue'),
              subtitle: Text(
                syncQueueSummary.when(
                  data: (summary) {
                    if (!summary.hasPendingChanges) {
                      return strings.isJapanese
                          ? 'この端末に保留中の変更はありません。'
                          : 'No pending device changes.';
                    }
                    final timestamp = summary.lastQueuedAt;
                    final stampText = timestamp == null
                        ? (strings.isJapanese ? 'キュー準備済み' : 'queue ready')
                        : (strings.isJapanese
                              ? '最終追加 ${_formatDateTime(timestamp)}'
                              : 'last queued ${_formatDateTime(timestamp)}');
                    return strings.isJapanese
                        ? '${summary.totalChanges}件が保留中（更新 ${summary.upserts} / 削除 ${summary.deletes}）、$stampText'
                        : '${summary.totalChanges} changes pending (${summary.upserts} upserts, ${summary.deletes} deletes), $stampText';
                  },
                  loading: () => strings.isJapanese
                      ? '保留中の変更を確認中...'
                      : 'Checking pending changes...',
                  error: (_, _) => strings.isJapanese
                      ? 'ローカル同期キューを確認できませんでした。'
                      : 'Unable to inspect the local sync queue.',
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.isJapanese ? 'リモートバンドル' : 'Remote bundle'),
              subtitle: Text(
                _remoteBundleSummary(syncProvider, syncTransferState),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.isJapanese
                    ? '同期キーのフィンガープリント'
                    : 'Sync key fingerprint',
              ),
              subtitle: Text(
                syncBundleFingerprint.when(
                  data: (value) => value,
                  loading: () => strings.isJapanese
                      ? '同期キーを準備中...'
                      : 'Preparing sync key...',
                  error: (_, _) => strings.isJapanese
                      ? '同期キーのフィンガープリントを読めませんでした。'
                      : 'Unable to read the sync key fingerprint.',
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
                        SnackBar(
                          content: Text(
                            strings.isJapanese
                                ? '同期キーをクリップボードにコピーしました。'
                                : 'Sync key copied to clipboard.',
                          ),
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      messenger.showSnackBar(SnackBar(content: Text('$error')));
                    }
                  },
                  child: Text(strings.isJapanese ? '同期キーをコピー' : 'Copy sync key'),
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
                            strings.isJapanese
                                ? '同期キーを読み込みました。フィンガープリント: $fingerprint'
                                : 'Sync key imported. Fingerprint: $fingerprint',
                          ),
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      messenger.showSnackBar(SnackBar(content: Text('$error')));
                    }
                  },
                  child: Text(strings.isJapanese ? '同期キーを読み込む' : 'Import sync key'),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(strings.isJapanese ? '直近の同期履歴' : 'Last sync activity'),
              subtitle: Text(
                syncBundleState.when(
                  data: (value) {
                    final entries = <String>[];
                    if (value.lastUploadedAt != null) {
                      entries.add(
                        strings.isJapanese
                            ? '最終アップロード ${_formatDateTime(value.lastUploadedAt!)}'
                            : 'Last upload ${_formatDateTime(value.lastUploadedAt!)}',
                      );
                    }
                    if (value.lastAppliedAt != null) {
                      entries.add(
                        strings.isJapanese
                            ? '最終適用 ${_formatDateTime(value.lastAppliedAt!)}'
                            : 'Last apply ${_formatDateTime(value.lastAppliedAt!)}',
                      );
                    }
                    if (value.lastRemoteModifiedAt != null) {
                      entries.add(
                        strings.isJapanese
                            ? 'リモート更新 ${_formatDateTime(value.lastRemoteModifiedAt!)}'
                            : 'Remote bundle ${_formatDateTime(value.lastRemoteModifiedAt!)}',
                      );
                    }
                    if (entries.isEmpty) {
                      return strings.isJapanese
                          ? 'この端末ではまだ同期履歴がありません。'
                          : 'No sync activity has been recorded on this device yet.';
                    }
                    return entries.join('\n');
                  },
                  loading: () => strings.isJapanese
                      ? '同期履歴を読み込み中...'
                      : 'Reading sync activity...',
                  error: (_, _) => strings.isJapanese
                      ? 'ローカル同期履歴を読めませんでした。'
                      : 'Unable to read local sync activity.',
                ),
              ),
            ),
            if (syncTransferState.localBundle != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.isJapanese ? 'ローカルバンドルキャッシュ' : 'Local bundle cache'),
                subtitle: Text(
                  strings.isJapanese
                      ? '${syncTransferState.localBundle!.reference} に保存済み'
                      : 'Stored at ${syncTransferState.localBundle!.reference}',
                ),
              ),
            _ThemeOptionTile(
              tileKey: syncOffKey,
              title: strings.isJapanese ? 'オフ' : 'Off',
              subtitle: strings.isJapanese
                  ? 'データをこの端末のみに保存します。'
                  : 'Keep data on this device only.',
              selected: syncProvider == SyncProvider.off,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.off),
            ),
            _ThemeOptionTile(
              tileKey: syncICloudKey,
              title: 'iCloud',
              subtitle: strings.isJapanese
                  ? 'Apple 管理のアプリデータ同期先です。'
                  : 'Apple-managed app data sync target.',
              selected: syncProvider == SyncProvider.iCloud,
              onTap: () => ref
                  .read(syncProviderControllerProvider.notifier)
                  .setProvider(SyncProvider.iCloud),
            ),
            _ThemeOptionTile(
              tileKey: syncGoogleDriveKey,
              title: 'Google Drive',
              subtitle: strings.isJapanese
                  ? 'Google Drive の app-data 同期先です。'
                  : 'Google Drive app-data sync target.',
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
                      syncAuthState.isAuthenticated
                          ? (strings.isJapanese ? '再接続' : 'Reconnect')
                          : (strings.isJapanese ? '接続' : 'Connect'),
                    ),
                  ),
                if (syncProvider != SyncProvider.off &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncDisconnectKey,
                    onPressed: () => ref
                        .read(syncAuthControllerProvider.notifier)
                        .disconnectSelected(),
                    child: Text(strings.isJapanese ? '切断' : 'Disconnect'),
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
                  child: Text(strings.isJapanese ? 'リモートを更新' : 'Refresh remote'),
                ),
                if (syncProvider == SyncProvider.googleDrive &&
                    syncAuthState.isAuthenticated)
                  OutlinedButton(
                    key: syncUploadBundleKey,
                    onPressed:
                        syncTransferState.isBusy || syncConflictWarning != null
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
                    child: Text(
                      strings.isJapanese
                          ? 'バンドルをアップロード'
                          : 'Upload bundle',
                    ),
                  ),
                if (syncProvider == SyncProvider.googleDrive &&
                    syncAuthState.isAuthenticated &&
                    syncConflictWarning != null)
                  FilledButton.tonal(
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            final shouldForce =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: Text(
                                        strings.isJapanese
                                            ? '強制アップロードしますか？'
                                            : 'Force upload?',
                                      ),
                                      content: Text(
                                        strings.isJapanese
                                            ? 'この端末に保留中の変更がある状態で、より新しいリモートバンドルが見つかりました。強制アップロードすると、リモートのバックアップをこの端末の状態で上書きします。'
                                            : 'A newer remote bundle was found while this device still has pending changes. Force upload will overwrite the remote backup with this device state.',
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
                                            strings.isJapanese
                                                ? '強制アップロード'
                                                : 'Force upload',
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
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          },
                    child: Text(
                      strings.isJapanese
                          ? '強制アップロード'
                          : 'Force upload',
                    ),
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
                                  .read(syncTransferControllerProvider.notifier)
                                  .listRemoteBundleHistory();
                              if (!context.mounted) {
                                return;
                              }
                              if (history.isEmpty) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      strings.isJapanese
                                          ? '利用できるリモートバンドル履歴がありません。'
                                          : 'No remote bundle history is available.',
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
                                  .read(syncTransferControllerProvider.notifier)
                                  .downloadBundlePreview(selected);
                              if (!context.mounted) {
                                return;
                              }
                              final shouldKeep =
                                  await _showBundlePreviewDialog(
                                    context,
                                    preview,
                                    confirmLabel: strings.isJapanese
                                        ? '適用候補として保持'
                                        : 'Keep for apply',
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
                                  SnackBar(
                                    content: Text(
                                      strings.isJapanese
                                          ? '選択したバンドルを適用候補として保持しました。'
                                          : 'Selected bundle is ready for apply.',
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
                    child: Text(strings.isJapanese ? 'バンドル履歴' : 'Bundle history'),
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
                    child: Text(
                      strings.isJapanese
                          ? 'バンドルをダウンロード'
                          : 'Download bundle',
                    ),
                  ),
                if (syncTransferState.localBundle != null)
                  OutlinedButton(
                    onPressed: syncTransferState.isBusy
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final preview = await ref
                                  .read(syncTransferControllerProvider.notifier)
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
                                SnackBar(content: Text('$error')),
                              );
                            }
                          },
                    child: Text(
                      strings.isJapanese ? 'バンドルを確認' : 'Review bundle',
                    ),
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
                                  .read(syncTransferControllerProvider.notifier)
                                  .previewDownloadedBundle();
                              if (!context.mounted) {
                                return;
                              }
                              final shouldApply =
                                  await _showBundlePreviewDialog(
                                    context,
                                    preview,
                                    confirmLabel: strings.isJapanese
                                        ? 'バンドルを適用'
                                        : 'Apply bundle',
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
                    child: Text(
                      strings.isJapanese ? 'バンドルを適用' : 'Apply bundle',
                    ),
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
                          title: Text(
                            strings.isJapanese
                                ? '同期スナップショットを準備しました'
                                : 'Prepared sync snapshot',
                          ),
                          content: Text(
                            strings.isJapanese
                                ? 'ノート: ${snapshot.notes.length}\n'
                                  '添付: ${snapshot.attachments.length}\n'
                                  'キュー: ${snapshot.summary.totalChanges}件保留中\n'
                                  '端末 ID: ${snapshot.deviceId}'
                                : 'Notes: ${snapshot.notes.length}\n'
                                  'Attachments: ${snapshot.attachments.length}\n'
                                  'Queue: ${snapshot.summary.totalChanges} pending\n'
                                  'Device ID: ${snapshot.deviceId}',
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
                  },
                  child: Text(
                    strings.isJapanese
                        ? 'スナップショットを確認'
                        : 'Inspect snapshot',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.isJapanese ? 'ストレージ' : 'Storage',
          summary: strings.isJapanese
              ? 'この端末に $noteCount 件のノートを保存しています。'
              : '$noteCount notes saved on this device.',
          assetPath: 'assets/settings/storage.svg',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.isJapanese
                    ? 'この端末に保存されたノート'
                    : 'Saved notes on this device',
              ),
              subtitle: Text(strings.isJapanese ? '$noteCount 件' : '$noteCount entries'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () {
                  ref.read(notesControllerProvider.notifier).seedIfEmpty();
                },
                child: Text(
                  strings.isJapanese
                      ? '空の場合にサンプルノートを復元'
                      : 'Restore sample notes if empty',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.appearance,
          summary: appearanceSummary,
          assetPath: 'assets/settings/appearance.svg',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                strings.language,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            _ThemeOptionTile(
              title: strings.languageSystem,
              subtitle: strings.languageSystemDesc,
              selected: localeSetting == AppLocaleSetting.system,
              onTap: () => ref
                  .read(appLocaleControllerProvider.notifier)
                  .setLocale(AppLocaleSetting.system),
            ),
            _ThemeOptionTile(
              title: strings.languageJapanese,
              subtitle: strings.isJapanese ? '表示を日本語に固定します。' : 'Use Japanese across the app.',
              selected: localeSetting == AppLocaleSetting.japanese,
              onTap: () => ref
                  .read(appLocaleControllerProvider.notifier)
                  .setLocale(AppLocaleSetting.japanese),
            ),
            _ThemeOptionTile(
              title: strings.languageEnglish,
              subtitle: strings.isJapanese ? '表示を英語に固定します。' : 'Use English across the app.',
              selected: localeSetting == AppLocaleSetting.english,
              onTap: () => ref
                  .read(appLocaleControllerProvider.notifier)
                  .setLocale(AppLocaleSetting.english),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                strings.accentColor,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            _ThemeOptionTile(
              tileKey: blueColorThemeKey,
              title: strings.colorBlue,
              subtitle: strings.colorBlueDesc,
              selected: colorTheme == AppColorTheme.blue,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.blue),
            ),
            _ThemeOptionTile(
              tileKey: greenColorThemeKey,
              title: strings.colorGreen,
              subtitle: strings.colorGreenDesc,
              selected: colorTheme == AppColorTheme.green,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.green),
            ),
            _ThemeOptionTile(
              tileKey: orangeColorThemeKey,
              title: strings.colorOrange,
              subtitle: strings.colorOrangeDesc,
              selected: colorTheme == AppColorTheme.orange,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.orange),
            ),
            _ThemeOptionTile(
              title: strings.colorSlate,
              subtitle: strings.colorSlateDesc,
              selected: colorTheme == AppColorTheme.slate,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.slate),
            ),
            _ThemeOptionTile(
              title: strings.colorTeal,
              subtitle: strings.colorTealDesc,
              selected: colorTheme == AppColorTheme.teal,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.teal),
            ),
            _ThemeOptionTile(
              title: strings.colorRose,
              subtitle: strings.colorRoseDesc,
              selected: colorTheme == AppColorTheme.rose,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.rose),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: strings.about,
          summary: '$aboutVersion / $displayName',
          assetPath: 'assets/settings/about.svg',
          children: [
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
                  data: (info) => info.displayVersion,
                  loading: strings.readingVersion,
                  error: (_, _) => '1.0.0 (1)',
                ),
              ),
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

  String _syncSubtitle(BuildContext context, SyncProvider provider) {
    final strings = context.strings;
    switch (provider) {
      case SyncProvider.off:
        return strings.isJapanese ? '同期はオフです。' : 'Sync is disabled.';
      case SyncProvider.iCloud:
        return strings.isJapanese
            ? 'iCloud を選択中です。次にアカウント接続を行います。'
            : 'iCloud selected. Account wiring comes next.';
      case SyncProvider.googleDrive:
        return strings.isJapanese
            ? 'Google Drive を選択中です。次にアカウント接続を行います。'
            : 'Google Drive selected. Account wiring comes next.';
    }
  }

  String _syncAuthSummary(
    BuildContext context,
    SyncProvider provider,
    SyncAuthState authState,
  ) {
    final strings = context.strings;
    if (provider == SyncProvider.off) {
      return strings.isJapanese
          ? 'クラウドアカウントは接続されていません。'
          : 'No cloud account is connected.';
    }

    switch (authState.stage) {
      case SyncAuthStage.idle:
        return strings.isJapanese
            ? 'まだアカウントが接続されていません。'
            : 'No account connected yet.';
      case SyncAuthStage.busy:
        return strings.isJapanese
            ? '認証完了を待っています...'
            : 'Waiting for authentication to complete...';
      case SyncAuthStage.authenticated:
        final identity =
            authState.email ?? authState.displayName ?? authState.userId;
        final suffix = authState.message == null ? '' : ' ${authState.message}';
        return identity == null
            ? (strings.isJapanese ? '接続済み。$suffix' : 'Connected.$suffix')
            : (strings.isJapanese
                  ? '$identity として接続済み。$suffix'
                  : 'Connected as $identity.$suffix');
      case SyncAuthStage.unsupported:
      case SyncAuthStage.error:
        return authState.message ??
            (strings.isJapanese
                ? '認証は利用できません。'
                : 'Authentication is not available.');
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

  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    final strings = context.strings;
    return switch (mode) {
      ThemeMode.light => strings.themeLight,
      ThemeMode.system => strings.themeSystem,
      ThemeMode.dark => strings.themeDark,
    };
  }

  String _localeSettingLabel(BuildContext context, AppLocaleSetting setting) {
    final strings = context.strings;
    return switch (setting) {
      AppLocaleSetting.system => strings.languageSystem,
      AppLocaleSetting.japanese => strings.languageJapanese,
      AppLocaleSetting.english => strings.languageEnglish,
    };
  }

  String _colorThemeLabel(BuildContext context, AppColorTheme theme) {
    final strings = context.strings;
    return switch (theme) {
      AppColorTheme.blue => strings.colorBlue,
      AppColorTheme.green => strings.colorGreen,
      AppColorTheme.orange => strings.colorOrange,
      AppColorTheme.slate => strings.colorSlate,
      AppColorTheme.teal => strings.colorTeal,
      AppColorTheme.rose => strings.colorRose,
    };
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
    final strings = context.strings;
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
                        style: Theme.of(context).textTheme.headlineSmall
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
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            strings.isJapanese
                                ? '${activeIdentity.name} 利用中'
                                : '${activeIdentity.name} active',
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
                  label: strings.notes,
                  selected: section == AppSection.notes,
                  onTap: () => onSectionSelected(AppSection.notes),
                ),
                _SidebarItem(
                  icon: Icons.calendar_month_outlined,
                  selectedIcon: Icons.calendar_month_rounded,
                  label: strings.calendar,
                  selected: section == AppSection.calendar,
                  onTap: () => onSectionSelected(AppSection.calendar),
                ),
                _SidebarItem(
                  icon: Icons.insert_chart_outlined_rounded,
                  selectedIcon: Icons.insert_chart_rounded,
                  label: strings.insights,
                  selected: section == AppSection.insights,
                  onTap: () => onSectionSelected(AppSection.insights),
                ),
                _SidebarItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: strings.settings,
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final dayDiff = today.difference(target).inDays;
    final suffix = switch (dayDiff) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => null,
    };
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
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              suffix == null ? label : '$label  $suffix',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _mutedTextColor(context),
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
    final changedAt = note.updatedAt ?? note.createdAt;
    final dateLabel =
        '${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;
    final bodyText = note.body.trim();
    final compactPreview = _normalizeCompactPreview(note.body);
    final hasDistinctBody =
        bodyText.isNotEmpty &&
        bodyText.replaceAll('\n', ' ').trim() != note.title.trim();
    final showAttachmentPreviews = density != NotesListDensity.compact;
    final thumbnailSize = switch (density) {
      NotesListDensity.compact => 44.0,
      NotesListDensity.standard => 56.0,
      NotesListDensity.media => 76.0,
    };
    final maxThumbs = density == NotesListDensity.media ? 4 : 3;
    final bodyLines = switch (density) {
      NotesListDensity.compact => 1,
      NotesListDensity.standard => 2,
      NotesListDensity.media => 3,
    };

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

  String _normalizeCompactPreview(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
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
                tooltip: strings.isJapanese ? '前のメモ' : 'Previous note',
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
                tooltip: strings.isJapanese ? '次のメモ' : 'Next note',
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
                  strings.isJapanese
                      ? '左右にスワイプして前後のメモへ移動できます。'
                      : 'Swipe left or right to move between notes.',
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
                  'Created $createdLabel ﾂｷ Revision ${note.revision}',
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
    blocks.add(NoteBlock(type: NoteBlockType.paragraph, text: note.body));
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

class _SettingsOverviewCard extends StatelessWidget {
  const _SettingsOverviewCard({required this.items});

  final List<_SettingsOverviewItem> items;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedTextColor(context);
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in items)
            SizedBox(
              width: 180,
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
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: muted),
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
    this.initiallyExpanded = false,
  });

  final String title;
  final String summary;
  final String assetPath;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: _sectionDecoration(context),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          maintainState: true,
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    this.tileKey,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Key? tileKey;
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
    final hasAdvancedFilters = !filters.isDefault;
    final listDensity = ref.watch(notesListDensityControllerProvider);

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const Key('notes-search-input'),
            initialValue: query,
            decoration: InputDecoration(
              labelText: strings.search,
              hintText: strings.isJapanese
                  ? 'ノート、日記、添付の名前を検索'
                  : 'Search notes, diary entries, and attachment labels',
              prefixIcon: const Icon(Icons.search_rounded),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: ref.read(searchQueryProvider.notifier).setQuery,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (hasAdvancedFilters)
                Text(
                  strings.isJapanese ? '詳細検索を適用中' : 'Advanced search active',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              const Spacer(),
              PopupMenuButton<NotesListDensity>(
                tooltip: strings.isJapanese ? '一覧表示' : 'List layout',
                onSelected: ref
                    .read(notesListDensityControllerProvider.notifier)
                    .setDensity,
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: NotesListDensity.standard,
                    checked: listDensity == NotesListDensity.standard,
                    child: Text(strings.isJapanese ? '標準表示' : 'Standard list'),
                  ),
                  CheckedPopupMenuItem(
                    value: NotesListDensity.compact,
                    checked: listDensity == NotesListDensity.compact,
                    child: Text(strings.isJapanese ? 'コンパクト表示' : 'Compact list'),
                  ),
                  CheckedPopupMenuItem(
                    value: NotesListDensity.media,
                    checked: listDensity == NotesListDensity.media,
                    child: Text(strings.isJapanese ? 'メディア重視' : 'Media list'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Icon(Icons.view_agenda_outlined, size: 20),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAdvanced = !_showAdvanced;
                  });
                },
                icon: Icon(
                  _showAdvanced
                      ? Icons.expand_less_rounded
                      : Icons.tune_rounded,
                ),
                label: Text(
                  _showAdvanced
                      ? (strings.isJapanese ? '条件を閉じる' : 'Hide filters')
                      : (strings.isJapanese ? '詳細条件' : 'More filters'),
                ),
              ),
            ],
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: Text(strings.isJapanese ? 'ピン留めのみ' : 'Pinned only'),
                  selected: filters.pinnedOnly,
                  onSelected: ref
                      .read(searchFiltersControllerProvider.notifier)
                      .setPinnedOnly,
                ),
                FilterChip(
                  label: Text(strings.isJapanese ? '添付あり' : 'With media'),
                  selected: filters.withMediaOnly,
                  onSelected: ref
                      .read(searchFiltersControllerProvider.notifier)
                      .setWithMediaOnly,
                ),
                SizedBox(
                  width: widget.compact ? 240 : 220,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey(filters.vaultId ?? 'all-vaults'),
                    initialValue: filters.vaultId,
                    decoration: InputDecoration(
                      labelText: strings.isJapanese ? '保管先' : 'Vault',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All visible vaults'),
                      ),
                      for (final vault in visibleVaults)
                        DropdownMenuItem<String?>(
                          value: vault.id,
                          child: Text(vault.name),
                        ),
                    ],
                    onChanged: ref
                        .read(searchFiltersControllerProvider.notifier)
                        .setVault,
                  ),
                ),
                if (hasAdvancedFilters)
                  TextButton(
                    onPressed: ref
                        .read(searchFiltersControllerProvider.notifier)
                        .reset,
                    child: const Text('Reset'),
                  ),
              ],
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
  final Set<String> _pendingAttachmentDeletes = <String>{};
  int? _activeRichParagraphIndex;
  String? _selectedVaultId;
  bool _saved = false;
  bool _draftLoaded = false;
  bool _showTemplates = false;
  Timer? _draftSaveTimer;

  @override
  void initState() {
    super.initState();
    final lastSettings = ref.read(lastNoteEditorSettingsControllerProvider);
    _contentController = TextEditingController(text: _composeEditorContent());
    _contentController.addListener(_handleTextChanged);
    _createdAt = widget.note?.createdAt ?? DateTime.now();
    _isPinned = widget.note?.isPinned ?? false;
    _editorMode =
        widget.note?.editorMode ??
        ((widget.note?.blocks.isNotEmpty ?? false)
            ? NoteEditorMode.rich
            : lastSettings.mode);
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
    _selectedVaultId = widget.note?.vaultId ?? lastSettings.vaultId;
    if (widget.note == null) {
      unawaited(_restoreDraftIfAny());
    }
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    if (!_saved && widget.note == null && _selectedVaultId != null) {
      unawaited(
        ref
            .read(noteEditorDraftStoreProvider)
            .save(
              NoteEditorDraftSnapshot(
                createdAt: _createdAt,
                isPinned: _isPinned,
                editorMode: _editorMode,
                vaultId: _selectedVaultId!,
                quickContent: _contentController.text,
                quickAttachments: _attachments,
                richBlocks: _richBlocksToNoteBlocks(),
              ),
            ),
      );
    }
    if (!_saved) {
      for (final filePath in _pendingAttachmentDeletes) {
        unawaited(
          ref.read(encryptedAttachmentStoreProvider).deleteAttachment(filePath),
        );
      }
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
    _scheduleDraftPersist();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Draft restored'),
        action: SnackBarAction(
          label: 'Discard',
          onPressed: () {
            ref.read(noteEditorDraftStoreProvider).clear();
          },
        ),
      ),
    );
  }

  void _scheduleDraftPersist() {
    if (widget.note != null) {
      return;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
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
              quickContent: _contentController.text,
              quickAttachments: _attachments,
              richBlocks: _richBlocksToNoteBlocks(),
            ),
          );
    });
  }

  void _applyTemplate(_NoteTemplate template) {
    setState(() {
      _contentController.text = template.quickContent;
      _attachments = [];
      for (final block in _richBlocks) {
        block.dispose();
      }
      _richBlocks = [
        for (final block in template.richBlocks)
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
      _showTemplates = false;
    });
    _scheduleDraftPersist();
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  if (widget.note == null) ...[
                    Container(
                      decoration: _sectionDecoration(context),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        initiallyExpanded: _showTemplates,
                        onExpansionChanged: (value) {
                          setState(() {
                            _showTemplates = value;
                          });
                        },
                        title: const Text('Start from template'),
                        subtitle: const Text(
                          'Optional. Begin with a simple writing pattern.',
                        ),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final template in _noteTemplates)
                                ActionChip(
                                  label: Text(template.label),
                                  onPressed: () => _applyTemplate(template),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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
                      _scheduleDraftPersist();
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
                            onMoveBlock: _moveRichBlock,
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
                      _scheduleDraftPersist();
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
                      _scheduleDraftPersist();
                    },
                  ),
                  if (_editorMode == NoteEditorMode.quick)
                    _QuickAttachmentSection(
                      attachments: _attachments,
                      onSelected: _handleAttachmentAction,
                      onRemove: _removeQuickAttachmentAt,
                      onMove: _moveQuickAttachment,
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

  void _showEditorSnackBar({
    required Widget content,
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final availableWidth = mediaQuery.size.width - 32;
    final snackBarWidth = availableWidth <= 420
        ? null
        : math.min(420.0, availableWidth);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(child: content),
            const SizedBox(width: 8),
            IconButton(
              onPressed: messenger.hideCurrentSnackBar,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
          ],
        ),
        action: action,
        behavior: SnackBarBehavior.floating,
        width: snackBarWidth,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16),
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
      content: const Text('Date and time updated'),
      action: SnackBarAction(
          label: 'Undo',
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
    final result = await ref
        .read(mediaImportServiceProvider)
        .importAttachment(action);
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
      content: Text('${removed.label} removed'),
      action: SnackBarAction(
          label: 'Undo',
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
        content: Text('${attachment.label} removed'),
        action: SnackBarAction(
            label: 'Undo',
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

class _RichMemoEditor extends StatelessWidget {
  const _RichMemoEditor({
    required this.blocks,
    required this.onRemoveBlock,
    required this.onBackspaceAtParagraphStart,
    required this.onMoveBlock,
  });

  final List<_RichBlockDraft> blocks;
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
    this.emphasizeInput = false,
    required this.onRemove,
    required this.onBackspaceAtStart,
    required this.onMovePrevious,
    required this.onMoveNext,
    required this.canMovePrevious,
    required this.canMoveNext,
  });

  final _RichBlockDraft block;
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

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _AttachmentPreview(attachment: block.attachment!),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filledTonal(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Remove block',
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
          const SizedBox(width: 6),
          _CompactMediaActionRail(
            canMovePrevious: canMovePrevious,
            canMoveNext: canMoveNext,
            onMovePrevious: onMovePrevious,
            onMoveNext: onMoveNext,
          ),
        ],
      ),
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
            tooltip: 'Move earlier',
          ),
          Divider(height: 1, thickness: 1, color: borderColor),
          _CompactMediaIconButton(
            onPressed: canMoveNext ? onMoveNext : null,
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Move later',
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
    required this.attachments,
    required this.onSelected,
    required this.onRemove,
    required this.onMove,
  });

  final List<NoteAttachment> attachments;
  final ValueChanged<MediaImportAction> onSelected;
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
        _AttachmentListTile(attachment: attachment),
        Positioned(
          top: 8,
          right: 0,
          child: Row(
            children: [
              IconButton(
                onPressed: onMovePrevious,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Move earlier',
              ),
              IconButton(
                onPressed: onMoveNext,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Move later',
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Remove attachment',
              ),
            ],
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
                IconButton(
                  onPressed: () => _shareAttachment(context, ref, attachment),
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Share attachment',
                ),
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
  final filePath = attachment.filePath;
  if (filePath == null || filePath.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This attachment cannot be shared yet.')),
    );
    return;
  }
  await Share.shareXFiles([XFile(filePath)], text: attachment.label);
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
                          fit: BoxFit.contain,
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
  const _AttachmentPreview({required this.attachment, this.size = 72});

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
  final strings = AppStrings(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  if (provider != SyncProvider.googleDrive) {
    return strings.isJapanese
        ? 'リモートバンドル転送は現在 Google Drive のみ対応しています。'
        : 'Remote bundle transport is only wired for Google Drive right now.';
  }
  final remote = transferState.remoteStatus;
  if (remote == null) {
    return transferState.message ??
        (strings.isJapanese
            ? 'まだリモートバンドルのメタデータは読み込まれていません。'
            : 'No remote bundle metadata loaded yet.');
  }
  final modifiedAt = remote.modifiedAt == null
      ? (strings.isJapanese ? '時刻不明' : 'unknown time')
      : _formatDateTime(remote.modifiedAt!);
  final sizeLabel = remote.sizeBytes == null
      ? (strings.isJapanese ? 'サイズ不明' : 'size unknown')
      : (strings.isJapanese
            ? '${remote.sizeBytes} バイト'
            : '${remote.sizeBytes} bytes');
  final noteCount = remote.noteCount == null ? '?' : '${remote.noteCount}';
  final attachmentCount = remote.attachmentCount == null
      ? '?'
      : '${remote.attachmentCount}';
  return strings.isJapanese
      ? '最新バンドル: $modifiedAt、$sizeLabel、ノート $noteCount 件、添付 $attachmentCount 件。'
      : 'Last bundle: $modifiedAt, $sizeLabel, $noteCount notes, $attachmentCount attachments.';
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
        title: Text(strings.isJapanese ? 'バンドル確認' : 'Bundle review'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.isJapanese ? 'バンドル内ノート: ${preview.noteCount}' : 'Notes in bundle: ${preview.noteCount}'),
                Text(strings.isJapanese ? 'バンドル内添付: ${preview.attachmentCount}' : 'Attachments in bundle: ${preview.attachmentCount}'),
                Text(strings.isJapanese ? '追加: ${preview.addedCount}' : 'Adds: ${preview.addedCount}'),
                Text(strings.isJapanese ? '更新: ${preview.updatedCount}' : 'Updates: ${preview.updatedCount}'),
                Text(strings.isJapanese ? 'この端末で削除されるもの: ${preview.removedCount}' : 'Removals on this device: ${preview.removedCount}'),
                if (preview.privateVaultNoteCount > 0)
                  Text(
                    strings.isJapanese
                        ? 'Private vault に影響するノート: ${preview.privateVaultNoteCount}'
                        : 'Private vault notes affected: ${preview.privateVaultNoteCount}',
                  ),
                if (preview.deviceId != null && preview.deviceId!.isNotEmpty)
                  Text(strings.isJapanese ? 'リモート端末: ${preview.deviceId}' : 'Remote device: ${preview.deviceId}'),
                if (preview.exportedAt != null)
                  Text(strings.isJapanese ? '書き出し日時: ${_formatDateTime(preview.exportedAt!)}' : 'Exported at: ${_formatDateTime(preview.exportedAt!)}'),
                if (preview.sampleTitles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(strings.isJapanese ? 'サンプル: ${preview.sampleTitles.join(', ')}' : 'Bundle sample: ${preview.sampleTitles.join(', ')}'),
                ],
                _PreviewTitlesSection(
                  title: strings.isJapanese ? '追加されるノート' : 'Added notes',
                  titles: preview.addedTitles,
                ),
                _PreviewTitlesSection(
                  title: strings.isJapanese ? '更新されるノート' : 'Updated notes',
                  titles: preview.updatedTitles,
                ),
                _PreviewTitlesSection(
                  title: strings.isJapanese ? '適用後にこの端末で消えるノート' : 'Removed locally after apply',
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
        title: Text(
          strings.isJapanese ? 'リモートバンドル履歴' : 'Remote bundle history',
        ),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = history[index];
              final modifiedAt = entry.modifiedAt == null
                  ? (strings.isJapanese ? '時刻不明' : 'Unknown time')
                  : _formatDateTime(entry.modifiedAt!);
              final counts =
                  strings.isJapanese
                      ? '${entry.noteCount ?? '?'}件のノート / ${entry.attachmentCount ?? '?'}件の添付'
                      : '${entry.noteCount ?? '?'} notes, ${entry.attachmentCount ?? '?'} attachments';
              final device = entry.deviceId == null || entry.deviceId!.isEmpty
                  ? (strings.isJapanese ? '端末不明' : 'Unknown device')
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
        title: Text(strings.isJapanese ? '同期キーを読み込む' : 'Import sync key'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: strings.isJapanese
                ? 'himemo-sync-key-v1:... を貼り付け'
                : 'Paste himemo-sync-key-v1:...',
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
            child: Text(strings.isJapanese ? '読み込む' : 'Import'),
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
              strings.isJapanese
                  ? 'このブラウザで使う 4 桁の PIN を設定します。'
                  : 'Use a 4 digit PIN for this browser.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _PinEntryField(controller: _pinController, label: strings.pin),
            const SizedBox(height: 12),
            _PinEntryField(
              controller: _confirmController,
              label: strings.isJapanese ? 'PIN を確認' : 'Confirm PIN',
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
        _errorText = strings.isJapanese
            ? 'PIN は 4 桁ちょうどで入力してください。'
            : 'PIN must be exactly 4 digits.';
      });
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      setState(() {
        _errorText = strings.isJapanese
            ? 'PIN は数字だけで入力してください。'
            : 'PIN must contain digits only.';
      });
      return;
    }
    if (pin != confirm) {
      setState(() {
        _errorText = strings.isJapanese
            ? '確認用 PIN が一致しません。'
            : 'PIN confirmation did not match.';
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
          _attachmentDescription(attachment),
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
            icon: const Icon(
              Icons.center_focus_strong_rounded,
              color: Colors.white,
            ),
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
        child: Text('No image is stored for this attachment.'),
      );
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
