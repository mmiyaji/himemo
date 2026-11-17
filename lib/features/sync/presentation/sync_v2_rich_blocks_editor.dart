import 'dart:async';

import 'package:flutter/material.dart';

import '../../home/domain/note_entry.dart';

class SyncV2PendingBlock {
  const SyncV2PendingBlock({
    required this.draftId,
    required this.label,
    required this.type,
  });
  final String draftId;
  final String label;
  final AttachmentType type;
}

class RichBlockInsertionTarget {
  const RichBlockInsertionTarget({
    required this.paragraphId,
    required this.offset,
    required this.paragraphIndex,
    required this.originalText,
    required this.selection,
    required this.revision,
  });
  final String paragraphId;
  final int offset;
  final int paragraphIndex;
  final String originalText;
  final TextSelection selection;
  final int revision;
}

/// Edits paragraph text and structure while retaining attachment block data.
/// The owner must discard this widget when its profile is locked.
class SyncV2RichBlocksEditor extends StatefulWidget {
  const SyncV2RichBlocksEditor({
    super.key,
    required this.blocks,
    required this.onChanged,
    this.enabled = true,
    this.searchQuery = '',
    this.selectedSearchMatch = -1,
    this.searchRequest = 0,
    this.allowStructureChanges = true,
    this.removableAttachmentIds = const <String>{},
  });

  final List<NoteBlock> blocks;
  final ValueChanged<List<NoteBlock>> onChanged;
  final bool enabled;
  final String searchQuery;
  final int selectedSearchMatch;
  final int searchRequest;
  final bool allowStructureChanges;
  final Set<String> removableAttachmentIds;

  @override
  State<SyncV2RichBlocksEditor> createState() => SyncV2RichBlocksEditorState();
}

class _RichBlockDraft {
  _RichBlockDraft(this.id, this.block)
    : controller = block.type == NoteBlockType.paragraph
          ? TextEditingController(text: block.text ?? '')
          : null,
      focusNode = block.type == NoteBlockType.paragraph ? FocusNode() : null;

  final String id;
  NoteBlock block;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  void dispose() {
    controller?.clear();
    controller?.dispose();
    focusNode?.dispose();
  }
}

class _RemovedAttachmentDraft {
  _RemovedAttachmentDraft({
    required this.draft,
    required this.originalIndex,
    required this.previousId,
    required this.nextId,
  });

  final _RichBlockDraft draft;
  final int originalIndex;
  final String? previousId;
  final String? nextId;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? snackBar;
}

class SyncV2RichBlocksEditorState extends State<SyncV2RichBlocksEditor> {
  late List<_RichBlockDraft> _drafts;
  var _nextBlockId = 0;
  var _nextUndoId = 0;
  final _attachmentUndos = <int, _RemovedAttachmentDraft>{};
  String? _lastFocusedParagraphId;
  int _draftRevision = 0;

  RichBlockInsertionTarget? captureInsertionTarget() {
    if (!mounted || !widget.enabled || !widget.allowStructureChanges) {
      return null;
    }
    final paragraphs = _drafts.where((d) => d.controller != null).toList();
    if (paragraphs.isEmpty) return null;
    final paragraph = paragraphs.firstWhere(
      (d) => d.focusNode?.hasFocus == true,
      orElse: () => paragraphs.firstWhere(
        (d) => d.id == _lastFocusedParagraphId,
        orElse: () => paragraphs.last,
      ),
    );
    final controller = paragraph.controller!;
    final selection = controller.selection;
    final offset = selection.isValid
        ? (selection.isCollapsed ? selection.extentOffset : selection.start)
              .clamp(0, controller.text.length)
        : controller.text.length;
    return RichBlockInsertionTarget(
      paragraphId: paragraph.id,
      offset: offset,
      paragraphIndex: _drafts.indexOf(paragraph),
      originalText: controller.text,
      // Keep the exact selection for the stale-target check. The insertion
      // offset above is normalized separately when the selection is invalid.
      selection: selection,
      revision: _draftRevision,
    );
  }

  bool insertPendingAttachments(
    RichBlockInsertionTarget target,
    List<SyncV2PendingBlock> attachments,
  ) {
    if (!mounted ||
        !widget.enabled ||
        !widget.allowStructureChanges ||
        attachments.isEmpty ||
        target.revision != _draftRevision) {
      return false;
    }
    final index = _drafts.indexWhere((d) => d.id == target.paragraphId);
    if (index < 0 ||
        index != target.paragraphIndex ||
        _drafts[index].controller == null ||
        _drafts[index].controller!.text != target.originalText ||
        _drafts[index].controller!.selection != target.selection) {
      return false;
    }
    final paragraph = _drafts[index];
    final controller = paragraph.controller!;
    final originalText = controller.text;
    final offset = target.offset.clamp(0, originalText.length);
    final whitespaceOnly = originalText.trim().isEmpty;
    final split = whitespaceOnly ? originalText.length : offset;
    final before = originalText.substring(0, split);
    final after = originalText.substring(split);
    final inserted = <_RichBlockDraft>[];
    for (final item in attachments) {
      inserted.add(
        _RichBlockDraft(
          'new-${_nextBlockId++}',
          NoteBlock(
            type: NoteBlockType.values.byName(item.type.name),
            attachment: NoteAttachment(
              type: item.type,
              label: item.label,
              filePath: 'v2pending:${item.draftId}',
            ),
          ),
        ),
      );
    }
    late final _RichBlockDraft trailing;
    if (whitespaceOnly || before.isEmpty) {
      trailing = paragraph;
      final trailingText = whitespaceOnly ? originalText : after;
      paragraph.block = paragraph.block.copyWith(text: trailingText);
      controller.value = TextEditingValue(
        text: trailingText,
        selection: TextSelection.collapsed(
          offset: whitespaceOnly ? trailingText.length : 0,
        ),
      );
      setState(() => _drafts.insertAll(index, inserted));
    } else {
      trailing = _RichBlockDraft(
        'new-${_nextBlockId++}',
        paragraph.block.copyWith(text: after),
      );
      paragraph.block = paragraph.block.copyWith(text: before);
      controller.value = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      setState(() => _drafts.insertAll(index + 1, [...inserted, trailing]));
    }
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_drafts.contains(trailing)) return;
      _lastFocusedParagraphId = trailing.id;
      trailing.focusNode?.requestFocus();
      trailing.controller?.selection = TextSelection.collapsed(
        offset: whitespaceOnly || before.isEmpty ? 0 : 0,
      );
    });
    return true;
  }

  bool removePendingAttachment(String draftId) {
    if (!mounted || !widget.enabled) return false;
    final index = _drafts.indexWhere(
      (d) => d.block.attachment?.filePath == 'v2pending:$draftId',
    );
    if (index < 0) return false;
    final removed = _drafts.removeAt(index);
    removed.dispose();
    setState(() {});
    _emit();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _drafts = [
      for (var i = 0; i < widget.blocks.length; i++)
        _RichBlockDraft('$i', widget.blocks[i]),
    ];
    _nextBlockId = _drafts.length;
  }

  @override
  void didUpdateWidget(covariant SyncV2RichBlocksEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchRequest != widget.searchRequest) {
      _selectSearchMatch();
    }
  }

  void _selectSearchMatch() {
    final query = widget.searchQuery.trim().toLowerCase();
    var matchIndex = widget.selectedSearchMatch;
    if (query.isEmpty || matchIndex < 0) return;
    for (final draft in _drafts) {
      final controller = draft.controller;
      if (controller == null) continue;
      final lower = controller.text.toLowerCase();
      var cursor = 0;
      while (cursor < lower.length) {
        final offset = lower.indexOf(query, cursor);
        if (offset < 0) break;
        if (matchIndex == 0) {
          final selectedDraft = draft;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_drafts.contains(selectedDraft)) return;
            selectedDraft.focusNode?.requestFocus();
            selectedDraft.controller?.selection = TextSelection(
              baseOffset: offset,
              extentOffset: offset + query.length,
            );
          });
          return;
        }
        matchIndex--;
        cursor = offset + query.length;
      }
    }
  }

  List<NoteBlock> _blocksForSave() => [
    for (final draft in _drafts)
      draft.controller == null
          ? draft.block
          : draft.block.copyWith(text: draft.controller!.text),
  ];

  void _emit() {
    _draftRevision++;
    widget.onChanged(List.unmodifiable(_blocksForSave()));
  }

  void _insertParagraph(int index) {
    if (!widget.enabled || !widget.allowStructureChanges) return;
    final paragraph = _RichBlockDraft(
      'new-${_nextBlockId++}',
      const NoteBlock(type: NoteBlockType.paragraph, text: ''),
    );
    setState(() => _drafts.insert(index, paragraph));
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_drafts.contains(paragraph)) return;
      paragraph.focusNode?.requestFocus();
    });
  }

  void _removeParagraph(_RichBlockDraft draft) {
    if (!widget.enabled ||
        !widget.allowStructureChanges ||
        draft.controller == null ||
        _drafts.where((item) => item.controller != null).length <= 1) {
      return;
    }
    setState(() => _drafts.remove(draft));
    draft.dispose();
    _emit();
  }

  String? _linkedAttachmentId(_RichBlockDraft draft) {
    final path = draft.block.attachment?.filePath;
    if (path == null || !path.startsWith('v2attachment:')) return null;
    final id = path.substring('v2attachment:'.length);
    return id.isEmpty ? null : id;
  }

  bool _canRemoveAttachment(_RichBlockDraft draft) {
    final id = _linkedAttachmentId(draft);
    if (id == null || !widget.removableAttachmentIds.contains(id)) return false;
    return _drafts
            .where((candidate) => _linkedAttachmentId(candidate) == id)
            .length ==
        1;
  }

  void _removeAttachment(_RichBlockDraft draft) {
    if (!widget.enabled ||
        !widget.allowStructureChanges ||
        !_canRemoveAttachment(draft)) {
      return;
    }
    final index = _drafts.indexOf(draft);
    final previousId = index > 0 ? _drafts[index - 1].id : null;
    final nextId = index + 1 < _drafts.length ? _drafts[index + 1].id : null;
    final undoId = _nextUndoId++;
    final undo = _RemovedAttachmentDraft(
      draft: draft,
      originalIndex: index,
      previousId: previousId,
      nextId: nextId,
    );
    _attachmentUndos[undoId] = undo;
    setState(() => _drafts.remove(draft));
    _emit();

    final japanese = Localizations.localeOf(context).languageCode == 'ja';
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _attachmentUndos.remove(undoId);
      return;
    }
    undo.snackBar = messenger.showSnackBar(
      SnackBar(
        content: Text(japanese ? '添付を削除しました' : 'Attachment removed'),
        action: SnackBarAction(
          label: japanese ? '元に戻す' : 'Undo',
          onPressed: () => _restoreAttachment(undoId),
        ),
      ),
    );
    unawaited(
      undo.snackBar!.closed.then((_) {
        _attachmentUndos.remove(undoId);
      }),
    );
  }

  void _restoreAttachment(int undoId) {
    if (!mounted) return;
    final undo = _attachmentUndos.remove(undoId);
    if (undo == null || _drafts.contains(undo.draft)) return;
    final nextIndex = undo.nextId == null
        ? -1
        : _drafts.indexWhere((candidate) => candidate.id == undo.nextId);
    final previousIndex = undo.previousId == null
        ? -1
        : _drafts.indexWhere((candidate) => candidate.id == undo.previousId);
    final restoreIndex = nextIndex >= 0
        ? nextIndex
        : previousIndex >= 0
        ? previousIndex + 1
        : undo.originalIndex.clamp(0, _drafts.length);
    setState(() => _drafts.insert(restoreIndex, undo.draft));
    _emit();
  }

  void _moveBlock(int index, int delta) {
    final target = index + delta;
    if (!widget.enabled ||
        !widget.allowStructureChanges ||
        target < 0 ||
        target >= _drafts.length) {
      return;
    }
    setState(() {
      final draft = _drafts.removeAt(index);
      _drafts.insert(target, draft);
    });
    _emit();
  }

  @override
  void dispose() {
    for (final undo in _attachmentUndos.values) {
      undo.snackBar?.close();
    }
    _attachmentUndos.clear();
    for (final draft in _drafts) {
      draft.dispose();
    }
    _drafts.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final japanese = Localizations.localeOf(context).languageCode == 'ja';
    String text(String ja, String en) => japanese ? ja : en;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _drafts.length; i++) ...[
          _blockTile(context, _drafts[i], i, text),
          if (i != _drafts.length - 1) const SizedBox(height: 8),
        ],
        if (widget.allowStructureChanges)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('sync-v2-add-paragraph'),
              onPressed: widget.enabled
                  ? () => _insertParagraph(_drafts.length)
                  : null,
              icon: const Icon(Icons.add),
              label: Text(text('段落を追加', 'Add paragraph')),
            ),
          ),
      ],
    );
  }

  Widget _blockTile(
    BuildContext context,
    _RichBlockDraft draft,
    int index,
    String Function(String, String) text,
  ) {
    final controller = draft.controller;
    final isParagraph = controller != null;
    final paragraphCount = _drafts
        .where((item) => item.controller != null)
        .length;
    final canRemoveAttachment = !isParagraph && _canRemoveAttachment(draft);
    final controls = widget.allowStructureChanges
        ? Wrap(
            spacing: 0,
            children: [
              IconButton(
                key: ValueKey('sync-v2-rich-move-up-${draft.id}'),
                tooltip: text('上へ移動', 'Move up'),
                onPressed: widget.enabled && index > 0
                    ? () => _moveBlock(index, -1)
                    : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                key: ValueKey('sync-v2-rich-move-down-${draft.id}'),
                tooltip: text('下へ移動', 'Move down'),
                onPressed: widget.enabled && index < _drafts.length - 1
                    ? () => _moveBlock(index, 1)
                    : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              if (isParagraph)
                IconButton(
                  key: ValueKey('sync-v2-rich-remove-paragraph-${draft.id}'),
                  tooltip: text('段落を削除', 'Remove paragraph'),
                  onPressed: widget.enabled && paragraphCount > 1
                      ? () => _removeParagraph(draft)
                      : null,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              if (!isParagraph)
                IconButton(
                  key: ValueKey('sync-v2-rich-remove-attachment-${draft.id}'),
                  tooltip: text('添付を削除', 'Remove attachment'),
                  onPressed: widget.enabled && canRemoveAttachment
                      ? () => _removeAttachment(draft)
                      : null,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
            ],
          )
        : const SizedBox.shrink();
    final content = isParagraph
        ? TextField(
            key: draft.id == '0'
                ? const Key('sync-v2-body')
                : ValueKey('sync-v2-rich-paragraph-${draft.id}'),
            controller: controller,
            focusNode: draft.focusNode,
            onTap: () => _lastFocusedParagraphId = draft.id,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: null,
            decoration: InputDecoration(
              labelText: text('本文 ${index + 1}', 'Text ${index + 1}'),
            ),
            onChanged: (value) {
              draft.block = draft.block.copyWith(text: value);
              _emit();
            },
          )
        : ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.attach_file),
            title: Text(
              draft.block.attachment?.label ?? text('添付ファイル', 'Attachment'),
            ),
            subtitle: Text(text('添付内容は保持されます', 'Attachment data is retained')),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: content),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            controls,
            if (widget.allowStructureChanges)
              IconButton(
                key: ValueKey('sync-v2-rich-insert-paragraph-${draft.id}'),
                tooltip: text('この後に段落を追加', 'Add paragraph after this block'),
                onPressed: widget.enabled
                    ? () => _insertParagraph(index + 1)
                    : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_box_outlined, size: 18),
              ),
          ],
        ),
      ],
    );
  }
}
