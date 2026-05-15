part of 'home_page.dart';

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
