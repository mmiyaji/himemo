part of 'home_page.dart';

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
                          final result = await _showDeleteNoteDialog(
                            hostContext,
                            selectedNote,
                          );
                          if (result != null) {
                            final controller = ref.read(
                              notesControllerProvider.notifier,
                            );
                            await controller.delete(selectedNote.id);
                            if (result.deletePermanently) {
                              await controller.deletePermanently(
                                selectedNote.id,
                              );
                            }
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
            for (var index = 0; index < weekdays.length; index++)
              Expanded(
                child: Center(
                  child: Text(
                    weekdays[index],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _calendarWeekdayLabelColor(context, index),
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

Color _calendarWeekdayLabelColor(BuildContext context, int weekdayIndex) {
  return switch (weekdayIndex) {
    5 => Colors.blue.shade700,
    6 => Colors.red.shade700,
    _ => _mutedTextColor(context),
  };
}
