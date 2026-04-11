import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/note_entry.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';

enum AppSection { notes, calendar, settings }

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  static const profileSwitchKey = Key('profile-switch-button');
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
        actions: [
          IconButton(
            onPressed: () => _showIdentityPicker(context, ref),
            key: profileSwitchKey,
            icon: const Icon(Icons.lock_open_rounded),
            tooltip: 'Switch unlock profile',
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

  Future<void> _showIdentityPicker(BuildContext context, WidgetRef ref) async {
    final identities = ref.read(identitiesProvider);
    final activeId = ref.read(activeIdentityProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final identity in identities)
                ListTile(
                  leading: Icon(
                    activeId == identity.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(identity.name),
                  subtitle: Text('${identity.lockLabel}  ${identity.tagline}'),
                  onTap: () {
                    ref
                        .read(activeIdentityProvider.notifier)
                        .switchTo(identity.id);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useSplitView = width >= 1180;
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final visibleNotes = ref.watch(visibleNotesProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);

    if (visibleNotes.isNotEmpty &&
        (_selectedNoteId == null ||
            visibleNotes.every((note) => note.id != _selectedNoteId))) {
      _selectedNoteId = visibleNotes.first.id;
    }

    final selectedNote = _selectedNoteId == null
        ? null
        : ref.watch(noteByIdProvider(_selectedNoteId!));

    if (!useSplitView) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _IdentityHeader(identity: activeIdentity),
          const SizedBox(height: 12),
          const _NotesToolbar(),
          const SizedBox(height: 12),
          _StatsStrip(
            visibleCount: visibleNotes.length,
            pinnedCount: visibleNotes.where((note) => note.isPinned).length,
            vaultCount: visibleVaults.length,
          ),
          const SizedBox(height: 16),
          if (visibleNotes.isEmpty)
            const _EmptyNotesState()
          else
            for (final vault in visibleVaults) ...[
              _VaultSectionCard(
                vault: vault,
                notes: ref.watch(notesForVaultProvider(vault.id)),
                selectedNoteId: _selectedNoteId,
                onNoteSelected: (note) => _openMobileNoteActions(context, note),
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
              _IdentityHeader(identity: activeIdentity),
              const SizedBox(height: 12),
              const _NotesToolbar(),
              const SizedBox(height: 12),
              _StatsStrip(
                visibleCount: visibleNotes.length,
                pinnedCount: visibleNotes.where((note) => note.isPinned).length,
                vaultCount: visibleVaults.length,
              ),
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
            child: _NoteDetailPane(
              note: selectedNote,
              vaultName: selectedNote == null
                  ? null
                  : ref.watch(vaultByIdProvider(selectedNote.vaultId)).name,
              onEdit: selectedNote == null
                  ? null
                  : () => showNoteEditorSheet(context, ref, note: selectedNote),
              onDelete: selectedNote == null
                  ? null
                  : () => _deleteNote(context, selectedNote),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMobileNoteActions(
    BuildContext context,
    NoteEntry note,
  ) async {
    final vaultName = ref.read(vaultByIdProvider(note.vaultId)).name;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: _NoteDetailPane(
              note: note,
              vaultName: vaultName,
              onEdit: () async {
                Navigator.of(context).pop();
                await showNoteEditorSheet(context, ref, note: note);
              },
              onDelete: () async {
                Navigator.of(context).pop();
                await _deleteNote(context, note);
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
    final markedDays = notes
        .map((note) => DateTime(note.createdAt.year, note.createdAt.month, note.createdAt.day))
        .toSet();
    final sameDayNotes = notes
        .where((note) => _isSameDay(note.createdAt, _selectedDay))
        .toList(growable: false);

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
                _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
              });
            },
            onNextMonth: () {
              setState(() {
                _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
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
              Text(
                '${_selectedDay.year}/${_selectedDay.month.toString().padLeft(2, '0')}/${_selectedDay.day.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.titleMedium,
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
                  ),
                  if (i != sameDayNotes.length - 1)
                    Divider(
                      height: 24,
                      color: Theme.of(context).dividerColor,
                    ),
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
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingEmpty = (firstDay.weekday + 6) % 7;
    final totalCells = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;
    final monthLabel = '${visibleMonth.year}/${visibleMonth.month.toString().padLeft(2, '0')}';
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
            TextButton(
              onPressed: onTodaySelected,
              child: const Text('Today'),
            ),
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
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
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
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: isSelected
                                            ? colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
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

  static const lightThemeKey = Key('theme-light-option');
  static const systemThemeKey = Key('theme-system-option');
  static const darkThemeKey = Key('theme-dark-option');
  static const blueColorThemeKey = Key('color-theme-blue-option');
  static const greenColorThemeKey = Key('color-theme-green-option');
  static const orangeColorThemeKey = Key('color-theme-orange-option');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identities = ref.watch(identitiesProvider);
    final activeIdentity = ref.watch(activeIdentityProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final colorTheme = ref.watch(appColorThemeControllerProvider);
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
          description: 'Manage lock profiles, sync, and display policy.',
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          title: 'Lock profiles',
          children: [
            for (final identity in identities)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(identity.name),
                subtitle: Text(identity.lockLabel),
                trailing: activeIdentity == identity.id
                    ? const Icon(Icons.check_rounded)
                    : null,
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
              subtitle: 'Warm orange palette for highlighted actions and notes.',
              selected: colorTheme == AppColorTheme.orange,
              onTap: () => ref
                  .read(appColorThemeControllerProvider.notifier)
                  .setTheme(AppColorTheme.orange),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SettingsGroup(
          title: 'Cloud sync roadmap',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('iCloud / Google sync'),
              subtitle: Text(
                'Local-first persistence is active. End-to-end encrypted sync remains the next implementation milestone.',
              ),
            ),
          ],
        ),
      ],
    );
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
    final accent = Color(activeIdentity.accentHex);

    return SizedBox(
      width: 256,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 4, color: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HiMemo',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  activeIdentity.lockLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(activeIdentity.name),
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
            identity.lockLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(identity.name),
          const SizedBox(height: 6),
          Text(
            identity.tagline,
            style: Theme.of(
              context,
            )
                .textTheme
                .bodyLarge
                ?.copyWith(color: _strongMutedTextColor(context)),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.visibleCount,
    required this.pinnedCount,
    required this.vaultCount,
  });

  final int visibleCount;
  final int pinnedCount;
  final int vaultCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(label: 'Visible', value: '$visibleCount'),
          ),
          _ThinDivider(color: Theme.of(context).dividerColor),
          Expanded(
            child: _StatTile(label: 'Pinned', value: '$pinnedCount'),
          ),
          _ThinDivider(color: Theme.of(context).dividerColor),
          Expanded(
            child: _StatTile(label: 'Vaults', value: '$vaultCount'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
        ],
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 52, color: color);
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
            _NoteListTile(
              note: notes[i],
              vaultName: vault.name,
              selected: notes[i].id == selectedNoteId,
              onTap: () => onNoteSelected(notes[i]),
            ),
            if (i != notes.length - 1)
              Divider(height: 1, color: Theme.of(context).dividerColor),
          ],
        ],
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.vaultName,
    required this.selected,
    required this.onTap,
  });

  final NoteEntry note;
  final String vaultName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${note.createdAt.month}/${note.createdAt.day} ${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';

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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in note.attachments)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(attachment.label),
                        avatar:
                            Icon(_iconForAttachment(attachment.type), size: 16),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    vaultName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _mutedTextColor(context),
                        ),
                  ),
                  const Spacer(),
                  Text(
                    dateLabel,
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

class _NoteDetailPane extends StatelessWidget {
  const _NoteDetailPane({
    required this.note,
    required this.vaultName,
    this.onEdit,
    this.onDelete,
  });

  final NoteEntry? note;
  final String? vaultName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (note == null) {
      return const _EmptyNotesState();
    }

    final dateLabel =
        '${note!.createdAt.year}/${note!.createdAt.month}/${note!.createdAt.day} ${note!.createdAt.hour.toString().padLeft(2, '0')}:${note!.createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vaultName ?? '',
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
          Text(note!.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            dateLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                note!.body,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ),
          ),
          if (note!.attachments.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in note!.attachments)
                  Chip(
                    label: Text(attachment.label),
                    avatar: Icon(_iconForAttachment(attachment.type), size: 16),
                  ),
              ],
            ),
          ],
        ],
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
          style: Theme.of(
            context,
          )
              .textTheme
              .bodyLarge
              ?.copyWith(color: _strongMutedTextColor(context)),
        ),
      ],
    );
  }
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
  const _NotesToolbar();

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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.lock_outline_rounded,
                text: ref.watch(activeIdentityDataProvider).lockLabel,
              ),
              _InfoChip(
                icon: Icons.folder_outlined,
                text:
                    '${ref.watch(visibleVaultsProvider).length} vaults visible',
              ),
              _InfoChip(
                icon: Icons.push_pin_outlined,
                text:
                    '${ref.watch(visibleNotesProvider).where((note) => note.isPinned).length} pinned',
              ),
            ],
          ),
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
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
    );
  }
}

class _CalendarNoteRow extends StatelessWidget {
  const _CalendarNoteRow({required this.note, required this.vaultName});

  final NoteEntry note;
  final String vaultName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(note.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          note.body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _strongMutedTextColor(context),
              ),
        ),
        const SizedBox(height: 8),
        Text(
          vaultName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _mutedTextColor(context),
              ),
        ),
      ],
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _mutedTextColor(context),
                ),
          ),
        ],
      ),
    );
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
  late List<NoteAttachment> _attachments;
  String? _selectedVaultId;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: _composeEditorContent());
    _contentController.addListener(_handleTextChanged);
    _createdAt = widget.note?.createdAt ?? DateTime.now();
    _isPinned = widget.note?.isPinned ?? false;
    _attachments = [...?widget.note?.attachments];
    _selectedVaultId = widget.note?.vaultId ?? 'everyday';
  }

  @override
  void dispose() {
    _contentController.removeListener(_handleTextChanged);
    _contentController.dispose();
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
            Text(
              widget.note == null ? 'New note' : 'Edit note',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    key: const Key('note-content-input'),
                    controller: _contentController,
                    minLines: 8,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Memo',
                      hintText: 'Use the first line as the title',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(
                      '${_createdAt.year}/${_createdAt.month.toString().padLeft(2, '0')}/${_createdAt.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: OutlinedButton(
                      onPressed: _pickDate,
                      child: const Text('Change'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
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
                            PopupMenuButton<AttachmentType>(
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: AttachmentType.photo,
                                  child: Text('Add photo placeholder'),
                                ),
                                PopupMenuItem(
                                  value: AttachmentType.video,
                                  child: Text('Add video placeholder'),
                                ),
                                PopupMenuItem(
                                  value: AttachmentType.audio,
                                  child: Text('Add audio placeholder'),
                                ),
                              ],
                              onSelected: _addAttachment,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text('Add'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_attachments.isEmpty)
                          Text(
                            'Use placeholders for decoy photo, video, or audio entries.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _mutedTextColor(context),
                                    ),
                          )
                        else
                          for (var i = 0; i < _attachments.length; i++)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                  _iconForAttachment(_attachments[i].type)),
                              title: Text(_attachments[i].label),
                              trailing: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _attachments.removeAt(i);
                                  });
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                      ],
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
    return _splitMemoContent(_contentController.text).title.isNotEmpty &&
        _selectedVaultId != null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _createdAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _createdAt.hour,
        _createdAt.minute,
      );
    });
  }

  void _addAttachment(AttachmentType type) {
    final count =
        _attachments.where((attachment) => attachment.type == type).length;
    final label = switch (type) {
      AttachmentType.photo => 'photo-${count + 1}.jpg',
      AttachmentType.video => 'video-${count + 1}.mp4',
      AttachmentType.audio => 'audio-${count + 1}.m4a',
    };
    setState(() {
      _attachments = [
        ..._attachments,
        NoteAttachment(type: type, label: label),
      ];
    });
  }

  Future<void> _save() async {
    if (!_canSave) {
      return;
    }
    final content = _splitMemoContent(_contentController.text);
    final note = NoteEntry(
      id: widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      vaultId: _selectedVaultId!,
      title: content.title,
      body: content.body,
      createdAt: _createdAt,
      attachments: _attachments,
      isPinned: _isPinned,
    );
    await ref.read(notesControllerProvider.notifier).upsert(note);
    if (mounted) {
      Navigator.of(context).pop();
    }
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
