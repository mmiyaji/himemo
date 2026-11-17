import 'package:flutter/material.dart';

import '../../home/domain/note_tags.dart';
import '../../home/presentation/home_providers.dart'
    show
        AutoTagRule,
        autoTagRuleMatchesNote,
        isSystemSyncExclusionTag,
        splitAutoTagKeywords;
import 'sync_v2_workspace.dart';

class SyncV2AutoTagRuleDraft {
  const SyncV2AutoTagRuleDraft({
    required this.tag,
    required this.keywords,
    required this.matchTitle,
    required this.matchBody,
    required this.matchAttachments,
  });

  final String tag;
  final List<String> keywords;
  final bool matchTitle;
  final bool matchBody;
  final bool matchAttachments;
}

/// Public dialog content so a host can open it through its tracked dialog
/// lifecycle and receive a validated draft from Navigator.pop.
class SyncV2AutoTagRuleEditorDialog extends StatefulWidget {
  const SyncV2AutoTagRuleEditorDialog({super.key, this.initialRule});

  final AutoTagRule? initialRule;

  @override
  State<SyncV2AutoTagRuleEditorDialog> createState() =>
      _SyncV2AutoTagRuleEditorDialogState();
}

class _SyncV2AutoTagRuleEditorDialogState
    extends State<SyncV2AutoTagRuleEditorDialog> {
  late final TextEditingController _tagController;
  late final TextEditingController _keywordsController;
  late bool _matchTitle;
  late bool _matchBody;
  late bool _matchAttachments;
  String? _error;

  bool get _english => Localizations.localeOf(context).languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.initialRule?.tag ?? '');
    _keywordsController = TextEditingController(
      text: widget.initialRule?.keywords.join(', ') ?? '',
    );
    _matchTitle = widget.initialRule?.matchTitle ?? true;
    _matchBody = widget.initialRule?.matchBody ?? true;
    _matchAttachments = widget.initialRule?.matchAttachments ?? true;
  }

  @override
  void dispose() {
    _tagController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  void _submit() {
    final tag = normalizeNoteTag(_tagController.text);
    final keywords = splitAutoTagKeywords(_keywordsController.text);
    final validation = tag.isEmpty
        ? (_english ? 'Enter a tag name.' : 'タグ名を入力してください。')
        : isSystemSyncExclusionTag(tag)
        ? (_english ? 'This tag is reserved by the app.' : 'このタグ名はアプリが使用しています。')
        : keywords.isEmpty
        ? (_english ? 'Enter one or more keywords.' : 'キーワードを1つ以上入力してください。')
        : !_matchTitle && !_matchBody && !_matchAttachments
        ? (_english
              ? 'Select at least one match target.'
              : '照合対象を1つ以上選択してください。')
        : null;
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    Navigator.of(context).pop(
      SyncV2AutoTagRuleDraft(
        tag: tag,
        keywords: keywords,
        matchTitle: _matchTitle,
        matchBody: _matchBody,
        matchAttachments: _matchAttachments,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initialRule == null
          ? (_english ? 'Create auto-tag rule' : '自動タグルールを作成')
          : (_english ? 'Edit auto-tag rule' : '自動タグルールを編集'),
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('sync-v2-auto-tag-name'),
              autofocus: true,
              controller: _tagController,
              decoration: InputDecoration(
                labelText: _english ? 'Tag to add' : '追加するタグ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('sync-v2-auto-tag-keywords'),
              controller: _keywordsController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _english ? 'Keywords' : 'キーワード',
                helperText: _english
                    ? 'Separate keywords with commas or new lines.'
                    : 'カンマまたは改行で区切ってください。',
              ),
            ),
            const SizedBox(height: 8),
            _target(
              _english ? 'Title' : 'タイトル',
              _matchTitle,
              (value) => setState(() => _matchTitle = value),
            ),
            _target(
              _english ? 'Body' : '本文',
              _matchBody,
              (value) => setState(() => _matchBody = value),
            ),
            _target(
              _english ? 'Attachment names' : '添付ファイル名',
              _matchAttachments,
              (value) => setState(() => _matchAttachments = value),
            ),
            if (_error != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(_english ? 'Cancel' : 'キャンセル'),
      ),
      FilledButton(
        key: const ValueKey('sync-v2-auto-tag-save'),
        onPressed: _submit,
        child: Text(_english ? 'Save' : '保存'),
      ),
    ],
  );

  Widget _target(String label, bool value, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: (next) => onChanged(next ?? false),
      );
}

/// Convenience launcher for hosts that use the standard dialog lifecycle.
/// Tracked screens can instead place [SyncV2AutoTagRuleEditorDialog] in their
/// own dialog route and receive the draft from Navigator.pop.
Future<void> showSyncV2AutoTagRuleEditor(
  BuildContext context, {
  required Future<void> Function(SyncV2AutoTagRuleDraft value) onSave,
  AutoTagRule? initialRule,
}) async {
  final value = await showDialog<SyncV2AutoTagRuleDraft>(
    context: context,
    builder: (_) => SyncV2AutoTagRuleEditorDialog(initialRule: initialRule),
  );
  if (value != null) await onSave(value);
}

/// Produces safe V2 tag edits from the existing local auto-tag rules.
///
/// This is a pure projection over already decrypted V2 workspace notes. It
/// never opens the V1 note database. Unavailable, conflicting, archived,
/// deleted, and non-selected-profile notes are excluded. A locked workspace
/// produces no edits.
Map<SyncV2WorkspaceNote, List<String>> planSyncV2AutoTagEdits({
  required Iterable<SyncV2WorkspaceNote> notes,
  required Iterable<AutoTagRule> rules,
  required String? selectedProfileId,
  required bool locked,
}) {
  if (locked || selectedProfileId == null) return const {};
  final activeRules = rules.where((rule) => rule.enabled).toList();
  final edits = <SyncV2WorkspaceNote, List<String>>{};
  for (final entry in notes) {
    if (!entry.ready ||
        entry.isConflict ||
        entry.isDeleted ||
        entry.note.deletedAt != null ||
        entry.note.archivedAt != null ||
        entry.note.vaultId != selectedProfileId) {
      continue;
    }
    final originalTags = dedupeNoteTags(entry.note.tags);
    final tags = <String>[...originalTags];
    final existing = tags.map((tag) => canonicalizeNoteTag(tag)).toSet();
    for (final rule in activeRules) {
      final tag = normalizeNoteTag(rule.tag);
      final key = canonicalizeNoteTag(tag);
      if (tag.isEmpty ||
          key.isEmpty ||
          existing.contains(key) ||
          isSystemSyncExclusionTag(tag) ||
          !autoTagRuleMatchesNote(rule, entry.note)) {
        continue;
      }
      tags.add(tag);
      existing.add(key);
    }
    final deduped = dedupeNoteTags(tags);
    if (deduped.length != originalTags.length) {
      edits[entry] = deduped;
    }
  }
  return Map.unmodifiable(edits);
}

/// V2-ready rule management surface. The caller owns persistence and applies
/// each planned edit through the V2 workspace controller's save API.
class SyncV2AutoTagRulesPanel extends StatelessWidget {
  const SyncV2AutoTagRulesPanel({
    super.key,
    required this.rules,
    required this.onAdd,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onApply,
    this.busy = false,
  });

  final List<AutoTagRule> rules;
  final VoidCallback onAdd;
  final void Function(AutoTagRule rule, bool enabled) onToggle;
  final ValueChanged<AutoTagRule> onEdit;
  final ValueChanged<AutoTagRule> onDelete;
  final VoidCallback onApply;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final actions = [
          TextButton.icon(
            onPressed: busy ? null : onAdd,
            icon: const Icon(Icons.add),
            label: Text(english ? 'Add rule' : 'ルールを追加'),
          ),
          TextButton.icon(
            onPressed: busy || rules.isEmpty ? null : onApply,
            icon: const Icon(Icons.play_arrow),
            label: Text(english ? 'Apply to V2 notes' : 'V2ノートに適用'),
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              Text(
                english ? 'Auto-tag rules' : '自動タグ付与ルール',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(spacing: 4, runSpacing: 4, children: actions),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      english ? 'Auto-tag rules' : '自動タグ付与ルール',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ...actions,
                ],
              ),
            if (rules.isEmpty)
              ListTile(title: Text(english ? 'No rules yet' : 'ルールはありません'))
            else
              for (final rule in rules)
                Card(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 4, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Switch(
                              value: rule.enabled,
                              onChanged: busy
                                  ? null
                                  : (value) => onToggle(rule, value),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rule.tag, softWrap: true),
                                  Text(
                                    rule.keywords.join(english ? ', ' : '、'),
                                    softWrap: true,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: english ? 'Edit' : '編集',
                              onPressed: busy ? null : () => onEdit(rule),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: english ? 'Delete' : '削除',
                              onPressed: busy ? null : () => onDelete(rule),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
