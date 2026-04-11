import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:go_router/go_router.dart';

import '../domain/note_entry.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';

enum AppSection { notes, calendar, settings }

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

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
            icon: const Icon(Icons.lock_open_rounded),
            tooltip: 'Switch unlock profile',
          ),
        ],
      ),
      body: SafeArea(
        child: useRail
            ? Row(
                children: [
                  _Sidebar(
                    section: section,
                    activeIdentity: activeIdentity,
                    flavorName: flavor,
                    onSectionSelected: (section) =>
                        _goToSection(context, section),
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
                  icon: Icon(Icons.notes_outlined),
                  selectedIcon: Icon(Icons.notes_rounded),
                  label: 'Notes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Calendar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
      floatingActionButton: section == AppSection.notes
          ? FloatingActionButton.small(
              onPressed: () {},
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
          _StatsStrip(
            visibleCount: visibleNotes.length,
            pinnedCount: visibleNotes.where((note) => note.isPinned).length,
            vaultCount: visibleVaults.length,
          ),
          const SizedBox(height: 20),
          for (final vault in visibleVaults) ...[
            _VaultSectionCard(
              vault: vault,
              notes: ref.watch(notesForVaultProvider(vault.id)),
              selectedNoteId: _selectedNoteId,
              onNoteSelected: (noteId) {
                setState(() {
                  _selectedNoteId = noteId;
                });
              },
            ),
            const SizedBox(height: 20),
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
              _StatsStrip(
                visibleCount: visibleNotes.length,
                pinnedCount: visibleNotes.where((note) => note.isPinned).length,
                vaultCount: visibleVaults.length,
              ),
              const SizedBox(height: 20),
              Container(
                decoration: _panelDecoration(context),
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
                        const Divider(height: 1),
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
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).dividerColor),
    );
  }
}

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = <String, List<NoteEntry>>{};
    for (final note in ref.watch(visibleNotesProvider)) {
      final key =
          '${note.createdAt.year}/${note.createdAt.month.toString().padLeft(2, '0')}/${note.createdAt.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(note);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionIntro(
          title: 'Calendar',
          description: 'Review notes grouped by day.',
        ),
        const SizedBox(height: 16),
        for (final entry in grouped.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: _sectionDecoration(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final note in entry.value)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('- ${note.title}'),
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

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identities = ref.watch(identitiesProvider);
    final activeIdentity = ref.watch(activeIdentityProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final flavorName =
        FlavorConfig.instance.variables['flavor'] as String? ?? 'development';
    final displayName =
        FlavorConfig.instance.variables['displayName'] as String? ?? 'HiMemo';

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
          title: 'Theme',
          children: [
            _ThemeOptionTile(
              title: 'Light',
              subtitle: 'Keep the white memo-style interface.',
              selected: themeMode == ThemeMode.light,
              onTap: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .setMode(ThemeMode.light),
            ),
            _ThemeOptionTile(
              title: 'System',
              subtitle: 'Follow the device setting.',
              selected: themeMode == ThemeMode.system,
              onTap: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .setMode(ThemeMode.system),
            ),
            _ThemeOptionTile(
              title: 'Dark',
              subtitle: 'Use the dark theme explicitly.',
              selected: themeMode == ThemeMode.dark,
              onTap: () => ref
                  .read(themeModeControllerProvider.notifier)
                  .setMode(ThemeMode.dark),
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
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HiMemo',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  activeIdentity.lockLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  activeIdentity.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  flavorName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D7C87),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(selected ? selectedIcon : icon),
        title: Text(label),
        selected: selected,
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            identity.lockLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            identity.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            identity.tagline,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF4F6270)),
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
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D7C87)),
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
  final ValueChanged<String> onNoteSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vault.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  vault.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D7C87),
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
              onTap: () => onNoteSelected(notes[i].id),
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
      color: selected ? const Color(0xFFF2F5F7) : Colors.transparent,
      child: InkWell(
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (note.isPinned)
                    const Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: Color(0xFF6D7C87),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                note.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF4F6270),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    vaultName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6D7C87),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7B8A95),
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
  const _NoteDetailPane({required this.note, required this.vaultName});

  final NoteEntry? note;
  final String? vaultName;

  @override
  Widget build(BuildContext context) {
    if (note == null) {
      return const Center(child: Text('No note selected'));
    }

    final dateLabel =
        '${note!.createdAt.year}/${note!.createdAt.month}/${note!.createdAt.day} ${note!.createdAt.hour.toString().padLeft(2, '0')}:${note!.createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vaultName ?? '',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: const Color(0xFF6D7C87)),
          ),
          const SizedBox(height: 8),
          Text(
            note!.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            dateLabel,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF7B8A95)),
          ),
          const SizedBox(height: 20),
          Text(
            note!.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
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
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF4F6270)),
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
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
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

BoxDecoration _sectionDecoration(BuildContext context) {
  return BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Theme.of(context).dividerColor),
  );
}
