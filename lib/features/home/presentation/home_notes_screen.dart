part of 'home_page.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  static const double _defaultSplitListFraction = 5 / 11;
  static const double _narrowSplitListFraction = 0.36;
  static const double _wideSplitListFraction = 0.58;
  static const double _minSplitListWidth = 320;
  static const double _maxSplitListFraction = 0.62;

  double _splitListFraction = _defaultSplitListFraction;

  void _resizeSplitList(double delta, double availableWidth) {
    if (availableWidth <= 0) {
      return;
    }
    final currentWidth = availableWidth * _splitListFraction;
    final minWidth = math.min(_minSplitListWidth, availableWidth * 0.45);
    final maxWidth = math.max(minWidth, availableWidth * _maxSplitListFraction);
    setState(() {
      _splitListFraction =
          (currentWidth + delta).clamp(minWidth, maxWidth) / availableWidth;
    });
  }

  void _cycleSplitListWidth(double availableWidth) {
    if (availableWidth <= 0) {
      return;
    }
    setState(() {
      if (_splitListFraction < _defaultSplitListFraction - 0.02) {
        _splitListFraction = _defaultSplitListFraction;
      } else if (_splitListFraction < _wideSplitListFraction - 0.02) {
        _splitListFraction = _wideSplitListFraction;
      } else {
        _splitListFraction = _narrowSplitListFraction;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width;
    final useSplitView = width >= 1180;
    final useCompactHeader =
        !useSplitView && width < 720 && screenSize.height > screenSize.width;
    final activeIdentity = ref.watch(activeIdentityDataProvider);
    final privateVaultUnlocked = ref.watch(
      privateVaultSessionControllerProvider,
    );
    final visibleNotes = ref.watch(visibleNotesProvider);
    final visibleVaults = ref.watch(visibleVaultsProvider);
    final vaultNameById = {
      for (final vault in visibleVaults)
        vault.id: _vaultDisplayName(context, vault),
    };
    final listDensity = ref.watch(notesListDensityControllerProvider);
    final sortField = ref.watch(notesListSortControllerProvider);
    final attachmentPreviewFit = ref.watch(
      attachmentPreviewFitControllerProvider,
    );
    final query = ref.watch(searchQueryProvider).trim();
    final selectedNoteId = ref.watch(selectedNoteIdProvider);
    final syncProvider = ref.watch(syncProviderControllerProvider);
    final adminMode = ref.watch(adminModeSessionControllerProvider);

    if (!useSplitView) {
      return _MobileNotesList(
        activeIdentity: activeIdentity,
        showPrivateVaultNotice:
            activeIdentity.id == 'private' && !privateVaultUnlocked,
        showAdminModeNotice: adminMode,
        compactHeader: useCompactHeader,
        vaultNameById: vaultNameById,
        showVaultName: visibleVaults.length > 1,
        allVisibleNotes: visibleNotes,
        selectedNoteId: selectedNoteId,
        density: listDensity,
        sortField: sortField,
        attachmentPreviewFit: attachmentPreviewFit,
        query: query,
        onRefresh: syncProvider == SyncProvider.off
            ? null
            : () => _refreshNotesFromCloud(context),
        onUnlockPrivateProfile: () => _showProfileAccessDialog(context, ref),
        onExitAdminMode: () => _exitAdminMode(ref),
        onTogglePinned: (note) =>
            ref.read(notesControllerProvider.notifier).togglePinned(note.id),
        onShareNote: (note) => _handleNoteDetailAction(
          context,
          ref,
          note,
          _NoteDetailAction.share,
        ),
        onDeleteNote: (note) => _deleteNote(context, note),
        onNoteSelected: (note) =>
            _openMobileNoteActions(context, note, visibleNotes),
      );
    }

    final visibleNoteIndexById = ref.watch(visibleNoteIndexByIdProvider);
    final selectedIndex = selectedNoteId == null
        ? -1
        : (visibleNoteIndexById[selectedNoteId] ?? -1);
    final effectiveSelectedNoteId = selectedNoteId != null && selectedIndex >= 0
        ? selectedNoteId
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final minWidth = math.min(_minSplitListWidth, availableWidth * 0.45);
        final maxWidth = math.max(
          minWidth,
          availableWidth * _maxSplitListFraction,
        );
        final listWidth = (availableWidth * _splitListFraction).clamp(
          minWidth,
          maxWidth,
        );
        return Row(
          children: [
            SizedBox(
              width: listWidth,
              child: _SplitNotesListPane(
                activeIdentity: activeIdentity,
                showPrivateVaultNotice:
                    activeIdentity.id == 'private' && !privateVaultUnlocked,
                showAdminModeNotice: adminMode,
                notes: visibleNotes,
                selectedNoteId: effectiveSelectedNoteId,
                vaultNameById: vaultNameById,
                showVaultName: visibleVaults.length > 1,
                density: listDensity,
                sortField: sortField,
                attachmentPreviewFit: attachmentPreviewFit,
                query: query,
                onAddNote: () => showNoteEditorSheet(context, ref),
                onRefresh: syncProvider == SyncProvider.off
                    ? null
                    : () => _refreshNotesFromCloud(context),
                onUnlockPrivateProfile: () =>
                    _showProfileAccessDialog(context, ref),
                onExitAdminMode: () => _exitAdminMode(ref),
                onTogglePinned: (note) => ref
                    .read(notesControllerProvider.notifier)
                    .togglePinned(note.id),
                onShareNote: (note) => _handleNoteDetailAction(
                  context,
                  ref,
                  note,
                  _NoteDetailAction.share,
                ),
                onDeleteNote: (note) => _deleteNote(context, note),
                onNoteSelected: (note) {
                  _debugNotePerf('select split-list ${_notePerfLabel(note)}');
                  ref.read(selectedNoteIdProvider.notifier).select(note.id);
                },
              ),
            ),
            _SplitPaneResizeHandle(
              onDragDelta: (delta) => _resizeSplitList(delta, availableWidth),
              onTap: () => _cycleSplitListWidth(availableWidth),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: visibleNotes.isEmpty
                    ? _EmptySplitDetailState(
                        onAddNote: () => showNoteEditorSheet(context, ref),
                      )
                    : selectedIndex < 0
                    ? const _EmptyNoteSelectionState()
                    : _StaticNoteDetailView(
                        notes: visibleNotes,
                        selectedIndex: selectedIndex,
                        onSelected: (index) => ref
                            .read(selectedNoteIdProvider.notifier)
                            .select(visibleNotes[index].id),
                        onEdit: (note) =>
                            showNoteEditorSheet(context, ref, note: note),
                        onDelete: (note) => _deleteNote(context, note),
                        onTagTap: (tag) => _applyTagFilter(context, tag),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _exitAdminMode(WidgetRef ref) {
    ref.read(adminModeSessionControllerProvider.notifier).lock();
    ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
  }

  Future<void> _openMobileNoteActions(
    BuildContext context,
    NoteEntry note,
    List<NoteEntry> visibleNotes,
  ) async {
    _debugNotePerf('open mobile detail ${_notePerfLabel(note)}');
    final hostContext = context;
    final initialIndex = visibleNotes.indexWhere(
      (entry) => entry.id == note.id,
    );
    BuildContext? sheetContextForClose;
    void handleCloseRequest() {
      final sheetContext = sheetContextForClose;
      if (sheetContext != null && sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
    }

    _pushNoteOverlaySheet();
    _pushMobileNoteDetailSheet();
    _mobileNoteDetailCloseRequests.addListener(handleCloseRequest);
    try {
      await showModalBottomSheet<void>(
        context: hostContext,
        isScrollControlled: true,
        showDragHandle: false,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (sheetContext) {
          sheetContextForClose = sheetContext;
          final mediaQuery = MediaQuery.of(sheetContext);
          return LayoutBuilder(
            builder: (context, constraints) {
              final sheetHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : mediaQuery.size.height;
              return SizedBox(
                height: sheetHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                  child: _NoteDetailPager(
                    notes: visibleNotes,
                    selectedIndex: initialIndex < 0 ? 0 : initialIndex,
                    onPageChanged: (index) => ref
                        .read(selectedNoteIdProvider.notifier)
                        .select(visibleNotes[index].id),
                    onEdit: (selectedNote) async {
                      Navigator.of(sheetContext).pop();
                      await showNoteEditorSheet(
                        hostContext,
                        ref,
                        note: selectedNote,
                      );
                    },
                    onDelete: (selectedNote) async {
                      Navigator.of(sheetContext).pop();
                      await _deleteNote(hostContext, selectedNote);
                    },
                    onClose: () => Navigator.of(sheetContext).pop(),
                    onTagTap: (tag) {
                      Navigator.of(sheetContext).pop();
                      _applyTagFilter(hostContext, tag);
                    },
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _mobileNoteDetailCloseRequests.removeListener(handleCloseRequest);
      _popMobileNoteDetailSheet();
      _popNoteOverlaySheet();
    }
  }

  Future<void> _refreshNotesFromCloud(BuildContext context) async {
    final strings = context.strings;
    final warning = await ref
        .read(syncTransferControllerProvider.notifier)
        .largeMobileTransferWarning(includeUpload: true, includeDownload: true);
    if (!context.mounted) {
      return;
    }
    final confirmed = warning == null
        ? true
        : await _showLargeMobileSyncConfirmDialog(context, warning) ?? false;
    if (!confirmed || !context.mounted) {
      return;
    }
    await ref
        .read(syncTransferControllerProvider.notifier)
        .syncNow(allowLargeMobileTransfer: true);
    if (!context.mounted) {
      return;
    }
    final syncProvider = ref.read(syncProviderControllerProvider);
    if (syncProvider == SyncProvider.off) {
      return;
    }
    final message = _cloudSyncSnackBarMessage(
      strings,
      ref.read(syncTransferControllerProvider),
      _CloudSyncSnackBarAction.syncNow,
      syncProvider,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
  }

  Future<void> _deleteNote(BuildContext context, NoteEntry note) async {
    final strings = context.strings;
    final result = await _showDeleteNoteDialog(context, note);

    if (result != null) {
      final controller = ref.read(notesControllerProvider.notifier);
      await controller.delete(note.id);
      if (result.deletePermanently) {
        await controller.deletePermanently(note.id);
      }
      if (ref.read(selectedNoteIdProvider) == note.id) {
        ref.read(selectedNoteIdProvider.notifier).select(null);
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            result.deletePermanently
                ? strings.noteDeleted(note.title)
                : strings.movedNoteToTrash(note.title),
          ),
          action: result.deletePermanently
              ? null
              : SnackBarAction(
                  label: strings.undo,
                  onPressed: () {
                    ref
                        .read(notesControllerProvider.notifier)
                        .upsert(
                          note.copyWith(
                            deletedAt: null,
                            syncState: NoteSyncState.pendingUpload,
                            updatedAt: DateTime.now(),
                            revision: note.revision + 1,
                          ),
                        );
                  },
                ),
        ),
      );
    }
  }

  void _applyTagFilter(BuildContext context, String tag) {
    ref.read(searchFiltersControllerProvider.notifier).setTags([tag]);
    ref.read(searchQueryProvider.notifier).setQuery('');
    ref.read(selectedNoteIdProvider.notifier).select(null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          context.strings.tagFilterApplied(_displayNoteTag(context, tag)),
        ),
      ),
    );
  }
}

class _EmptySplitDetailState extends StatelessWidget {
  const _EmptySplitDetailState({required this.onAddNote});

  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.note_add_outlined,
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            strings.localized(
              en: 'Start with a new note',
              ja: '\u65b0\u3057\u3044\u30e1\u30e2\u304b\u3089\u59cb\u3081\u308b',
              zh: '\u4ece\u65b0\u7b14\u8bb0\u5f00\u59cb',
              ko: '\uc0c8 \uba54\ubaa8\ub85c \uc2dc\uc791',
              es: 'Empieza con una nota nueva',
              de: 'Mit einer neuen Notiz beginnen',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.localized(
              en: 'Saved notes appear in the list on the left. Create one to preview and edit it here.',
              ja: '\u4fdd\u5b58\u3057\u305f\u30e1\u30e2\u306f\u5de6\u306e\u4e00\u89a7\u306b\u8868\u793a\u3055\u308c\u307e\u3059\u3002\u4f5c\u6210\u3059\u308b\u3068\u3053\u3053\u3067\u8868\u793a\u30fb\u7de8\u96c6\u3067\u304d\u307e\u3059\u3002',
              zh: '\u4fdd\u5b58\u7684\u7b14\u8bb0\u4f1a\u663e\u793a\u5728\u5de6\u4fa7\u5217\u8868\u4e2d\u3002\u521b\u5efa\u540e\u53ef\u5728\u6b64\u9884\u89c8\u548c\u7f16\u8f91\u3002',
              ko: '\uc800\uc7a5\ub41c \uba54\ubaa8\ub294 \uc67c\ucabd \ubaa9\ub85d\uc5d0 \ud45c\uc2dc\ub429\ub2c8\ub2e4. \uba54\ubaa8\ub97c \ub9cc\ub4e4\uba74 \uc5ec\uae30\uc11c \ubcf4\uace0 \ud3b8\uc9d1\ud560 \uc218 \uc788\uc2b5\ub2c8\ub2e4.',
              es: 'Las notas guardadas apareceran en la lista izquierda. Crea una para verla y editarla aqui.',
              de: 'Gespeicherte Notizen erscheinen links. Erstelle eine, um sie hier anzusehen und zu bearbeiten.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAddNote,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(strings.addNote),
          ),
        ],
      ),
    );
  }
}
