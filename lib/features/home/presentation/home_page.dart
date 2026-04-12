import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pinput/pinput.dart';
import 'package:video_player/video_player.dart';

import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/sync_bundle_preview.dart';
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

    final selectedNote = _selectedNoteId == null
        ? null
        : ref.watch(noteByIdProvider(_selectedNoteId!));

    if (!useSplitView) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _IdentityHeader(identity: activeIdentity),
          if (activeIdentity.id == 'private' && !privateVaultUnlocked) ...[
            const SizedBox(height: 12),
            const _PrivateVaultLockedNotice(),
          ],
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
              if (activeIdentity.id == 'private' && !privateVaultUnlocked) ...[
                const SizedBox(height: 12),
                const _PrivateVaultLockedNotice(),
              ],
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
        .map(
          (note) => DateTime(
            note.createdAt.year,
            note.createdAt.month,
            note.createdAt.day,
          ),
        )
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identities = ref.watch(identitiesProvider);
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
                              await ref
                                  .read(
                                    syncTransferControllerProvider.notifier,
                                  )
                                  .downloadBundle(selected);
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
                                SnackBar(content: Text(message)),
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
    final accent = Color(activeIdentity.accentHex);

    return SizedBox(
      width: 256,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 4, color: accent),
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
    final changedAt = note.updatedAt ?? note.createdAt;
    final dateLabel =
        '${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;

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
                        avatar: Icon(
                          _iconForAttachment(attachment.type),
                          size: 16,
                        ),
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

    final createdLabel =
        '${note!.createdAt.year}/${note!.createdAt.month}/${note!.createdAt.day} ${note!.createdAt.hour.toString().padLeft(2, '0')}:${note!.createdAt.minute.toString().padLeft(2, '0')}';
    final changedAt = note!.updatedAt ?? note!.createdAt;
    final updatedLabel =
        '${changedAt.year}/${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited =
        note!.updatedAt != null && note!.updatedAt != note!.createdAt;

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
            isEdited ? 'Edited $updatedLabel' : createdLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
          if (isEdited)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Created $createdLabel · Revision ${note!.revision}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
              ),
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
            Column(
              children: [
                for (final attachment in note!.attachments) ...[
                  _AttachmentListTile(attachment: attachment),
                  if (attachment != note!.attachments.last)
                    const SizedBox(height: 12),
                ],
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _strongMutedTextColor(context),
              ),
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
    return Chip(avatar: Icon(icon, size: 16), label: Text(text));
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
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
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
  late final Set<String> _initialAttachmentPaths;
  String? _selectedVaultId;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: _composeEditorContent());
    _contentController.addListener(_handleTextChanged);
    _createdAt = widget.note?.createdAt ?? DateTime.now();
    _isPinned = widget.note?.isPinned ?? false;
    _attachments = [...?widget.note?.attachments];
    _initialAttachmentPaths = _attachments
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    _selectedVaultId = widget.note?.vaultId ?? 'everyday';
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final attachment in _attachments) {
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
                            PopupMenuButton<MediaImportAction>(
                              key: const Key('attachment-add-menu'),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: MediaImportAction.takePhoto,
                                  child: Text('Take photo'),
                                ),
                                PopupMenuItem(
                                  value: MediaImportAction.pickPhoto,
                                  child: Text('Pick photo'),
                                ),
                                PopupMenuItem(
                                  value: MediaImportAction.recordVideo,
                                  child: Text('Record video'),
                                ),
                                PopupMenuItem(
                                  value: MediaImportAction.pickVideo,
                                  child: Text('Pick video'),
                                ),
                                PopupMenuItem(
                                  value: MediaImportAction.pickAudio,
                                  child: Text('Pick audio'),
                                ),
                              ],
                              onSelected: _handleAttachmentAction,
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
                            'Attach photos, videos, or audio files from camera or device storage.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: _mutedTextColor(context)),
                          )
                        else
                          for (var i = 0; i < _attachments.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _EditableAttachmentTile(
                                attachment: _attachments[i],
                                onRemove: () {
                                  final removed = _attachments[i];
                                  setState(() {
                                    _attachments.removeAt(i);
                                  });
                                  final filePath = removed.filePath;
                                  if (filePath != null &&
                                      !_initialAttachmentPaths.contains(
                                        filePath,
                                      )) {
                                    unawaited(
                                      ref
                                          .read(
                                              encryptedAttachmentStoreProvider)
                                          .deleteAttachment(filePath),
                                    );
                                  }
                                },
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('quick-attach-photo-button'),
                  onPressed: () =>
                      _handleAttachmentAction(MediaImportAction.pickPhoto),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Add photo'),
                ),
                OutlinedButton.icon(
                  key: const Key('quick-attach-camera-button'),
                  onPressed: () =>
                      _handleAttachmentAction(MediaImportAction.takePhoto),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Use camera'),
                ),
              ],
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
      _attachments = [..._attachments, attachment];
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
      updatedAt: widget.note == null ? _createdAt : DateTime.now(),
      attachments: _attachments,
      isPinned: _isPinned,
      revision: widget.note?.revision ?? 1,
      deviceId: widget.note?.deviceId,
      syncState: widget.note?.syncState ?? NoteSyncState.localOnly,
    );
    await ref.read(notesControllerProvider.notifier).upsert(note);
    _saved = true;
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

class _AttachmentPreview extends ConsumerWidget {
  const _AttachmentPreview({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachment.type != AttachmentType.photo) {
      return _AttachmentIconBox(type: attachment.type);
    }

    final previewBytesBase64 = attachment.previewBytesBase64;
    if (previewBytesBase64 != null && previewBytesBase64.isNotEmpty) {
      return _AttachmentImageBox(bytes: base64Decode(previewBytesBase64));
    }

    final filePath = attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      return _AttachmentIconBox(type: attachment.type);
    }

    return FutureBuilder<List<int>?>(
      future: ref
          .watch(encryptedAttachmentStoreProvider)
          .readAttachment(filePath, type: attachment.type),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _AttachmentIconBox(type: attachment.type);
        }
        return _AttachmentImageBox(bytes: bytes);
      },
    );
  }
}

class _AttachmentImageBox extends StatelessWidget {
  const _AttachmentImageBox({required this.bytes});

  final List<int> bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        Uint8List.fromList(bytes),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

class _AttachmentIconBox extends StatelessWidget {
  const _AttachmentIconBox({required this.type});

  final AttachmentType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _iconForAttachment(type),
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
  final details = <String>[
    'Notes in bundle: ${preview.noteCount}',
    'Attachments in bundle: ${preview.attachmentCount}',
    'Adds: ${preview.addedCount}',
    'Updates: ${preview.updatedCount}',
    'Removals on this device: ${preview.removedCount}',
    if (preview.deviceId != null && preview.deviceId!.isNotEmpty)
      'Remote device: ${preview.deviceId}',
    if (preview.exportedAt != null)
      'Exported at: ${_formatDateTime(preview.exportedAt!)}',
    if (preview.sampleTitles.isNotEmpty)
      'Sample notes: ${preview.sampleTitles.join(', ')}',
  ];

  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Bundle review'),
        content: Text(details.join('\n')),
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
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(modifiedAt),
                subtitle: Text(
                  '${entry.fileName}\n$counts',
                ),
                isThreeLine: true,
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
  NoteAttachment attachment,
) async {
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
