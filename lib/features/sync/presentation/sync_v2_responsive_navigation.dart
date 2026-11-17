import 'package:flutter/material.dart';

import '../../home/presentation/home_page.dart'
    show AppSection, HomeSharedSidebar;
import '../../home/presentation/home_providers.dart' show VisibleTagSummary;

/// Navigation presentation for the isolated V2 workspace.
///
/// This widget owns no routing, note state, profiles, or repositories. The
/// caller decides whether a section change is safe and handles it in callbacks.
enum SyncV2NavigationSection {
  notes,
  calendar,
  insights,
  trash,
  tags,
  settings,
}

class SyncV2ResponsiveNavigation extends StatelessWidget {
  const SyncV2ResponsiveNavigation({
    super.key,
    required this.section,
    required this.wide,
    required this.onSectionSelected,
    required this.onAddNote,
    this.enabled = true,
    this.canOpenSettings = true,
    this.isJapanese = true,
    this.tagSummaries = const [],
    this.activeTags = const [],
    this.onTagSelected,
    this.onShowAllNotes,
  });

  final SyncV2NavigationSection section;

  /// Whether the parent viewport uses the wide sidebar layout. This must be
  /// computed from the full window width, since the sidebar itself is narrow.
  final bool wide;
  final ValueChanged<SyncV2NavigationSection> onSectionSelected;
  final VoidCallback onAddNote;
  final bool enabled;
  final bool canOpenSettings;
  final bool isJapanese;
  final List<VisibleTagSummary> tagSummaries;
  final List<String> activeTags;
  final ValueChanged<String>? onTagSelected;
  final VoidCallback? onShowAllNotes;

  String _label(SyncV2NavigationSection value) => switch ((isJapanese, value)) {
    (true, SyncV2NavigationSection.notes) => 'ノート',
    (true, SyncV2NavigationSection.calendar) => 'カレンダー',
    (true, SyncV2NavigationSection.insights) => '記録',
    (true, SyncV2NavigationSection.trash) => 'ゴミ箱',
    (true, SyncV2NavigationSection.tags) => 'タグ',
    (true, SyncV2NavigationSection.settings) => '設定',
    (false, SyncV2NavigationSection.notes) => 'Notes',
    (false, SyncV2NavigationSection.calendar) => 'Calendar',
    (false, SyncV2NavigationSection.insights) => 'Insights',
    (false, SyncV2NavigationSection.trash) => 'Trash',
    (false, SyncV2NavigationSection.tags) => 'Tags',
    (false, SyncV2NavigationSection.settings) => 'Settings',
  };

  IconData _icon(
    SyncV2NavigationSection value, {
    required bool selected,
  }) => switch ((value, selected)) {
    (SyncV2NavigationSection.notes, false) => Icons.notes_outlined,
    (SyncV2NavigationSection.notes, true) => Icons.notes_rounded,
    (SyncV2NavigationSection.calendar, false) => Icons.calendar_month_outlined,
    (SyncV2NavigationSection.calendar, true) => Icons.calendar_month_rounded,
    (SyncV2NavigationSection.insights, false) =>
      Icons.insert_chart_outlined_rounded,
    (SyncV2NavigationSection.insights, true) => Icons.insert_chart_rounded,
    (SyncV2NavigationSection.trash, false) => Icons.delete_outline_rounded,
    (SyncV2NavigationSection.trash, true) => Icons.delete_rounded,
    (SyncV2NavigationSection.tags, false) => Icons.sell_outlined,
    (SyncV2NavigationSection.tags, true) => Icons.sell_rounded,
    (SyncV2NavigationSection.settings, false) => Icons.settings_outlined,
    (SyncV2NavigationSection.settings, true) => Icons.settings_rounded,
  };

  @override
  Widget build(BuildContext context) => wide
      ? _sidebar(context)
      : LayoutBuilder(
          builder: (context, constraints) =>
              _bottomBar(context, hideLabels: constraints.maxWidth < 380),
        );

  Widget _sidebar(BuildContext context) {
    return HomeSharedSidebar(
      section: AppSection.values.byName(section.name),
      enabled: enabled,
      canOpenSettings: canOpenSettings,
      tagSummaries: tagSummaries,
      activeTags: activeTags,
      onTagSelected: onTagSelected,
      onShowAllNotes: onShowAllNotes,
      onSectionSelected: (value) =>
          onSectionSelected(SyncV2NavigationSection.values.byName(value.name)),
      onAddNote: onAddNote,
    );
  }

  Widget _bottomBar(BuildContext context, {required bool hideLabels}) {
    final primary = [
      SyncV2NavigationSection.notes,
      SyncV2NavigationSection.calendar,
      SyncV2NavigationSection.insights,
      SyncV2NavigationSection.settings,
    ];
    final selectedIndex = primary.indexOf(section);
    return SafeArea(
      top: false,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          NavigationBar(
            selectedIndex: selectedIndex < 0 ? 3 : selectedIndex,
            labelBehavior: hideLabels
                ? NavigationDestinationLabelBehavior.alwaysHide
                : NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (index) {
              if (enabled &&
                  (primary[index] != SyncV2NavigationSection.settings ||
                      canOpenSettings)) {
                onSectionSelected(primary[index]);
              }
            },
            destinations: [
              for (var index = 0; index < primary.length; index++)
                FractionalTranslation(
                  translation: Offset(const [-0.05, -0.3, 0.3, 0.05][index], 0),
                  child: NavigationDestination(
                    icon: Icon(_icon(primary[index], selected: false)),
                    selectedIcon: Icon(_icon(primary[index], selected: true)),
                    label: hideLabels ? '' : _label(primary[index]),
                    tooltip: _label(primary[index]),
                    enabled:
                        enabled &&
                        (primary[index] != SyncV2NavigationSection.settings ||
                            canOpenSettings),
                  ),
                ),
            ],
          ),
          Positioned(
            top: -4,
            child: Tooltip(
              message: isJapanese ? 'ノートを追加' : 'Add note',
              child: SizedBox.square(
                dimension: 68,
                child: Center(
                  child: SizedBox.square(
                    dimension: 56,
                    child: FilledButton(
                      onPressed: enabled ? onAddNote : null,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.edit_note_rounded, size: 32),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
