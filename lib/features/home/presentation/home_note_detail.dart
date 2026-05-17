part of 'home_page.dart';

class _StaticNoteDetailView extends ConsumerWidget {
  const _StaticNoteDetailView({
    required this.notes,
    required this.selectedIndex,
    required this.onSelected,
    required this.onEdit,
    required this.onDelete,
    this.onTagTap,
  });

  final List<NoteEntry> notes;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<NoteEntry> onEdit;
  final ValueChanged<NoteEntry> onDelete;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final note = notes[selectedIndex];
    final canMovePrevious = selectedIndex > 0;
    final canMoveNext = selectedIndex < notes.length - 1;
    _debugNotePerf(
      'detail static build index=$selectedIndex ${_notePerfLabel(note)}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              IconButton(
                onPressed: canMovePrevious
                    ? () => onSelected(selectedIndex - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: strings.text('home.previous.note'),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: canMoveNext
                    ? () => onSelected(selectedIndex + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: strings.text('home.next.note'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Text(
                '${selectedIndex + 1} / ${notes.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _NoteDetailPane(
            note: note,
            isActive: true,
            vaultName: _vaultDisplayName(
              context,
              ref.watch(vaultByIdProvider(note.vaultId)),
            ),
            onEdit: () => onEdit(note),
            onDelete: () => onDelete(note),
            onTagTap: onTagTap,
          ),
        ),
      ],
    );
  }
}

class _NoteDetailPager extends ConsumerStatefulWidget {
  const _NoteDetailPager({
    required this.notes,
    required this.selectedIndex,
    required this.onPageChanged,
    required this.onEdit,
    required this.onDelete,
    this.onClose,
    this.onTagTap,
  });

  final List<NoteEntry> notes;
  final int selectedIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<NoteEntry> onEdit;
  final ValueChanged<NoteEntry> onDelete;
  final VoidCallback? onClose;
  final ValueChanged<String>? onTagTap;

  @override
  ConsumerState<_NoteDetailPager> createState() => _NoteDetailPagerState();
}

class _NoteDetailPagerState extends ConsumerState<_NoteDetailPager> {
  static const double _edgeDismissThreshold = 72;
  late final PageController _pageController;
  int? _programmaticPageTarget;
  double _edgeDismissPull = 0;
  _EdgeDismissDirection? _edgeDismissDirection;
  bool _edgeDismissClosing = false;
  bool _detailScrollAtTop = true;
  bool _detailScrollAtBottom = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.selectedIndex);
  }

  @override
  void didUpdateWidget(covariant _NoteDetailPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _debugNotePerf(
        'detail pager selectedIndex ${oldWidget.selectedIndex}->${widget.selectedIndex}',
      );
    }
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        _pageController.hasClients) {
      final currentPage = _pageController.page?.round();
      if (currentPage != widget.selectedIndex) {
        _debugNotePerf(
          'detail pager jumpToPage ${widget.selectedIndex} current=$currentPage',
        );
        _programmaticPageTarget = widget.selectedIndex;
        _pageController.jumpToPage(widget.selectedIndex);
        Timer(const Duration(milliseconds: 250), () {
          if (mounted && _programmaticPageTarget == widget.selectedIndex) {
            _programmaticPageTarget = null;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _applyEdgeDismissPull(double signedDelta) {
    if (widget.onClose == null || _edgeDismissClosing || signedDelta == 0) {
      return;
    }
    final direction =
        _edgeDismissDirection ??
        (signedDelta > 0
            ? _EdgeDismissDirection.down
            : _EdgeDismissDirection.up);
    final nextPull = switch (direction) {
      _EdgeDismissDirection.down => (_edgeDismissPull + signedDelta).clamp(
        0.0,
        _edgeDismissThreshold,
      ),
      _EdgeDismissDirection.up => (_edgeDismissPull + signedDelta).clamp(
        -_edgeDismissThreshold,
        0.0,
      ),
    };
    if (nextPull != _edgeDismissPull) {
      setState(() {
        _edgeDismissDirection = direction;
        _edgeDismissPull = nextPull.toDouble();
      });
    } else if (_edgeDismissDirection == null) {
      setState(() {
        _edgeDismissDirection = direction;
      });
    }
  }

  void _resetEdgeDismissPull() {
    if (_edgeDismissPull == 0 && _edgeDismissDirection == null) {
      return;
    }
    setState(() {
      _edgeDismissPull = 0;
      _edgeDismissDirection = null;
    });
  }

  void _finishEdgeDismissGesture() {
    if (_edgeDismissClosing || _edgeDismissPull == 0) {
      return;
    }
    if (_edgeDismissPull.abs() >= _edgeDismissThreshold) {
      _edgeDismissClosing = true;
      widget.onClose?.call();
      return;
    }
    _resetEdgeDismissPull();
  }

  bool _handleDetailScrollNotification(ScrollNotification notification) {
    if (widget.onClose == null ||
        _edgeDismissClosing ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final metrics = notification.metrics;
    final isAtTop = metrics.pixels <= metrics.minScrollExtent + 2;
    final isAtBottom = metrics.pixels >= metrics.maxScrollExtent - 2;
    _detailScrollAtTop = isAtTop;
    _detailScrollAtBottom = isAtBottom;
    if (notification is OverscrollNotification) {
      if (isAtTop && notification.overscroll < 0) {
        _applyEdgeDismissPull(-notification.overscroll);
        return false;
      }
      if (isAtBottom && notification.overscroll > 0) {
        _applyEdgeDismissPull(-notification.overscroll);
        return false;
      }
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      if (!isAtTop && !isAtBottom && _edgeDismissPull != 0) {
        _resetEdgeDismissPull();
      }
      return false;
    }

    if (notification is ScrollEndNotification && _edgeDismissPull != 0) {
      _finishEdgeDismissGesture();
    }
    return false;
  }

  void _handleDetailPointerMove(PointerMoveEvent event) {
    if (_detailScrollAtTop && event.delta.dy > 0) {
      _applyEdgeDismissPull(event.delta.dy);
    } else if (_detailScrollAtBottom && event.delta.dy < 0) {
      _applyEdgeDismissPull(event.delta.dy);
    } else if (_edgeDismissPull != 0) {
      _resetEdgeDismissPull();
    }
  }

  void _handleDetailPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (_detailScrollAtTop && event.scrollDelta.dy < 0) {
      _applyEdgeDismissPull(-event.scrollDelta.dy * 0.3);
    } else if (_detailScrollAtBottom && event.scrollDelta.dy > 0) {
      _applyEdgeDismissPull(-event.scrollDelta.dy * 0.3);
    }
  }

  void _handleHeaderDismissDragUpdate(DragUpdateDetails details) {
    if (widget.onClose == null || _edgeDismissClosing) {
      return;
    }
    final delta = details.primaryDelta ?? 0;
    if (delta != 0) {
      _applyEdgeDismissPull(delta);
    }
  }

  void _handleHeaderDismissDragEnd(DragEndDetails details) {
    _finishEdgeDismissGesture();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canMovePrevious = widget.selectedIndex > 0;
    final canMoveNext = widget.selectedIndex < widget.notes.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _handleHeaderDismissDragUpdate,
          onVerticalDragEnd: _handleHeaderDismissDragEnd,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: strings.close,
                    visualDensity: VisualDensity.compact,
                  ),
                const Spacer(),
                IconButton(
                  onPressed: canMovePrevious
                      ? () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: strings.text('home.previous.note'),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: canMoveNext
                      ? () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: strings.text('home.next.note'),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  '${widget.selectedIndex + 1} / ${widget.notes.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleDetailScrollNotification,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: _handleDetailPointerMove,
              onPointerUp: (_) => _finishEdgeDismissGesture(),
              onPointerCancel: (_) => _resetEdgeDismissPull(),
              onPointerSignal: _handleDetailPointerSignal,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: widget.notes.length,
                    onPageChanged: (index) {
                      final programmaticTarget = _programmaticPageTarget;
                      if (programmaticTarget != null) {
                        if (index == programmaticTarget) {
                          _programmaticPageTarget = null;
                        }
                        _debugNotePerf(
                          'detail pager ignored programmatic onPageChanged index=$index target=$programmaticTarget',
                        );
                        return;
                      }
                      widget.onPageChanged(index);
                    },
                    itemBuilder: (context, index) {
                      final note = widget.notes[index];
                      _debugNotePerf(
                        'detail page build index=$index ${_notePerfLabel(note)}',
                      );
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _NoteDetailPane(
                          note: note,
                          isActive: index == widget.selectedIndex,
                          vaultName: _vaultDisplayName(
                            context,
                            ref.watch(vaultByIdProvider(note.vaultId)),
                          ),
                          onEdit: () => widget.onEdit(note),
                          onDelete: () => widget.onDelete(note),
                          onTagTap: widget.onTagTap,
                        ),
                      );
                    },
                  ),
                  if (widget.onClose != null)
                    _EdgePullDismissHint(
                      progress: _edgeDismissPull.abs() / _edgeDismissThreshold,
                      direction:
                          _edgeDismissDirection ?? _EdgeDismissDirection.down,
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

enum _EdgeDismissDirection { up, down }

class _EdgePullDismissHint extends StatelessWidget {
  const _EdgePullDismissHint({required this.progress, required this.direction});

  final double progress;
  final _EdgeDismissDirection direction;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = progress.clamp(0.0, 1.0);
    final visible = effectiveProgress > 0.04;
    final colorScheme = Theme.of(context).colorScheme;
    final strings = context.strings;
    final isUp = direction == _EdgeDismissDirection.up;
    return Positioned(
      left: 0,
      right: 0,
      top: isUp ? null : 16,
      bottom: isUp ? 16 : null,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: Offset(0, visible ? 0 : (isUp ? 0.2 : -0.2)),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Center(
              child: SizedBox(
                width: 252,
                height: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.inverseSurface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(
                            0,
                            (isUp ? -3 : 3) * effectiveProgress,
                          ),
                          child: Icon(
                            effectiveProgress >= 1
                                ? (isUp
                                      ? Icons.keyboard_double_arrow_up_rounded
                                      : Icons
                                            .keyboard_double_arrow_down_rounded)
                                : (isUp
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded),
                            color: colorScheme.onInverseSurface,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            effectiveProgress >= 0.92
                                ? strings.close
                                : strings.localized(
                                    en: 'Release past the edge to close',
                                    ja: 'さらに下へスクロールして閉じる',
                                    zh: '继续向下滚动以关闭',
                                    ko: '더 아래로 스크롤해 닫기',
                                    es: 'Sigue desplazando para cerrar',
                                    de: 'Weiter scrollen zum Schließen',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: colorScheme.onInverseSurface),
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
      ),
    );
  }
}

enum _NoteDetailAction { copy, share }

Future<void> _handleNoteDetailAction(
  BuildContext context,
  NoteEntry note,
  _NoteDetailAction action,
) async {
  final text = _shareTextForNote(note);
  switch (action) {
    case _NoteDetailAction.copy:
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            context.strings.localized(
              en: 'Note text copied.',
              ja: 'メモのテキストをコピーしました。',
              zh: '已复制笔记文本。',
              ko: '메모 텍스트를 복사했습니다.',
              es: 'Texto de la nota copiado.',
              de: 'Notiztext kopiert.',
            ),
          ),
        ),
      );
    case _NoteDetailAction.share:
      await SharePlus.instance.share(
        ShareParams(text: text, subject: note.title),
      );
  }
}

String _shareTextForNote(NoteEntry note) {
  final buffer = StringBuffer(note.title.trim());
  final body = note.body.trim();
  if (body.isNotEmpty && body != note.title.trim()) {
    buffer
      ..writeln()
      ..writeln()
      ..write(body);
  }
  if (note.tags.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(note.tags.map((tag) => '#$tag').join(' '));
  }
  if (note.location != null) {
    final location = note.location!;
    buffer
      ..writeln()
      ..writeln(
        location.address?.trim().isNotEmpty == true
            ? location.address!.trim()
            : '${location.latitude}, ${location.longitude}',
      );
  }
  return buffer.toString().trim();
}

class _NoteDetailPane extends ConsumerStatefulWidget {
  const _NoteDetailPane({
    required this.note,
    required this.isActive,
    required this.vaultName,
    this.onEdit,
    this.onDelete,
    this.onTagTap,
  });

  final NoteEntry note;
  final bool isActive;
  final String vaultName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onTagTap;

  @override
  ConsumerState<_NoteDetailPane> createState() => _NoteDetailPaneState();
}

class _NoteDetailPaneState extends ConsumerState<_NoteDetailPane> {
  late final TextEditingController _detailSearchController;
  final ScrollController _detailScrollController = ScrollController();
  final GlobalKey _detailTitleKey = GlobalKey();
  final Map<int, GlobalKey> _detailContentItemKeys = <int, GlobalKey>{};
  String _detailSearchQuery = '';
  bool _detailSearchVisible = false;
  bool _detailSearchNavigatorPinned = false;
  int? _detailSearchTargetIndex;
  int _detailSearchScrollRequest = 0;
  String? _pendingInitialSearchJumpNoteId;

  @override
  void initState() {
    super.initState();
    _detailSearchQuery = ref.read(searchQueryProvider).trim();
    _detailSearchVisible = _detailSearchQuery.isNotEmpty;
    _pendingInitialSearchJumpNoteId = _detailSearchVisible
        ? widget.note.id
        : null;
    _detailSearchController = TextEditingController(text: _detailSearchQuery);
    _detailScrollController.addListener(_handleDetailScroll);
  }

  @override
  void didUpdateWidget(covariant _NoteDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id == widget.note.id) {
      return;
    }
    final listSearchQuery = ref.read(searchQueryProvider).trim();
    _detailSearchTargetIndex = null;
    if (listSearchQuery.isEmpty) {
      _pendingInitialSearchJumpNoteId = null;
      return;
    }
    _detailSearchVisible = true;
    _detailSearchQuery = listSearchQuery;
    _detailSearchController.value = TextEditingValue(
      text: listSearchQuery,
      selection: TextSelection.collapsed(offset: listSearchQuery.length),
    );
    _pendingInitialSearchJumpNoteId = widget.note.id;
  }

  @override
  void dispose() {
    _detailScrollController.removeListener(_handleDetailScroll);
    _detailSearchController.dispose();
    _detailScrollController.dispose();
    super.dispose();
  }

  void _handleDetailScroll() {
    if (!_detailScrollController.hasClients) {
      return;
    }
    final shouldPinNavigator = _detailScrollController.offset > 120;
    if (shouldPinNavigator == _detailSearchNavigatorPinned) {
      return;
    }
    setState(() {
      _detailSearchNavigatorPinned = shouldPinNavigator;
    });
  }

  void _toggleDetailSearch(String fallbackQuery) {
    setState(() {
      _detailSearchVisible = !_detailSearchVisible;
      if (_detailSearchVisible && _detailSearchController.text.isEmpty) {
        _detailSearchQuery = fallbackQuery;
        _detailSearchController.text = fallbackQuery;
      }
      if (!_detailSearchVisible) {
        _detailSearchNavigatorPinned = false;
      }
      _pendingInitialSearchJumpNoteId =
          _detailSearchVisible && _detailSearchController.text.trim().isNotEmpty
          ? widget.note.id
          : null;
    });
  }

  void _clearDetailSearch() {
    if (_detailSearchController.text.isNotEmpty) {
      _detailSearchController.clear();
    }
    setState(() {
      _detailSearchQuery = '';
      _detailSearchTargetIndex = null;
      _detailSearchNavigatorPinned = false;
      _pendingInitialSearchJumpNoteId = null;
    });
  }

  void _setDetailSearchQuery(String value) {
    setState(() {
      _detailSearchQuery = value;
      _detailSearchTargetIndex = null;
      _pendingInitialSearchJumpNoteId = null;
    });
  }

  GlobalKey _detailContentItemKey(int index) =>
      _detailContentItemKeys.putIfAbsent(index, GlobalKey.new);

  List<_NoteDetailSearchTarget> _buildDetailSearchTargets({
    required NoteEntry note,
    required List<_DetailContentItem> items,
    required String query,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const <_NoteDetailSearchTarget>[];
    }
    final targets = <_NoteDetailSearchTarget>[];
    targets.addAll(
      _noteDetailSearchTargetsForText(
        key: _detailTitleKey,
        text: note.title,
        query: normalizedQuery,
      ),
    );
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final text = item.text ?? _locationSearchText(item.location);
      if (text != null) {
        targets.addAll(
          _noteDetailSearchTargetsForText(
            key: _detailContentItemKey(index),
            text: text,
            query: normalizedQuery,
            scrollText: item.text,
          ),
        );
      }
    }
    return targets;
  }

  void _jumpDetailSearch(List<_NoteDetailSearchTarget> targets, int delta) {
    if (targets.isEmpty) {
      return;
    }
    final current = _detailSearchTargetIndex;
    final next = current == null
        ? (delta >= 0 ? 0 : targets.length - 1)
        : (current + delta) % targets.length;
    final normalizedNext = next < 0 ? targets.length - 1 : next;
    final scrollPolicy = _detailSearchScrollPolicy(
      current: current,
      next: normalizedNext,
      delta: delta,
    );
    final useEdgeScroll =
        (scrollPolicy == ScrollPositionAlignmentPolicy.keepVisibleAtEnd &&
            normalizedNext == targets.length - 1) ||
        (scrollPolicy == ScrollPositionAlignmentPolicy.keepVisibleAtStart &&
            normalizedNext == 0);
    setState(() {
      _detailSearchTargetIndex = normalizedNext;
    });
    _scheduleDetailSearchTargetVisibilityCheck(
      targets[normalizedNext],
      scrollPolicy,
      useEdgeScroll: useEdgeScroll,
    );
  }

  ScrollPositionAlignmentPolicy _detailSearchScrollPolicy({
    required int? current,
    required int next,
    required int delta,
  }) {
    final movingDown = current == null
        ? delta >= 0
        : next == current
        ? delta >= 0
        : next > current;
    return movingDown
        ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
        : ScrollPositionAlignmentPolicy.keepVisibleAtStart;
  }

  void _scheduleDetailSearchTargetVisibilityCheck(
    _NoteDetailSearchTarget target,
    ScrollPositionAlignmentPolicy scrollPolicy, {
    required bool useEdgeScroll,
  }) {
    final request = ++_detailSearchScrollRequest;
    final movingDown =
        scrollPolicy == ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDetailSearchTargetVisible(
        target,
        request,
        alignment: movingDown ? 0.78 : 0.12,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: const Duration(milliseconds: 220),
        fallbackToEnd: movingDown,
      );
      for (final delay in const [
        Duration(milliseconds: 260),
        Duration(milliseconds: 900),
      ]) {
        unawaited(
          Future<void>.delayed(delay, () {
            _ensureDetailSearchTargetVisible(
              target,
              request,
              alignment: movingDown ? 0.78 : 0.12,
              alignmentPolicy: scrollPolicy,
              duration: Duration.zero,
              fallbackToEnd: movingDown,
            );
          }),
        );
      }
      if (useEdgeScroll) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 1100), () {
            if (!mounted || request != _detailSearchScrollRequest) {
              return;
            }
            _fallbackDetailSearchScroll(
              movingDown,
              Duration.zero,
              position: _detailSearchScrollPosition(target.key.currentContext),
            );
          }),
        );
      }
    });
  }

  void _ensureDetailSearchTargetVisible(
    _NoteDetailSearchTarget searchTarget,
    int request, {
    required double alignment,
    required ScrollPositionAlignmentPolicy alignmentPolicy,
    required Duration duration,
    required bool fallbackToEnd,
  }) {
    if (!mounted || request != _detailSearchScrollRequest) {
      return;
    }
    final targetKey = searchTarget.key;
    final targetContext = targetKey.currentContext;
    if (targetContext == null) {
      _fallbackDetailSearchScroll(fallbackToEnd, duration);
      return;
    }
    final position = _detailSearchScrollPosition(targetContext);
    if (position == null) {
      return;
    }
    final target = targetContext.findRenderObject();
    if (target == null) {
      _fallbackDetailSearchScroll(fallbackToEnd, duration, position: position);
      return;
    }
    final revealOffset = _detailSearchMatchRevealOffset(
      targetContext,
      target,
      searchTarget,
      alignment,
    );
    if (revealOffset != null) {
      final nextOffset = revealOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((nextOffset - position.pixels).abs() < 1) {
        return;
      }
      if (duration == Duration.zero) {
        position.jumpTo(nextOffset);
        return;
      }
      unawaited(
        position.animateTo(
          nextOffset,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      );
      return;
    }
    unawaited(
      position.ensureVisible(
        target,
        alignment: alignment,
        duration: duration,
        curve: Curves.easeOutCubic,
        alignmentPolicy: alignmentPolicy,
      ),
    );
  }

  double? _detailSearchMatchRevealOffset(
    BuildContext targetContext,
    RenderObject target,
    _NoteDetailSearchTarget searchTarget,
    double alignment,
  ) {
    final text = searchTarget.scrollText;
    if (text == null || target is! RenderBox || target.size.width <= 0) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) {
      return null;
    }
    final textLength = text.length;
    if (textLength == 0) {
      return null;
    }
    final start = searchTarget.matchStart.clamp(0, textLength);
    final end = (start + searchTarget.matchLength).clamp(start, textLength);
    final style = Theme.of(targetContext).textTheme.bodyLarge;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(targetContext),
    )..layout(maxWidth: target.size.width);
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    if (boxes.isEmpty) {
      return null;
    }
    final rect = boxes.first
        .toRect()
        .inflate(8)
        .intersect(Offset.zero & target.size);
    if (rect.isEmpty) {
      return null;
    }
    return viewport.getOffsetToReveal(target, alignment, rect: rect).offset;
  }

  ScrollPosition? _detailSearchScrollPosition(BuildContext? targetContext) {
    final targetPosition = targetContext == null
        ? null
        : Scrollable.maybeOf(targetContext)?.position;
    if (targetPosition != null) {
      return targetPosition;
    }
    if (_detailScrollController.hasClients) {
      return _detailScrollController.position;
    }
    return null;
  }

  void _fallbackDetailSearchScroll(
    bool toEnd,
    Duration duration, {
    ScrollPosition? position,
  }) {
    final scrollPosition = position ?? _detailSearchScrollPosition(null);
    if (scrollPosition == null) {
      return;
    }
    final targetOffset = toEnd
        ? scrollPosition.maxScrollExtent
        : scrollPosition.minScrollExtent;
    if ((targetOffset - scrollPosition.pixels).abs() < 1) {
      return;
    }
    if (duration == Duration.zero) {
      scrollPosition.jumpTo(targetOffset);
      return;
    }
    unawaited(
      scrollPosition.animateTo(
        targetOffset,
        duration: duration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _scheduleInitialDetailSearchJump(List<_NoteDetailSearchTarget> targets) {
    final pendingNoteId = _pendingInitialSearchJumpNoteId;
    if (pendingNoteId == null ||
        pendingNoteId != widget.note.id ||
        !_detailSearchVisible ||
        _detailSearchQuery.trim().isEmpty ||
        targets.isEmpty) {
      return;
    }
    _pendingInitialSearchJumpNoteId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.note.id != pendingNoteId) {
        return;
      }
      _jumpDetailSearch(targets, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final note = ref.watch(
      notesControllerProvider.select((notes) {
        for (final candidate in notes) {
          if (candidate.id == widget.note.id) {
            return candidate;
          }
        }
        return widget.note;
      }),
    );
    final listSearchQuery = ref.watch(searchQueryProvider).trim();
    final highlightQuery = _detailSearchVisible
        ? _detailSearchQuery.trim()
        : listSearchQuery;
    final detailContentItems = _buildDetailContentItems(note);
    final detailSearchTargets = _buildDetailSearchTargets(
      note: note,
      items: detailContentItems,
      query: highlightQuery,
    );
    _scheduleInitialDetailSearchJump(detailSearchTargets);
    final detailSearchTargetIndex = _detailSearchTargetIndex;
    final activeSearchTarget = detailSearchTargetIndex == null
        ? null
        : detailSearchTargets.elementAtOrNull(detailSearchTargetIndex);
    final detailSearchPositionLabel = detailSearchTargets.isEmpty
        ? '0 / 0'
        : '${((detailSearchTargetIndex ?? 0) + 1).clamp(1, detailSearchTargets.length)} / ${detailSearchTargets.length}';
    final createdAt = note.createdAt.toLocal();
    final createdLabel =
        '${createdAt.year}/${createdAt.month}/${createdAt.day} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    final changedAt = (note.updatedAt ?? note.createdAt).toLocal();
    final updatedLabel =
        '${changedAt.year}/${changedAt.month}/${changedAt.day} ${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final isEdited = note.updatedAt != null && note.updatedAt != note.createdAt;
    final tags = note.normalizedTags;
    final buildWatch = kDebugMode ? (Stopwatch()..start()) : null;
    if (buildWatch != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        buildWatch.stop();
        _debugNotePerf(
          'detail pane frame ${buildWatch.elapsedMicroseconds / 1000}ms ${_notePerfLabel(note)} tags=${tags.length}',
        );
      });
    }

    return Container(
      decoration: _sectionDecoration(context),
      child: Stack(
        children: [
          CustomScrollView(
            controller: _detailScrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.vaultName,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: _mutedTextColor(context)),
                          ),
                        ),
                        IconButton(
                          onPressed: () => ref
                              .read(notesControllerProvider.notifier)
                              .togglePinned(note.id),
                          icon: Icon(
                            note.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                          ),
                          tooltip: note.isPinned
                              ? strings.localized(
                                  en: 'Unpin note',
                                  ja: 'ピン留めを解除',
                                  zh: '取消置顶',
                                  ko: '고정 해제',
                                  es: 'Desfijar nota',
                                  de: 'Notiz lösen',
                                )
                              : strings.pinThisNote,
                        ),
                        IconButton(
                          key: const Key('note-detail-search-button'),
                          onPressed: () => _toggleDetailSearch(highlightQuery),
                          icon: Icon(
                            _detailSearchVisible
                                ? Icons.search_off_rounded
                                : Icons.search_rounded,
                          ),
                          tooltip: _detailSearchVisible
                              ? strings.localized(
                                  en: 'Hide note search',
                                  ja: 'メモ内検索を閉じる',
                                )
                              : strings.localized(
                                  en: 'Search in note',
                                  ja: 'メモ内を検索',
                                ),
                        ),
                        PopupMenuButton<_NoteDetailAction>(
                          tooltip: strings.localized(
                            en: 'Note actions',
                            ja: 'メモ操作',
                            zh: '笔记操作',
                            ko: '메모 작업',
                            es: 'Acciones de nota',
                            de: 'Notizaktionen',
                          ),
                          icon: const Icon(Icons.more_horiz_rounded),
                          onSelected: (action) =>
                              _handleNoteDetailAction(context, note, action),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _NoteDetailAction.copy,
                              child: _MediaMenuEntry(
                                icon: Icons.content_copy_rounded,
                                label: strings.localized(
                                  en: 'Copy text',
                                  ja: 'テキストをコピー',
                                  zh: '复制文本',
                                  ko: '텍스트 복사',
                                  es: 'Copiar texto',
                                  de: 'Text kopieren',
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: _NoteDetailAction.share,
                              child: _MediaMenuEntry(
                                icon: Icons.ios_share_rounded,
                                label: strings.localized(
                                  en: 'Share',
                                  ja: '共有',
                                  zh: '分享',
                                  ko: '공유',
                                  es: 'Compartir',
                                  de: 'Teilen',
                                ),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          key: const Key('edit-note-button'),
                          onPressed: widget.onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: strings.editNote,
                        ),
                        IconButton(
                          key: const Key('note-detail-delete-button'),
                          onPressed: widget.onDelete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: strings.deleteNote,
                        ),
                      ],
                    ),
                    if (_detailSearchVisible) ...[
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('note-detail-search-input'),
                        controller: _detailSearchController,
                        decoration: InputDecoration(
                          labelText: strings.localized(
                            en: 'Search in this note',
                            ja: 'このメモ内を検索',
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _detailSearchQuery.isNotEmpty
                              ? IconButton(
                                  key: const Key(
                                    'note-detail-search-clear-button',
                                  ),
                                  tooltip: strings.localized(
                                    en: 'Clear note search',
                                    ja: 'メモ内検索をクリア',
                                  ),
                                  onPressed: _clearDetailSearch,
                                  icon: const Icon(Icons.clear_rounded),
                                )
                              : null,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: _setDetailSearchQuery,
                        onSubmitted: (_) =>
                            _jumpDetailSearch(detailSearchTargets, 1),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            key: const Key(
                              'note-detail-search-previous-button',
                            ),
                            onPressed: detailSearchTargets.isEmpty
                                ? null
                                : () => _jumpDetailSearch(
                                    detailSearchTargets,
                                    -1,
                                  ),
                            tooltip: strings.localized(
                              en: 'Previous match',
                              ja: '前の一致へ',
                            ),
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          Text(
                            detailSearchPositionLabel,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: _mutedTextColor(context)),
                          ),
                          IconButton(
                            key: const Key('note-detail-search-next-button'),
                            onPressed: detailSearchTargets.isEmpty
                                ? null
                                : () =>
                                      _jumpDetailSearch(detailSearchTargets, 1),
                            tooltip: strings.localized(
                              en: 'Next match',
                              ja: '次の一致へ',
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    _HighlightedInlineText(
                      key: _detailTitleKey,
                      text: note.title,
                      query: highlightQuery,
                      activeMatchStart:
                          activeSearchTarget?.key == _detailTitleKey
                          ? activeSearchTarget?.matchStart
                          : null,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isEdited
                          ? strings.noteEditedAt(updatedLabel)
                          : createdLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedTextColor(context),
                      ),
                    ),
                    if (note.syncState == NoteSyncState.conflict) ...[
                      const SizedBox(height: 12),
                      _SyncConflictNotice(
                        onResolve: () =>
                            _showNoteConflictResolver(context, ref, note),
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in tags)
                            _NoteTagChip(
                              tag: tag,
                              onTap: widget.onTagTap == null
                                  ? null
                                  : () => widget.onTagTap!(tag),
                            ),
                        ],
                      ),
                    ],
                    if (isEdited)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          strings.noteCreatedRevision(
                            createdLabel,
                            note.revision,
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _mutedTextColor(context)),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: _DetailContentSliver(
                  note: note,
                  items: detailContentItems,
                  itemKeys: _detailContentItemKeys,
                  mediaActive: widget.isActive,
                  highlightQuery: highlightQuery,
                  activeSearchTarget: activeSearchTarget,
                ),
              ),
            ],
          ),
          if (_detailSearchVisible && _detailSearchNavigatorPinned)
            Positioned(
              top: 10,
              right: 12,
              child: _FloatingNoteSearchNavigator(
                positionLabel: detailSearchPositionLabel,
                hasMatches: detailSearchTargets.isNotEmpty,
                onPrevious: () => _jumpDetailSearch(detailSearchTargets, -1),
                onNext: () => _jumpDetailSearch(detailSearchTargets, 1),
              ),
            ),
        ],
      ),
    );
  }
}

class _FloatingNoteSearchNavigator extends StatelessWidget {
  const _FloatingNoteSearchNavigator({
    required this.positionLabel,
    required this.hasMatches,
    required this.onPrevious,
    required this.onNext,
  });

  final String positionLabel;
  final bool hasMatches;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = context.strings;
    return Material(
      elevation: 3,
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('note-detail-search-floating-previous-button'),
              visualDensity: VisualDensity.compact,
              onPressed: hasMatches ? onPrevious : null,
              tooltip: strings.localized(en: 'Previous match', ja: '蜑阪・荳閾ｴ縺ｸ'),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            Text(
              positionLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _mutedTextColor(context),
              ),
            ),
            IconButton(
              key: const Key('note-detail-search-floating-next-button'),
              visualDensity: VisualDensity.compact,
              onPressed: hasMatches ? onNext : null,
              tooltip: strings.localized(en: 'Next match', ja: '谺｡縺ｮ荳閾ｴ縺ｸ'),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkifiedMemoText extends StatefulWidget {
  const _LinkifiedMemoText({
    required this.text,
    this.style,
    this.query = '',
    this.activeMatchStart,
  });

  final String text;
  final TextStyle? style;
  final String query;
  final int? activeMatchStart;

  @override
  State<_LinkifiedMemoText> createState() => _LinkifiedMemoTextState();
}

class _LinkifiedMemoTextState extends State<_LinkifiedMemoText> {
  static final _urlPattern = RegExp(r'((?:https?:\/\/|www\.)[^\s<>()]+)');
  final List<TapGestureRecognizer> _recognizers = [];
  late List<_MemoTextSegment> _segments;

  @override
  void initState() {
    super.initState();
    _segments = _parseSegments(widget.text);
  }

  @override
  void didUpdateWidget(covariant _LinkifiedMemoText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
      _segments = _parseSegments(widget.text);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final highlightStyle = _noteSearchHighlightStyle(context, style);
    if (_segments.length == 1 &&
        !_segments.single.isLink &&
        widget.query.trim().isEmpty) {
      return SelectableText(_segments.single.text, style: style);
    }

    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );
    final span = TextSpan(
      style: style,
      children: [
        for (final segment in _segments)
          ..._highlightTextSpans(
            text: segment.text,
            query: widget.query,
            baseStyle: segment.isLink ? linkStyle : null,
            highlightStyle: highlightStyle,
            activeHighlightStyle: _noteSearchActiveHighlightStyle(
              context,
              style,
            ),
            activeMatchStart: widget.activeMatchStart,
            segmentStart: segment.start,
            recognizer: segment.recognizer,
          ),
      ],
    );
    if (widget.query.trim().isNotEmpty) {
      return Text.rich(span);
    }
    return SelectableText.rich(span);
  }

  List<_MemoTextSegment> _parseSegments(String text) {
    final matches = _urlPattern.allMatches(text).toList(growable: false);
    if (matches.isEmpty) {
      return [_MemoTextSegment.text(text, 0)];
    }

    final segments = <_MemoTextSegment>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        segments.add(
          _MemoTextSegment.text(text.substring(cursor, match.start), cursor),
        );
      }

      final rawMatch = match.group(0)!;
      final trimmed = _trimTrailingUrlPunctuation(rawMatch);
      final trailing = rawMatch.substring(trimmed.length);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openMemoLink(context, trimmed);
      _recognizers.add(recognizer);
      segments.add(_MemoTextSegment.link(trimmed, match.start, recognizer));
      if (trailing.isNotEmpty) {
        segments.add(
          _MemoTextSegment.text(trailing, match.start + trimmed.length),
        );
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      segments.add(_MemoTextSegment.text(text.substring(cursor), cursor));
    }
    return segments;
  }
}

class _HighlightedInlineText extends StatelessWidget {
  const _HighlightedInlineText({
    super.key,
    required this.text,
    required this.query,
    this.activeMatchStart,
    this.style,
  });

  final String text;
  final String query;
  final int? activeMatchStart;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return Text(text, style: style);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: _highlightTextSpans(
          text: text,
          query: normalizedQuery,
          highlightStyle: _noteSearchHighlightStyle(context, style),
          activeHighlightStyle: _noteSearchActiveHighlightStyle(context, style),
          activeMatchStart: activeMatchStart,
        ),
      ),
      overflow: TextOverflow.clip,
    );
  }
}

class _NoteDetailSearchTarget {
  const _NoteDetailSearchTarget({
    required this.key,
    required this.matchStart,
    required this.matchLength,
    this.scrollText,
  });

  final GlobalKey key;
  final int matchStart;
  final int matchLength;
  final String? scrollText;
}

TextStyle _noteSearchHighlightStyle(BuildContext context, TextStyle? style) {
  final colorScheme = Theme.of(context).colorScheme;
  return (style ?? const TextStyle()).copyWith(
    backgroundColor: colorScheme.primary.withValues(alpha: 0.18),
    color: colorScheme.onSurface,
  );
}

TextStyle _noteSearchActiveHighlightStyle(
  BuildContext context,
  TextStyle? style,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return (style ?? const TextStyle()).copyWith(
    backgroundColor: colorScheme.tertiaryContainer,
    color: colorScheme.onTertiaryContainer,
    fontWeight: FontWeight.w700,
  );
}

List<TextSpan> _highlightTextSpans({
  required String text,
  required String query,
  TextStyle? baseStyle,
  required TextStyle highlightStyle,
  required TextStyle activeHighlightStyle,
  int? activeMatchStart,
  int segmentStart = 0,
  TapGestureRecognizer? recognizer,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty || text.isEmpty) {
    return [TextSpan(text: text, style: baseStyle, recognizer: recognizer)];
  }
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var cursor = 0;
  while (cursor < text.length) {
    final matchIndex = lower.indexOf(normalizedQuery, cursor);
    if (matchIndex == -1) {
      spans.add(
        TextSpan(
          text: text.substring(cursor),
          style: baseStyle,
          recognizer: recognizer,
        ),
      );
      break;
    }
    if (matchIndex > cursor) {
      spans.add(
        TextSpan(
          text: text.substring(cursor, matchIndex),
          style: baseStyle,
          recognizer: recognizer,
        ),
      );
    }
    final absoluteMatchStart = segmentStart + matchIndex;
    spans.add(
      TextSpan(
        text: text.substring(matchIndex, matchIndex + normalizedQuery.length),
        style:
            (activeMatchStart == absoluteMatchStart
                    ? activeHighlightStyle
                    : highlightStyle)
                .merge(baseStyle),
        recognizer: recognizer,
      ),
    );
    cursor = matchIndex + normalizedQuery.length;
  }
  return spans;
}

List<_NoteDetailSearchTarget> _noteDetailSearchTargetsForText({
  required GlobalKey key,
  required String text,
  required String query,
  String? scrollText,
}) {
  if (query.isEmpty || text.isEmpty) {
    return const <_NoteDetailSearchTarget>[];
  }
  final lower = text.toLowerCase();
  final targets = <_NoteDetailSearchTarget>[];
  var cursor = 0;
  while (cursor < text.length) {
    final matchIndex = lower.indexOf(query, cursor);
    if (matchIndex == -1) {
      break;
    }
    targets.add(
      _NoteDetailSearchTarget(
        key: key,
        matchStart: matchIndex,
        matchLength: query.length,
        scrollText: scrollText,
      ),
    );
    cursor = matchIndex + query.length;
  }
  return targets;
}

class _MemoTextSegment {
  const _MemoTextSegment.text(this.text, this.start)
    : recognizer = null,
      isLink = false;

  const _MemoTextSegment.link(this.text, this.start, this.recognizer)
    : isLink = true;

  final String text;
  final int start;
  final TapGestureRecognizer? recognizer;
  final bool isLink;
}

String _trimTrailingUrlPunctuation(String value) {
  var end = value.length;
  while (end > 0 && '.,;:!?、。)]）}'.contains(value[end - 1])) {
    end -= 1;
  }
  return value.substring(0, end);
}

Future<void> _openMemoLink(BuildContext context, String rawUrl) async {
  final normalized = rawUrl.startsWith(RegExp(r'https?://'))
      ? rawUrl
      : 'https://$rawUrl';
  final shouldOpen = await _confirmExternalLinkOpen(context, normalized);
  if (!shouldOpen || !context.mounted) {
    return;
  }
  final uri = Uri.tryParse(normalized);
  if (uri != null) {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        return;
      }
    } catch (_) {
      // Show a visible failure below.
    }
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      showCloseIcon: true,
      content: Text(context.strings.linkOpenFailed),
    ),
  );
}

Future<bool> _confirmExternalLinkOpen(BuildContext context, String url) async {
  final strings = context.strings;
  return await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(strings.openExternalLinkTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.openExternalLinkMessage),
                const SizedBox(height: 12),
                SelectableText(
                  url,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(strings.cancel),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(strings.openLink),
              ),
            ],
          );
        },
      ) ??
      false;
}

class _DetailContentSliver extends StatefulWidget {
  const _DetailContentSliver({
    required this.note,
    required this.items,
    required this.itemKeys,
    required this.mediaActive,
    required this.highlightQuery,
    this.activeSearchTarget,
  });

  final NoteEntry note;
  final List<_DetailContentItem> items;
  final Map<int, GlobalKey> itemKeys;
  final bool mediaActive;
  final String highlightQuery;
  final _NoteDetailSearchTarget? activeSearchTarget;

  @override
  State<_DetailContentSliver> createState() => _DetailContentSliverState();
}

class _DetailContentSliverState extends State<_DetailContentSliver> {
  late List<_DetailContentItem> _items;
  late List<NoteAttachment> _photoAttachments;

  @override
  void initState() {
    super.initState();
    _rebuildContentCache();
  }

  @override
  void didUpdateWidget(covariant _DetailContentSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note != widget.note || oldWidget.items != widget.items) {
      _rebuildContentCache();
    }
  }

  void _rebuildContentCache() {
    final watch = kDebugMode ? (Stopwatch()..start()) : null;
    final items = widget.items;
    final photoAttachments = items
        .map((item) => item.attachment)
        .whereType<NoteAttachment>()
        .where((attachment) => attachment.type == AttachmentType.photo)
        .toList(growable: false);
    _items = items;
    _photoAttachments = photoAttachments;
    final elapsed = watch?.elapsedMicroseconds;
    if (elapsed != null &&
        (widget.note.blocks.length >= 20 ||
            widget.note.attachments.length >= 10 ||
            elapsed >= 2000)) {
      _debugNotePerf(
        'detail content cache items=${items.length} photos=${photoAttachments.length} ${_notePerfLabel(widget.note)} completed ${elapsed / 1000}ms',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverList.list(
      children: [
        for (var index = 0; index < _items.length; index++)
          Builder(
            builder: (context) {
              final item = _items[index];
              final child = _DetailContentItemWidget(
                item: item,
                mediaActive: widget.mediaActive,
                photoAttachments: _photoAttachments,
                highlightQuery: widget.highlightQuery,
                activeMatchStart:
                    widget.activeSearchTarget?.key == widget.itemKeys[index]
                    ? widget.activeSearchTarget?.matchStart
                    : null,
              );
              return KeyedSubtree(
                key: widget.itemKeys[index],
                child: Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
                  child: child,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _DetailContentItemWidget extends StatelessWidget {
  const _DetailContentItemWidget({
    required this.item,
    required this.mediaActive,
    required this.photoAttachments,
    required this.highlightQuery,
    this.activeMatchStart,
  });

  final _DetailContentItem item;
  final bool mediaActive;
  final List<NoteAttachment> photoAttachments;
  final String highlightQuery;
  final int? activeMatchStart;

  @override
  Widget build(BuildContext context) {
    final location = item.location;
    if (location != null) {
      return _LocationMemoCard(
        location: location,
        strings: context.strings,
        width: double.infinity,
        highlightQuery: highlightQuery,
        activeSearchMatchStart: activeMatchStart,
      );
    }
    final text = item.text;
    if (text != null) {
      return _LinkifiedMemoText(
        text: text,
        query: highlightQuery,
        activeMatchStart: activeMatchStart,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    final attachment = item.attachment;
    if (attachment == null) {
      return const SizedBox.shrink();
    }
    return _EmbeddedAttachmentBlock(
      attachment: attachment,
      mediaActive: mediaActive,
      photoAttachments: photoAttachments,
      photoIndex: item.photoIndex,
    );
  }
}

class _DetailContentItem {
  const _DetailContentItem.text(this.text)
    : attachment = null,
      location = null,
      photoIndex = null;

  const _DetailContentItem.attachment(this.attachment, {this.photoIndex})
    : text = null,
      location = null;

  const _DetailContentItem.location(this.location)
    : text = null,
      attachment = null,
      photoIndex = null;

  final String? text;
  final NoteAttachment? attachment;
  final _LocationMemoData? location;
  final int? photoIndex;
}

List<_DetailContentItem> _buildDetailContentItems(NoteEntry note) {
  final blocks = note.blocks.isNotEmpty
      ? note.blocks
      : _legacyBlocksFromNote(note);
  if (blocks.isEmpty && note.location == null) {
    return [_DetailContentItem.text(note.body)];
  }

  final items = <_DetailContentItem>[];
  var photoIndex = 0;
  for (final block in blocks) {
    switch (block.type) {
      case NoteBlockType.paragraph:
        final text = block.text?.trim() ?? '';
        if (text.isNotEmpty) {
          final location = _tryParseLocationMemo(text);
          items.add(
            location == null
                ? _DetailContentItem.text(text)
                : _DetailContentItem.location(location),
          );
        }
      case NoteBlockType.photo:
      case NoteBlockType.video:
      case NoteBlockType.audio:
      case NoteBlockType.file:
        final attachment = block.attachment;
        if (attachment != null) {
          items.add(
            _DetailContentItem.attachment(
              attachment,
              photoIndex: attachment.type == AttachmentType.photo
                  ? photoIndex++
                  : null,
            ),
          );
        }
    }
  }
  if (note.location != null) {
    items.add(
      _DetailContentItem.location(
        _locationMemoDataFromMetadata(note.location!),
      ),
    );
  }
  return items;
}

List<NoteBlock> _legacyBlocksFromNote(NoteEntry note) {
  final blocks = <NoteBlock>[];
  if (note.body.trim().isNotEmpty) {
    blocks.add(NoteBlock(type: NoteBlockType.paragraph, text: note.body));
  }
  for (final attachment in note.attachments) {
    blocks.add(
      NoteBlock(
        type: switch (attachment.type) {
          AttachmentType.photo => NoteBlockType.photo,
          AttachmentType.video => NoteBlockType.video,
          AttachmentType.audio => NoteBlockType.audio,
          AttachmentType.file => NoteBlockType.file,
        },
        attachment: attachment,
      ),
    );
  }
  return blocks;
}
