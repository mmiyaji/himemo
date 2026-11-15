import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A presentation-only quick memo editor. The owner retains controller and
/// attachment lifetimes and supplies the surrounding actions.
class SyncV2OriginalEditor extends StatelessWidget {
  const SyncV2OriginalEditor({
    super.key,
    required this.titleController,
    required this.bodyController,
    required this.writable,
    required this.onClose,
    required this.attachments,
    required this.actions,
    this.createdAt,
    this.editing = false,
    this.wide = false,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final bool writable;
  final VoidCallback? onClose;
  final Widget attachments;
  final Widget actions;
  final DateTime? createdAt;
  final bool editing;
  final bool wide;

  String _text(BuildContext context, String japanese, String english) =>
      Localizations.localeOf(context).languageCode == 'ja' ? japanese : english;

  Widget _pill(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool primary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = primary ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: primary
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerLow,
        border: Border.all(
          color: primary
              ? colorScheme.primary.withValues(alpha: 0.22)
              : colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 12, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxWidth = wide ? 1040.0 : 760.0;
    final horizontalPadding = wide ? 24.0 : 16.0;
    final date = createdAt?.toLocal();
    final dateLabel = date == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(date);
    final timeLabel = date == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(date),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = math
              .max(0.0, constraints.maxWidth - horizontalPadding * 2)
              .toDouble();
          final bottomInset = math.max(16.0, viewInsets.bottom + 20).toDouble();
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              bottomInset,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(maxWidth, availableWidth).toDouble(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (dateLabel != null) ...[
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                top: 10,
                                end: 8,
                              ),
                              child: Text(
                                '$dateLabel  ·  $timeLabel',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        TextButton.icon(
                          onPressed: onClose,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: Text(_text(context, '一覧', 'Notes')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(
                          context,
                          icon: Icons.notes_outlined,
                          label: _text(context, 'クイックメモ', 'Quick memo'),
                          primary: true,
                        ),
                        _pill(
                          context,
                          icon: editing
                              ? Icons.edit_outlined
                              : Icons.add_rounded,
                          label: editing
                              ? _text(context, '編集中', 'Editing')
                              : _text(context, '新規', 'New'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.35),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              key: const Key('sync-v2-title'),
                              controller: titleController,
                              readOnly: !writable,
                              textCapitalization: TextCapitalization.sentences,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: _text(context, 'タイトル', 'Title'),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              key: const Key('sync-v2-body'),
                              controller: bodyController,
                              readOnly: !writable,
                              minLines: 8,
                              maxLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.55,
                              ),
                              scrollPadding: const EdgeInsets.only(
                                top: 96,
                                left: 16,
                                right: 16,
                                bottom: 128,
                              ),
                              decoration: InputDecoration(
                                hintText: _text(
                                  context,
                                  'メモを書く',
                                  'Write your note',
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    attachments,
                    const SizedBox(height: 12),
                    actions,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
