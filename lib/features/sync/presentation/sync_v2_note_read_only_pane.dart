import 'package:flutter/material.dart';

import '../../home/domain/note_entry.dart';
import '../../home/presentation/note_detail_shared.dart';

/// Plain, already-authorized note content for the V2 workspace preview.
///
/// This intentionally carries no note ID, vault ID, attachment reference, or
/// provider/controller handle. The caller must only construct it after V2 has
/// confirmed that the selected version is decrypted and available.
@immutable
class SyncV2NotePreviewData {
  SyncV2NotePreviewData({
    required this.title,
    required this.body,
    required this.createdAt,
    this.updatedAt,
    List<String> tags = const [],
    this.location,
    this.isPinned = false,
  }) : tags = List.unmodifiable(tags);

  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final NoteLocation? location;
  final bool isPinned;
}

/// A read-only note pane with V1-like metadata and action placement.
///
/// Attachment widgets are supplied by the parent after its authorization and
/// session checks. This widget never resolves attachment references itself.
class SyncV2NoteReadOnlyPane extends StatelessWidget {
  const SyncV2NoteReadOnlyPane({
    super.key,
    required this.note,
    this.contentWidgets,
    this.attachmentWidgets = const [],
    this.onEdit,
    this.onCopy,
    this.onShare,
    this.onDelete,
    this.onTogglePinned,
  });

  final SyncV2NotePreviewData note;

  /// Optional, already-authorized body and attachment blocks in original order.
  /// The caller must omit [note]'s location from this list; it is shown after
  /// the content widgets, as V1 does for the note-level location attribute.
  /// When supplied, [body] and [attachmentWidgets] are fallback content and
  /// are not rendered separately.
  final List<Widget>? contentWidgets;
  final List<Widget> attachmentWidgets;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePinned;

  String _dateLabel(DateTime value) {
    final date = value.toLocal();
    return '${date.year}/${date.month}/${date.day} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _label(BuildContext context, String japanese, String english) =>
      Localizations.localeOf(context).languageCode == 'ja' ? japanese : english;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final updatedAt = note.updatedAt;
    final displayedDate = updatedAt ?? note.createdAt;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateLabel(displayedDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onTogglePinned != null)
                    IconButton(
                      tooltip: note.isPinned
                          ? _label(context, 'ピン留めを解除', 'Unpin note')
                          : _label(context, 'このノートを固定', 'Pin note'),
                      onPressed: onTogglePinned,
                      icon: Icon(
                        note.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                      ),
                    ),
                  if (onCopy != null)
                    IconButton(
                      tooltip: _label(context, 'テキストをコピー', 'Copy text'),
                      onPressed: onCopy,
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                  if (onShare != null)
                    IconButton(
                      tooltip: _label(context, '共有', 'Share'),
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                  if (onEdit != null)
                    IconButton(
                      tooltip: _label(context, '編集', 'Edit'),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: _label(context, '削除', 'Delete'),
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            sliver: SliverList.list(
              children: [
                Text(note.title, style: theme.textTheme.headlineSmall),
                if (updatedAt != null && updatedAt != note.createdAt) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_label(context, '作成', 'Created')} '
                    '${_dateLabel(note.createdAt)} · '
                    '${_label(context, '更新', 'Updated')} ${_dateLabel(updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in note.tags)
                        NoteDetailTagChip(label: tag),
                    ],
                  ),
                ],
                if (contentWidgets case final content?) ...[
                  for (final (index, widget) in content.indexed) ...[
                    SizedBox(height: index == 0 ? 20 : 16),
                    widget,
                  ],
                ] else ...[
                  if (note.body.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SelectableText(
                      note.body,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                    ),
                  ],
                  for (final attachment in attachmentWidgets) ...[
                    const SizedBox(height: 16),
                    attachment,
                  ],
                ],
                if (note.location case final location?) ...[
                  const SizedBox(height: 16),
                  _LocationSummary(location: location),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationSummary extends StatelessWidget {
  const _LocationSummary({required this.location});

  final NoteLocation location;

  @override
  Widget build(BuildContext context) {
    final label = location.address?.trim();
    final coordinates =
        '${location.latitude.toStringAsFixed(5)}, '
        '${location.longitude.toStringAsFixed(5)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null && label.isNotEmpty) Text(label),
                  Text(
                    coordinates,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
