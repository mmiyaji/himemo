part of 'home_page.dart';

class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  static const tagSearchKey = Key('tag-management-search');

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final summaries = ref.watch(visibleTagSummariesProvider);
    final queryKey = canonicalizeNoteTag(_query);
    final filtered = queryKey.isEmpty
        ? summaries
        : summaries
              .where(
                (summary) => canonicalizeNoteTag(
                  _displayNoteTag(context, summary.name),
                ).contains(queryKey),
              )
              .toList(growable: false);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          sliver: SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tagManagementTitle(strings),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.localized(
                      en: 'Rename or delete tags used by visible notes.',
                      ja: '\u8868\u793a\u4e2d\u306e\u30e1\u30e2\u3067\u4f7f\u3063\u3066\u3044\u308b\u30bf\u30b0\u3092\u30ea\u30cd\u30fc\u30e0\u30fb\u524a\u9664\u3057\u307e\u3059\u3002',
                      zh: '\u91cd\u547d\u540d\u6216\u5220\u9664\u53ef\u89c1\u7b14\u8bb0\u4f7f\u7528\u7684\u6807\u7b7e\u3002',
                      ko: '\ud45c\uc2dc \uc911\uc778 \uba54\ubaa8\uc758 \ud0dc\uadf8\ub97c \uc774\ub984 \ubcc0\uacbd \ub610\ub294 \uc0ad\uc81c\ud569\ub2c8\ub2e4.',
                      es: 'Renombra o elimina etiquetas usadas por las notas visibles.',
                      de: 'Tags sichtbarer Notizen umbenennen oder loeschen.',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: TagsScreen.tagSearchKey,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: strings.localized(
                                en: 'Clear search',
                                ja: '\u691c\u7d22\u3092\u30af\u30ea\u30a2',
                                zh: '\u6e05\u9664\u641c\u7d22',
                                ko: '\uac80\uc0c9 \uc9c0\uc6b0\uae30',
                                es: 'Borrar busqueda',
                                de: 'Suche loeschen',
                              ),
                              onPressed: () => setState(() => _query = ''),
                              icon: const Icon(Icons.close_rounded),
                            ),
                      labelText: strings.localized(
                        en: 'Search tags',
                        ja: '\u30bf\u30b0\u3092\u691c\u7d22',
                        zh: '\u641c\u7d22\u6807\u7b7e',
                        ko: '\ud0dc\uadf8 \uac80\uc0c9',
                        es: 'Buscar etiquetas',
                        de: 'Tags suchen',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (summaries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _TagsEmptyState(
              strings: strings,
              description: strings.localized(
                en: 'Tags appear here after you add them to notes.',
                ja: '\u30e1\u30e2\u306b\u30bf\u30b0\u3092\u8ffd\u52a0\u3059\u308b\u3068\u3053\u3053\u306b\u8868\u793a\u3055\u308c\u307e\u3059\u3002',
                zh: '\u5c06\u6807\u7b7e\u6dfb\u52a0\u5230\u7b14\u8bb0\u540e\uff0c\u5b83\u4eec\u4f1a\u663e\u793a\u5728\u8fd9\u91cc\u3002',
                ko: '\uba54\ubaa8\uc5d0 \ud0dc\uadf8\ub97c \ucd94\uac00\ud558\uba74 \uc5ec\uae30\uc5d0 \ud45c\uc2dc\ub429\ub2c8\ub2e4.',
                es: 'Las etiquetas apareceran aqui cuando las anadas a notas.',
                de: 'Tags erscheinen hier, nachdem du sie Notizen hinzugefuegt hast.',
              ),
              actionLabel: strings.addNote,
              onAction: () => showNoteEditorSheet(context, ref),
            ),
          )
        else if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _TagsEmptyState(
              strings: strings,
              title: strings.localized(
                en: 'No matching tags',
                ja: '\u4e00\u81f4\u3059\u308b\u30bf\u30b0\u306f\u3042\u308a\u307e\u305b\u3093',
                zh: '\u6ca1\u6709\u5339\u914d\u7684\u6807\u7b7e',
                ko: '\uc77c\uce58\ud558\ub294 \ud0dc\uadf8\uac00 \uc5c6\uc2b5\ub2c8\ub2e4',
                es: 'No hay etiquetas coincidentes',
                de: 'Keine passenden Tags',
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  children: [
                    for (var index = 0; index < filtered.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _TagManagementTile(
                        summary: filtered[index],
                        onOpen: () => _openTag(context, filtered[index].name),
                        onRename: isSystemSyncExclusionTag(filtered[index].name)
                            ? null
                            : () => _renameTag(context, filtered[index]),
                        onDelete: isSystemSyncExclusionTag(filtered[index].name)
                            ? null
                            : () => _deleteTag(context, filtered[index]),
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

  void _openTag(BuildContext context, String tag) {
    ref.read(searchFiltersControllerProvider.notifier).setTags([tag]);
    ref.read(searchQueryProvider.notifier).setQuery('');
    ref.read(selectedNoteIdProvider.notifier).select(null);
    context.go('/notes');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        duration: const Duration(seconds: 2),
        content: Text(
          context.strings.tagFilterApplied(_displayNoteTag(context, tag)),
        ),
      ),
    );
  }

  Future<void> _renameTag(
    BuildContext context,
    VisibleTagSummary summary,
  ) async {
    final strings = context.strings;
    final renamed = await _showRenameTagDialog(context, summary.name);
    if (renamed == null || !mounted) {
      return;
    }
    final count = await ref
        .read(notesControllerProvider.notifier)
        .renameTag(
          from: summary.name,
          to: renamed,
          vaultIds: _visibleVaultIds(),
        );
    if (!context.mounted) {
      return;
    }
    if (count > 0) {
      _replaceActiveFilterTag(summary.name, renamed);
    }
    _showTagSnackBar(
      context,
      strings.localized(
        en: count == 1 ? 'Renamed 1 note.' : 'Renamed $count notes.',
        ja: '$count\u4ef6\u306e\u30e1\u30e2\u306e\u30bf\u30b0\u3092\u5909\u66f4\u3057\u307e\u3057\u305f\u3002',
        zh: '\u5df2\u91cd\u547d\u540d $count \u6761\u7b14\u8bb0\u7684\u6807\u7b7e\u3002',
        ko: '$count\uac1c \uba54\ubaa8\uc758 \ud0dc\uadf8 \uc774\ub984\uc744 \ubcc0\uacbd\ud588\uc2b5\ub2c8\ub2e4.',
        es: count == 1 ? 'Se renombro 1 nota.' : 'Se renombraron $count notas.',
        de: count == 1 ? '1 Notiz umbenannt.' : '$count Notizen umbenannt.',
      ),
    );
  }

  Future<void> _deleteTag(
    BuildContext context,
    VisibleTagSummary summary,
  ) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.localized(
            en: 'Delete tag',
            ja: '\u30bf\u30b0\u3092\u524a\u9664',
            zh: '\u5220\u9664\u6807\u7b7e',
            ko: '\ud0dc\uadf8 \uc0ad\uc81c',
            es: 'Eliminar etiqueta',
            de: 'Tag loeschen',
          ),
        ),
        content: Text(
          strings.localized(
            en: 'Remove "${_displayNoteTag(context, summary.name)}" from ${summary.count} notes?',
            ja: '\u300c${_displayNoteTag(context, summary.name)}\u300d\u3092${summary.count}\u4ef6\u306e\u30e1\u30e2\u304b\u3089\u5916\u3057\u307e\u3059\u304b\uff1f',
            zh: '\u4ece ${summary.count} \u6761\u7b14\u8bb0\u4e2d\u79fb\u9664\u201c${_displayNoteTag(context, summary.name)}\u201d\uff1f',
            ko: '${summary.count}\uac1c \uba54\ubaa8\uc5d0\uc11c "${_displayNoteTag(context, summary.name)}" \ud0dc\uadf8\ub97c \uc81c\uac70\ud560\uae4c\uc694?',
            es: 'Quitar "${_displayNoteTag(context, summary.name)}" de ${summary.count} notas?',
            de: '"${_displayNoteTag(context, summary.name)}" aus ${summary.count} Notizen entfernen?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final count = await ref
        .read(notesControllerProvider.notifier)
        .deleteTag(summary.name, vaultIds: _visibleVaultIds());
    if (!context.mounted) {
      return;
    }
    if (count > 0) {
      ref
          .read(searchFiltersControllerProvider.notifier)
          .removeTag(summary.name);
    }
    _showTagSnackBar(
      context,
      strings.localized(
        en: count == 1 ? 'Removed from 1 note.' : 'Removed from $count notes.',
        ja: '$count\u4ef6\u306e\u30e1\u30e2\u304b\u3089\u30bf\u30b0\u3092\u5916\u3057\u307e\u3057\u305f\u3002',
        zh: '\u5df2\u4ece $count \u6761\u7b14\u8bb0\u4e2d\u79fb\u9664\u6807\u7b7e\u3002',
        ko: '$count\uac1c \uba54\ubaa8\uc5d0\uc11c \ud0dc\uadf8\ub97c \uc81c\uac70\ud588\uc2b5\ub2c8\ub2e4.',
        es: count == 1 ? 'Quitada de 1 nota.' : 'Quitada de $count notas.',
        de: count == 1
            ? 'Aus 1 Notiz entfernt.'
            : 'Aus $count Notizen entfernt.',
      ),
    );
  }

  void _replaceActiveFilterTag(String oldTag, String newTag) {
    final filters = ref.read(searchFiltersControllerProvider);
    final oldKey = canonicalizeNoteTag(oldTag);
    if (!filters.tags.any((tag) => canonicalizeNoteTag(tag) == oldKey)) {
      return;
    }
    ref.read(searchFiltersControllerProvider.notifier).setTags([
      for (final tag in filters.tags)
        if (canonicalizeNoteTag(tag) == oldKey) newTag else tag,
    ]);
  }

  Set<String> _visibleVaultIds() {
    return {for (final vault in ref.read(visibleVaultsProvider)) vault.id};
  }

  Future<String?> _showRenameTagDialog(
    BuildContext context,
    String currentTag,
  ) {
    final strings = context.strings;
    final controller = TextEditingController(text: currentTag);
    String? errorText;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final normalized = normalizeNoteTag(controller.text);
            if (normalized.isEmpty) {
              setDialogState(() {
                errorText = strings.localized(
                  en: 'Enter a tag name.',
                  ja: '\u30bf\u30b0\u540d\u3092\u5165\u529b\u3057\u3066\u304f\u3060\u3055\u3044\u3002',
                  zh: '\u8bf7\u8f93\u5165\u6807\u7b7e\u540d\u3002',
                  ko: '\ud0dc\uadf8 \uc774\ub984\uc744 \uc785\ub825\ud558\uc138\uc694.',
                  es: 'Introduce un nombre de etiqueta.',
                  de: 'Tag-Namen eingeben.',
                );
              });
              return;
            }
            if (isSystemSyncExclusionTag(normalized)) {
              setDialogState(() {
                errorText = strings.localized(
                  en: 'This tag is reserved by the app.',
                  ja: '\u3053\u306e\u30bf\u30b0\u540d\u306f\u30a2\u30d7\u30ea\u304c\u4f7f\u7528\u3057\u3066\u3044\u307e\u3059\u3002',
                  zh: '\u6b64\u6807\u7b7e\u540d\u7531\u5e94\u7528\u4fdd\u7559\u3002',
                  ko: '\uc774 \ud0dc\uadf8 \uc774\ub984\uc740 \uc571\uc5d0\uc11c \uc0ac\uc6a9 \uc911\uc785\ub2c8\ub2e4.',
                  es: 'Esta etiqueta esta reservada por la app.',
                  de: 'Dieser Tag ist von der App reserviert.',
                );
              });
              return;
            }
            Navigator.of(context).pop(normalized);
          }

          return AlertDialog(
            title: Text(
              strings.localized(
                en: 'Rename tag',
                ja: '\u30bf\u30b0\u3092\u30ea\u30cd\u30fc\u30e0',
                zh: '\u91cd\u547d\u540d\u6807\u7b7e',
                ko: '\ud0dc\uadf8 \uc774\ub984 \ubcc0\uacbd',
                es: 'Renombrar etiqueta',
                de: 'Tag umbenennen',
              ),
            ),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: InputDecoration(
                labelText: strings.localized(
                  en: 'Tag name',
                  ja: '\u30bf\u30b0\u540d',
                  zh: '\u6807\u7b7e\u540d',
                  ko: '\ud0dc\uadf8 \uc774\ub984',
                  es: 'Nombre de etiqueta',
                  de: 'Tag-Name',
                ),
                errorText: errorText,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(strings.save)),
            ],
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  void _showTagSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
  }
}

class _TagManagementTile extends StatelessWidget {
  const _TagManagementTile({
    required this.summary,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final VisibleTagSummary summary;
  final VoidCallback onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final systemTag = isSystemSyncExclusionTag(summary.name);
    final label = _displayNoteTag(context, summary.name);
    return DecoratedBox(
      decoration: _sectionDecoration(context),
      child: ListTile(
        key: Key('tag-management-${canonicalizeNoteTag(summary.name)}'),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Icon(
            systemTag ? Icons.lock_outline_rounded : Icons.tag_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          strings.localized(
            en: '${summary.count} notes / Latest ${_formatDateTime(summary.latestAt, strings)}',
            ja: '${summary.count}\u4ef6\u306e\u30e1\u30e2 / \u6700\u7d42 ${_formatDateTime(summary.latestAt, strings)}',
            zh: '${summary.count} \u6761\u7b14\u8bb0 / \u6700\u65b0 ${_formatDateTime(summary.latestAt, strings)}',
            ko: '${summary.count}\uac1c \uba54\ubaa8 / \ucd5c\uc2e0 ${_formatDateTime(summary.latestAt, strings)}',
            es: '${summary.count} notas / Ultima ${_formatDateTime(summary.latestAt, strings)}',
            de: '${summary.count} Notizen / Zuletzt ${_formatDateTime(summary.latestAt, strings)}',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: _mutedTextColor(context),
          ),
        ),
        onTap: onOpen,
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: strings.localized(
                en: 'Open tagged notes',
                ja: '\u3053\u306e\u30bf\u30b0\u306e\u30e1\u30e2\u3092\u958b\u304f',
                zh: '\u6253\u5f00\u6b64\u6807\u7b7e\u7684\u7b14\u8bb0',
                ko: '\uc774 \ud0dc\uadf8\uc758 \uba54\ubaa8 \uc5f4\uae30',
                es: 'Abrir notas con esta etiqueta',
                de: 'Notizen mit diesem Tag oeffnen',
              ),
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
            IconButton(
              key: Key('tag-rename-${canonicalizeNoteTag(summary.name)}'),
              tooltip: strings.localized(
                en: 'Rename',
                ja: '\u30ea\u30cd\u30fc\u30e0',
                zh: '\u91cd\u547d\u540d',
                ko: '\uc774\ub984 \ubcc0\uacbd',
                es: 'Renombrar',
                de: 'Umbenennen',
              ),
              onPressed: onRename,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              key: Key('tag-delete-${canonicalizeNoteTag(summary.name)}'),
              tooltip: strings.delete,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagsEmptyState extends StatelessWidget {
  const _TagsEmptyState({
    required this.strings,
    this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  final AppStrings strings;
  final String? title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sell_outlined,
              size: 48,
              color: _mutedTextColor(context),
            ),
            const SizedBox(height: 12),
            Text(
              title ??
                  strings.localized(
                    en: 'No tags yet',
                    ja: '\u30bf\u30b0\u306f\u307e\u3060\u3042\u308a\u307e\u305b\u3093',
                    zh: '\u5c1a\u65e0\u6807\u7b7e',
                    ko: '\uc544\uc9c1 \ud0dc\uadf8\uac00 \uc5c6\uc2b5\ub2c8\ub2e4',
                    es: 'Aun no hay etiquetas',
                    de: 'Noch keine Tags',
                  ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (description case final description?) ...[
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ],
            if (actionLabel case final actionLabel?) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _tagManagementTitle(AppStrings strings) {
  return strings.localized(
    en: 'Tags',
    ja: '\u30bf\u30b0',
    zh: '\u6807\u7b7e',
    ko: '\ud0dc\uadf8',
    es: 'Etiquetas',
    de: 'Tags',
  );
}
