part of 'home_page.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      ref
          .read(notesControllerProvider.notifier)
          .purgeTrashOlderThan(NotesController.trashRetention);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final notes = ref.watch(trashedNotesProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final vaultNameById = {
      for (final vault in visibleVaults)
        vault.id: _vaultDisplayName(context, vault),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.localized(
            en: 'Trash',
            ja: 'ゴミ箱',
            zh: '废纸篓',
            ko: '휴지통',
            es: 'Papelera',
            de: 'Papierkorb',
          ),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          strings.localized(
            en: 'Deleted notes are hidden from normal lists, search, and Spotlight. Notes older than 7 days are permanently deleted with their attachments.',
            ja: '削除したメモは通常の一覧、検索、Spotlightから除外されます。7日を過ぎたメモは添付と一緒に完全削除されます。',
            zh: '已删除的备忘录不会出现在普通列表、搜索和 Spotlight 中。超过 7 天的备忘录及其附件会被永久删除。',
            ko: '삭제한 메모는 일반 목록, 검색, Spotlight에서 제외됩니다. 7일이 지난 메모는 첨부와 함께 완전히 삭제됩니다.',
            es: 'Las notas eliminadas se ocultan de las listas normales, busqueda y Spotlight. Tras 7 dias se borran definitivamente con sus adjuntos.',
            de: 'Geloeschte Notizen werden aus normalen Listen, Suche und Spotlight ausgeblendet. Nach 7 Tagen werden sie mit ihren Anhaengen endgueltig geloescht.',
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          _EmptyTrashState(strings: strings)
        else
          for (final note in notes) ...[
            _TrashNoteTile(
              note: note,
              vaultName: vaultNameById[note.vaultId],
              onRestore: () => _restoreNote(context, note),
              onDeletePermanently: () => _deletePermanently(context, note),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _restoreNote(BuildContext context, NoteEntry note) async {
    final strings = context.strings;
    await ref.read(notesControllerProvider.notifier).restoreFromTrash(note.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Restored note.',
            ja: 'メモを復元しました。',
            zh: '已恢复备忘录。',
            ko: '메모를 복원했습니다.',
            es: 'Nota restaurada.',
            de: 'Notiz wiederhergestellt.',
          ),
        ),
      ),
    );
  }

  Future<void> _deletePermanently(BuildContext context, NoteEntry note) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.localized(
            en: 'Delete permanently?',
            ja: '完全に削除しますか？',
            zh: '要永久删除吗？',
            ko: '완전히 삭제할까요?',
            es: 'Borrar definitivamente?',
            de: 'Endgueltig loeschen?',
          ),
        ),
        content: Text(
          strings.localized(
            en: 'This removes the note and its attachments from this device. This cannot be undone.',
            ja: 'この端末からメモと添付を削除します。この操作は元に戻せません。',
            zh: '这会从此设备删除备忘录及其附件。此操作无法撤销。',
            ko: '이 기기에서 메모와 첨부를 삭제합니다. 이 작업은 되돌릴 수 없습니다.',
            es: 'Esto elimina la nota y sus adjuntos de este dispositivo. No se puede deshacer.',
            de: 'Dies entfernt die Notiz und ihre Anhaenge von diesem Geraet. Das kann nicht rueckgaengig gemacht werden.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(notesControllerProvider.notifier).deletePermanently(note.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Deleted permanently.',
            ja: '完全に削除しました。',
            zh: '已永久删除。',
            ko: '완전히 삭제했습니다.',
            es: 'Borrada definitivamente.',
            de: 'Endgueltig geloescht.',
          ),
        ),
      ),
    );
  }
}
