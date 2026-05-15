part of 'home_page.dart';

class _EmptyTrashState extends StatelessWidget {
  const _EmptyTrashState({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.delete_outline_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            strings.localized(
              en: 'Trash is empty',
              ja: 'ゴミ箱は空です',
              zh: '废纸篓是空的',
              ko: '휴지통이 비어 있습니다',
              es: 'La papelera esta vacia',
              de: 'Der Papierkorb ist leer',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _TrashNoteTile extends StatelessWidget {
  const _TrashNoteTile({
    required this.note,
    required this.vaultName,
    required this.onRestore,
    required this.onDeletePermanently,
  });

  final NoteEntry note;
  final String? vaultName;
  final VoidCallback onRestore;
  final VoidCallback onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final deletedAt = note.deletedAt?.toLocal();
    final title = note.title.trim().isEmpty
        ? strings.localized(
            en: 'Untitled note',
            ja: '無題のメモ',
            zh: '无标题备忘录',
            ko: '제목 없는 메모',
            es: 'Nota sin titulo',
            de: 'Unbenannte Notiz',
          )
        : note.title.trim();
    final body = note.body.trim();
    return DecoratedBox(
      decoration: _sectionDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (note.attachments.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.attach_file_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  Text('${note.attachments.length}'),
                ],
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (deletedAt != null)
                  _TrashMetaChip(
                    icon: Icons.schedule_rounded,
                    label: strings.localized(
                      en: 'Deleted ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      ja: '削除 ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      zh: '删除 ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      ko: '삭제 ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      es: 'Borrada ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                      de: 'Geloescht ${deletedAt.year}/${deletedAt.month.toString().padLeft(2, '0')}/${deletedAt.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                if (vaultName != null)
                  _TrashMetaChip(
                    icon: Icons.folder_outlined,
                    label: vaultName!,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(
                    strings.localized(
                      en: 'Restore',
                      ja: '復元',
                      zh: '恢复',
                      ko: '복원',
                      es: 'Restaurar',
                      de: 'Wiederherstellen',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDeletePermanently,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    strings.localized(
                      en: 'Delete',
                      ja: '削除',
                      zh: '删除',
                      ko: '삭제',
                      es: 'Borrar',
                      de: 'Loeschen',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashMetaChip extends StatelessWidget {
  const _TrashMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
