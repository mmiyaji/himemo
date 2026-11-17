import 'package:flutter/material.dart';

import '../../home/presentation/home_providers.dart';

/// Opens the V1-style search filter dialog and returns the selected filters.
/// The caller owns persistence and applies the result to its own note list.
Future<SearchFilters?> showSyncV2SearchFiltersDialog(
  BuildContext context, {
  required SearchFilters initialFilters,
  required List<String> availableTags,
  required List<int> availableYears,
  required bool hasArchivedNotes,
}) {
  return showDialog<SearchFilters>(
    context: context,
    builder: (context) => SyncV2SearchFiltersDialog(
      initialFilters: initialFilters,
      availableTags: availableTags,
      availableYears: availableYears,
      hasArchivedNotes: hasArchivedNotes,
    ),
  );
}

/// A self-contained filter editor. No storage or note-list state is accessed.
class SyncV2SearchFiltersDialog extends StatefulWidget {
  const SyncV2SearchFiltersDialog({
    super.key,
    required this.initialFilters,
    required this.availableTags,
    required this.availableYears,
    required this.hasArchivedNotes,
  });

  final SearchFilters initialFilters;
  final List<String> availableTags;
  final List<int> availableYears;
  final bool hasArchivedNotes;

  @override
  State<SyncV2SearchFiltersDialog> createState() =>
      _SyncV2SearchFiltersDialogState();
}

class _SyncV2SearchFiltersDialogState extends State<SyncV2SearchFiltersDialog> {
  late SearchFilters _filters;

  bool get _ja => Localizations.localeOf(context).languageCode == 'ja';
  String tx(String en, String ja) => _ja ? ja : en;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
  }

  void _update(SearchFilters value) => setState(() => _filters = value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = {...widget.availableTags, ..._filters.tags}.toList()..sort();
    final years = widget.availableYears.toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Expanded(child: Text(tx('Filters', '詳細条件'))),
          if (!_filters.isDefault)
            TextButton(
              onPressed: () => _update(const SearchFilters()),
              child: Text(tx('Reset', 'リセット')),
            ),
          IconButton(
            tooltip: tx('Close', '閉じる'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .68,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(tx('Pinned only', 'ピン留めのみ')),
                  value: _filters.pinnedOnly,
                  onChanged: (v) =>
                      _update(_filters.copyWith(pinnedOnly: v ?? false)),
                ),
                const Divider(height: 12),
                Text(
                  tx('Attachments', '添付ファイル'),
                  style: theme.textTheme.titleSmall,
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final entry
                        in <(SearchAttachmentFilter, String, String)>[
                          (SearchAttachmentFilter.any, 'Any', 'あり'),
                          (SearchAttachmentFilter.photo, 'Images', '画像'),
                          (SearchAttachmentFilter.video, 'Videos', '動画'),
                          (SearchAttachmentFilter.audio, 'Audio', '音声'),
                          (SearchAttachmentFilter.location, 'Location', '位置情報'),
                        ])
                      FilterChip(
                        label: Text(tx(entry.$2, entry.$3)),
                        selected: entry.$1 == SearchAttachmentFilter.any
                            ? _filters.withMediaOnly ||
                                  _filters.attachmentFilters.contains(entry.$1)
                            : _filters.attachmentFilters.contains(entry.$1),
                        onSelected: (selected) {
                          final next = _filters.attachmentFilters
                              .where((e) => e != SearchAttachmentFilter.any)
                              .toList();
                          if (entry.$1 == SearchAttachmentFilter.any) {
                            _update(
                              _filters.copyWith(
                                withMediaOnly: false,
                                attachmentFilters: selected
                                    ? [entry.$1]
                                    : const [],
                              ),
                            );
                          } else {
                            if (selected) {
                              next.add(entry.$1);
                            } else {
                              next.remove(entry.$1);
                            }
                            _update(
                              _filters.copyWith(
                                withMediaOnly: false,
                                attachmentFilters: next.isEmpty
                                    ? const []
                                    : next,
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(tx('Tags', 'タグ'), style: theme.textTheme.titleSmall),
                if (tags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      tx('No tags available', '利用できるタグがありません'),
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    children: [
                      for (final tag in tags)
                        FilterChip(
                          label: Text(tag.startsWith('#') ? tag : '#$tag'),
                          selected: _filters.tags.contains(tag),
                          onSelected: (selected) {
                            final next = [..._filters.tags];
                            if (selected) {
                              next.add(tag);
                            } else {
                              next.remove(tag);
                            }
                            _update(
                              _filters.copyWith(
                                tags: next,
                                requireAllTags: next.length > 1
                                    ? _filters.requireAllTags
                                    : false,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                if (_filters.tags.length > 1)
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(tx('Any tag', 'いずれか')),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(tx('All tags', 'すべて')),
                      ),
                    ],
                    selected: {_filters.requireAllTags},
                    onSelectionChanged: (v) =>
                        _update(_filters.copyWith(requireAllTags: v.single)),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SearchDateRange>(
                  key: ValueKey(('range', _filters.dateRange)),
                  initialValue: _filters.dateRange,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tx('Period', '期間'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final value in SearchDateRange.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(switch (value) {
                          SearchDateRange.all => tx('All dates', 'すべて'),
                          SearchDateRange.last7Days => tx(
                            'Last 7 days',
                            '直近7日',
                          ),
                          SearchDateRange.last30Days => tx(
                            'Last 30 days',
                            '直近30日',
                          ),
                          SearchDateRange.thisMonth => tx('This month', '今月'),
                        }),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _update(
                        _filters.copyWith(
                          dateRange: v,
                          dateField: v == SearchDateRange.all
                              ? SearchDateField.createdAt
                              : _filters.dateField,
                        ),
                      );
                    }
                  },
                ),
                if (_filters.dateRange != SearchDateRange.all) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<SearchDateField>(
                    key: ValueKey(('dateField', _filters.dateField)),
                    initialValue: _filters.dateField,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tx('Date target', '日付対象'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: SearchDateField.createdAt,
                        child: Text(tx('Created date', '作成日')),
                      ),
                      DropdownMenuItem(
                        value: SearchDateField.updatedAt,
                        child: Text(tx('Updated date', '更新日')),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) _update(_filters.copyWith(dateField: v));
                    },
                  ),
                ],
                if (years.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    key: ValueKey(('year', _filters.year)),
                    initialValue:
                        _filters.year != null && years.contains(_filters.year)
                        ? _filters.year
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tx('Year', '年'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<int>(
                        value: null,
                        child: Text(tx('Any year', 'すべての年')),
                      ),
                      for (final year in years)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (v) => _update(
                      v == null
                          ? _filters.copyWith(clearYear: true)
                          : _filters.copyWith(year: v),
                    ),
                  ),
                ],
                if (widget.hasArchivedNotes ||
                    _filters.archivedOnly ||
                    _filters.includeArchived) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    key: ValueKey((
                      'archive',
                      _filters.archivedOnly,
                      _filters.includeArchived,
                    )),
                    initialValue: _filters.archivedOnly
                        ? 1
                        : (_filters.includeArchived ? 2 : 0),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tx('Target', '対象'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(tx('Active only', '通常のみ')),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text(tx('Archive only', 'アーカイブのみ')),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text(tx('Active + archive', '通常 + アーカイブ')),
                      ),
                    ],
                    onChanged: (v) => _update(
                      _filters.copyWith(
                        archivedOnly: v == 1,
                        includeArchived: v == 2,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tx('Cancel', 'キャンセル')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_filters),
          child: Text(tx('Apply', '適用')),
        ),
      ],
    );
  }
}
