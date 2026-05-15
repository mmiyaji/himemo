part of 'home_page.dart';

class _PrivateVaultLockedNotice extends StatelessWidget {
  const _PrivateVaultLockedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.strings.text(
                'home.locked.profiles.are.hidden.unlock.the.target.profile.fro',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _vaultDisplayName(BuildContext context, VaultBucket vault) {
  if (vault.id == 'everyday') {
    return context.strings.notes;
  }
  if (vault.id == legacyPrivateVaultId &&
      (vault.name == 'Private profile' ||
          vault.name == '__private_profile__')) {
    return context.strings.text('home.private.profile');
  }
  if (vault.name == 'Notes' || vault.name == '__notes__') {
    return context.strings.notes;
  }
  return vault.name;
}

DateTime _noteListMoment(NoteEntry note, NotesListSortField sortField) {
  return switch (sortField) {
    NotesListSortField.updatedAt => note.updatedAt ?? note.createdAt,
    NotesListSortField.createdAt => note.createdAt,
  };
}

bool _isSameNoteDay(
  NoteEntry left,
  NoteEntry right,
  NotesListSortField sortField,
) {
  final leftMoment = _noteListMoment(left, sortField).toLocal();
  final rightMoment = _noteListMoment(right, sortField).toLocal();
  return leftMoment.year == rightMoment.year &&
      leftMoment.month == rightMoment.month &&
      leftMoment.day == rightMoment.day;
}

class _MobileNotesList extends StatefulWidget {
  const _MobileNotesList({
    required this.activeIdentity,
    required this.showPrivateVaultNotice,
    required this.compactHeader,
    required this.vaultNameById,
    required this.showVaultName,
    required this.allVisibleNotes,
    required this.selectedNoteId,
    required this.density,
    required this.sortField,
    required this.attachmentPreviewFit,
    required this.query,
    required this.onRefresh,
    required this.onNoteSelected,
  });

  final UnlockIdentity activeIdentity;
  final bool showPrivateVaultNotice;
  final bool compactHeader;
  final Map<String, String> vaultNameById;
  final bool showVaultName;
  final List<NoteEntry> allVisibleNotes;
  final String? selectedNoteId;
  final NotesListDensity density;
  final NotesListSortField sortField;
  final AttachmentPreviewFit attachmentPreviewFit;
  final String query;
  final Future<void> Function()? onRefresh;
  final ValueChanged<NoteEntry> onNoteSelected;

  @override
  State<_MobileNotesList> createState() => _MobileNotesListState();
}

class _MobileNotesListState extends State<_MobileNotesList> {
  late List<_MobileNoteRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows();
  }

  @override
  void didUpdateWidget(covariant _MobileNotesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.allVisibleNotes, widget.allVisibleNotes) ||
        oldWidget.activeIdentity.id != widget.activeIdentity.id ||
        oldWidget.showPrivateVaultNotice != widget.showPrivateVaultNotice ||
        oldWidget.compactHeader != widget.compactHeader ||
        oldWidget.density != widget.density ||
        oldWidget.sortField != widget.sortField ||
        oldWidget.attachmentPreviewFit != widget.attachmentPreviewFit ||
        oldWidget.showVaultName != widget.showVaultName ||
        oldWidget.vaultNameById.length != widget.vaultNameById.length) {
      _rows = _buildRows();
    }
  }

  List<_MobileNoteRow> _buildRows() {
    final watch = kDebugMode ? (Stopwatch()..start()) : null;
    final rows = _buildMobileNoteRows(
      activeIdentity: widget.activeIdentity,
      showPrivateVaultNotice: widget.showPrivateVaultNotice,
      compactHeader: widget.compactHeader,
      notes: widget.allVisibleNotes,
      density: widget.density,
      sortField: widget.sortField,
    );
    if (watch != null) {
      watch.stop();
      _debugNotePerf(
        'mobile list rows notes=${widget.allVisibleNotes.length} rows=${rows.length} completed ${watch.elapsedMicroseconds / 1000}ms',
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      physics: widget.onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        return switch (row) {
          _MobileIdentityRow() => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _IdentityHeader(identity: widget.activeIdentity),
          ),
          _MobilePrivateNoticeRow() => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _PrivateVaultLockedNotice(),
          ),
          _MobileToolbarRow() => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _NotesToolbar(compact: widget.compactHeader),
          ),
          _MobileEmptyRow() => const _EmptyNotesState(),
          _MobileDayRow(:final date) => _DecoratedMobileNoteRow(
            position: row.position,
            child: _NoteDayDivider(date: date),
          ),
          _MobileTileRow(:final note) => _DecoratedMobileNoteRow(
            position: row.position,
            child: RepaintBoundary(
              child: _NoteListTile(
                note: note,
                vaultName: widget.vaultNameById[note.vaultId] ?? note.vaultId,
                showVaultName: widget.showVaultName,
                density: widget.density,
                attachmentPreviewFit: widget.attachmentPreviewFit,
                query: widget.query,
                selected: note.id == widget.selectedNoteId,
                onTap: () => widget.onNoteSelected(note),
              ),
            ),
          ),
          _MobileDividerRow() => _DecoratedMobileNoteRow(
            position: row.position,
            child: const _IntraDayNoteGap(),
          ),
        };
      },
    );
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      return list;
    }
    return RefreshIndicator(onRefresh: onRefresh, child: list);
  }
}

List<_MobileNoteRow> _buildMobileNoteRows({
  required UnlockIdentity activeIdentity,
  required bool showPrivateVaultNotice,
  required bool compactHeader,
  required List<NoteEntry> notes,
  required NotesListDensity density,
  required NotesListSortField sortField,
}) {
  final rows = <_MobileNoteRow>[
    if (activeIdentity.id != 'daily') const _MobileIdentityRow(),
    if (showPrivateVaultNotice) const _MobilePrivateNoticeRow(),
    _MobileToolbarRow(compactHeader),
  ];
  if (notes.isEmpty) {
    rows.add(const _MobileEmptyRow());
    return rows;
  }

  final noteRows = <_MobileNoteRow>[];
  for (var i = 0; i < notes.length; i++) {
    if (density != NotesListDensity.compact &&
        (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i], sortField))) {
      noteRows.add(_MobileDayRow(_noteListMoment(notes[i], sortField)));
    }
    noteRows.add(_MobileTileRow(notes[i]));
    if (density != NotesListDensity.compact &&
        i != notes.length - 1 &&
        _isSameNoteDay(notes[i], notes[i + 1], sortField)) {
      noteRows.add(const _MobileDividerRow());
    }
  }
  for (var i = 0; i < noteRows.length; i++) {
    rows.add(
      noteRows[i].withPosition(
        _MobileNoteRowPosition(first: i == 0, last: i == noteRows.length - 1),
      ),
    );
  }
  return rows;
}

class _MobileNoteRowPosition {
  const _MobileNoteRowPosition({required this.first, required this.last});

  final bool first;
  final bool last;
}

sealed class _MobileNoteRow {
  const _MobileNoteRow({this.position});

  final _MobileNoteRowPosition? position;

  _MobileNoteRow withPosition(_MobileNoteRowPosition position);
}

class _MobileIdentityRow extends _MobileNoteRow {
  const _MobileIdentityRow();

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobilePrivateNoticeRow extends _MobileNoteRow {
  const _MobilePrivateNoticeRow();

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobileToolbarRow extends _MobileNoteRow {
  const _MobileToolbarRow(this.compact);

  final bool compact;

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobileEmptyRow extends _MobileNoteRow {
  const _MobileEmptyRow();

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) => this;
}

class _MobileDayRow extends _MobileNoteRow {
  const _MobileDayRow(this.date, {super.position});

  final DateTime date;

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) =>
      _MobileDayRow(date, position: position);
}

class _MobileTileRow extends _MobileNoteRow {
  const _MobileTileRow(this.note, {super.position});

  final NoteEntry note;

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) =>
      _MobileTileRow(note, position: position);
}

class _MobileDividerRow extends _MobileNoteRow {
  const _MobileDividerRow({super.position});

  @override
  _MobileNoteRow withPosition(_MobileNoteRowPosition position) =>
      _MobileDividerRow(position: position);
}

class _DecoratedMobileNoteRow extends StatelessWidget {
  const _DecoratedMobileNoteRow({required this.position, required this.child});

  final _MobileNoteRowPosition? position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(pos?.first == true ? 6 : 0),
      bottom: Radius.circular(pos?.last == true ? 6 : 0),
    );
    final border = Border(
      left: BorderSide(color: Theme.of(context).dividerColor),
      right: BorderSide(color: Theme.of(context).dividerColor),
      top: pos?.first == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
      bottom: pos?.last == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
    );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );
  }
}

class _NoteDayDivider extends StatelessWidget {
  const _NoteDayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final label = strings.noteDayLabel(date);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final dayDiff = today.difference(target).inDays;
    final suffix = switch (dayDiff) {
      0 => strings.today,
      1 => strings.yesterday,
      _ => null,
    };
    final weekendColor = _noteDayWeekendColor(context, date);
    final effectiveColor = weekendColor ?? _mutedTextColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 1, color: Theme.of(context).dividerColor),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:
                  weekendColor?.withValues(alpha: 0.08) ??
                  Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color:
                    weekendColor?.withValues(alpha: 0.45) ??
                    Theme.of(context).dividerColor,
              ),
            ),
            child: Text(
              suffix == null ? label : '$label  $suffix',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: effectiveColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Container(height: 1, color: Theme.of(context).dividerColor),
          ),
        ],
      ),
    );
  }
}

class _IntraDayNoteGap extends StatelessWidget {
  const _IntraDayNoteGap();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        height: 1,
        color: Theme.of(context).dividerColor.withValues(alpha: 0.62),
      ),
    );
  }
}

Color? _noteDayWeekendColor(BuildContext context, DateTime date) {
  final brightness = Theme.of(context).brightness;
  if (date.weekday == DateTime.saturday) {
    return brightness == Brightness.dark
        ? const Color(0xFF7DB7FF)
        : const Color(0xFF0B63CE);
  }
  if (date.weekday == DateTime.sunday) {
    return brightness == Brightness.dark
        ? const Color(0xFFFF8A8A)
        : const Color(0xFFC62828);
  }
  return null;
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({
    required this.note,
    required this.vaultName,
    required this.showVaultName,
    required this.density,
    required this.attachmentPreviewFit,
    required this.query,
    required this.selected,
    required this.onTap,
  });

  final NoteEntry note;
  final String vaultName;
  final bool showVaultName;
  final NotesListDensity density;
  final AttachmentPreviewFit attachmentPreviewFit;
  final String query;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final isPrivateNote = isPrivateVaultId(note.vaultId);
    final changedAt = (note.updatedAt ?? note.createdAt).toLocal();
    final dateLabel =
        '${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;
    final compactPreview = _normalizePreviewText(
      note.body,
      query: query,
      maxChars: 140,
    );
    final bodyPreview = _normalizePreviewText(
      note.body,
      query: query,
      maxChars: 360,
    );
    final tags = note.normalizedTags;
    final previewFacts = _notePreviewFacts(note);
    final hasLocationPreview = _firstLocationPreview(note) != null;
    final showLocationPreviewIconOnly =
        attachmentPreviewFit == AttachmentPreviewFit.icon && hasLocationPreview;
    final visiblePreviewFacts =
        (showLocationPreviewIconOnly
                ? previewFacts.where(
                    (fact) => fact.icon != Icons.location_on_outlined,
                  )
                : previewFacts)
            .take(3)
            .toList(growable: false);
    final hasCompactMediaAttachment = note.attachments.any(
      (attachment) =>
          attachment.type == AttachmentType.photo ||
          attachment.type == AttachmentType.video ||
          attachment.type == AttachmentType.audio,
    );
    final hasDistinctBody =
        bodyPreview.isNotEmpty && bodyPreview != note.title.trim();
    final showAttachmentPreviews = density != NotesListDensity.compact;
    final thumbnailSize = switch (density) {
      NotesListDensity.compact => 44.0,
      NotesListDensity.standard => 56.0,
    };
    const maxThumbs = 3;
    final bodyLines = switch (density) {
      NotesListDensity.compact => 1,
      NotesListDensity.standard => 2,
    };

    if (density == NotesListDensity.compact) {
      return _NoteListTileSelectionSurface(
        selected: selected,
        child: InkWell(
          key: Key('note-tile-${note.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    dateLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (isPrivateNote) ...[
                  const _PrivateNoteMarker(compact: true),
                  const SizedBox(width: 8),
                ],
                if (note.syncState == NoteSyncState.conflict) ...[
                  const _SyncConflictChip(compact: true),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _HighlightedText(
                    text: compactPreview.isEmpty ? note.title : compactPreview,
                    query: query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _strongMutedTextColor(context),
                    ),
                  ),
                ),
                if (note.isPinned) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.push_pin_rounded,
                    size: 14,
                    color: _mutedTextColor(context),
                  ),
                ],
                if (hasLocationPreview) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: _mutedTextColor(context),
                  ),
                ],
                if (hasCompactMediaAttachment) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.perm_media_outlined,
                    size: 14,
                    color: _mutedTextColor(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return _NoteListTileSelectionSurface(
      selected: selected,
      child: InkWell(
        key: Key('note-tile-${note.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isPrivateNote) ...[
                    const _PrivateNoteMarker(),
                    const SizedBox(width: 8),
                  ],
                  if (note.syncState == NoteSyncState.conflict) ...[
                    const _SyncConflictChip(),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _HighlightedText(
                      text: note.title,
                      query: query,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (note.isPinned)
                    Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: _mutedTextColor(context),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (hasDistinctBody)
                _HighlightedText(
                  text: density == NotesListDensity.compact
                      ? compactPreview
                      : bodyPreview,
                  query: query,
                  maxLines: bodyLines,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _strongMutedTextColor(context),
                  ),
                ),
              if (visiblePreviewFacts.isNotEmpty ||
                  showLocationPreviewIconOnly) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final fact in visiblePreviewFacts)
                      _NotePreviewFactChip(fact: fact),
                    if (showLocationPreviewIconOnly)
                      const _NotePreviewFactIcon(
                        icon: Icons.location_on_outlined,
                      ),
                  ],
                ),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags.take(4))
                      _NoteTagChip(tag: tag, compact: true),
                    if (tags.length > 4)
                      _NoteTagChip(tag: '+${tags.length - 4}', compact: true),
                  ],
                ),
              ],
              if (showAttachmentPreviews && note.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (
                      var i = 0;
                      i < note.attachments.length && i < maxThumbs;
                      i++
                    ) ...[
                      Padding(
                        padding: EdgeInsets.only(
                          right: i == maxThumbs - 1 ? 0 : 8,
                        ),
                        child: _NoteListAttachmentPreview(
                          attachment: note.attachments[i],
                          size: thumbnailSize,
                          previewFit: attachmentPreviewFit,
                        ),
                      ),
                    ],
                    if (note.attachments.length > maxThumbs) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          width: thumbnailSize,
                          height: thumbnailSize,
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
                            '+${note.attachments.length - maxThumbs}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (showVaultName)
                    Text(
                      vaultName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isPrivateNote
                            ? Theme.of(context).colorScheme.primary
                            : _mutedTextColor(context),
                        fontWeight: isPrivateNote ? FontWeight.w600 : null,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    isEdited ? strings.noteEditedAt(dateLabel) : dateLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotePreviewFact {
  const _NotePreviewFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _PrivateNoteMarker extends StatelessWidget {
  const _PrivateNoteMarker({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = compact ? 22.0 : 24.0;
    final iconSize = compact ? 13.0 : 14.0;
    return Tooltip(
      message: context.strings.text('home.private.profile'),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.28),
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.lock_outline_rounded,
          size: iconSize,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

class _SyncConflictChip extends StatelessWidget {
  const _SyncConflictChip({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = context.strings.localized(
      en: 'Conflict',
      ja: '競合',
      zh: '冲突',
      ko: '충돌',
      es: 'Conflicto',
      de: 'Konflikt',
    );
    return Tooltip(
      message: context.strings.localized(
        en: 'This note has conflicting local and remote changes.',
        ja: 'このメモはローカルとリモートの変更が競合しています。',
        zh: '此笔记存在本地和远程更改冲突。',
        ko: '이 메모는 로컬 변경과 원격 변경이 충돌합니다.',
        es: 'Esta nota tiene cambios locales y remotos en conflicto.',
        de: 'Diese Notiz hat widersprechende lokale und Remote-Anderungen.',
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.56)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync_problem_rounded,
              size: compact ? 13 : 15,
              color: colorScheme.onErrorContainer,
            ),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncConflictNotice extends StatelessWidget {
  const _SyncConflictNotice({required this.onResolve});

  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.56)),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              strings.localized(
                en: 'This note has conflicting local and remote changes.',
                ja: 'このメモはローカルとリモートの変更が競合しています。',
                zh: '此笔记存在本地和远程更改冲突。',
                ko: '이 메모는 로컬 변경과 원격 변경이 충돌합니다.',
                es: 'Esta nota tiene cambios locales y remotos en conflicto.',
                de: 'Diese Notiz hat widersprechende lokale und Remote-Anderungen.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            onPressed: onResolve,
            icon: const Icon(Icons.rule_rounded),
            label: Text(
              strings.localized(
                en: 'Resolve',
                ja: '解決',
                zh: '解决',
                ko: '해결',
                es: 'Resolver',
                de: 'Losen',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<_NotePreviewFact> _notePreviewFacts(NoteEntry note) {
  final facts = <_NotePreviewFact>[];
  final location = _firstLocationPreview(note);
  if (location != null) {
    facts.add(
      _NotePreviewFact(
        icon: Icons.location_on_outlined,
        label: location.address?.trim().isNotEmpty == true
            ? location.address!.trim()
            : '${location.latitude}, ${location.longitude}',
      ),
    );
  }

  for (final attachment in note.attachments) {
    final durationMs = attachment.durationMs;
    if (durationMs == null || durationMs <= 0) {
      continue;
    }
    final type = attachment.type;
    if (type != AttachmentType.audio && type != AttachmentType.video) {
      continue;
    }
    facts.add(
      _NotePreviewFact(
        icon: type == AttachmentType.audio
            ? Icons.graphic_eq_rounded
            : Icons.videocam_outlined,
        label: _formatAudioDuration(Duration(milliseconds: durationMs)),
      ),
    );
  }
  return facts;
}

_LocationMemoData? _firstLocationPreview(NoteEntry note) {
  final metadataLocation = note.location;
  if (metadataLocation != null) {
    return _locationMemoDataFromMetadata(metadataLocation);
  }
  for (final block in note.blocks) {
    if (block.type != NoteBlockType.paragraph) {
      continue;
    }
    final text = block.text;
    if (text == null || text.trim().isEmpty) {
      continue;
    }
    final location = _tryParseLocationMemo(text);
    if (location != null) {
      return location;
    }
  }
  return _tryParseLocationMemo(note.body);
}

class _NotePreviewFactChip extends StatelessWidget {
  const _NotePreviewFactChip({required this.fact});

  final _NotePreviewFact fact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              fact.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotePreviewFactIcon extends StatelessWidget {
  const _NotePreviewFactIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
    );
  }
}

class _NoteListTileSelectionSurface extends StatelessWidget {
  const _NoteListTileSelectionSurface({
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return Material(color: Colors.transparent, child: child);
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(color: _selectedSurfaceColor(context), child: child),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return Text(text, maxLines: maxLines, overflow: overflow, style: style);
    }
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (true) {
      final matchIndex = lower.indexOf(normalizedQuery, cursor);
      if (matchIndex == -1) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (matchIndex > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, matchIndex)));
      }
      spans.add(
        TextSpan(
          text: text.substring(matchIndex, matchIndex + normalizedQuery.length),
          style: style?.copyWith(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.16),
          ),
        ),
      );
      cursor = matchIndex + normalizedQuery.length;
      if (cursor >= text.length) {
        break;
      }
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

String _normalizePreviewText(
  String value, {
  String query = '',
  int maxChars = 360,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final normalizedQuery = query.trim().toLowerCase();
  var source = trimmed;
  var hasPrefix = false;
  var hasSuffix = false;
  if (normalizedQuery.isNotEmpty) {
    final matchIndex = trimmed.toLowerCase().indexOf(normalizedQuery);
    if (matchIndex > maxChars ~/ 2) {
      final start = math.max(0, matchIndex - (maxChars ~/ 3));
      final end = math.min(trimmed.length, start + maxChars);
      hasPrefix = start > 0;
      hasSuffix = end < trimmed.length;
      source = trimmed.substring(start, end);
    } else if (trimmed.length > maxChars) {
      hasSuffix = true;
      source = trimmed.substring(0, maxChars);
    }
  } else if (trimmed.length > maxChars) {
    hasSuffix = true;
    source = trimmed.substring(0, maxChars);
  }

  final normalized = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return '';
  }
  final prefix = hasPrefix ? '... ' : '';
  final suffix = hasSuffix ? ' ...' : '';
  return '$prefix$normalized$suffix';
}

class _SplitPaneResizeHandle extends StatefulWidget {
  const _SplitPaneResizeHandle({
    required this.onDragDelta,
    required this.onTap,
  });

  final ValueChanged<double> onDragDelta;
  final VoidCallback onTap;

  @override
  State<_SplitPaneResizeHandle> createState() => _SplitPaneResizeHandleState();
}

class _SplitPaneResizeHandleState extends State<_SplitPaneResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;
    final strings = context.strings;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: strings.localized(
          en: 'Drag to resize the note list. Tap to switch widths.',
          ja: 'ドラッグでノート一覧の幅を変更します。タップで幅を切り替えます。',
          zh: '拖动可调整笔记列表宽度。点击可切换宽度。',
          ko: '드래그하여 노트 목록 너비를 조정합니다. 탭하면 너비가 전환됩니다.',
          es: 'Arrastra para cambiar el ancho de la lista. Toca para alternar anchos.',
          de: 'Ziehen, um die Breite der Notizliste zu ändern. Tippen, um Breiten zu wechseln.',
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          onHorizontalDragUpdate: (details) {
            widget.onDragDelta(details.delta.dx);
          },
          child: SizedBox(
            width: 14,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).dividerColor,
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: active ? 5 : 3,
                  height: active ? 56 : 42,
                  decoration: BoxDecoration(
                    color: active
                        ? colorScheme.primary.withValues(alpha: 0.72)
                        : colorScheme.outlineVariant.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(999),
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

class _SplitNotesListPane extends StatefulWidget {
  const _SplitNotesListPane({
    required this.activeIdentity,
    required this.showPrivateVaultNotice,
    required this.notes,
    required this.selectedNoteId,
    required this.vaultNameById,
    required this.showVaultName,
    required this.density,
    required this.sortField,
    required this.attachmentPreviewFit,
    required this.query,
    required this.onAddNote,
    required this.onRefresh,
    required this.onNoteSelected,
  });

  final UnlockIdentity activeIdentity;
  final bool showPrivateVaultNotice;
  final List<NoteEntry> notes;
  final String? selectedNoteId;
  final Map<String, String> vaultNameById;
  final bool showVaultName;
  final NotesListDensity density;
  final NotesListSortField sortField;
  final AttachmentPreviewFit attachmentPreviewFit;
  final String query;
  final VoidCallback onAddNote;
  final Future<void> Function()? onRefresh;
  final ValueChanged<NoteEntry> onNoteSelected;

  @override
  State<_SplitNotesListPane> createState() => _SplitNotesListPaneState();
}

class _SplitNotesListPaneState extends State<_SplitNotesListPane> {
  late List<_SplitNoteRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows();
  }

  @override
  void didUpdateWidget(covariant _SplitNotesListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notes, widget.notes) ||
        oldWidget.density != widget.density ||
        oldWidget.sortField != widget.sortField ||
        oldWidget.attachmentPreviewFit != widget.attachmentPreviewFit ||
        oldWidget.showPrivateVaultNotice != widget.showPrivateVaultNotice ||
        oldWidget.activeIdentity.id != widget.activeIdentity.id) {
      _rows = _buildRows();
    }
  }

  List<_SplitNoteRow> _buildRows() {
    return _buildSplitNoteRows(
      activeIdentity: widget.activeIdentity,
      showPrivateVaultNotice: widget.showPrivateVaultNotice,
      notes: widget.notes,
      density: widget.density,
      sortField: widget.sortField,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      physics: widget.onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        return switch (row) {
          _SplitNoteIdentityRow() => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _IdentityHeader(identity: widget.activeIdentity),
          ),
          _SplitNotePrivateNoticeRow() => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _PrivateVaultLockedNotice(),
          ),
          _SplitNoteToolbarRow() => const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: _NotesToolbar(),
          ),
          _SplitNoteEmptyRow() => const _EmptyNotesState(),
          _SplitNoteDayRow(:final date) => _DecoratedSplitNoteRow(
            position: row.position,
            child: _NoteDayDivider(date: date),
          ),
          _SplitNoteTileRow(:final note) => _DecoratedSplitNoteRow(
            position: row.position,
            child: RepaintBoundary(
              child: _NoteListTile(
                note: note,
                vaultName: widget.vaultNameById[note.vaultId] ?? note.vaultId,
                showVaultName: widget.showVaultName,
                density: widget.density,
                attachmentPreviewFit: widget.attachmentPreviewFit,
                query: widget.query,
                selected: widget.selectedNoteId == note.id,
                onTap: () => widget.onNoteSelected(note),
              ),
            ),
          ),
          _SplitNoteDividerRow() => _DecoratedSplitNoteRow(
            position: row.position,
            child: const _IntraDayNoteGap(),
          ),
        };
      },
    );
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      return list;
    }
    return RefreshIndicator(onRefresh: onRefresh, child: list);
  }
}

List<_SplitNoteRow> _buildSplitNoteRows({
  required UnlockIdentity activeIdentity,
  required bool showPrivateVaultNotice,
  required List<NoteEntry> notes,
  required NotesListDensity density,
  required NotesListSortField sortField,
}) {
  final rows = <_SplitNoteRow>[
    if (activeIdentity.id != 'daily') const _SplitNoteIdentityRow(),
    if (showPrivateVaultNotice) const _SplitNotePrivateNoticeRow(),
    const _SplitNoteToolbarRow(),
  ];
  if (notes.isEmpty) {
    rows.add(const _SplitNoteEmptyRow());
    return rows;
  }

  final noteRows = <_SplitNoteRow>[];
  for (var i = 0; i < notes.length; i++) {
    if (density != NotesListDensity.compact &&
        (i == 0 || !_isSameNoteDay(notes[i - 1], notes[i], sortField))) {
      noteRows.add(_SplitNoteDayRow(_noteListMoment(notes[i], sortField)));
    }
    noteRows.add(_SplitNoteTileRow(notes[i]));
    if (density != NotesListDensity.compact &&
        i != notes.length - 1 &&
        _isSameNoteDay(notes[i], notes[i + 1], sortField)) {
      noteRows.add(const _SplitNoteDividerRow());
    }
  }

  for (var i = 0; i < noteRows.length; i++) {
    rows.add(
      noteRows[i].withPosition(
        _SplitNoteRowPosition(first: i == 0, last: i == noteRows.length - 1),
      ),
    );
  }
  return rows;
}

class _SplitNoteRowPosition {
  const _SplitNoteRowPosition({required this.first, required this.last});

  final bool first;
  final bool last;
}

sealed class _SplitNoteRow {
  const _SplitNoteRow({this.position});

  final _SplitNoteRowPosition? position;

  _SplitNoteRow withPosition(_SplitNoteRowPosition position);
}

class _SplitNoteIdentityRow extends _SplitNoteRow {
  const _SplitNoteIdentityRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNotePrivateNoticeRow extends _SplitNoteRow {
  const _SplitNotePrivateNoticeRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNoteToolbarRow extends _SplitNoteRow {
  const _SplitNoteToolbarRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNoteEmptyRow extends _SplitNoteRow {
  const _SplitNoteEmptyRow();

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) => this;
}

class _SplitNoteDayRow extends _SplitNoteRow {
  const _SplitNoteDayRow(this.date, {super.position});

  final DateTime date;

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) =>
      _SplitNoteDayRow(date, position: position);
}

class _SplitNoteTileRow extends _SplitNoteRow {
  const _SplitNoteTileRow(this.note, {super.position});

  final NoteEntry note;

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) =>
      _SplitNoteTileRow(note, position: position);
}

class _SplitNoteDividerRow extends _SplitNoteRow {
  const _SplitNoteDividerRow({super.position});

  @override
  _SplitNoteRow withPosition(_SplitNoteRowPosition position) =>
      _SplitNoteDividerRow(position: position);
}

class _DecoratedSplitNoteRow extends StatelessWidget {
  const _DecoratedSplitNoteRow({required this.position, required this.child});

  final _SplitNoteRowPosition? position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(pos?.first == true ? 6 : 0),
      bottom: Radius.circular(pos?.last == true ? 6 : 0),
    );
    final border = Border(
      left: BorderSide(color: Theme.of(context).dividerColor),
      right: BorderSide(color: Theme.of(context).dividerColor),
      top: pos?.first == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
      bottom: pos?.last == true
          ? BorderSide(color: Theme.of(context).dividerColor)
          : BorderSide.none,
    );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: borderRadius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );
  }
}
