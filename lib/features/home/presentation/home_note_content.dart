part of 'home_page.dart';

Future<void> showNoteEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  NoteEntry? note,
  DateTime? initialCreatedAt,
}) async {
  _pushNoteOverlaySheet();
  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  final initialTags = note == null
      ? ref.read(searchFiltersControllerProvider).tags
      : const <String>[];
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final bottomInset = mediaQuery.viewInsets.bottom;
        return SizedBox(
          height: mediaQuery.size.height - mediaQuery.padding.top,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: _NoteEditorSheet(
              note: note,
              initialCreatedAt: initialCreatedAt,
              initialTags: initialTags,
            ),
          ),
        );
      },
    );
  } finally {
    scaffoldMessenger?.hideCurrentSnackBar();
    _popNoteOverlaySheet();
  }
}

class _NotesToolbar extends ConsumerStatefulWidget {
  const _NotesToolbar({this.compact = false});

  final bool compact;

  @override
  ConsumerState<_NotesToolbar> createState() => _NotesToolbarState();
}

class _NotesToolbarState extends ConsumerState<_NotesToolbar> {
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  late String _lastAppliedSearchQuery;

  @override
  void initState() {
    super.initState();
    _lastAppliedSearchQuery = ref.read(searchQueryProvider);
    _searchController = TextEditingController(text: _lastAppliedSearchQuery);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final query = ref.watch(searchQueryProvider);
    _syncExternalSearchQuery(query);
    final filters = ref.watch(searchFiltersControllerProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final tagSummaries = ref.watch(visibleTagSummariesProvider);
    final visibleVaultIds = {for (final vault in visibleVaults) vault.id};
    final hasArchivedNotes = ref
        .watch(notesControllerProvider)
        .any(
          (note) =>
              note.deletedAt == null &&
              note.archivedAt != null &&
              visibleVaultIds.contains(note.vaultId),
        );
    final hasAdvancedFilters = !filters.isDefault;
    final listDensity = ref.watch(notesListDensityControllerProvider);
    final privateModeActive = ref.watch(privacyScreenActiveProvider);
    final availableWidth = MediaQuery.sizeOf(context).width;
    final compactToolbarButtons = widget.compact || availableWidth < 560;
    final activeFilterCount =
        (filters.pinnedOnly ? 1 : 0) +
        (filters.attachmentFilters.isNotEmpty ? 1 : 0) +
        (filters.archivedOnly || filters.includeArchived ? 1 : 0) +
        (filters.requireAllTags && filters.tags.length > 1 ? 1 : 0) +
        (filters.dateRange != SearchDateRange.all ? 1 : 0) +
        (filters.vaultId != null ? 1 : 0) +
        (filters.year != null ? 1 : 0) +
        filters.tags.length;

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, searchValue, _) {
                    final hasSearchText = searchValue.text.isNotEmpty;
                    return TextFormField(
                      key: const Key('notes-search-input'),
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: strings.search,
                        hintText: strings.text(
                          'home.search.notes.diary.entries.and.attachment.labels',
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: hasSearchText
                            ? IconButton(
                                key: const Key('notes-search-clear-button'),
                                tooltip: strings.localized(
                                  en: 'Clear search',
                                  ja: '検索をクリア',
                                ),
                                onPressed: _clearSearchQuery,
                                icon: const Icon(Icons.clear_rounded),
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _scheduleSearchQuery,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<NotesListDensity>(
                tooltip: strings.text('home.list.layout'),
                onSelected: ref
                    .read(notesListDensityControllerProvider.notifier)
                    .setDensity,
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: NotesListDensity.standard,
                    checked: listDensity == NotesListDensity.standard,
                    child: Text(strings.text('home.standard.list')),
                  ),
                  CheckedPopupMenuItem(
                    value: NotesListDensity.compact,
                    checked: listDensity == NotesListDensity.compact,
                    child: Text(strings.text('home.compact.list')),
                  ),
                ],
                child: Semantics(
                  button: true,
                  label: strings.text('home.list.layout'),
                  child: Tooltip(
                    message: strings.text('home.list.layout'),
                    child: Container(
                      height: 48,
                      width: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.view_agenda_outlined, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: strings.text('home.filters'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openAdvancedFiltersSheet(
                    context,
                    hasArchivedNotes: hasArchivedNotes,
                  ),
                  child: Container(
                    height: 48,
                    width: compactToolbarButtons ? 48 : null,
                    constraints: BoxConstraints(
                      minWidth: compactToolbarButtons
                          ? 48
                          : activeFilterCount > 0
                          ? 110
                          : 84,
                    ),
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(
                      horizontal: compactToolbarButtons ? 0 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: hasAdvancedFilters
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: compactToolbarButtons
                        ? Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.tune_rounded, size: 20),
                              if (activeFilterCount > 0)
                                Positioned(
                                  top: -5,
                                  right: -5,
                                  child: _FilterCountBadge(
                                    count: activeFilterCount,
                                  ),
                                ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tune_rounded, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                strings.text('home.filters'),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              if (activeFilterCount > 0) ...[
                                const SizedBox(width: 8),
                                _FilterCountBadge(count: activeFilterCount),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (privateModeActive) ...[
            const SizedBox(height: 8),
            Text(
              strings.text(
                'home.search.terms.are.cleared.when.private.mode.closes',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
          ],
          if (tagSummaries.isNotEmpty) ...[
            const SizedBox(height: 10),
            _QuickTagStrip(
              summaries: tagSummaries,
              activeTags: filters.tags,
              onTagSelected: (tag) {
                final notifier = ref.read(
                  searchFiltersControllerProvider.notifier,
                );
                final selected = filters.tags
                    .map(canonicalizeNoteTag)
                    .contains(canonicalizeNoteTag(tag));
                if (selected) {
                  notifier.removeTag(tag);
                } else {
                  notifier.addTag(tag);
                }
                ref.read(searchQueryProvider.notifier).setQuery('');
                ref.read(selectedNoteIdProvider.notifier).select(null);
              },
            ),
          ],
          if (filters.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (filters.requireAllTags && filters.tags.length > 1)
                  InputChip(
                    label: Text(
                      strings.localized(
                        en: 'All tags',
                        ja: 'タグ: すべて',
                        zh: '所有标签',
                        ko: '모든 태그',
                        es: 'Todas las etiquetas',
                        de: 'Alle Tags',
                      ),
                    ),
                    onDeleted: () => ref
                        .read(searchFiltersControllerProvider.notifier)
                        .setRequireAllTags(false),
                  ),
              ],
            ),
          ],
          ..._buildDetailedFilterRows(context, strings, filters, visibleVaults),
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

  void _syncExternalSearchQuery(String query) {
    if (query == _lastAppliedSearchQuery || query == _searchController.text) {
      return;
    }
    _searchDebounce?.cancel();
    _lastAppliedSearchQuery = query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchController.text == query) {
        return;
      }
      _searchController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    });
  }

  void _scheduleSearchQuery(String value) {
    _searchDebounce?.cancel();
    if (value.isEmpty) {
      _applySearchQuery(value);
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 260),
      () => _applySearchQuery(_searchController.text),
    );
  }

  void _applySearchQuery(String value) {
    if (!mounted || value == _lastAppliedSearchQuery) {
      return;
    }
    _lastAppliedSearchQuery = value;
    ref.read(searchQueryProvider.notifier).setQuery(value);
  }

  void _clearSearchQuery() {
    _searchDebounce?.cancel();
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    _applySearchQuery('');
  }

  List<Widget> _buildDetailedFilterRows(
    BuildContext context,
    AppStrings strings,
    SearchFilters filters,
    List<VaultBucket> visibleVaults,
  ) {
    final notifier = ref.read(searchFiltersControllerProvider.notifier);
    final chips = <Widget>[];

    if (filters.pinnedOnly) {
      chips.add(
        _filterSummaryChip(
          context,
          label: strings.text('home.pinned.only'),
          onDeleted: () => notifier.setPinnedOnly(false),
        ),
      );
    }
    if (filters.attachmentFilters.isNotEmpty) {
      chips.add(
        _filterSummaryChip(
          context,
          label: _attachmentFilterSummaryLabel(
            strings,
            filters.attachmentFilters,
          ),
          onDeleted: () =>
              notifier.setAttachmentFilter(SearchAttachmentFilter.all),
        ),
      );
    }
    if (filters.archivedOnly) {
      chips.add(
        _filterSummaryChip(
          context,
          label: strings.localized(
            en: 'Archive',
            ja: 'アーカイブ',
            zh: '归档',
            ko: '아카이브',
            es: 'Archivo',
            de: 'Archiv',
          ),
          onDeleted: () => notifier.setArchivedOnly(false),
        ),
      );
    }
    if (filters.includeArchived) {
      chips.add(
        _filterSummaryChip(
          context,
          label: strings.localized(
            en: 'Normal + archive',
            ja: '通常 + アーカイブ',
            zh: '普通 + 归档',
            ko: '일반 + 아카이브',
            es: 'Normal + archivo',
            de: 'Normal + Archiv',
          ),
          onDeleted: () => notifier.setIncludeArchived(false),
        ),
      );
    }
    if (filters.dateRange != SearchDateRange.all) {
      chips.add(
        _filterSummaryChip(
          context,
          label:
              '${_dateRangeLabel(strings, filters.dateRange)} / ${_dateFieldLabel(strings, filters.dateField)}',
          onDeleted: () => notifier.setDateRange(SearchDateRange.all),
        ),
      );
    }
    if (filters.vaultId != null) {
      chips.add(
        _filterSummaryChip(
          context,
          label: _selectedVaultLabel(context, visibleVaults, filters.vaultId!),
          onDeleted: () => notifier.setVault(null),
        ),
      );
    }
    if (filters.year != null) {
      chips.add(
        _filterSummaryChip(
          context,
          label: '${filters.year}',
          onDeleted: () => notifier.setYear(null),
        ),
      );
    }

    if (chips.isEmpty) {
      return const [];
    }
    return [
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: chips),
    ];
  }

  Widget _filterSummaryChip(
    BuildContext context, {
    required String label,
    required VoidCallback onDeleted,
  }) {
    return InputChip(
      label: Text(label),
      avatar: const Icon(Icons.filter_alt_outlined, size: 16),
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
  }

  String _selectedVaultLabel(
    BuildContext context,
    List<VaultBucket> visibleVaults,
    String vaultId,
  ) {
    for (final vault in visibleVaults) {
      if (vault.id == vaultId) {
        return _vaultDisplayName(context, vault);
      }
    }
    return vaultId;
  }

  String _dateRangeLabel(AppStrings strings, SearchDateRange range) {
    return switch (range) {
      SearchDateRange.all => strings.localized(
        en: 'All dates',
        ja: '\u3059\u3079\u3066\u306e\u671f\u9593',
        zh: '\u6240\u6709\u65e5\u671f',
        ko: '\ubaa8\ub4e0 \uae30\uac04',
        es: 'Todas las fechas',
        de: 'Alle Daten',
      ),
      SearchDateRange.last7Days => strings.localized(
        en: 'Last 7 days',
        ja: '\u76f4\u8fd17\u65e5',
        zh: '\u6700\u8fd1 7 \u5929',
        ko: '\ucd5c\uadfc 7\uc77c',
        es: 'Ultimos 7 dias',
        de: 'Letzte 7 Tage',
      ),
      SearchDateRange.last30Days => strings.localized(
        en: 'Last 30 days',
        ja: '\u76f4\u8fd130\u65e5',
        zh: '\u6700\u8fd1 30 \u5929',
        ko: '\ucd5c\uadfc 30\uc77c',
        es: 'Ultimos 30 dias',
        de: 'Letzte 30 Tage',
      ),
      SearchDateRange.thisMonth => strings.localized(
        en: 'This month',
        ja: '\u4eca\u6708',
        zh: '\u672c\u6708',
        ko: '\uc774\ubc88 \ub2ec',
        es: 'Este mes',
        de: 'Dieser Monat',
      ),
    };
  }

  String _dateFieldLabel(AppStrings strings, SearchDateField field) {
    return switch (field) {
      SearchDateField.createdAt => strings.localized(
        en: 'Created date',
        ja: '\u4f5c\u6210\u65e5',
        zh: '\u521b\u5efa\u65e5\u671f',
        ko: '\uc791\uc131\uc77c',
        es: 'Fecha de creacion',
        de: 'Erstellt am',
      ),
      SearchDateField.updatedAt => strings.localized(
        en: 'Updated date',
        ja: '\u66f4\u65b0\u65e5',
        zh: '\u66f4\u65b0\u65e5\u671f',
        ko: '\uc218\uc815\uc77c',
        es: 'Fecha de actualizacion',
        de: 'Geandert am',
      ),
    };
  }

  String _attachmentFilterLabel(
    AppStrings strings,
    SearchAttachmentFilter filter,
  ) {
    return switch (filter) {
      SearchAttachmentFilter.all => strings.localized(
        en: 'All attachments',
        ja: '\u3059\u3079\u3066',
        zh: '\u5168\u90e8',
        ko: '\ubaa8\ub450',
        es: 'Todos',
        de: 'Alle',
      ),
      SearchAttachmentFilter.any => strings.text('home.with.media'),
      SearchAttachmentFilter.photo => strings.localized(
        en: 'Images',
        ja: '\u753b\u50cf',
        zh: '\u56fe\u50cf',
        ko: '\uc774\ubbf8\uc9c0',
        es: 'Imagenes',
        de: 'Bilder',
      ),
      SearchAttachmentFilter.video => strings.localized(
        en: 'Videos',
        ja: '\u52d5\u753b',
        zh: '\u89c6\u9891',
        ko: '\ub3d9\uc601\uc0c1',
        es: 'Videos',
        de: 'Videos',
      ),
      SearchAttachmentFilter.audio => strings.localized(
        en: 'Audio',
        ja: '\u97f3\u58f0',
        zh: '\u97f3\u9891',
        ko: '\uc624\ub514\uc624',
        es: 'Audio',
        de: 'Audio',
      ),
      SearchAttachmentFilter.location => strings.localized(
        en: 'Location',
        ja: '\u4f4d\u7f6e\u60c5\u5831',
        zh: '\u4f4d\u7f6e\u4fe1\u606f',
        ko: '\uc704\uce58 \uc815\ubcf4',
        es: 'Ubicacion',
        de: 'Standort',
      ),
    };
  }

  String _attachmentFilterSummaryLabel(
    AppStrings strings,
    List<SearchAttachmentFilter> filters,
  ) {
    if (filters.isEmpty) {
      return _attachmentFilterLabel(strings, SearchAttachmentFilter.all);
    }
    if (filters.contains(SearchAttachmentFilter.any)) {
      return _attachmentFilterLabel(strings, SearchAttachmentFilter.any);
    }
    return filters
        .map((filter) => _attachmentFilterLabel(strings, filter))
        .join(' / ');
  }

  void _openAdvancedFiltersSheet(
    BuildContext context, {
    required bool hasArchivedNotes,
  }) {
    _pushNoteOverlaySheet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final strings = sheetContext.strings;
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.92;
        return Consumer(
          builder: (context, ref, _) {
            final filters = ref.watch(searchFiltersControllerProvider);
            final notifier = ref.read(searchFiltersControllerProvider.notifier);
            final visibleVaults = ref.watch(visibleVaultsProvider);
            final canFilterVaults = visibleVaults.length > 1;
            if (!canFilterVaults && filters.vaultId != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  notifier.setVault(null);
                }
              });
            }
            final years = ref.watch(visibleNoteYearsProvider);
            final suggestions = ref.watch(visibleTagSuggestionsProvider);
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.text('home.filters'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          if (!filters.isDefault)
                            TextButton(
                              onPressed: notifier.reset,
                              child: Text(strings.text('home.reset.filters')),
                            ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: strings.close,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: filters.pinnedOnly,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: Text(strings.text('home.pinned.only')),
                        onChanged: (value) =>
                            notifier.setPinnedOnly(value ?? false),
                      ),
                      _AttachmentSearchFilterControls(
                        filters: filters.attachmentFilters,
                        onHasAttachmentsChanged: (enabled) =>
                            notifier.setAttachmentFilter(
                              enabled
                                  ? SearchAttachmentFilter.any
                                  : SearchAttachmentFilter.all,
                            ),
                        onFilterToggled: notifier.toggleAttachmentFilter,
                      ),
                      const SizedBox(height: 12),
                      _TagAutocompleteField(
                        key: const Key('search-tag-input-sheet'),
                        suggestions: suggestions,
                        label: strings.text('home.filter.by.tag'),
                        hintText: strings.text(
                          'home.add.tags.to.narrow.the.list',
                        ),
                        existingTags: filters.tags,
                        onTagSelected: notifier.addTag,
                        showSubmitAction: true,
                      ),
                      if (filters.tags.length > 1) ...[
                        const SizedBox(height: 10),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text(
                                strings.localized(
                                  en: 'Any tag',
                                  ja: 'いずれかのタグ',
                                  zh: '任一标签',
                                  ko: '태그 중 하나',
                                  es: 'Cualquier etiqueta',
                                  de: 'Ein beliebiger Tag',
                                ),
                              ),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text(
                                strings.localized(
                                  en: 'All tags',
                                  ja: 'すべてのタグ',
                                  zh: '所有标签',
                                  ko: '모든 태그',
                                  es: 'Todas las etiquetas',
                                  de: 'Alle Tags',
                                ),
                              ),
                            ),
                          ],
                          selected: {filters.requireAllTags},
                          onSelectionChanged: (selection) =>
                              notifier.setRequireAllTags(selection.single),
                        ),
                      ],
                      if (filters.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in filters.tags)
                              InputChip(
                                label: Text('#$tag'),
                                onDeleted: () => notifier.removeTag(tag),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<SearchDateRange>(
                        initialValue: filters.dateRange,
                        decoration: InputDecoration(
                          labelText: strings.localized(
                            en: 'Period',
                            ja: '\u671f\u9593',
                            zh: '\u671f\u95f4',
                            ko: '\uae30\uac04',
                            es: 'Periodo',
                            de: 'Zeitraum',
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final range in SearchDateRange.values)
                            DropdownMenuItem(
                              value: range,
                              child: Text(_dateRangeLabel(strings, range)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            notifier.setDateRange(value);
                          }
                        },
                      ),
                      if (filters.dateRange != SearchDateRange.all) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<SearchDateField>(
                          initialValue: filters.dateField,
                          decoration: InputDecoration(
                            labelText: strings.localized(
                              en: 'Date target',
                              ja: '\u65e5\u4ed8\u5bfe\u8c61',
                              zh: '\u65e5\u671f\u5bf9\u8c61',
                              ko: '\ub0a0\uc9dc \uae30\uc900',
                              es: 'Fecha objetivo',
                              de: 'Datumsfeld',
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final field in SearchDateField.values)
                              DropdownMenuItem(
                                value: field,
                                child: Text(_dateFieldLabel(strings, field)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              notifier.setDateField(value);
                            }
                          },
                        ),
                      ],
                      if (hasArchivedNotes ||
                          filters.archivedOnly ||
                          filters.includeArchived) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: filters.archivedOnly
                              ? 1
                              : (filters.includeArchived ? 2 : 0),
                          decoration: InputDecoration(
                            labelText: strings.localized(
                              en: 'Target',
                              ja: '\u5bfe\u8c61',
                              zh: '\u5bf9\u8c61',
                              ko: '\ub300\uc0c1',
                              es: 'Objetivo',
                              de: 'Ziel',
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 0,
                              child: Text(
                                strings.localized(
                                  en: 'Normal notes',
                                  ja: '\u901a\u5e38\u30ce\u30fc\u30c8',
                                  zh: '\u666e\u901a\u7b14\u8bb0',
                                  ko: '\uc77c\ubc18 \uba54\ubaa8',
                                  es: 'Notas normales',
                                  de: 'Normale Notizen',
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text(
                                strings.localized(
                                  en: 'Archive only',
                                  ja: '\u30a2\u30fc\u30ab\u30a4\u30d6\u306e\u307f',
                                  zh: '\u4ec5\u5f52\u6863',
                                  ko: '\uc544\uce74\uc774\ube0c\ub9cc',
                                  es: 'Solo archivo',
                                  de: 'Nur Archiv',
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text(
                                strings.localized(
                                  en: 'Normal + archive',
                                  ja: '\u901a\u5e38 + \u30a2\u30fc\u30ab\u30a4\u30d6',
                                  zh: '\u666e\u901a + \u5f52\u6863',
                                  ko: '\uc77c\ubc18 + \uc544\uce74\uc774\ube0c',
                                  es: 'Normal + archivo',
                                  de: 'Normal + Archiv',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == 1) {
                              notifier.setArchivedOnly(true);
                            } else if (value == 2) {
                              notifier.setIncludeArchived(true);
                            } else {
                              notifier
                                ..setArchivedOnly(false)
                                ..setIncludeArchived(false);
                            }
                          },
                        ),
                      ],
                      if (canFilterVaults) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          key: ValueKey(filters.vaultId ?? 'all-vaults-sheet'),
                          initialValue: filters.vaultId,
                          decoration: InputDecoration(
                            labelText: strings.text('home.vault'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                strings.text('home.all.visible.vaults'),
                              ),
                            ),
                            for (final vault in visibleVaults)
                              DropdownMenuItem<String?>(
                                value: vault.id,
                                child: Text(_vaultDisplayName(context, vault)),
                              ),
                          ],
                          onChanged: notifier.setVault,
                        ),
                      ],
                      if (years.length > 1) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          key: ValueKey(filters.year ?? 'all-years-sheet'),
                          initialValue: filters.year,
                          decoration: InputDecoration(
                            labelText: strings.text('home.year.partition'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem<int?>(
                              value: null,
                              child: Text(strings.text('home.all.years')),
                            ),
                            for (final year in years)
                              DropdownMenuItem<int?>(
                                value: year,
                                child: Text('$year'),
                              ),
                          ],
                          onChanged: notifier.setYear,
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_popNoteOverlaySheet);
  }
}

class _QuickTagStrip extends StatelessWidget {
  const _QuickTagStrip({
    required this.summaries,
    required this.activeTags,
    required this.onTagSelected,
  });

  final List<VisibleTagSummary> summaries;
  final List<String> activeTags;
  final ValueChanged<String> onTagSelected;

  @override
  Widget build(BuildContext context) {
    final activeKeys = activeTags.map(canonicalizeNoteTag).toSet();
    final visibleSummaries = summaries.take(10).toList(growable: false);
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: ScrollConfiguration(
        behavior: const _HorizontalMouseDragScrollBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          itemCount: visibleSummaries.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final summary = visibleSummaries[index];
            return Center(
              child: _QuickTagChip(
                summary: summary,
                selected: activeKeys.contains(
                  canonicalizeNoteTag(summary.name),
                ),
                onTap: () => onTagSelected(summary.name),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HorizontalMouseDragScrollBehavior extends MaterialScrollBehavior {
  const _HorizontalMouseDragScrollBehavior();

  @override
  Set<ui.PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    ui.PointerDeviceKind.mouse,
  };
}

class _QuickTagChip extends StatelessWidget {
  const _QuickTagChip({
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
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: selected ? colorScheme.onPrimaryContainer : null,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return Tooltip(
      message: '#${summary.name}',
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? colorScheme.primary : theme.dividerColor,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tag_rounded,
                  size: 15,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${summary.name} (${summary.count})',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: labelStyle,
                  strutStyle: labelStyle == null
                      ? null
                      : StrutStyle.fromTextStyle(
                          labelStyle,
                          forceStrutHeight: true,
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

class _AttachmentSearchFilterControls extends StatelessWidget {
  const _AttachmentSearchFilterControls({
    required this.filters,
    required this.onHasAttachmentsChanged,
    required this.onFilterToggled,
  });

  final List<SearchAttachmentFilter> filters;
  final ValueChanged<bool> onHasAttachmentsChanged;
  final ValueChanged<SearchAttachmentFilter> onFilterToggled;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final hasAttachmentFilter = filters.isNotEmpty;
    final selectedFilters = filters.isEmpty
        ? const <SearchAttachmentFilter>[SearchAttachmentFilter.any]
        : filters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: hasAttachmentFilter,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(
            strings.localized(
              en: 'Has attachments',
              ja: '\u6dfb\u4ed8\u3042\u308a',
              zh: '\u6709\u9644\u4ef6',
              ko: '\ucca8\ubd80 \uc788\uc74c',
              es: 'Con adjuntos',
              de: 'Mit Anhangen',
            ),
          ),
          onChanged: (value) => onHasAttachmentsChanged(value == true),
        ),
        if (hasAttachmentFilter) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const [
                SearchAttachmentFilter.any,
                SearchAttachmentFilter.photo,
                SearchAttachmentFilter.video,
                SearchAttachmentFilter.audio,
                SearchAttachmentFilter.location,
              ])
                ChoiceChip(
                  avatar: Icon(_attachmentSearchFilterIcon(option), size: 18),
                  label: Text(_attachmentSearchFilterLabel(strings, option)),
                  selected: selectedFilters.contains(option),
                  onSelected: (_) => onFilterToggled(option),
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _attachmentSearchFilterLabel(
  AppStrings strings,
  SearchAttachmentFilter filter,
) {
  return switch (filter) {
    SearchAttachmentFilter.all => strings.localized(
      en: 'All attachments',
      ja: '\u3059\u3079\u3066',
      zh: '\u5168\u90e8',
      ko: '\ubaa8\ub450',
      es: 'Todos',
      de: 'Alle',
    ),
    SearchAttachmentFilter.any => strings.localized(
      en: 'Any',
      ja: '\u3059\u3079\u3066',
      zh: '\u5168\u90e8',
      ko: '\ubaa8\ub450',
      es: 'Cualquiera',
      de: 'Alle',
    ),
    SearchAttachmentFilter.photo => strings.localized(
      en: 'Images',
      ja: '\u753b\u50cf',
      zh: '\u56fe\u50cf',
      ko: '\uc774\ubbf8\uc9c0',
      es: 'Imagenes',
      de: 'Bilder',
    ),
    SearchAttachmentFilter.video => strings.localized(
      en: 'Videos',
      ja: '\u52d5\u753b',
      zh: '\u89c6\u9891',
      ko: '\ub3d9\uc601\uc0c1',
      es: 'Videos',
      de: 'Videos',
    ),
    SearchAttachmentFilter.audio => strings.localized(
      en: 'Audio',
      ja: '\u97f3\u58f0',
      zh: '\u97f3\u9891',
      ko: '\uc624\ub514\uc624',
      es: 'Audio',
      de: 'Audio',
    ),
    SearchAttachmentFilter.location => strings.localized(
      en: 'Location',
      ja: '\u4f4d\u7f6e\u60c5\u5831',
      zh: '\u4f4d\u7f6e\u4fe1\u606f',
      ko: '\uc704\uce58 \uc815\ubcf4',
      es: 'Ubicacion',
      de: 'Standort',
    ),
  };
}

IconData _attachmentSearchFilterIcon(SearchAttachmentFilter filter) {
  return switch (filter) {
    SearchAttachmentFilter.all => Icons.attach_file_rounded,
    SearchAttachmentFilter.any => Icons.attach_file_rounded,
    SearchAttachmentFilter.photo => Icons.image_outlined,
    SearchAttachmentFilter.video => Icons.movie_outlined,
    SearchAttachmentFilter.audio => Icons.mic_none_rounded,
    SearchAttachmentFilter.location => Icons.location_on_outlined,
  };
}

class _FilterCountBadge extends StatelessWidget {
  const _FilterCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 20,
      constraints: const BoxConstraints(minWidth: 20),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.surface, width: 1.5),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
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

class _NoteTagChip extends StatelessWidget {
  const _NoteTagChip({required this.tag, this.onTap, this.compact = false});

  final String tag;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = '#$tag';
    final chipLabel = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall,
    );
    if (onTap == null) {
      return Chip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        side: BorderSide(color: Theme.of(context).dividerColor),
        label: chipLabel,
      );
    }
    return ActionChip(
      label: chipLabel,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
  }
}

class _TagAutocompleteField extends StatefulWidget {
  const _TagAutocompleteField({
    super.key,
    this.inputKey,
    required this.suggestions,
    required this.label,
    required this.hintText,
    required this.existingTags,
    required this.onTagSelected,
    this.showSubmitAction = false,
  });

  final Key? inputKey;
  final List<String> suggestions;
  final String label;
  final String hintText;
  final List<String> existingTags;
  final ValueChanged<String> onTagSelected;
  final bool showSubmitAction;

  @override
  State<_TagAutocompleteField> createState() => _TagAutocompleteFieldState();
}

class _TagAutocompleteFieldState extends State<_TagAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late Set<String> _existingTagKeys;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
    _existingTagKeys = _currentExistingTagKeys();
  }

  @override
  void didUpdateWidget(covariant _TagAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKeys = _currentExistingTagKeys();
    if (_setEquals(_existingTagKeys, nextKeys)) {
      return;
    }
    _existingTagKeys = nextKeys;
    final currentTag = canonicalizeNoteTag(_controller.text);
    if (currentTag.isNotEmpty && nextKeys.contains(currentTag)) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    setState(() {});
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _submitTag(String raw) {
    final normalized = normalizeNoteTag(raw);
    if (normalized.isEmpty) {
      return;
    }
    final existingKeys = _currentExistingTagKeys();
    if (existingKeys.contains(canonicalizeNoteTag(normalized))) {
      _controller.clear();
      return;
    }
    widget.onTagSelected(normalized);
    _controller.clear();
  }

  String? consumePendingTag() {
    final normalized = normalizeNoteTag(_controller.text);
    if (normalized.isEmpty) {
      return null;
    }
    _controller.clear();
    final existingKeys = _currentExistingTagKeys();
    if (existingKeys.contains(canonicalizeNoteTag(normalized))) {
      return null;
    }
    return normalized;
  }

  bool get _canSubmitCurrentText {
    final normalized = normalizeNoteTag(_controller.text);
    return normalized.isNotEmpty &&
        !_currentExistingTagKeys().contains(canonicalizeNoteTag(normalized));
  }

  Set<String> _currentExistingTagKeys() {
    return widget.existingTags
        .map(canonicalizeNoteTag)
        .where((tag) => tag.isNotEmpty)
        .toSet();
  }

  bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    return left.containsAll(right);
  }

  List<String> _matchingSuggestions() {
    final existingKeys = _currentExistingTagKeys();
    final seenKeys = <String>{};
    final input = canonicalizeNoteTag(_controller.text);
    final matches = <String>[];
    for (final tag in widget.suggestions) {
      final key = canonicalizeNoteTag(tag);
      if (key.isEmpty || existingKeys.contains(key) || !seenKeys.add(key)) {
        continue;
      }
      if (input.isNotEmpty && !key.contains(input)) {
        continue;
      }
      matches.add(tag);
      if (matches.length == 8) {
        break;
      }
    }
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final matches = _focusNode.hasFocus
        ? _matchingSuggestions()
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: widget.inputKey,
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            isDense: true,
            prefixIcon: const Icon(Icons.sell_outlined),
            suffixIcon: widget.showSubmitAction && _canSubmitCurrentText
                ? IconButton(
                    tooltip: MaterialLocalizations.of(context).okButtonLabel,
                    icon: const Icon(Icons.check_rounded),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _submitTag(_controller.text),
                  )
                : null,
          ),
          onFieldSubmitted: _submitTag,
        ),
        if (matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  children: [
                    for (final option in matches)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.sell_outlined, size: 18),
                        title: Text(option),
                        onTap: () {
                          _submitTag(option);
                          _focusNode.requestFocus();
                        },
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
    final bodyPreview = _normalizePreviewText(note.body, maxChars: 320);
    final hasDistinctBody =
        bodyPreview.isNotEmpty && bodyPreview != note.title.trim();
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
                bodyPreview,
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

class _CalendarDayNotesList extends ConsumerWidget {
  const _CalendarDayNotesList({
    required this.notes,
    required this.itemCount,
    required this.expanded,
    required this.onTap,
  });

  final List<NoteEntry> notes;
  final int itemCount;
  final bool expanded;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dividerColor = Theme.of(context).dividerColor;
    final cappedItemCount = itemCount.clamp(0, notes.length);

    Widget buildRow(int index) {
      final note = notes[index];
      return _CalendarNoteRow(
        note: note,
        vaultName: _vaultDisplayName(
          context,
          ref.watch(vaultByIdProvider(note.vaultId)),
        ),
        onTap: () => onTap(index),
      );
    }

    if (!expanded) {
      return Column(
        children: [
          for (var index = 0; index < cappedItemCount; index++) ...[
            buildRow(index),
            if (index != cappedItemCount - 1)
              Divider(height: 24, color: dividerColor),
          ],
        ],
      );
    }

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final listHeight = math.min(560.0, math.max(280.0, viewportHeight * 0.55));
    return SizedBox(
      height: listHeight,
      child: ListView.separated(
        primary: false,
        itemCount: cappedItemCount,
        separatorBuilder: (context, index) =>
            Divider(height: 24, color: dividerColor),
        itemBuilder: (context, index) => buildRow(index),
      ),
    );
  }
}

class _EmptyNotesState extends StatelessWidget {
  const _EmptyNotesState();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.emptyNotesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.emptyNotesBody,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
          ),
        ],
      ),
    );
  }
}

class _EmptyNoteSelectionState extends StatelessWidget {
  const _EmptyNoteSelectionState();

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('home.select.a.note'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.text('home.pick.a.note.from.the.list.to.preview.it.here'),
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
        AttachmentType.file => NoteBlockType.file,
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
  const _NoteEditorSheet({
    this.note,
    this.initialCreatedAt,
    this.initialTags = const <String>[],
  });

  final NoteEntry? note;
  final DateTime? initialCreatedAt;
  final List<String> initialTags;

  @override
  ConsumerState<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends ConsumerState<_NoteEditorSheet> {
  late final TextEditingController _contentController;
  late final FocusNode _quickContentFocusNode;
  late final NoteEditorDraftStore _draftStore;
  late final EncryptedAttachmentStore _attachmentStore;
  final GlobalKey<_TagAutocompleteFieldState> _tagFieldKey =
      GlobalKey<_TagAutocompleteFieldState>();
  late DateTime _createdAt;
  late bool _isPinned;
  late NoteEditorMode _editorMode;
  late List<NoteAttachment> _attachments;
  late List<String> _tags;
  late List<_RichBlockDraft> _richBlocks;
  late final Set<String> _initialAttachmentPaths;
  late final ValueNotifier<bool> _canSubmitNotifier;
  late final String _newNoteId;
  late bool _captureLocationEnabled;
  final Set<String> _pendingAttachmentDeletes = <String>{};
  int? _activeRichParagraphIndex;
  String? _selectedVaultId;
  NoteLocation? _location;
  bool _locationBusy = false;
  bool _saved = false;
  bool _draftLoaded = false;
  bool _editorDisposed = false;
  bool _attachmentPickerBusy = false;
  bool _attachmentImportBusy = false;
  int _pendingAttachmentPlaceholderCount = 0;
  bool _saveBusy = false;
  bool _tagSuggestionsBusy = false;
  List<String> _tagSuggestions = const [];
  String? _tagSuggestionSource;
  Timer? _draftSaveTimer;
  bool _discardingDraft = false;
  bool _draftRestoreSnackBarActive = false;
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    _draftStore = ref.read(noteEditorDraftStoreProvider);
    _attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    _newNoteId = DateTime.now().microsecondsSinceEpoch.toString();
    final lastSettings = ref.read(lastNoteEditorSettingsControllerProvider);
    _contentController = TextEditingController(text: _composeEditorContent());
    _canSubmitNotifier = ValueNotifier<bool>(false);
    _quickContentFocusNode = FocusNode();
    _contentController.addListener(_handleTextChanged);
    _createdAt =
        (widget.note?.createdAt ?? widget.initialCreatedAt ?? DateTime.now())
            .toLocal();
    _isPinned = widget.note?.isPinned ?? false;
    _editorMode =
        widget.note?.editorMode ??
        ((widget.note?.blocks.isNotEmpty ?? false)
            ? NoteEditorMode.rich
            : lastSettings.mode);
    _captureLocationEnabled =
        widget.note == null && lastSettings.captureLocation;
    _location = widget.note?.location;
    _attachments = [...?widget.note?.attachments];
    _tags = widget.note == null
        ? dedupeNoteTags(widget.initialTags).toList(growable: true)
        : [...?widget.note?.tags];
    _richBlocks = _buildInitialRichBlocks();
    for (final block in _richBlocks) {
      _attachRichBlockListener(block);
    }
    _activeRichParagraphIndex = _richBlocks.indexWhere(
      (block) => block.type == NoteBlockType.paragraph,
    );
    _updateCanSubmit();
    _initialAttachmentPaths = _attachments
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    _selectedVaultId = widget.note?.vaultId ?? _initialNewNoteVaultId();
    _scheduleInitialEditorFocus();
    if (widget.note == null) {
      unawaited(_applyRestoredEditorSettings());
      unawaited(_restoreDraftIfAny());
      if (_captureLocationEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _location == null) {
            unawaited(_captureCurrentLocationForNote(showErrors: false));
          }
        });
      }
    }
  }

  Future<void> _applyRestoredEditorSettings() async {
    final controller = ref.read(
      lastNoteEditorSettingsControllerProvider.notifier,
    );
    await controller.ensureRestored();
    if (!mounted || widget.note != null) {
      return;
    }
    final restored = ref.read(lastNoteEditorSettingsControllerProvider);
    final shouldEnableLocation =
        restored.captureLocation && !_captureLocationEnabled;
    setState(() {
      _captureLocationEnabled = restored.captureLocation;
      if (_selectedVaultId == null || _selectedVaultId == 'everyday') {
        _selectedVaultId = restored.vaultId;
      }
    });
    if (shouldEnableLocation && _location == null) {
      await _captureCurrentLocationForNote(showErrors: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  }

  String _initialNewNoteVaultId() {
    final unlockedVaultId = ref.read(unlockedPrivateProfileVaultIdProvider);
    if (unlockedVaultId != null) {
      return unlockedVaultId;
    }
    return ref.read(lastNoteEditorSettingsControllerProvider).vaultId;
  }

  VaultBucket _privateTargetFor(
    String vaultId,
    List<PrivateMemoProfile> privateProfiles,
  ) {
    if (vaultId == legacyPrivateVaultId) {
      return VaultBucket(
        id: legacyPrivateVaultId,
        name: context.strings.text('home.private.profile'),
        description: context.strings.unlockedPrivateNotes,
      );
    }
    for (final profile in privateProfiles) {
      if (profile.vaultId == vaultId) {
        return VaultBucket(
          id: profile.vaultId,
          name: profile.name,
          description: context.strings.unlockedPrivateNotes,
        );
      }
    }
    return VaultBucket(
      id: vaultId,
      name: context.strings.text('home.private.profile'),
      description: context.strings.unlockedPrivateNotes,
    );
  }

  @override
  void dispose() {
    _editorDisposed = true;
    _draftSaveTimer?.cancel();
    if (_draftRestoreSnackBarActive) {
      _scaffoldMessenger?.hideCurrentSnackBar();
    }
    final shouldKeepDraft = !_saved && widget.note == null && _hasDraftContent;
    if (shouldKeepDraft && _selectedVaultId != null) {
      unawaited(
        _draftStore.save(
          NoteEditorDraftSnapshot(
            createdAt: _createdAt,
            isPinned: _isPinned,
            editorMode: _editorMode,
            vaultId: _selectedVaultId!,
            tags: _tags,
            quickContent: _contentController.text,
            quickAttachments: _attachments,
            richBlocks: _richBlocksToNoteBlocks(),
            location: _location,
          ),
        ),
      );
    } else if (!_saved && widget.note == null) {
      unawaited(_draftStore.clear());
    }
    if (!_saved) {
      for (final filePath in _pendingAttachmentDeletes) {
        unawaited(_attachmentStore.deleteAttachment(filePath));
      }
      if (!shouldKeepDraft) {
        for (final attachment in _allCurrentAttachments) {
          final filePath = attachment.filePath;
          if (filePath == null || _initialAttachmentPaths.contains(filePath)) {
            continue;
          }
          unawaited(_attachmentStore.deleteAttachment(filePath));
        }
      }
    }
    _contentController.removeListener(_handleTextChanged);
    _contentController.dispose();
    _quickContentFocusNode.dispose();
    _canSubmitNotifier.dispose();
    for (final block in _richBlocks) {
      block.dispose();
    }
    super.dispose();
  }

  void _handleTextChanged() {
    _scheduleDraftPersist();
    _updateCanSubmit();
  }

  void _updateCanSubmit() {
    if (_editorDisposed) {
      return;
    }
    final next = _hasSubmitContent && !_attachmentActionBusy;
    if (_canSubmitNotifier.value != next) {
      _canSubmitNotifier.value = next;
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
        case NoteBlockType.file:
          if (block.attachment != null) {
            drafts.add(_RichBlockDraft.attachment(block.attachment!));
          }
      }
    }
    final noteTitle = widget.note?.title.trim() ?? '';
    if (noteTitle.isNotEmpty) {
      final firstParagraphIndex = drafts.indexWhere(
        (block) => block.type == NoteBlockType.paragraph,
      );
      if (firstParagraphIndex == -1) {
        drafts.insert(0, _RichBlockDraft.paragraph(noteTitle));
      } else {
        final paragraph = drafts[firstParagraphIndex];
        final text = paragraph.controller?.text ?? '';
        final firstLine = text.split('\n').first.trim();
        if (text.trim().isEmpty) {
          paragraph.controller?.text = noteTitle;
        } else if (firstLine != noteTitle) {
          paragraph.controller?.text = '$noteTitle\n$text';
        }
      }
    }
    if (drafts.isEmpty) {
      drafts.add(_RichBlockDraft.paragraph());
    }
    _ensureTrailingRichParagraph(drafts);
    return drafts;
  }

  List<_RichBlockDraft> _buildRichBlocksFromQuickMemo() {
    final content = _contentController.text.trim();
    final drafts = <_RichBlockDraft>[];
    if (content.isNotEmpty) {
      drafts.add(_RichBlockDraft.paragraph(content));
    }
    for (final attachment in _attachments) {
      drafts.add(_RichBlockDraft.attachment(attachment));
    }
    if (drafts.isEmpty || drafts.last.type != NoteBlockType.paragraph) {
      drafts.add(_RichBlockDraft.paragraph());
    }
    return drafts;
  }

  void _replaceRichBlocks(List<_RichBlockDraft> nextBlocks) {
    for (final block in _richBlocks) {
      block.dispose();
    }
    _richBlocks = nextBlocks.isEmpty
        ? [_RichBlockDraft.paragraph()]
        : nextBlocks;
    _ensureTrailingRichParagraph(_richBlocks);
    for (final block in _richBlocks) {
      _attachRichBlockListener(block);
    }
    _activeRichParagraphIndex = _richBlocks.indexWhere(
      (block) => block.type == NoteBlockType.paragraph,
    );
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
    if (!_draftHasContent(draft)) {
      await ref.read(noteEditorDraftStoreProvider).clear();
      return;
    }
    setState(() {
      _createdAt = draft.createdAt.toLocal();
      _isPinned = draft.isPinned;
      _editorMode = draft.editorMode;
      _selectedVaultId = draft.vaultId;
      _tags = [...draft.tags];
      _location = draft.location;
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
      _ensureTrailingRichParagraph(_richBlocks);
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
    _scheduleInitialEditorFocus();
    _showEditorSnackBar(
      content: Text(context.strings.draftRestored),
      action: SnackBarAction(
        label: context.strings.discardDraft,
        onPressed: _discardRestoredDraft,
      ),
    );
    _draftRestoreSnackBarActive = true;
  }

  void _discardRestoredDraft() {
    if (!mounted || _editorDisposed) {
      return;
    }
    _discardingDraft = true;
    _draftSaveTimer?.cancel();
    unawaited(ref.read(noteEditorDraftStoreProvider).clear());
    for (final attachment in _allCurrentAttachments) {
      final filePath = attachment.filePath;
      if (filePath == null || _initialAttachmentPaths.contains(filePath)) {
        continue;
      }
      unawaited(_attachmentStore.deleteAttachment(filePath));
    }
    setState(() {
      _createdAt = DateTime.now();
      _isPinned = false;
      _tags = [];
      _attachments = [];
      _contentController.clear();
      _replaceRichBlocks([_RichBlockDraft.paragraph()]);
    });
    _discardingDraft = false;
    _draftRestoreSnackBarActive = false;
    _updateCanSubmit();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _scheduleInitialEditorFocus();
  }

  void _scheduleDraftPersist() {
    _updateCanSubmit();
    if (widget.note != null || _discardingDraft) {
      return;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _editorDisposed) {
        return;
      }
      final vaultId = _selectedVaultId;
      if (vaultId == null) {
        return;
      }
      final snapshot = NoteEditorDraftSnapshot(
        createdAt: _createdAt,
        isPinned: _isPinned,
        editorMode: _editorMode,
        vaultId: vaultId,
        tags: _tags,
        quickContent: _contentController.text,
        quickAttachments: _attachments,
        richBlocks: _richBlocksToNoteBlocks(),
        location: _location,
      );
      if (!_draftHasContent(snapshot)) {
        unawaited(_draftStore.clear());
        return;
      }
      unawaited(_draftStore.save(snapshot));
    });
  }

  bool _draftHasContent(NoteEditorDraftSnapshot draft) {
    if (draft.quickContent.trim().isNotEmpty ||
        draft.quickAttachments.isNotEmpty) {
      return true;
    }
    for (final block in draft.richBlocks) {
      if ((block.text ?? '').trim().isNotEmpty || block.attachment != null) {
        return true;
      }
    }
    return false;
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

  void _scheduleInitialEditorFocus() {
    if (!mounted || _editorDisposed || widget.note != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editorDisposed) {
        return;
      }
      if (_editorMode == NoteEditorMode.quick) {
        if (!_quickContentFocusNode.canRequestFocus) {
          return;
        }
        _quickContentFocusNode.requestFocus();
        final textLength = _contentController.text.length;
        _contentController.selection = TextSelection.collapsed(
          offset: textLength,
        );
        return;
      }
      final paragraphIndex = _richBlocks.indexWhere(
        (block) => block.type == NoteBlockType.paragraph,
      );
      if (paragraphIndex == -1) {
        return;
      }
      final paragraphToFocus = _richBlocks[paragraphIndex];
      _requestParagraphFocus(
        paragraphToFocus,
        paragraphToFocus.controller?.text.length ?? 0,
      );
    });
  }

  void _requestParagraphFocus(_RichBlockDraft block, int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editorDisposed || !_richBlocks.contains(block)) {
        return;
      }
      final controller = block.controller;
      final focusNode = block.focusNode;
      if (controller == null ||
          focusNode == null ||
          !focusNode.canRequestFocus) {
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

  String _deriveRichPlainText() {
    return _richBlocks
        .map((block) => block.controller?.text.trim())
        .whereType<String>()
        .where((text) => text.isNotEmpty)
        .join('\n\n');
  }

  void _switchEditorMode(NoteEditorMode nextMode) {
    if (nextMode == _editorMode) {
      return;
    }
    _RichBlockDraft? paragraphToFocus;
    setState(() {
      final previousMode = _editorMode;
      if (previousMode == NoteEditorMode.quick &&
          nextMode == NoteEditorMode.rich) {
        _replaceRichBlocks(_buildRichBlocksFromQuickMemo());
        final paragraphIndex = _activeRichParagraphIndex;
        if (paragraphIndex != null &&
            paragraphIndex >= 0 &&
            paragraphIndex < _richBlocks.length) {
          paragraphToFocus = _richBlocks[paragraphIndex];
        }
      } else if (previousMode == NoteEditorMode.rich &&
          nextMode == NoteEditorMode.quick) {
        _contentController.text = _deriveRichPlainText();
        _attachments = _allCurrentAttachments;
      }
      _editorMode = nextMode;
    });
    if (nextMode == NoteEditorMode.quick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _quickContentFocusNode.requestFocus();
        final textLength = _contentController.text.length;
        _contentController.selection = TextSelection.collapsed(
          offset: textLength,
        );
      });
    } else if (paragraphToFocus != null) {
      _requestParagraphFocus(
        paragraphToFocus!,
        paragraphToFocus!.controller?.text.length ?? 0,
      );
    }
    _scheduleDraftPersist();
  }

  bool get _hasDraftContent {
    if (_editorMode == NoteEditorMode.quick) {
      final content = _splitMemoContent(_contentController.text);
      return content.title.isNotEmpty ||
          content.body.isNotEmpty ||
          _attachments.isNotEmpty ||
          _tags.isNotEmpty ||
          _isPinned;
    }
    return _deriveRichTitle().isNotEmpty ||
        _deriveRichBody().isNotEmpty ||
        _allCurrentAttachments.isNotEmpty ||
        _tags.isNotEmpty ||
        _isPinned;
  }

  ({String title, String body}) _currentTagSuggestionContent() {
    if (_editorMode == NoteEditorMode.quick) {
      return _splitMemoContent(_contentController.text);
    }
    final richContent = _deriveRichSaveContent();
    return (title: richContent.title, body: richContent.body);
  }

  Future<void> _suggestTags() async {
    if (_tagSuggestionsBusy) {
      return;
    }
    final content = _currentTagSuggestionContent();
    if (content.title.trim().isEmpty && content.body.trim().isEmpty) {
      _showTagSuggestionEmptyMessage();
      return;
    }
    setState(() {
      _tagSuggestionsBusy = true;
      _tagSuggestions = const [];
      _tagSuggestionSource = null;
    });
    final knownSummaries = ref.read(visibleTagSummariesProvider);
    final knownTags = [for (final summary in knownSummaries) summary.name];
    final knownTagCounts = <String, int>{
      for (final summary in knownSummaries)
        canonicalizeNoteTag(summary.name): summary.count,
    };
    final attachments = _allCurrentAttachments;
    try {
      final result = await ref
          .read(tagSuggestionGatewayProvider)
          .suggestTags(
            TagSuggestionRequest(
              title: content.title,
              body: content.body,
              existingTags: _tags,
              knownTags: knownTags,
              knownTagCounts: knownTagCounts,
              attachmentLabels: [
                for (final attachment in attachments) attachment.label,
              ],
              preferredLanguageCode: context.strings.locale.languageCode,
            ),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _tagSuggestions = result.tags;
        _tagSuggestionSource = result.source;
      });
      if (result.tags.isEmpty) {
        _showTagSuggestionEmptyMessage();
      }
    } finally {
      if (mounted) {
        setState(() {
          _tagSuggestionsBusy = false;
        });
      }
    }
  }

  void _showTagSuggestionEmptyMessage() {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    final strings = context.strings;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        behavior: SnackBarBehavior.floating,
        content: Text(
          strings.localized(
            en: 'No tag suggestions found.',
            ja: '推奨タグが見つかりませんでした。',
            zh: '未找到推荐标签。',
            ko: '추천 태그를 찾을 수 없습니다.',
            es: 'No se encontraron sugerencias de etiquetas.',
            de: 'Keine Tag-Vorschläge gefunden.',
          ),
        ),
      ),
    );
  }

  void _applySuggestedTag(String tag) {
    setState(() {
      _tags = dedupeNoteTags([..._tags, tag]);
      _tagSuggestions = [
        for (final suggestion in _tagSuggestions)
          if (canonicalizeNoteTag(suggestion) != canonicalizeNoteTag(tag))
            suggestion,
      ];
    });
    _scheduleDraftPersist();
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
    final strings = context.strings;
    final privateProfiles = ref.watch(privateMemoProfilesControllerProvider);
    final accessiblePrivateVaultIds = ref.watch(
      accessiblePrivateVaultIdsProvider,
    );
    final adminMode = ref.watch(adminModeSessionControllerProvider);
    final privateTargets = <VaultBucket>[
      for (final vaultId in accessiblePrivateVaultIds)
        _privateTargetFor(vaultId, privateProfiles),
    ];
    final hasPrivateTargets = privateTargets.isNotEmpty;
    _selectedVaultId ??= widget.note?.vaultId ?? 'everyday';
    if (_selectedVaultId != 'everyday' &&
        !privateTargets.any((vault) => vault.id == _selectedVaultId)) {
      _selectedVaultId = 'everyday';
    }
    final isPrivateSelection = _selectedVaultId != 'everyday';
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final editorListBottomPadding = keyboardVisible
        ? 16.0
        : (_editorMode == NoteEditorMode.rich ? 16.0 : 96.0);
    final footerTopGap = keyboardVisible
        ? 4.0
        : (_editorMode == NoteEditorMode.rich ? 8.0 : 16.0);

    return SafeArea(
      top: false,
      bottom: !keyboardVisible,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, keyboardVisible ? 6 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _pickDateTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_createdAt.year}/${_createdAt.month.toString().padLeft(2, '0')}/${_createdAt.day.toString().padLeft(2, '0')} ${_createdAt.hour.toString().padLeft(2, '0')}:${_createdAt.minute.toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: _mutedTextColor(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        PopupMenuButton<NoteEditorMode>(
                          tooltip: _editorMode == NoteEditorMode.quick
                              ? strings.quickMemo
                              : strings.richMemo,
                          offset: const Offset(0, 8),
                          onSelected: _switchEditorMode,
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: NoteEditorMode.quick,
                              child: _MediaMenuEntry(
                                icon: _editorMode == NoteEditorMode.quick
                                    ? Icons.check_rounded
                                    : Icons.notes_outlined,
                                label: strings.quickMemo,
                              ),
                            ),
                            PopupMenuItem(
                              value: NoteEditorMode.rich,
                              child: _MediaMenuEntry(
                                icon: _editorMode == NoteEditorMode.rich
                                    ? Icons.check_rounded
                                    : Icons.view_stream_outlined,
                                label: strings.richMemo,
                              ),
                            ),
                          ],
                          child: _EditorModeButton(
                            mode: _editorMode,
                            strings: strings,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Wrap(
                              spacing: 4,
                              alignment: WrapAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: strings.pinThisNote,
                                  onPressed: () {
                                    setState(() {
                                      _isPinned = !_isPinned;
                                    });
                                    _scheduleDraftPersist();
                                  },
                                  icon: Icon(
                                    _isPinned
                                        ? Icons.push_pin_rounded
                                        : Icons.push_pin_outlined,
                                    color: _isPinned
                                        ? Theme.of(context).colorScheme.primary
                                        : _mutedTextColor(context),
                                  ),
                                ),
                                IconButton(
                                  tooltip: _captureLocationEnabled
                                      ? strings.currentLocationLabel
                                      : strings.addCurrentLocation,
                                  onPressed: _locationBusy
                                      ? null
                                      : _toggleLocationCapture,
                                  icon: _locationBusy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          _location != null
                                              ? Icons.my_location_rounded
                                              : Icons.my_location_outlined,
                                          color:
                                              _captureLocationEnabled ||
                                                  _location != null
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : _mutedTextColor(context),
                                        ),
                                ),
                                PopupMenuButton<MediaImportAction>(
                                  key: const Key('note-capture-media-menu'),
                                  tooltip: strings.captureMedia,
                                  enabled: !_attachmentActionBusy,
                                  icon: Icon(
                                    Icons.photo_camera_outlined,
                                    color: _attachmentActionBusy
                                        ? Theme.of(context).disabledColor
                                        : _mutedTextColor(context),
                                  ),
                                  onSelected: _handleAttachmentAction,
                                  itemBuilder: (context) => [
                                    if (!kIsWeb)
                                      PopupMenuItem(
                                        value: MediaImportAction.takePhoto,
                                        child: _MediaMenuEntry(
                                          icon: Icons.photo_camera_outlined,
                                          label: strings.takePhoto,
                                        ),
                                      ),
                                    if (!kIsWeb)
                                      PopupMenuItem(
                                        value: MediaImportAction.recordVideo,
                                        child: _MediaMenuEntry(
                                          icon: Icons.videocam_outlined,
                                          label: strings.recordVideo,
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: MediaImportAction.recordAudio,
                                      child: _MediaMenuEntry(
                                        icon: Icons.mic_none_rounded,
                                        label: strings.recordAudio,
                                      ),
                                    ),
                                  ],
                                ),
                                PopupMenuButton<MediaImportAction>(
                                  key: const Key('note-import-file-menu'),
                                  tooltip: strings.importFiles,
                                  enabled: !_attachmentActionBusy,
                                  icon: Icon(
                                    Icons.folder_open_outlined,
                                    color: _attachmentActionBusy
                                        ? Theme.of(context).disabledColor
                                        : _mutedTextColor(context),
                                  ),
                                  onSelected: _handleAttachmentAction,
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: MediaImportAction.pickPhoto,
                                      child: _MediaMenuEntry(
                                        icon: Icons.photo_library_outlined,
                                        label: strings.pickPhoto,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: MediaImportAction.pickVideo,
                                      child: _MediaMenuEntry(
                                        icon: Icons.video_library_outlined,
                                        label: strings.pickVideo,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: MediaImportAction.pickAudio,
                                      child: _MediaMenuEntry(
                                        icon: Icons.graphic_eq_rounded,
                                        label: strings.pickAudio,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: MediaImportAction.pickFile,
                                      child: _MediaMenuEntry(
                                        icon: Icons.insert_drive_file_outlined,
                                        label: strings.pickFile,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  top: keyboardVisible ? 12 : 0,
                  bottom: editorListBottomPadding,
                ),
                children: [
                  if (_editorMode == NoteEditorMode.quick) ...[
                    Container(
                      decoration: _sectionDecoration(context),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: TextField(
                        key: const Key('note-content-input'),
                        controller: _contentController,
                        focusNode: _quickContentFocusNode,
                        autofocus: widget.note == null,
                        minLines: 4,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        scrollPadding: const EdgeInsets.only(
                          top: 96,
                          left: 20,
                          right: 20,
                          bottom: 96,
                        ),
                        decoration: InputDecoration(
                          hintText: strings.memoFirstLineHint,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Container(
                      decoration: _sectionDecoration(context),
                      padding: const EdgeInsets.all(12),
                      child: _RichMemoEditor(
                        blocks: _richBlocks,
                        strings: strings,
                        pendingAttachmentCount:
                            _pendingAttachmentPlaceholderCount,
                        onRemoveBlock: _removeRichBlock,
                        onBackspaceAtParagraphStart:
                            _removeMediaBeforeParagraph,
                        onMoveBlock: _moveRichBlock,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    decoration: _sectionDecoration(context),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                strings.text('home.tags'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _tagSuggestionsBusy
                                  ? null
                                  : _suggestTags,
                              icon: _tagSuggestionsBusy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_awesome_rounded),
                              label: Text(
                                strings.localized(
                                  en: 'Suggest',
                                  ja: '提案',
                                  zh: '建议',
                                  ko: '추천',
                                  es: 'Sugerir',
                                  de: 'Vorschlagen',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _TagAutocompleteField(
                          key: _tagFieldKey,
                          inputKey: const Key('note-tag-input'),
                          suggestions: ref.watch(visibleTagSuggestionsProvider),
                          label: strings.text('home.add.a.tag'),
                          hintText: strings.text(
                            'home.type.a.tag.and.press.enter',
                          ),
                          existingTags: _tags,
                          showSubmitAction: true,
                          onTagSelected: (tag) {
                            setState(() {
                              _tags = dedupeNoteTags([..._tags, tag]);
                            });
                            _scheduleDraftPersist();
                          },
                        ),
                        if (_tagSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final tagCounts = <String, int>{
                                for (final summary in ref.watch(
                                  visibleTagSummariesProvider,
                                ))
                                  canonicalizeNoteTag(summary.name):
                                      summary.count,
                              };
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final tag in _tagSuggestions)
                                    ActionChip(
                                      avatar: Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      label: Text(() {
                                        final count =
                                            tagCounts[canonicalizeNoteTag(
                                              tag,
                                            )] ??
                                            0;
                                        return count > 0
                                            ? '#$tag ($count)'
                                            : '#$tag';
                                      }()),
                                      tooltip: strings.localized(
                                        en: _tagSuggestionSource == 'local'
                                            ? 'Local suggestion'
                                            : 'Apple Intelligence suggestion',
                                        ja: _tagSuggestionSource == 'local'
                                            ? 'ローカル提案'
                                            : 'Apple Intelligence提案',
                                        zh: _tagSuggestionSource == 'local'
                                            ? '本地建议'
                                            : 'Apple Intelligence 建议',
                                        ko: _tagSuggestionSource == 'local'
                                            ? '로컬 추천'
                                            : 'Apple Intelligence 추천',
                                        es: _tagSuggestionSource == 'local'
                                            ? 'Sugerencia local'
                                            : 'Sugerencia de Apple Intelligence',
                                        de: _tagSuggestionSource == 'local'
                                            ? 'Lokaler Vorschlag'
                                            : 'Apple Intelligence-Vorschlag',
                                      ),
                                      onPressed: () => _applySuggestedTag(tag),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                        if (_tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final tag in _tags)
                                InputChip(
                                  label: Text('#$tag'),
                                  onDeleted: () {
                                    setState(() {
                                      _tags = _tags
                                          .where(
                                            (entry) =>
                                                canonicalizeNoteTag(entry) !=
                                                canonicalizeNoteTag(tag),
                                          )
                                          .toList(growable: false);
                                    });
                                    _scheduleDraftPersist();
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasPrivateTargets)
                    SwitchListTile.adaptive(
                      key: const Key('note-save-private-toggle'),
                      value: isPrivateSelection,
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('home.save.to.private.profile')),
                      subtitle: Text(
                        adminMode
                            ? (strings.text(
                                'home.choose.which.private.profile.to.save.into.while.in.admin',
                              ))
                            : (strings.text(
                                'home.save.into.the.currently.unlocked.private.profile',
                              )),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _selectedVaultId = value
                              ? (privateTargets.isEmpty
                                    ? 'everyday'
                                    : privateTargets.first.id)
                              : 'everyday';
                        });
                        _scheduleDraftPersist();
                      },
                    ),
                  if (isPrivateSelection &&
                      adminMode &&
                      privateTargets.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DropdownButtonFormField<String>(
                        key: const Key('note-private-profile-select'),
                        initialValue: _selectedVaultId,
                        decoration: InputDecoration(
                          labelText: strings.text('home.private.profile'),
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final vault in privateTargets)
                            DropdownMenuItem(
                              value: vault.id,
                              child: Text(_vaultDisplayName(context, vault)),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedVaultId = value;
                          });
                          _scheduleDraftPersist();
                        },
                      ),
                    ),
                  if (_location != null) ...[
                    const SizedBox(height: 12),
                    _EditableLocationSection(
                      location: _location!,
                      strings: strings,
                      onEdit: _editLocation,
                      onRemove: () {
                        setState(() {
                          _location = null;
                          _captureLocationEnabled = false;
                        });
                        unawaited(
                          ref
                              .read(
                                lastNoteEditorSettingsControllerProvider
                                    .notifier,
                              )
                              .setCaptureLocation(false),
                        );
                        _scheduleDraftPersist();
                      },
                    ),
                  ],
                  if (_editorMode == NoteEditorMode.quick) ...[
                    const SizedBox(height: 12),
                    _QuickAttachmentSection(
                      strings: strings,
                      attachments: _attachments,
                      pendingAttachmentCount:
                          _pendingAttachmentPlaceholderCount,
                      onRemove: _removeQuickAttachmentAt,
                      onMove: _moveQuickAttachment,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: footerTopGap),
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: SizedBox(
                height: _attachmentActionBusy ? 56 : 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _attachmentActionBusy ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.48),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                _attachmentImportBusy
                                    ? strings.localized(
                                        en: 'Processing attachment...',
                                        ja: '添付処理中...',
                                        zh: '正在附加...',
                                        ko: '첨부 중...',
                                        es: 'Adjuntando...',
                                        de: 'Wird angehängt...',
                                      )
                                    : strings.localized(
                                        en: 'Selecting file...',
                                        ja: 'ファイル選択中...',
                                        zh: '选择文件中...',
                                        ko: '파일 선택 중...',
                                        es: 'Seleccionando...',
                                        de: 'Datei auswählen...',
                                      ),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_attachmentActionBusy) const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
                if (widget.note != null)
                  IconButton(
                    key: const Key('editor-delete-note-button'),
                    onPressed: _attachmentActionBusy || _saveBusy
                        ? null
                        : _deleteCurrentNote,
                    tooltip: strings.deleteNote,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: _canSubmitNotifier,
                  builder: (context, canSubmit, _) {
                    return FilledButton(
                      key: const Key('save-note-button'),
                      onPressed:
                          canSubmit &&
                              _selectedVaultId != null &&
                              !_attachmentActionBusy &&
                              !_saveBusy
                          ? _save
                          : null,
                      child: _saveBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              widget.note == null
                                  ? strings.createNote
                                  : strings.saveChanges,
                            ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasSubmitContent {
    final hasText = _editorMode == NoteEditorMode.quick
        ? (() {
            final content = _splitMemoContent(_contentController.text);
            return content.title.isNotEmpty || content.body.isNotEmpty;
          })()
        : _deriveRichTitle().isNotEmpty || _deriveRichBody().isNotEmpty;
    final hasAttachments = _allCurrentAttachments.isNotEmpty;
    return hasText || hasAttachments;
  }

  bool get _canSave {
    return _hasSubmitContent && _selectedVaultId != null;
  }

  bool get _attachmentActionBusy =>
      _attachmentPickerBusy || _attachmentImportBusy;

  void _showEditorSnackBar({required Widget content, SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final availableWidth = mediaQuery.size.width - 32;
    final snackBarWidth = availableWidth <= 420
        ? null
        : math.min(420.0, availableWidth);
    final useFloating =
        mediaQuery.size.width >= 520 &&
        mediaQuery.size.height - bottomInset >= 720;
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: content,
        action: action,
        behavior: useFloating
            ? SnackBarBehavior.floating
            : SnackBarBehavior.fixed,
        width: useFloating ? snackBarWidth : null,
        margin: useFloating && snackBarWidth == null
            ? EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16)
            : null,
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
      content: Text(context.strings.dateTimeUpdated),
      action: SnackBarAction(
        label: context.strings.undo,
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
    if (_attachmentActionBusy) {
      return;
    }
    if (action == MediaImportAction.addLocation) {
      await _toggleLocationCapture();
      return;
    }
    setState(() {
      _attachmentPickerBusy = true;
    });
    _updateCanSubmit();
    final strings = context.strings;
    final MediaImportResult result;
    try {
      if (action == MediaImportAction.recordAudio) {
        // ignore: use_build_context_synchronously
        result = await _showAudioRecordingDialog(context, ref);
      } else {
        final mediaImportService = ref.read(mediaImportServiceProvider);
        result = await mediaImportService.importAttachment(
          action,
          onProcessingStarted: _markAttachmentProcessingStarted,
        );
      }
      if (!mounted) {
        return;
      }
      final attachments = result.allAttachments;
      if (attachments.isEmpty) {
        final errorMessage = result.errorMessage;
        if (errorMessage != null && errorMessage.isNotEmpty) {
          _showEditorSnackBar(content: Text(errorMessage));
        }
        return;
      }
      setState(() {
        if (_editorMode == NoteEditorMode.quick) {
          _attachments = [..._attachments, ...attachments];
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

              replacement.addAll(attachments.map(_RichBlockDraft.attachment));

              final afterParagraph = _RichBlockDraft.paragraph(afterText);
              _attachRichBlockListener(afterParagraph);
              replacement.add(afterParagraph);

              nextBlocks.insertAll(insertionIndex, replacement);
              paragraphToFocus = afterParagraph;
              focusOffset = 0;
            } else {
              nextBlocks.insert(
                insertionIndex,
                _RichBlockDraft.attachment(attachments.first),
              );
              for (var i = 1; i < attachments.length; i += 1) {
                nextBlocks.insert(
                  insertionIndex + i,
                  _RichBlockDraft.attachment(attachments[i]),
                );
              }
              paragraphToFocus = current;
              focusOffset = 0;
            }
          } else {
            final trailingParagraph = _RichBlockDraft.paragraph();
            _attachRichBlockListener(trailingParagraph);
            nextBlocks.insertAll(insertionIndex, [
              ...attachments.map(_RichBlockDraft.attachment),
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
      for (final attachment in attachments) {
        _cancelAttachmentDelete(attachment);
      }
      _scheduleDraftPersist();
      if (result.deferredPreviews.isNotEmpty) {
        _applyDeferredPreviews(result.deferredPreviews);
      }
    } catch (error) {
      if (mounted) {
        _showEditorSnackBar(
          content: Text(
            strings.localized(
              en: 'Could not attach the selected file. ($error)',
              ja: '選択したファイルを添付できませんでした。($error)',
              zh: '无法附加所选文件。($error)',
              ko: '선택한 파일을 첨부할 수 없습니다. ($error)',
              es: 'No se pudo adjuntar el archivo seleccionado. ($error)',
              de: 'Die ausgewählte Datei konnte nicht angehängt werden. ($error)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _attachmentPickerBusy = false;
          _attachmentImportBusy = false;
          _pendingAttachmentPlaceholderCount = 0;
        });
        _updateCanSubmit();
      }
    }
  }

  void _markAttachmentProcessingStarted() {
    if (!mounted) {
      return;
    }
    setState(() {
      _attachmentPickerBusy = false;
      _attachmentImportBusy = true;
      _pendingAttachmentPlaceholderCount = 1;
    });
    _updateCanSubmit();
  }

  Future<void> _applyDeferredPreviews(
    Map<String, Future<String?>> deferredPreviews,
  ) async {
    for (final entry in deferredPreviews.entries) {
      try {
        final preview = await entry.value;
        if (preview == null || !mounted) continue;
        setState(() {
          _attachments = _attachments.map((a) {
            return a.filePath == entry.key
                ? a.copyWith(previewBytesBase64: preview)
                : a;
          }).toList();
          _richBlocks = [
            for (final b in _richBlocks)
              if (b.attachment != null && b.attachment!.filePath == entry.key)
                _RichBlockDraft.attachment(
                  b.attachment!.copyWith(previewBytesBase64: preview),
                )
              else
                b,
          ];
        });
        _scheduleDraftPersist();
      } catch (_) {}
    }
  }

  Future<void> _toggleLocationCapture() async {
    final nextEnabled = !_captureLocationEnabled;
    setState(() {
      _captureLocationEnabled = nextEnabled;
      if (!nextEnabled) {
        _location = null;
      }
    });
    await ref
        .read(lastNoteEditorSettingsControllerProvider.notifier)
        .setCaptureLocation(nextEnabled);
    _scheduleDraftPersist();
    if (nextEnabled) {
      await _captureCurrentLocationForNote(showErrors: true);
    }
  }

  Future<void> _captureCurrentLocationForNote({
    required bool showErrors,
  }) async {
    if (_locationBusy) {
      return;
    }
    final strings = context.strings;
    setState(() {
      _locationBusy = true;
    });
    try {
      final locationServiceEnabled =
          kIsWeb || await Geolocator.isLocationServiceEnabled();
      if (!locationServiceEnabled) {
        if (!mounted) {
          return;
        }
        if (showErrors) {
          _showEditorSnackBar(content: Text(strings.locationServicesOff));
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        if (showErrors) {
          _showEditorSnackBar(
            content: Text(strings.locationPermissionRequired),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) {
        return;
      }
      final address = await _resolveLocationAddress(position);
      if (!mounted) {
        return;
      }
      setState(() {
        _location = _noteLocationFromPosition(position, address: address);
      });
      _scheduleDraftPersist();
      if (showErrors) {
        _showEditorSnackBar(content: Text(strings.currentLocationAdded));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (showErrors) {
        _showEditorSnackBar(content: Text(strings.currentLocationUnavailable));
      }
    } finally {
      if (mounted) {
        setState(() {
          _locationBusy = false;
        });
      }
    }
  }

  Future<void> _editLocation() async {
    final current = _location;
    if (current == null) {
      return;
    }
    final edited = await _showLocationEditDialog(context, current);
    if (edited == null || !mounted) {
      return;
    }
    setState(() {
      _location = edited;
    });
    _scheduleDraftPersist();
  }

  Future<void> _save() async {
    if (!_canSave || _saveBusy || _saved || _attachmentActionBusy) {
      return;
    }
    setState(() {
      _saveBusy = true;
    });
    _updateCanSubmit();
    try {
      final pendingTag = _tagFieldKey.currentState?.consumePendingTag();
      final saveTags = pendingTag == null
          ? dedupeNoteTags(_tags)
          : dedupeNoteTags([..._tags, pendingTag]);
      final richContent = _editorMode == NoteEditorMode.rich
          ? _deriveRichSaveContent()
          : null;
      final content = _editorMode == NoteEditorMode.quick
          ? _splitMemoContent(_contentController.text)
          : (title: richContent!.title, body: richContent.body);
      final blocks = _editorMode == NoteEditorMode.quick
          ? const <NoteBlock>[]
          : richContent!.blocks;
      final note = NoteEntry(
        id: widget.note?.id ?? _newNoteId,
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
        tags: saveTags,
        isPinned: _isPinned,
        revision: widget.note?.revision ?? 1,
        deviceId: widget.note?.deviceId,
        syncState: widget.note?.syncState ?? NoteSyncState.localOnly,
        editorMode: _editorMode,
        location: _location,
      );
      final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
      for (final filePath in _pendingAttachmentDeletes) {
        await attachmentStore.deleteAttachment(filePath);
      }
      _pendingAttachmentDeletes.clear();
      await ref
          .read(lastNoteEditorSettingsControllerProvider.notifier)
          .remember(
            mode: _editorMode,
            vaultId: _selectedVaultId!,
            captureLocation: _captureLocationEnabled,
          );
      await ref.read(notesControllerProvider.notifier).upsert(note);
      if (widget.note == null) {
        await ref.read(noteEditorDraftStoreProvider).clear();
      }
      _saved = true;
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error, stackTrace) {
      logDiagnostic(
        'note_editor',
        'save failed',
        data: {
          'error': error,
          'editorMode': _editorMode.name,
          'vaultId': _selectedVaultId,
          'attachments': _allCurrentAttachments.length,
          'hasText': _hasSubmitContent,
        },
      );
      debugPrintStack(
        label: 'HiMemo note save failed: $error',
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showEditorSnackBar(
          content: Text(
            context.strings.localized(
              en: 'Could not save this note. Check diagnostic logs for details. ($error)',
              ja: 'このメモを保存できませんでした。詳細は診断ログを確認してください。($error)',
              zh: '无法保存此备忘录。请查看诊断日志了解详细信息。($error)',
              ko: '이 메모를 저장할 수 없습니다. 자세한 내용은 진단 로그를 확인하세요. ($error)',
              es: 'No se pudo guardar esta nota. Revisa los registros de diagnóstico. ($error)',
              de: 'Diese Notiz konnte nicht gespeichert werden. Details stehen im Diagnoseprotokoll. ($error)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saveBusy = false;
        });
        _updateCanSubmit();
      }
    }
  }

  Future<void> _deleteCurrentNote() async {
    final note = widget.note;
    if (note == null || _saveBusy || _attachmentActionBusy) {
      return;
    }
    final result = await _showDeleteNoteDialog(context, note);
    if (result == null || !mounted) {
      return;
    }
    final controller = ref.read(notesControllerProvider.notifier);
    await controller.delete(note.id);
    if (result.deletePermanently) {
      await controller.deletePermanently(note.id);
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
      content: Text(context.strings.attachmentRemoved(removed.label)),
      action: SnackBarAction(
        label: context.strings.undo,
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
        content: Text(context.strings.attachmentRemoved(attachment.label)),
        action: SnackBarAction(
          label: context.strings.undo,
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

  void _ensureTrailingRichParagraph(List<_RichBlockDraft> drafts) {
    if (drafts.isEmpty || drafts.last.type == NoteBlockType.paragraph) {
      return;
    }
    drafts.add(_RichBlockDraft.paragraph());
  }

  String _deriveRichTitle() {
    for (final block in _richBlocks) {
      final text = block.controller?.text.trim() ?? '';
      if (text.isNotEmpty) {
        return text.split('\n').first.trim();
      }
    }
    return '';
  }

  String _deriveRichBody() {
    return _deriveRichSaveContent().body;
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

  _RichSaveContent _deriveRichSaveContent() {
    var title = '';
    var consumedTitle = false;
    final bodyParts = <String>[];
    final blocks = <NoteBlock>[];

    for (final block in _richBlocks) {
      if (block.type != NoteBlockType.paragraph) {
        if (block.attachment != null) {
          blocks.add(NoteBlock(type: block.type, attachment: block.attachment));
        }
        continue;
      }

      final text = block.controller?.text.trim() ?? '';
      if (text.isEmpty) {
        continue;
      }

      var bodyText = text;
      if (!consumedTitle) {
        final content = _splitMemoContent(text);
        title = content.title;
        bodyText = content.body;
        consumedTitle = true;
      }

      if (bodyText.isEmpty) {
        continue;
      }
      bodyParts.add(bodyText);
      blocks.add(NoteBlock(type: NoteBlockType.paragraph, text: bodyText));
    }

    return _RichSaveContent(
      title: title,
      body: bodyParts.join('\n\n'),
      blocks: blocks,
    );
  }
}

class _RichSaveContent {
  const _RichSaveContent({
    required this.title,
    required this.body,
    required this.blocks,
  });

  final String title;
  final String body;
  final List<NoteBlock> blocks;
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

Future<String?> _resolveLocationAddress(Position position) async {
  if (kIsWeb) {
    return null;
  }
  try {
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 5));
    if (placemarks.isEmpty) {
      return null;
    }
    return _formatPlacemarkAddress(placemarks.first);
  } catch (_) {
    return null;
  }
}

String? _formatPlacemarkAddress(Placemark placemark) {
  final streetParts = [placemark.street, placemark.subLocality]
      .whereType<String>()
      .map((part) => part.trim())
      .where((part) {
        return part.isNotEmpty;
      })
      .toList(growable: false);

  final parts =
      [
            if (streetParts.isNotEmpty) streetParts.join(' '),
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country,
          ]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) {
            return part.isNotEmpty;
          })
          .toList(growable: false);

  final deduped = <String>[];
  for (final part in parts) {
    if (!deduped.contains(part)) {
      deduped.add(part);
    }
  }
  return deduped.isEmpty ? null : deduped.join(', ');
}

NoteLocation _noteLocationFromPosition(Position position, {String? address}) {
  return NoteLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
    address: address,
    capturedAt: DateTime.now(),
  );
}

class _LocationMemoData {
  const _LocationMemoData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.mapUrl,
    this.address,
  });

  final String latitude;
  final String longitude;
  final String accuracy;
  final String mapUrl;
  final String? address;
}

List<String> _locationSearchParts(_LocationMemoData? location) {
  if (location == null) {
    return const <String>[];
  }
  return [
    if (location.address?.trim().isNotEmpty == true) location.address!.trim(),
    location.latitude,
    location.longitude,
    if (location.accuracy.trim().isNotEmpty && location.accuracy != '-')
      location.accuracy,
    location.mapUrl,
  ];
}

String? _locationSearchText(_LocationMemoData? location) {
  final parts = _locationSearchParts(location);
  if (parts.isEmpty) {
    return null;
  }
  return parts.join('\n');
}

int? _locationFieldActiveMatchStart(
  _LocationMemoData location,
  String field,
  int? activeMatchStart,
) {
  if (activeMatchStart == null || field.isEmpty) {
    return null;
  }
  var offset = 0;
  for (final part in _locationSearchParts(location)) {
    final end = offset + part.length;
    if (part == field && activeMatchStart >= offset && activeMatchStart < end) {
      return activeMatchStart - offset;
    }
    offset = end + 1;
  }
  return null;
}

_LocationMemoData _locationMemoDataFromMetadata(NoteLocation location) {
  final latitude = location.latitude.toStringAsFixed(6);
  final longitude = location.longitude.toStringAsFixed(6);
  return _LocationMemoData(
    latitude: latitude,
    longitude: longitude,
    accuracy: location.accuracyMeters == null
        ? '-'
        : '${location.accuracyMeters!.round()}m',
    mapUrl: 'https://maps.google.com/?q=$latitude,$longitude',
    address: location.address,
  );
}

_LocationMemoData? _tryParseLocationMemo(String text) {
  final leadingText = text.trimLeft().toLowerCase();
  if (!leadingText.startsWith('迴ｾ蝨ｨ蝨ｰ') &&
      !leadingText.startsWith('current location')) {
    return null;
  }
  final normalized = text.replaceAll('\r\n', '\n').trim();
  final lines = normalized
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 4) {
    return null;
  }
  final heading = lines.first.toLowerCase();
  if (heading != '現在地' && heading != 'current location') {
    return null;
  }

  final urlMatch = RegExp(
    r'https://maps\.google\.com/\?q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
  ).firstMatch(normalized);
  if (urlMatch == null) {
    return null;
  }

  String valueAfterColon(String label) {
    final line = lines.firstWhere(
      (candidate) => candidate.toLowerCase().startsWith(label.toLowerCase()),
      orElse: () => '',
    );
    final colonIndex = line.indexOf(':');
    return colonIndex < 0 ? '' : line.substring(colonIndex + 1).trim();
  }

  final latitude = valueAfterColon('緯度').isNotEmpty
      ? valueAfterColon('緯度')
      : valueAfterColon('Latitude');
  final longitude = valueAfterColon('経度').isNotEmpty
      ? valueAfterColon('経度')
      : valueAfterColon('Longitude');
  var accuracy = valueAfterColon('精度').isNotEmpty
      ? valueAfterColon('精度')
      : valueAfterColon('Accuracy');
  accuracy = accuracy
      .replaceFirst(RegExp(r'^約\s*'), '')
      .replaceFirst(RegExp(r'^about\s+', caseSensitive: false), '');
  final address = valueAfterColon('推定住所').isNotEmpty
      ? valueAfterColon('推定住所')
      : valueAfterColon('Estimated address');

  return _LocationMemoData(
    latitude: latitude.isEmpty ? urlMatch.group(1)! : latitude,
    longitude: longitude.isEmpty ? urlMatch.group(2)! : longitude,
    accuracy: accuracy.isEmpty ? '-' : accuracy,
    mapUrl: urlMatch.group(0)!,
    address: address.isEmpty ? null : address,
  );
}

Future<void> _openLocationMap(
  BuildContext context,
  _LocationMemoData location,
) async {
  final uri = Uri.tryParse(location.mapUrl);
  if (uri != null) {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        return;
      }
    } catch (_) {
      // Fall through to the visible failure message below.
    }
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(showCloseIcon: true, content: Text(context.strings.mapOpenFailed)),
  );
}

class _EditableLocationSection extends StatelessWidget {
  const _EditableLocationSection({
    required this.location,
    required this.strings,
    required this.onEdit,
    required this.onRemove,
  });

  final NoteLocation location;
  final AppStrings strings;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final data = _locationMemoDataFromMetadata(location);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final address = data.address?.trim();
    final subtitle = address == null || address.isEmpty
        ? '${strings.latitudeLabel}: ${data.latitude}, '
              '${strings.longitudeLabel}: ${data.longitude}'
        : address;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.my_location_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.currentLocationLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.editNote,
                onPressed: onEdit,
                icon: const Icon(Icons.map_outlined),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.removeBlock,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationSearchResult {
  const _LocationSearchResult({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

Future<List<_LocationSearchResult>> _searchLocationCandidates(
  String query,
) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'jsonv2',
    'limit': '5',
    'q': trimmed,
  });
  final response = await http
      .get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': _httpUserAgent,
        },
      )
      .timeout(const Duration(seconds: 10));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('Location search failed: ${response.statusCode}');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! List) {
    return const [];
  }
  return [
    for (final entry in decoded)
      if (entry is Map)
        if (double.tryParse('${entry['lat']}') case final latitude?)
          if (double.tryParse('${entry['lon']}') case final longitude?)
            _LocationSearchResult(
              label: '${entry['display_name'] ?? ''}'.trim(),
              latitude: latitude,
              longitude: longitude,
            ),
  ].where((entry) => entry.label.isNotEmpty).toList(growable: false);
}

Future<String?> _reverseSearchLocationAddress(LatLng point) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': point.latitude.toStringAsFixed(7),
      'lon': point.longitude.toStringAsFixed(7),
      'zoom': '18',
      'addressdetails': '1',
    });
    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': _httpUserAgent,
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return null;
    }
    final displayName = '${decoded['display_name'] ?? ''}'.trim();
    return displayName.isEmpty ? null : displayName;
  } catch (_) {
    return null;
  }
}

Future<NoteLocation?> _showLocationEditDialog(
  BuildContext context,
  NoteLocation location,
) {
  return showDialog<NoteLocation>(
    context: context,
    builder: (dialogContext) => _LocationEditDialog(location: location),
  );
}

class _LocationEditDialog extends StatefulWidget {
  const _LocationEditDialog({required this.location});

  final NoteLocation location;

  @override
  State<_LocationEditDialog> createState() => _LocationEditDialogState();
}

class _LocationEditDialogState extends State<_LocationEditDialog> {
  late final TextEditingController _accuracyController;
  late final TextEditingController _addressController;
  late final TextEditingController _searchController;
  late final MapController _mapController;
  late LatLng _selectedPoint;
  double _selectedZoom = 15;
  bool _isSearching = false;
  bool _isResolvingAddress = false;
  String? _errorText;
  Timer? _reverseAddressDebounce;
  LatLng? _lastReverseAddressPoint;
  int _reverseAddressRequestId = 0;
  List<_LocationSearchResult> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _accuracyController = TextEditingController(
      text: widget.location.accuracyMeters == null
          ? ''
          : widget.location.accuracyMeters!.round().toString(),
    );
    _addressController = TextEditingController(
      text: widget.location.address ?? '',
    );
    _searchController = TextEditingController();
    _mapController = MapController();
    _selectedPoint = LatLng(
      widget.location.latitude,
      widget.location.longitude,
    );
  }

  @override
  void dispose() {
    _reverseAddressDebounce?.cancel();
    _accuracyController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(AppStrings strings) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _errorText = null;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _errorText = null;
    });
    try {
      final results = await _searchLocationCandidates(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _errorText = results.isEmpty
            ? strings.localized(
                en: 'No matching places were found.',
                ja: '一致する地点が見つかりませんでした。',
                zh: '未找到匹配的地点。',
                ko: '일치하는 장소를 찾을 수 없습니다.',
                es: 'No se encontraron lugares coincidentes.',
                de: 'Keine passenden Orte gefunden.',
              )
            : null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSearching = false;
        _errorText = strings.localized(
          en: 'Location search failed. Try again later.',
          ja: '地点検索に失敗しました。時間をおいて再試行してください。',
          zh: '地点搜索失败。请稍后重试。',
          ko: '장소 검색에 실패했습니다. 나중에 다시 시도하세요.',
          es: 'La búsqueda de ubicación falló. Inténtalo más tarde.',
          de: 'Standortsuche fehlgeschlagen. Versuche es später erneut.',
        );
      });
    }
  }

  void _selectSearchResult(_LocationSearchResult result) {
    final point = LatLng(result.latitude, result.longitude);
    _reverseAddressDebounce?.cancel();
    setState(() {
      _selectedPoint = point;
      _lastReverseAddressPoint = point;
      _addressController.text = result.label;
      _searchResults = const [];
      _isResolvingAddress = false;
      _errorText = null;
    });
    _mapController.move(point, 15);
  }

  void _scheduleReverseAddressUpdate() {
    _reverseAddressDebounce?.cancel();
    final point = _selectedPoint;
    final previous = _lastReverseAddressPoint;
    if (previous != null &&
        (previous.latitude - point.latitude).abs() < 0.00008 &&
        (previous.longitude - point.longitude).abs() < 0.00008) {
      return;
    }
    _reverseAddressDebounce = Timer(const Duration(milliseconds: 850), () {
      _resolveAddressForPoint(point);
    });
  }

  Future<void> _resolveAddressForPoint(LatLng point) async {
    final requestId = ++_reverseAddressRequestId;
    if (mounted) {
      setState(() {
        _isResolvingAddress = true;
      });
    }
    final address = await _reverseSearchLocationAddress(point);
    if (!mounted || requestId != _reverseAddressRequestId) {
      return;
    }
    setState(() {
      _lastReverseAddressPoint = point;
      _isResolvingAddress = false;
      if (address != null) {
        _addressController.text = address;
      }
    });
  }

  void _save() {
    Navigator.of(context).pop(
      NoteLocation(
        latitude: _selectedPoint.latitude,
        longitude: _selectedPoint.longitude,
        accuracyMeters: double.tryParse(_accuracyController.text.trim()),
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        capturedAt: widget.location.capturedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(strings.currentLocationLabel),
      content: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width - 48, 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.localized(
                  en: 'Move the map so the pin points to the note location.',
                  ja: 'ピンがメモの地点を指すように地図を移動してください。',
                  zh: '移动地图，让图钉指向笔记位置。',
                  ko: '핀이 메모 위치를 가리키도록 지도를 이동하세요.',
                  es: 'Mueve el mapa para que el pin señale la ubicación de la nota.',
                  de: 'Verschiebe die Karte, damit die Markierung auf den Notizort zeigt.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: strings.localized(
                          en: 'Search place',
                          ja: '地点を検索',
                          zh: '搜索地点',
                          ko: '장소 검색',
                          es: 'Buscar lugar',
                          de: 'Ort suchen',
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                      onSubmitted: (_) => _runSearch(strings),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: strings.localized(
                      en: 'Search',
                      ja: '検索',
                      zh: '搜索',
                      ko: '검색',
                      es: 'Buscar',
                      de: 'Suchen',
                    ),
                    onPressed: _isSearching ? null : () => _runSearch(strings),
                    icon: _isSearching
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                  ),
                ],
              ),
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final result in _searchResults)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            result.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSearchResult(result),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 280,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _selectedPoint,
                          initialZoom: _selectedZoom,
                          onPositionChanged: (camera, hasGesture) {
                            _selectedPoint = camera.center;
                            _selectedZoom = camera.zoom;
                            if (hasGesture) {
                              _scheduleReverseAddressUpdate();
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'org.ruhenheim.himemo',
                          ),
                        ],
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 42,
                            color: colorScheme.primary,
                            shadows: [
                              Shadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              '© OpenStreetMap © CARTO',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: strings.estimatedAddressLabel,
                  suffixIcon: _isResolvingAddress
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _accuracyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.locationAccuracyLabel,
                  suffixText: 'm',
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(_errorText!, style: TextStyle(color: colorScheme.error)),
              ],
              const SizedBox(height: 8),
              Text(
                '${strings.latitudeLabel}: ${_selectedPoint.latitude.toStringAsFixed(6)}\n'
                '${strings.longitudeLabel}: ${_selectedPoint.longitude.toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        TextButton.icon(
          onPressed: () => _openLocationMap(
            context,
            _locationMemoDataFromMetadata(widget.location),
          ),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(strings.openMap),
        ),
        FilledButton(onPressed: _save, child: Text(strings.save)),
      ],
    );
  }
}

class _LocationMemoCard extends StatelessWidget {
  const _LocationMemoCard({
    required this.location,
    required this.strings,
    this.width,
    this.highlightQuery = '',
    this.activeSearchMatchStart,
  });

  final _LocationMemoData location;
  final AppStrings strings;
  final double? width;
  final String highlightQuery;
  final int? activeSearchMatchStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final borderColor = theme.dividerColor.withValues(alpha: 0.8);
    final muted = _mutedTextColor(context);
    final activeSearch = activeSearchMatchStart != null;

    return Container(
      width: width,
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: activeSearch ? scheme.tertiary : borderColor,
          width: activeSearch ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.10),
                      scheme.surface,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LocationMapPatternPainter(
                      lineColor: scheme.primary.withValues(alpha: 0.18),
                      accentColor: scheme.tertiary.withValues(alpha: 0.20),
                    ),
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: scheme.onPrimary,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.currentLocationLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (location.address case final address?) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.estimatedAddressLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _HighlightedInlineText(
                              text: address,
                              query: highlightQuery,
                              activeMatchStart: _locationFieldActiveMatchStart(
                                location,
                                address,
                                activeSearchMatchStart,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _LocationValue(
                      label: strings.latitudeLabel,
                      value: location.latitude,
                      query: highlightQuery,
                      activeMatchStart: _locationFieldActiveMatchStart(
                        location,
                        location.latitude,
                        activeSearchMatchStart,
                      ),
                    ),
                    _LocationValue(
                      label: strings.longitudeLabel,
                      value: location.longitude,
                      query: highlightQuery,
                      activeMatchStart: _locationFieldActiveMatchStart(
                        location,
                        location.longitude,
                        activeSearchMatchStart,
                      ),
                    ),
                    _LocationValue(
                      label: strings.locationAccuracyLabel,
                      value: location.accuracy,
                      query: highlightQuery,
                      activeMatchStart: _locationFieldActiveMatchStart(
                        location,
                        location.accuracy,
                        activeSearchMatchStart,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openLocationMap(context, location),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: Text(strings.openMap),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: location.mapUrl),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            showCloseIcon: true,
                            content: Text(strings.mapLinkCopied),
                          ),
                        );
                      },
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(strings.copyMapLink),
                      style: TextButton.styleFrom(
                        foregroundColor: muted,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationValue extends StatelessWidget {
  const _LocationValue({
    required this.label,
    required this.value,
    this.query = '',
    this.activeMatchStart,
  });

  final String label;
  final String value;
  final String query;
  final int? activeMatchStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: _mutedTextColor(context),
        ),
        children: [
          TextSpan(text: '$label '),
          ..._highlightTextSpans(
            text: value,
            query: query,
            baseStyle: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            highlightStyle: _noteSearchHighlightStyle(context, null),
            activeHighlightStyle: _noteSearchActiveHighlightStyle(
              context,
              null,
            ),
            activeMatchStart: activeMatchStart,
          ),
        ],
      ),
    );
  }
}

class _LocationMapPatternPainter extends CustomPainter {
  const _LocationMapPatternPainter({
    required this.lineColor,
    required this.accentColor,
  });

  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final accentPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final route = Path()
      ..moveTo(size.width * 0.08, size.height * 0.76)
      ..cubicTo(
        size.width * 0.26,
        size.height * 0.24,
        size.width * 0.42,
        size.height * 0.92,
        size.width * 0.62,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.74,
        size.height * 0.12,
        size.width * 0.86,
        size.height * 0.18,
        size.width * 0.94,
        size.height * 0.08,
      );
    canvas.drawPath(route, accentPaint);

    for (final x in <double>[0.20, 0.48, 0.76]) {
      canvas.drawLine(
        Offset(size.width * x, 0),
        Offset(size.width * (x - 0.16), size.height),
        linePaint,
      );
    }
    for (final y in <double>[0.28, 0.62]) {
      canvas.drawLine(
        Offset(0, size.height * y),
        Offset(size.width, size.height * (y + 0.12)),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LocationMapPatternPainter oldDelegate) {
    return lineColor != oldDelegate.lineColor ||
        accentColor != oldDelegate.accentColor;
  }
}

class _RichMemoEditor extends StatelessWidget {
  const _RichMemoEditor({
    required this.blocks,
    required this.strings,
    required this.pendingAttachmentCount,
    required this.onRemoveBlock,
    required this.onBackspaceAtParagraphStart,
    required this.onMoveBlock,
  });

  final List<_RichBlockDraft> blocks;
  final AppStrings strings;
  final int pendingAttachmentCount;
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
            strings: strings,
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
        for (var i = 0; i < pendingAttachmentCount; i++) ...[
          if (blocks.isNotEmpty || i > 0) const SizedBox(height: 8),
          const _AttachmentProcessingPlaceholder(),
        ],
      ],
    );
  }
}

class _RichBlockEditorTile extends StatelessWidget {
  const _RichBlockEditorTile({
    required this.block,
    required this.strings,
    this.emphasizeInput = false,
    required this.onRemove,
    required this.onBackspaceAtStart,
    required this.onMovePrevious,
    required this.onMoveNext,
    required this.canMovePrevious,
    required this.canMoveNext,
  });

  final _RichBlockDraft block;
  final AppStrings strings;
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
      final location = _tryParseLocationMemo(paragraphText);
      if (location != null) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Stack(
                children: [
                  _LocationMemoCard(location: location, strings: strings),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filledTonal(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: strings.removeBlock,
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
            ),
            const SizedBox(width: 6),
            _CompactMediaActionRail(
              canMovePrevious: canMovePrevious,
              canMoveNext: canMoveNext,
              onMovePrevious: onMovePrevious,
              onMoveNext: onMoveNext,
            ),
          ],
        );
      }
      final showPrompt = emphasizeInput && paragraphText.trim().isEmpty;
      return Container(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                scrollPadding: const EdgeInsets.only(
                  top: 96,
                  left: 20,
                  right: 20,
                  bottom: 96,
                ),
                decoration: InputDecoration(
                  semanticCounterText: '',
                  hintText: showPrompt ? strings.memoFirstLineHint : null,
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
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
        _AttachmentListTile(
          attachment: block.attachment!,
          showShareAction: false,
          trailingActionWidth: 88,
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton.filledTonal(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: strings.removeBlock,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
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
        ),
      ],
    );
  }
}

class _EditorModeButton extends StatelessWidget {
  const _EditorModeButton({required this.mode, required this.strings});

  final NoteEditorMode mode;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRich = mode == NoteEditorMode.rich;
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRich ? Icons.view_stream_outlined : Icons.notes_outlined,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isRich ? strings.richMemo : strings.quickMemo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.expand_more_rounded, size: 18, color: colorScheme.primary),
        ],
      ),
    );
  }
}

class _MediaMenuEntry extends StatelessWidget {
  const _MediaMenuEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
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
            tooltip: context.strings.moveEarlier,
          ),
          Divider(height: 1, thickness: 1, color: borderColor),
          _CompactMediaIconButton(
            onPressed: canMoveNext ? onMoveNext : null,
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: context.strings.moveLater,
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

class _QuickAttachmentSection extends StatefulWidget {
  const _QuickAttachmentSection({
    required this.strings,
    required this.attachments,
    required this.pendingAttachmentCount,
    required this.onRemove,
    required this.onMove,
  });

  final AppStrings strings;
  final List<NoteAttachment> attachments;
  final int pendingAttachmentCount;
  final ValueChanged<int> onRemove;
  final void Function(int index, int delta) onMove;

  @override
  State<_QuickAttachmentSection> createState() =>
      _QuickAttachmentSectionState();
}

class _QuickAttachmentSectionState extends State<_QuickAttachmentSection> {
  static const _collapsedAttachmentLimit = 8;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final attachments = widget.attachments;
    final shouldCollapse = attachments.length > _collapsedAttachmentLimit;
    final visibleCount = shouldCollapse && !_expanded
        ? _collapsedAttachmentLimit
        : attachments.length;

    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.attachments,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.localized(
              en: 'Use the camera or folder icons in the top right to add media.',
              ja: '右上のカメラ・フォルダアイコンからメディアを追加できます。',
              zh: '可通过右上角的相机或文件夹图标添加媒体。',
              ko: '오른쪽 위의 카메라・폴더 아이콘에서 미디어를 추가할 수 있습니다.',
              es: 'Usa los iconos de cámara o carpeta arriba a la derecha para añadir medios.',
              de: 'Über die Kamera- oder Ordner-Symbole oben rechts kannst du Medien hinzufügen.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
          if (attachments.isNotEmpty || widget.pendingAttachmentCount > 0) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < widget.pendingAttachmentCount; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _AttachmentProcessingPlaceholder(),
              ),
            for (var i = 0; i < visibleCount; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EditableAttachmentTile(
                  attachment: attachments[i],
                  onRemove: () => widget.onRemove(i),
                  onMovePrevious: i > 0 ? () => widget.onMove(i, -1) : null,
                  onMoveNext: i < attachments.length - 1
                      ? () => widget.onMove(i, 1)
                      : null,
                ),
              ),
            if (shouldCollapse)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(
                    _expanded
                        ? strings.localized(
                            en: 'Show fewer attachments',
                            ja: '添付を少なく表示',
                            zh: '显示较少附件',
                            ko: '첨부 파일 적게 표시',
                            es: 'Mostrar menos adjuntos',
                            de: 'Weniger Anhaenge anzeigen',
                          )
                        : strings.localized(
                            en: 'Show all ${attachments.length} attachments',
                            ja: '${attachments.length}件の添付をすべて表示',
                            zh: '显示全部 ${attachments.length} 个附件',
                            ko: '첨부 파일 ${attachments.length}개 모두 표시',
                            es: 'Mostrar los ${attachments.length} adjuntos',
                            de: 'Alle ${attachments.length} Anhaenge anzeigen',
                          ),
                  ),
                ),
              ),
          ],
        ],
      ),
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
        _AttachmentListTile(
          attachment: attachment,
          showShareAction: false,
          trailingActionWidth: 108,
        ),
        Positioned(
          top: 8,
          right: 0,
          child: Row(
            children: [
              IconButton(
                onPressed: onMovePrevious,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: context.strings.moveEarlier,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
              IconButton(
                onPressed: onMoveNext,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: context.strings.moveLater,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
                tooltip: context.strings.removeBlock,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttachmentProcessingPlaceholder extends StatelessWidget {
  const _AttachmentProcessingPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.26)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.strings.localized(
                    en: 'Preparing attachment',
                    ja: '添付を準備中',
                    zh: '正在准备附件',
                    ko: '첨부 준비 중',
                    es: 'Preparando adjunto',
                    de: 'Anhang wird vorbereitet',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.strings.localized(
                    en: 'Keep this screen open while HiMemo encrypts and saves the file.',
                    ja: 'ファイルの暗号化と保存が終わるまで、この画面を開いたままにしてください。',
                    zh: 'HiMemo 加密并保存文件时，请保持此画面打开。',
                    ko: 'HiMemo가 파일을 암호화하고 저장하는 동안 이 화면을 열어 두세요.',
                    es: 'Mantén esta pantalla abierta mientras HiMemo cifra y guarda el archivo.',
                    de: 'Lasse diesen Bildschirm offen, waehrend HiMemo die Datei verschluesselt und speichert.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
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

class _AttachmentListTile extends ConsumerWidget {
  const _AttachmentListTile({
    required this.attachment,
    this.showShareAction = true,
    this.trailingActionWidth = 0,
  });

  final NoteAttachment attachment;
  final bool showShareAction;
  final double trailingActionWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth &&
            constraints.maxWidth < 340 &&
            !showShareAction;
        final previewSize = compact ? 56.0 : 72.0;
        final previewGap = compact ? 8.0 : 12.0;
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
                    _AttachmentPreview(
                      attachment: attachment,
                      size: previewSize,
                    ),
                    SizedBox(width: previewGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attachment.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _attachmentDescription(context, attachment),
                            maxLines: compact ? 1 : null,
                            overflow: compact ? TextOverflow.ellipsis : null,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _mutedTextColor(context)),
                          ),
                          const SizedBox(height: 2),
                          _AttachmentSizeText(attachment: attachment),
                        ],
                      ),
                    ),
                    if (showShareAction)
                      IconButton(
                        onPressed: () =>
                            _shareAttachment(context, ref, attachment),
                        icon: const Icon(Icons.share_outlined),
                        tooltip: context.strings.share,
                      )
                    else if (trailingActionWidth > 0)
                      SizedBox(width: trailingActionWidth),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _shareAttachment(
  BuildContext context,
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final strings = context.strings;
  final filePath = attachment.filePath;
  if (filePath == null || filePath.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(strings.unableToShareAttachment),
      ),
    );
    return;
  }

  final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
  try {
    if (kIsWeb) {
      final bytes = await attachmentStore.readAttachment(
        filePath,
        type: attachment.type,
      );
      if (bytes == null || bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              showCloseIcon: true,
              content: Text(strings.unableToDecryptAttachment),
            ),
          );
        }
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: attachment.label,
              mimeType: _mimeTypeForAttachment(attachment),
            ),
          ],
          text: attachment.label,
        ),
      );
      return;
    }

    final tempFilePath = await attachmentStore.materializeDecryptedFile(
      filePath,
      type: attachment.type,
      preferredFileName: attachment.label,
    );
    if (tempFilePath == null || tempFilePath.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            content: Text(strings.unableToDecryptAttachment),
          ),
        );
      }
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              tempFilePath,
              name: attachment.label,
              mimeType: _mimeTypeForAttachment(attachment),
            ),
          ],
          text: attachment.label,
        ),
      );
    } finally {
      await _markSharedAttachmentForCleanup(attachmentStore, tempFilePath);
    }
  } on HimemoDecryptionException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(strings.unableToDecryptAttachment),
        ),
      );
    }
  }
}

Future<void> _markSharedAttachmentForCleanup(
  EncryptedAttachmentStore attachmentStore,
  String tempFilePath,
) async {
  try {
    await attachmentStore.markMaterializedFileForCleanup(
      tempFilePath,
      deleteAfter: DateTime.now().add(_sharedAttachmentCleanupDelay),
    );
  } catch (_) {}
}

const _sharedAttachmentCleanupDelay = Duration(hours: 24);

String _mimeTypeForAttachment(NoteAttachment attachment) {
  return switch (attachment.type) {
    AttachmentType.photo => _mimeTypeForPhotoAttachment(attachment),
    AttachmentType.video => _mimeTypeForVideoAttachment(attachment),
    AttachmentType.audio => _mimeTypeForAudioAttachment(attachment),
    AttachmentType.file => _mimeTypeForFileAttachment(attachment),
  };
}

String _mimeTypeForPhotoAttachment(NoteAttachment attachment) {
  final label = attachment.label.toLowerCase();
  if (label.endsWith('.png')) {
    return 'image/png';
  }
  if (label.endsWith('.gif')) {
    return 'image/gif';
  }
  if (label.endsWith('.webp')) {
    return 'image/webp';
  }
  if (label.endsWith('.heic')) {
    return 'image/heic';
  }
  if (label.endsWith('.heif')) {
    return 'image/heif';
  }
  return 'image/jpeg';
}

String _mimeTypeForFileAttachment(NoteAttachment attachment) {
  final label = attachment.label.toLowerCase();
  if (label.endsWith('.pdf')) {
    return 'application/pdf';
  }
  if (label.endsWith('.txt') || label.endsWith('.md')) {
    return 'text/plain';
  }
  if (label.endsWith('.csv')) {
    return 'text/csv';
  }
  if (label.endsWith('.json')) {
    return 'application/json';
  }
  if (label.endsWith('.zip')) {
    return 'application/zip';
  }
  return 'application/octet-stream';
}

class _EmbeddedAttachmentBlock extends ConsumerWidget {
  const _EmbeddedAttachmentBlock({
    required this.attachment,
    required this.mediaActive,
    this.photoAttachments = const [],
    this.photoIndex,
  });

  final NoteAttachment attachment;
  final bool mediaActive;
  final List<NoteAttachment> photoAttachments;
  final int? photoIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (attachment.type) {
      case AttachmentType.photo:
        return _EmbeddedPhotoAttachment(
          attachment: attachment,
          mediaActive: mediaActive,
          photoAttachments: photoAttachments,
          photoIndex: photoIndex,
        );
      case AttachmentType.video:
        return SizedBox(
          height: 260,
          child: _VideoAttachmentViewer(
            attachment: attachment,
            onOpenFullScreen: () =>
                _openAttachmentViewer(context, ref, attachment),
          ),
        );
      case AttachmentType.audio:
        return SizedBox(
          height: 180,
          child: _AudioAttachmentViewer(attachment: attachment),
        );
      case AttachmentType.file:
        return _EmbeddedFileAttachment(attachment: attachment);
    }
  }
}

class _EmbeddedFileAttachment extends ConsumerWidget {
  const _EmbeddedFileAttachment({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AttachmentListTile(attachment: attachment);
  }
}

class _EmbeddedPhotoAttachment extends ConsumerStatefulWidget {
  const _EmbeddedPhotoAttachment({
    required this.attachment,
    required this.mediaActive,
    this.photoAttachments = const [],
    this.photoIndex,
  });

  final NoteAttachment attachment;
  final bool mediaActive;
  final List<NoteAttachment> photoAttachments;
  final int? photoIndex;

  @override
  ConsumerState<_EmbeddedPhotoAttachment> createState() =>
      _EmbeddedPhotoAttachmentState();
}

class _EmbeddedPhotoAttachmentState
    extends ConsumerState<_EmbeddedPhotoAttachment> {
  Future<List<int>?>? _imageBytesFuture;

  @override
  void didUpdateWidget(covariant _EmbeddedPhotoAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attachmentCacheKey(oldWidget.attachment) !=
        _attachmentCacheKey(widget.attachment)) {
      _imageBytesFuture = null;
    }
  }

  Future<List<int>?> _ensureImageBytesFuture() {
    return _imageBytesFuture ??= _readPhotoAttachmentBytesWithPerf(
      ref,
      widget.attachment,
      source: 'detail',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.mediaActive) {
      return _InactivePhotoAttachmentPreview(label: widget.attachment.label);
    }
    return FutureBuilder<List<int>?>(
      future: _ensureImageBytesFuture(),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (bytes == null || bytes.isEmpty) {
          return SizedBox(
            height: 180,
            child: Center(child: Text(context.strings.unableToLoadImage)),
          );
        }
        return InkWell(
          onTap: () => _openAttachmentViewer(
            context,
            ref,
            widget.attachment,
            photoAttachments: widget.photoAttachments,
            initialPhotoIndex: widget.photoIndex,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) {
                    _logAttachmentDisplayDiagnostic(
                      widget.attachment,
                      'image decode failed',
                      source: 'detail',
                      data: {'error': error, 'bytes': bytes.length},
                    );
                    return const _AttachmentImageErrorPanel(height: 180);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InactivePhotoAttachmentPreview extends StatelessWidget {
  const _InactivePhotoAttachmentPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Icon(
        Icons.image_outlined,
        color: _mutedTextColor(context),
        semanticLabel: label,
      ),
    );
  }
}

class _AttachmentPreview extends ConsumerStatefulWidget {
  const _AttachmentPreview({required this.attachment, this.size = 72});

  final NoteAttachment attachment;
  final double size;

  @override
  ConsumerState<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends ConsumerState<_AttachmentPreview> {
  Future<List<int>?>? _bytesFuture;
  String? _futureFilePath;
  Uint8List? _previewBytes;
  String? _previewBytesBase64;

  @override
  void didUpdateWidget(covariant _AttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.filePath != widget.attachment.filePath ||
        oldWidget.attachment.type != widget.attachment.type ||
        oldWidget.attachment.previewBytesBase64 !=
            widget.attachment.previewBytesBase64) {
      _bytesFuture = null;
      _futureFilePath = null;
      _previewBytes = null;
      _previewBytesBase64 = null;
    }
  }

  Future<List<int>?> _attachmentBytesFuture(String filePath) {
    if (_bytesFuture != null && _futureFilePath == filePath) {
      return _bytesFuture!;
    }
    _futureFilePath = filePath;
    return _bytesFuture = _readPhotoAttachmentBytesWithPerf(
      ref,
      widget.attachment,
      source: 'attachment preview',
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final size = widget.size;
    final previewBytesBase64 = attachment.previewBytesBase64;
    if (previewBytesBase64 != null && previewBytesBase64.isNotEmpty) {
      final bytes = _decodePreviewBytes();
      if (attachment.type == AttachmentType.video) {
        return _AttachmentVideoImageBox(bytes: bytes, size: size);
      }
      return _AttachmentImageBox(
        bytes: bytes,
        size: size,
        attachment: attachment,
        diagnosticSource: 'preview',
      );
    }

    if (attachment.type != AttachmentType.photo) {
      return _AttachmentIconBox(type: attachment.type, size: size);
    }

    final filePath = attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      return _AttachmentIconBox(type: attachment.type, size: size);
    }

    return FutureBuilder<List<int>?>(
      future: _attachmentBytesFuture(filePath),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _AttachmentIconBox(type: attachment.type, size: size);
        }
        return _AttachmentImageBox(
          bytes: Uint8List.fromList(bytes),
          size: size,
          attachment: attachment,
          diagnosticSource: 'attachment preview',
        );
      },
    );
  }

  Uint8List _decodePreviewBytes() {
    final encoded = widget.attachment.previewBytesBase64!;
    if (_previewBytes != null && _previewBytesBase64 == encoded) {
      return _previewBytes!;
    }
    _previewBytesBase64 = encoded;
    try {
      return _previewBytes = base64Decode(encoded);
    } on FormatException catch (error) {
      _logAttachmentDisplayDiagnostic(
        widget.attachment,
        'inline preview bytes decode failed',
        source: 'attachment preview',
        data: {'error': error},
      );
      return _previewBytes = Uint8List(0);
    }
  }
}

class _AttachmentImageBox extends StatelessWidget {
  const _AttachmentImageBox({
    required this.bytes,
    this.size = 72,
    this.attachment,
    this.diagnosticSource,
  });

  final Uint8List bytes;
  final double size;
  final NoteAttachment? attachment;
  final String? diagnosticSource;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final imageCacheHeight = (size * pixelRatio).round().clamp(1, 4096);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: size * 1.6, maxHeight: size),
        child: Image.memory(
          bytes,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheHeight: imageCacheHeight,
          errorBuilder: (context, error, stackTrace) {
            final attachment = this.attachment;
            if (attachment != null) {
              _logAttachmentDisplayDiagnostic(
                attachment,
                'image decode failed',
                source: diagnosticSource ?? 'attachment image',
                data: {
                  'error': error,
                  'bytes': bytes.length,
                  ..._attachmentByteDiagnosticData(bytes),
                },
              );
            }
            return _AttachmentImageErrorBox(size: size);
          },
        ),
      ),
    );
  }
}

class _AttachmentImageErrorPanel extends StatelessWidget {
  const _AttachmentImageErrorPanel({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(child: _AttachmentImageErrorBox(size: 72)),
    );
  }
}

class _AttachmentImageErrorBox extends StatelessWidget {
  const _AttachmentImageErrorBox({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Icon(
          Icons.broken_image_outlined,
          size: size * 0.42,
          color: _mutedTextColor(context),
        ),
      ),
    );
  }
}

class _NoteListAttachmentPreview extends StatelessWidget {
  const _NoteListAttachmentPreview({
    required this.attachment,
    required this.size,
    required this.previewFit,
  });

  final NoteAttachment attachment;
  final double size;
  final AttachmentPreviewFit previewFit;

  @override
  Widget build(BuildContext context) {
    if (previewFit == AttachmentPreviewFit.icon) {
      return _AttachmentIconBox(type: attachment.type, size: size);
    }
    return _AttachmentPreview(attachment: attachment, size: size);
  }
}

class _AttachmentVideoImageBox extends StatelessWidget {
  const _AttachmentVideoImageBox({required this.bytes, this.size = 72});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _AttachmentImageBox(bytes: bytes, size: size),
        Container(
          width: size * 0.42,
          height: size * 0.42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.52),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: size * 0.28,
          ),
        ),
      ],
    );
  }
}

class _AttachmentIconBox extends StatelessWidget {
  const _AttachmentIconBox({required this.type, this.size = 72});

  final AttachmentType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Icon(
        _iconForAttachment(type),
        size: size * 0.42,
        color: scheme.primary,
      ),
    );
  }
}

String _attachmentDescription(BuildContext context, NoteAttachment attachment) {
  final strings = context.strings;
  switch (attachment.type) {
    case AttachmentType.photo:
      return attachment.filePath == null
          ? strings.photoPlaceholder
          : strings.tapToViewPhoto;
    case AttachmentType.video:
      return attachment.filePath == null
          ? strings.videoPlaceholder
          : strings.tapToPlayVideo;
    case AttachmentType.audio:
      return attachment.filePath == null
          ? strings.audioPlaceholder
          : strings.tapToPlayAudio;
    case AttachmentType.file:
      return attachment.filePath == null
          ? strings.filePlaceholder
          : strings.tapToOpenFile;
  }
}

class _AttachmentSizeText extends ConsumerStatefulWidget {
  const _AttachmentSizeText({required this.attachment});

  final NoteAttachment attachment;

  @override
  ConsumerState<_AttachmentSizeText> createState() =>
      _AttachmentSizeTextState();
}

class _AttachmentSizeTextState extends ConsumerState<_AttachmentSizeText> {
  Future<int?>? _sizeFuture;
  String? _futureKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _primeFutureIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _AttachmentSizeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _primeFutureIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final future = _sizeFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<int?>(
      future: future,
      builder: (context, snapshot) {
        final sizeBytes = snapshot.data;
        if (sizeBytes == null || sizeBytes <= 0) {
          return const SizedBox.shrink();
        }
        return Text(
          context.strings.byteCount(sizeBytes),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: _mutedTextColor(context)),
        );
      },
    );
  }

  void _primeFutureIfNeeded() {
    final filePath = widget.attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      _futureKey = null;
      _sizeFuture = null;
      return;
    }
    final key = '${widget.attachment.type.name}:$filePath';
    if (_futureKey == key && _sizeFuture != null) {
      return;
    }
    _futureKey = key;
    _sizeFuture = _resolveAttachmentSize();
  }

  Future<int?> _resolveAttachmentSize() async {
    final filePath = widget.attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      return null;
    }
    if (isSyncAttachmentObjectRef(filePath)) {
      final bytes = await _readDisplayAttachmentBytes(ref, widget.attachment);
      return bytes?.length;
    }
    return ref
        .read(encryptedAttachmentStoreProvider)
        .attachmentByteLength(filePath, type: widget.attachment.type);
  }
}

Future<int?> _attachmentSizeFuture(
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final filePath = attachment.filePath;
  if (filePath == null || filePath.isEmpty) {
    return null;
  }
  if (isSyncAttachmentObjectRef(filePath)) {
    final bytes = await _readDisplayAttachmentBytes(ref, attachment);
    return bytes?.length;
  }
  return ref
      .read(encryptedAttachmentStoreProvider)
      .attachmentByteLength(filePath, type: attachment.type);
}

String? _attachmentSizeLabel(BuildContext context, int? sizeBytes) {
  if (sizeBytes == null || sizeBytes <= 0) {
    return null;
  }
  return context.strings.byteCount(sizeBytes);
}

String _videoMuteTooltip(bool muted) => muted ? 'Unmute video' : 'Mute video';
