import 'package:flutter/material.dart';

import 'home_providers.dart';

/// Search, list density, and advanced-filter controls shared by both note UIs.
/// All state and actions are supplied by the caller; this widget has no storage
/// or repository dependencies.
class HomeSearchToolbar extends StatelessWidget {
  const HomeSearchToolbar({
    super.key,
    required this.controller,
    required this.density,
    required this.searchLabel,
    required this.searchHint,
    required this.clearLabel,
    required this.layoutLabel,
    required this.standardLabel,
    required this.compactLabel,
    required this.detailsLabel,
    required this.filterCount,
    required this.onQueryChanged,
    required this.onClear,
    required this.onDensityChanged,
    required this.onDetailsPressed,
    this.searchKey,
    this.searchBoundaryKey,
    this.densityKey,
    this.detailsKey,
    this.clearKey,
    this.filterCountKey,
    this.compactButtons,
    this.activeDetailsMinWidth = 84,
    this.detailsTextStyle,
    this.showDensityControl = true,
    this.alignSearchHeight = false,
  });

  final TextEditingController controller;
  final NotesListDensity density;
  final String searchLabel;
  final String searchHint;
  final String clearLabel;
  final String layoutLabel;
  final String standardLabel;
  final String compactLabel;
  final String detailsLabel;
  final int filterCount;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final ValueChanged<NotesListDensity> onDensityChanged;
  final VoidCallback onDetailsPressed;
  final Key? searchKey;
  final Key? searchBoundaryKey;
  final Key? densityKey;
  final Key? detailsKey;
  final Key? clearKey;
  final Key? filterCountKey;
  final bool? compactButtons;
  final double activeDetailsMinWidth;
  final TextStyle? detailsTextStyle;
  final bool showDensityControl;
  final bool alignSearchHeight;

  @override
  Widget build(BuildContext context) {
    final compact = density == NotesListDensity.compact;
    final narrow = compactButtons ?? MediaQuery.sizeOf(context).width < 560;
    final border = Border.all(color: Theme.of(context).dividerColor);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: KeyedSubtree(
            key: searchBoundaryKey,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextFormField(
                key: searchKey,
                controller: controller,
                decoration: InputDecoration(
                  labelText: searchLabel,
                  hintText: searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  prefixIconConstraints: alignSearchHeight
                      ? const BoxConstraints(minWidth: 48, minHeight: 48)
                      : null,
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          key: clearKey,
                          tooltip: clearLabel,
                          onPressed: onClear,
                          icon: const Icon(Icons.clear_rounded),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  constraints: alignSearchHeight
                      ? const BoxConstraints(minHeight: 48)
                      : null,
                ),
                onChanged: onQueryChanged,
              ),
            ),
          ),
        ),
        if (showDensityControl) ...[
          const SizedBox(width: 8),
          PopupMenuButton<NotesListDensity>(
            key: densityKey ?? const ValueKey('shared-notes-density'),
            tooltip: layoutLabel,
            onSelected: onDensityChanged,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: NotesListDensity.standard,
                checked: !compact,
                child: Text(standardLabel),
              ),
              CheckedPopupMenuItem(
                value: NotesListDensity.compact,
                checked: compact,
                child: Text(compactLabel),
              ),
            ],
            child: Semantics(
              button: true,
              label: layoutLabel,
              child: Tooltip(
                message: layoutLabel,
                child: Container(
                  height: 48,
                  width: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: border,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.view_agenda_outlined, size: 20),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Semantics(
          key: detailsKey,
          button: true,
          label: detailsLabel,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onDetailsPressed,
            child: Container(
              height: 48,
              constraints: BoxConstraints(
                minWidth: narrow
                    ? 48
                    : filterCount > 0
                    ? activeDetailsMinWidth
                    : 84,
              ),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: narrow ? 0 : 12),
              decoration: BoxDecoration(
                color: filterCount > 0
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                border: border,
                borderRadius: BorderRadius.circular(12),
              ),
              child: narrow
                  ? Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.tune_rounded, size: 20),
                        if (filterCount > 0)
                          Positioned(
                            top: -5,
                            right: -5,
                            child: _FilterCountBadge(
                              count: filterCount,
                              key: filterCountKey,
                            ),
                          ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tune_rounded, size: 20),
                        const SizedBox(width: 6),
                        Text(detailsLabel, style: detailsTextStyle),
                        if (filterCount > 0) ...[
                          const SizedBox(width: 8),
                          _FilterCountBadge(
                            count: filterCount,
                            key: filterCountKey,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterCountBadge extends StatelessWidget {
  const _FilterCountBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    height: 20,
    constraints: const BoxConstraints(minWidth: 20),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: Theme.of(context).colorScheme.surface,
        width: 1.5,
      ),
    ),
    child: Text(
      '$count',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.0,
      ),
    ),
  );
}
