part of 'home_page.dart';

Future<void> _openAttachmentViewer(
  BuildContext context,
  WidgetRef ref,
  NoteAttachment attachment, {
  List<NoteAttachment> photoAttachments = const [],
  int? initialPhotoIndex,
}) async {
  if (attachment.type == AttachmentType.photo) {
    final attachments = photoAttachments.isEmpty
        ? [attachment]
        : photoAttachments;
    final fallbackIndex = attachments.indexOf(attachment);
    final resolvedIndex =
        initialPhotoIndex != null &&
            initialPhotoIndex >= 0 &&
            initialPhotoIndex < attachments.length
        ? initialPhotoIndex
        : (fallbackIndex >= 0 ? fallbackIndex : 0);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.strings.closeImageViewer,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (context, _, _) => _PhotoLightboxDialog(
        attachments: attachments,
        initialIndex: resolvedIndex,
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
    return;
  }
  if (attachment.type == AttachmentType.video) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (context, _, _) =>
          _VideoLightboxDialog(attachment: attachment),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: _AttachmentViewerSheet(attachment: attachment),
      ),
    ),
  );
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('home.use.a.4.digit.pin.for.this.browser'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _PinEntryField(controller: _pinController, label: strings.pin),
            const SizedBox(height: 12),
            _PinEntryField(
              controller: _confirmController,
              label: strings.text('home.confirm.pin'),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }

  void _submit() {
    final strings = context.strings;
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length != 4) {
      setState(() {
        _errorText = strings.text('home.pin.must.be.exactly.4.digits');
      });
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      setState(() {
        _errorText = strings.text('home.pin.must.contain.digits.only');
      });
      return;
    }
    if (pin != confirm) {
      setState(() {
        _errorText = strings.text('home.pin.confirmation.did.not.match');
      });
      return;
    }
    Navigator.of(context).pop(pin);
  }
}

class _PinEntryField extends StatelessWidget {
  const _PinEntryField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Pinput(
          controller: controller,
          length: 4,
          obscureText: true,
          obscuringCharacter: '•',
          keyboardType: TextInputType.number,
          defaultPinTheme: PinTheme(
            width: 42,
            height: 52,
            textStyle: Theme.of(context).textTheme.titleMedium,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          focusedPinTheme: PinTheme(
            width: 42,
            height: 52,
            textStyle: Theme.of(context).textTheme.titleMedium,
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentViewerSheet extends ConsumerWidget {
  const _AttachmentViewerSheet({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(attachment.label, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _attachmentDescription(context, attachment),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
        ),
        const SizedBox(height: 4),
        _AttachmentSizeText(attachment: attachment),
        const SizedBox(height: 16),
        Expanded(
          child: switch (attachment.type) {
            AttachmentType.photo => _PhotoAttachmentViewer(
              attachment: attachment,
            ),
            AttachmentType.video => _VideoAttachmentViewer(
              attachment: attachment,
            ),
            AttachmentType.audio => _AudioAttachmentViewer(
              attachment: attachment,
            ),
            AttachmentType.file => _FileAttachmentViewer(
              attachment: attachment,
            ),
          },
        ),
      ],
    );
  }
}

class _FileAttachmentViewer extends ConsumerWidget {
  const _FileAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              attachment.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              context.strings.filePreviewUnavailable,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _shareAttachment(context, ref, attachment),
              icon: const Icon(Icons.ios_share_outlined),
              label: Text(context.strings.share),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoLightboxDialog extends ConsumerWidget {
  const _VideoLightboxDialog({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final sizeFuture = _attachmentSizeFuture(ref, attachment);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                FutureBuilder<int?>(
                  future: sizeFuture,
                  builder: (context, snapshot) {
                    final sizeLabel = _attachmentSizeLabel(
                      context,
                      snapshot.data,
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).closeButtonTooltip,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  attachment.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _shareAttachment(context, ref, attachment),
                                icon: const Icon(
                                  Icons.ios_share_outlined,
                                  color: Colors.white,
                                ),
                                tooltip: strings.share,
                              ),
                            ],
                          ),
                          if (sizeLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 56, top: 2),
                              child: Text(
                                sizeLabel,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: _VideoAttachmentViewer(
                      attachment: attachment,
                      autoLoad: true,
                      fillAvailableHeight: true,
                      showFullScreenAction: false,
                      showShareAction: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoControllerLightboxDialog extends StatefulWidget {
  const _VideoControllerLightboxDialog({
    required this.attachment,
    required this.controller,
    required this.initialMuted,
    this.sizeLabel,
    this.onMutedChanged,
    this.onShare,
  });

  final NoteAttachment attachment;
  final VideoPlayerController controller;
  final bool initialMuted;
  final String? sizeLabel;
  final ValueChanged<bool>? onMutedChanged;
  final VoidCallback? onShare;

  @override
  State<_VideoControllerLightboxDialog> createState() =>
      _VideoControllerLightboxDialogState();
}

class _VideoControllerLightboxDialogState
    extends State<_VideoControllerLightboxDialog> {
  Duration? _dragPosition;
  late bool _muted;

  VideoPlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _muted = widget.initialMuted;
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final duration = _controller.value.duration;
    final position = _clampMediaPosition(
      _dragPosition ?? _controller.value.position,
      duration,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.attachment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (widget.onShare != null)
                            IconButton(
                              onPressed: widget.onShare,
                              icon: const Icon(
                                Icons.ios_share_outlined,
                                color: Colors.white,
                              ),
                              tooltip: strings.share,
                            ),
                        ],
                      ),
                      if (widget.sizeLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 56, top: 2),
                          child: Text(
                            widget.sizeLabel!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final aspectRatio = _controller.value.aspectRatio <= 0
                            ? 16 / 9
                            : _controller.value.aspectRatio;
                        return Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                    maxHeight: constraints.maxHeight,
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: aspectRatio,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          AbsorbPointer(
                                            child: VideoPlayer(_controller),
                                          ),
                                          Positioned.fill(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: _togglePlayback,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _togglePlayback,
                                  icon: Icon(
                                    _controller.value.isPlaying
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  onPressed: _toggleMuted,
                                  icon: Icon(
                                    _muted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    color: Colors.white,
                                  ),
                                  tooltip: _videoMuteTooltip(_muted),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: duration <= Duration.zero
                                        ? 0
                                        : position.inMilliseconds
                                              .clamp(0, duration.inMilliseconds)
                                              .toDouble(),
                                    max: duration <= Duration.zero
                                        ? 1
                                        : duration.inMilliseconds.toDouble(),
                                    onChanged: duration <= Duration.zero
                                        ? null
                                        : (value) {
                                            setState(() {
                                              _dragPosition = Duration(
                                                milliseconds: value.round(),
                                              );
                                            });
                                          },
                                    onChangeEnd: duration <= Duration.zero
                                        ? null
                                        : (value) {
                                            unawaited(_seek(value, duration));
                                          },
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  '${_formatAudioDuration(position)} / '
                                  '${_formatAudioDuration(duration)}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _togglePlayback() {
    if (_controller.value.isPlaying) {
      unawaited(_controller.pause());
      return;
    }
    final duration = _controller.value.duration;
    if (duration > Duration.zero &&
        _controller.value.position >=
            duration - const Duration(milliseconds: 250)) {
      unawaited(
        _controller.seekTo(Duration.zero).then((_) => _controller.play()),
      );
    } else {
      unawaited(_controller.play());
    }
  }

  Future<void> _seek(double value, Duration duration) async {
    final target = _clampMediaPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
    await _controller.seekTo(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _dragPosition = null;
    });
  }

  void _toggleMuted() {
    final nextMuted = !_muted;
    unawaited(_controller.setVolume(nextMuted ? 0.0 : 1.0));
    widget.onMutedChanged?.call(nextMuted);
    setState(() {
      _muted = nextMuted;
    });
  }
}

class _WebVideoLightboxDialog extends StatefulWidget {
  const _WebVideoLightboxDialog({
    required this.attachment,
    required this.objectUrl,
    required this.muted,
    this.sizeLabel,
    this.onMutedChanged,
    this.onShare,
  });

  final NoteAttachment attachment;
  final String objectUrl;
  final bool muted;
  final String? sizeLabel;
  final ValueChanged<bool>? onMutedChanged;
  final VoidCallback? onShare;

  @override
  State<_WebVideoLightboxDialog> createState() =>
      _WebVideoLightboxDialogState();
}

class _WebVideoLightboxDialogState extends State<_WebVideoLightboxDialog> {
  late bool _muted;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
    _viewType = 'himemo-video-lightbox-${identityHashCode(this)}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.attachment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (widget.onShare != null)
                            IconButton(
                              onPressed: widget.onShare,
                              icon: const Icon(
                                Icons.ios_share_outlined,
                                color: Colors.white,
                              ),
                              tooltip: strings.share,
                            ),
                          IconButton(
                            onPressed: _toggleMuted,
                            icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                            ),
                            tooltip: _videoMuteTooltip(_muted),
                          ),
                        ],
                      ),
                      if (widget.sizeLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 56, top: 2),
                          child: Text(
                            widget.sizeLabel!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: buildWebVideoElementView(
                            viewType: _viewType,
                            objectUrl: widget.objectUrl,
                            autoplay: true,
                            muted: _muted,
                            fillAvailableHeight: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMuted() {
    final nextMuted = !_muted;
    updateWebVideoElementMuted(_viewType, nextMuted);
    widget.onMutedChanged?.call(nextMuted);
    setState(() {
      _muted = nextMuted;
    });
  }
}

class _PhotoLightboxDialog extends ConsumerStatefulWidget {
  const _PhotoLightboxDialog({
    required this.attachments,
    required this.initialIndex,
  });

  final List<NoteAttachment> attachments;
  final int initialIndex;

  @override
  ConsumerState<_PhotoLightboxDialog> createState() =>
      _PhotoLightboxDialogState();
}

class _PhotoLightboxDialogState extends ConsumerState<_PhotoLightboxDialog> {
  final TransformationController _transformationController =
      TransformationController();
  bool _edgeToEdge = false;
  bool _backgroundPanStartedOnImage = false;
  Offset? _lastLightboxTapDownPosition;
  late int _selectedIndex;

  NoteAttachment get _attachment => widget.attachments[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FutureBuilder<List<int>?>(
          future: _readPhotoAttachmentBytes(ref, _attachment),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (bytes == null || bytes.isEmpty) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.strings.unableToDecryptImage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: _LightboxTopBar(
                      attachment: _attachment,
                      edgeToEdge: _edgeToEdge,
                      canMovePrevious: _selectedIndex > 0,
                      canMoveNext:
                          _selectedIndex < widget.attachments.length - 1,
                      onClose: () => Navigator.of(context).pop(),
                      onZoomOut: null,
                      onZoomIn: null,
                      onReset: null,
                      onPrevious: _showPreviousImage,
                      onNext: _showNextImage,
                      onToggleEdgeToEdge: null,
                      onShare: null,
                    ),
                  ),
                ],
              );
            }

            return FutureBuilder<ui.Size>(
              future: _decodeImageSize(bytes),
              builder: (context, dimensionSnapshot) {
                final imageSize = dimensionSnapshot.data;
                if (dimensionSnapshot.hasError) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.strings.unableToLoadImage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: _LightboxTopBar(
                          attachment: _attachment,
                          edgeToEdge: _edgeToEdge,
                          canMovePrevious: _selectedIndex > 0,
                          canMoveNext:
                              _selectedIndex < widget.attachments.length - 1,
                          onClose: () => Navigator.of(context).pop(),
                          onZoomOut: null,
                          onZoomIn: null,
                          onReset: null,
                          onPrevious: _showPreviousImage,
                          onNext: _showNextImage,
                          onToggleEdgeToEdge: null,
                          onShare: null,
                        ),
                      ),
                    ],
                  );
                }
                if (imageSize == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = _edgeToEdge ? 0.0 : 24.0;
                    const verticalTopPadding = 72.0;
                    final verticalBottomPadding = _edgeToEdge ? 0.0 : 24.0;
                    final viewportWidth =
                        constraints.maxWidth - horizontalPadding * 2;
                    final viewportHeight =
                        constraints.maxHeight -
                        verticalTopPadding -
                        verticalBottomPadding;
                    final containScale = math.min(
                      viewportWidth / imageSize.width,
                      viewportHeight / imageSize.height,
                    );
                    final displayScale = math.min(1.0, containScale);
                    final displayedWidth = imageSize.width * displayScale;
                    final displayedHeight = imageSize.height * displayScale;
                    final maxScale = displayScale < 1 ? 1 / displayScale : 1.0;
                    final minScale = math.min(0.25, maxScale);
                    final imageBaseRect = Rect.fromLTWH(
                      horizontalPadding + (viewportWidth - displayedWidth) / 2,
                      verticalTopPadding +
                          (viewportHeight - displayedHeight) / 2,
                      displayedWidth,
                      displayedHeight,
                    );

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ExcludeSemantics(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) {
                                _backgroundPanStartedOnImage =
                                    _transformedImageRect(
                                      imageBaseRect,
                                    ).contains(details.localPosition);
                              },
                              onPanUpdate: (details) {
                                if (_backgroundPanStartedOnImage) {
                                  _panImageBy(details.delta);
                                }
                              },
                              onPanEnd: (_) {
                                _backgroundPanStartedOnImage = false;
                              },
                              onPanCancel: () {
                                _backgroundPanStartedOnImage = false;
                              },
                              onTapUp: (details) {
                                if (!_transformedImageRect(
                                  imageBaseRect,
                                ).contains(details.localPosition)) {
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              verticalTopPadding,
                              horizontalPadding,
                              verticalBottomPadding,
                            ),
                            child: Center(
                              child: SizedBox(
                                width: displayedWidth,
                                height: displayedHeight,
                                child: InteractiveViewer(
                                  transformationController:
                                      _transformationController,
                                  minScale: minScale,
                                  maxScale: math.max(maxScale, minScale),
                                  panEnabled: true,
                                  boundaryMargin: EdgeInsets.all(
                                    math.max(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    ),
                                  ),
                                  clipBehavior: Clip.none,
                                  child: SizedBox(
                                    width: displayedWidth,
                                    height: displayedHeight,
                                    child: Image.memory(
                                      Uint8List.fromList(bytes),
                                      width: displayedWidth,
                                      height: displayedHeight,
                                      fit: BoxFit.fill,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const _AttachmentImageErrorPanel(
                                          height: 180,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: ExcludeSemantics(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapDown: (details) {
                                _lastLightboxTapDownPosition =
                                    details.localPosition;
                              },
                              onTap: () {
                                final position = _lastLightboxTapDownPosition;
                                _lastLightboxTapDownPosition = null;
                                if (position == null ||
                                    !_transformedImageRect(
                                      imageBaseRect,
                                    ).contains(position)) {
                                  Navigator.of(context).pop();
                                }
                              },
                              onDoubleTapDown: (details) {
                                _lastLightboxTapDownPosition = null;
                                if (_transformedImageRect(
                                  imageBaseRect,
                                ).contains(details.localPosition)) {
                                  _toggleActualSize(maxScale);
                                }
                              },
                            ),
                          ),
                        ),
                        if (_selectedIndex > 0)
                          Positioned(
                            left: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _LightboxEdgeButton(
                                icon: Icons.chevron_left_rounded,
                                tooltip: context.strings.previousImage,
                                onPressed: _showPreviousImage,
                              ),
                            ),
                          ),
                        if (_selectedIndex < widget.attachments.length - 1)
                          Positioned(
                            right: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _LightboxEdgeButton(
                                icon: Icons.chevron_right_rounded,
                                tooltip: context.strings.nextImage,
                                onPressed: _showNextImage,
                              ),
                            ),
                          ),
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: _LightboxTopBar(
                            attachment: _attachment,
                            metadataLabel: _attachmentSizeLabel(
                              context,
                              bytes.length,
                            ),
                            edgeToEdge: _edgeToEdge,
                            canMovePrevious: _selectedIndex > 0,
                            canMoveNext:
                                _selectedIndex < widget.attachments.length - 1,
                            onClose: () => Navigator.of(context).pop(),
                            onZoomOut: () => _zoomOut(maxScale),
                            onZoomIn: () => _zoomIn(maxScale),
                            onReset: _resetTransform,
                            onPrevious: _showPreviousImage,
                            onNext: _showNextImage,
                            onToggleEdgeToEdge: () {
                              setState(() {
                                _edgeToEdge = !_edgeToEdge;
                              });
                            },
                            onShare: () => _shareImage(bytes),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _zoomIn(double maxScale) => _scaleBy(1.2, maxScale);

  void _zoomOut(double maxScale) => _scaleBy(1 / 1.2, maxScale);

  void _toggleActualSize(double maxScale) {
    final current = _transformationController.value.getMaxScaleOnAxis();
    if ((current - 1).abs() < 0.05 && maxScale > 1) {
      _scaleBy(maxScale, maxScale);
      return;
    }
    _resetTransform();
  }

  void _resetTransform() {
    _transformationController.value = Matrix4.identity();
  }

  void _panImageBy(Offset delta) {
    final matrix = _transformationController.value.clone();
    matrix.storage[12] += delta.dx;
    matrix.storage[13] += delta.dy;
    _transformationController.value = matrix;
  }

  Rect _transformedImageRect(Rect baseRect) {
    final matrix = _transformationController.value;
    final transformedTopLeft = MatrixUtils.transformPoint(matrix, Offset.zero);
    final transformedTopRight = MatrixUtils.transformPoint(
      matrix,
      Offset(baseRect.width, 0),
    );
    final transformedBottomLeft = MatrixUtils.transformPoint(
      matrix,
      Offset(0, baseRect.height),
    );
    final transformedBottomRight = MatrixUtils.transformPoint(
      matrix,
      Offset(baseRect.width, baseRect.height),
    );
    final transformedPoints = [
      transformedTopLeft,
      transformedTopRight,
      transformedBottomLeft,
      transformedBottomRight,
    ].map((point) => point + baseRect.topLeft);
    return transformedPoints.fold<Rect>(
      Rect.fromPoints(transformedPoints.first, transformedPoints.first),
      (rect, point) =>
          rect.expandToInclude(Rect.fromLTWH(point.dx, point.dy, 0, 0)),
    );
  }

  void _scaleBy(double factor, double maxScale) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.25, maxScale);
    final ratio = targetScale / currentScale;
    matrix.scaleByDouble(ratio, ratio, ratio, 1);
    _transformationController.value = matrix;
  }

  void _showPreviousImage() {
    if (_selectedIndex <= 0) {
      return;
    }
    setState(() {
      _selectedIndex -= 1;
      _resetTransform();
    });
  }

  void _showNextImage() {
    if (_selectedIndex >= widget.attachments.length - 1) {
      return;
    }
    setState(() {
      _selectedIndex += 1;
      _resetTransform();
    });
  }

  Future<void> _shareImage(List<int> bytes) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: _attachment.label,
            mimeType: 'image/*',
          ),
        ],
        subject: _attachment.label,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}

class _LightboxTopBar extends StatelessWidget {
  const _LightboxTopBar({
    required this.attachment,
    this.metadataLabel,
    required this.edgeToEdge,
    required this.canMovePrevious,
    required this.canMoveNext,
    required this.onClose,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleEdgeToEdge,
    required this.onShare,
  });

  final NoteAttachment attachment;
  final String? metadataLabel;
  final bool edgeToEdge;
  final bool canMovePrevious;
  final bool canMoveNext;
  final VoidCallback onClose;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onReset;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onToggleEdgeToEdge;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;
        final compact = width < 390;
        final veryCompact = width < 330;
        final zoomActions = <Widget>[
          if (onZoomOut != null)
            IconButton(
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove_rounded, color: Colors.white),
              tooltip: strings.zoomOut,
            ),
          if (onZoomIn != null)
            IconButton(
              onPressed: onZoomIn,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              tooltip: strings.zoomIn,
            ),
          if (onReset != null)
            IconButton(
              onPressed: onReset,
              icon: const Icon(
                Icons.center_focus_strong_rounded,
                color: Colors.white,
              ),
              tooltip: strings.fitToScreen,
            ),
        ];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: strings.close,
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (metadataLabel != null && metadataLabel!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            metadataLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ] else
                const Spacer(),
              IconButton(
                onPressed: canMovePrevious ? onPrevious : null,
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                ),
                tooltip: strings.previousImage,
              ),
              IconButton(
                onPressed: canMoveNext ? onNext : null,
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                ),
                tooltip: strings.nextImage,
              ),
              if (veryCompact && zoomActions.isNotEmpty)
                PopupMenuButton<_LightboxOverflowAction>(
                  tooltip: strings.localized(
                    en: 'More',
                    ja: 'その他',
                    zh: '更多',
                    ko: '더보기',
                    es: 'Mas',
                    de: 'Mehr',
                  ),
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _LightboxOverflowAction.zoomOut:
                        onZoomOut?.call();
                      case _LightboxOverflowAction.zoomIn:
                        onZoomIn?.call();
                      case _LightboxOverflowAction.reset:
                        onReset?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onZoomOut != null)
                      PopupMenuItem(
                        value: _LightboxOverflowAction.zoomOut,
                        child: Text(strings.zoomOut),
                      ),
                    if (onZoomIn != null)
                      PopupMenuItem(
                        value: _LightboxOverflowAction.zoomIn,
                        child: Text(strings.zoomIn),
                      ),
                    if (onReset != null)
                      PopupMenuItem(
                        value: _LightboxOverflowAction.reset,
                        child: Text(strings.fitToScreen),
                      ),
                  ],
                )
              else
                ...zoomActions,
              if (onToggleEdgeToEdge != null)
                IconButton(
                  onPressed: onToggleEdgeToEdge,
                  icon: Icon(
                    edgeToEdge
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  tooltip: edgeToEdge ? strings.restoreFrame : strings.maximize,
                ),
              if (onShare != null)
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                  tooltip: strings.share,
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _LightboxOverflowAction { zoomOut, zoomIn, reset }

class _LightboxEdgeButton extends StatelessWidget {
  const _LightboxEdgeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
      ),
    );
  }
}

Future<ui.Size> _decodeImageSize(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  final image = frame.image;
  return ui.Size(image.width.toDouble(), image.height.toDouble());
}

Future<T> _profileNotePerfFuture<T>(
  String label,
  Future<T> Function() task,
) async {
  if (!kDebugMode) {
    return task();
  }
  final watch = Stopwatch()..start();
  try {
    final result = await task();
    watch.stop();
    _debugNotePerf('$label completed ${watch.elapsedMilliseconds}ms');
    return result;
  } catch (error) {
    watch.stop();
    _debugNotePerf('$label failed ${watch.elapsedMilliseconds}ms error=$error');
    rethrow;
  }
}

Future<List<int>?> _readPhotoAttachmentBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final filePath = attachment.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    List<int>? bytes;
    try {
      bytes = await _readDisplayAttachmentBytes(ref, attachment);
    } catch (error) {
      _logAttachmentDisplayDiagnostic(
        attachment,
        'attachment byte read failed',
        source: 'display',
        data: {'error': error},
      );
    }
    if (bytes != null && bytes.isNotEmpty) {
      _logAttachmentDisplayDiagnostic(
        attachment,
        'attachment byte read completed',
        source: 'display',
        data: {'bytes': bytes.length, ..._attachmentByteDiagnosticData(bytes)},
      );
      return bytes;
    }
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment byte read returned empty',
      source: 'display',
      data: {'hasPreview': attachment.previewBytesBase64?.isNotEmpty == true},
    );
    return _decodeAttachmentPreviewBytes(attachment);
  }
  _logAttachmentDisplayDiagnostic(
    attachment,
    'attachment has no file path for display',
    source: 'display',
    data: {'hasPreview': attachment.previewBytesBase64?.isNotEmpty == true},
  );
  return _decodeAttachmentPreviewBytes(attachment);
}

List<int>? _decodeAttachmentPreviewBytes(NoteAttachment attachment) {
  final previewBytesBase64 = attachment.previewBytesBase64;
  if (previewBytesBase64 == null || previewBytesBase64.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment preview bytes missing',
      source: 'preview',
    );
    return null;
  }
  try {
    final bytes = base64Decode(previewBytesBase64);
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment preview bytes decoded',
      source: 'preview',
      data: {'bytes': bytes.length, ..._attachmentByteDiagnosticData(bytes)},
    );
    return bytes;
  } on FormatException catch (error) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment preview bytes decode failed',
      source: 'preview',
      data: {'error': error},
    );
    return null;
  }
}

void _logAttachmentDisplayDiagnostic(
  NoteAttachment attachment,
  String message, {
  required String source,
  Map<String, Object?> data = const <String, Object?>{},
}) {
  final filePath = attachment.filePath;
  logDiagnostic(
    'attachment',
    message,
    data: {
      'source': source,
      'type': attachment.type.name,
      'label': attachment.label,
      'fileRef': _attachmentDiagnosticFileRef(filePath),
      'hasPreview': attachment.previewBytesBase64?.isNotEmpty == true,
      'previewBytesBase64Length': attachment.previewBytesBase64?.length,
      ...data,
    },
  );
}

Map<String, Object?> _attachmentByteDiagnosticData(List<int> bytes) {
  final header = bytes.take(16).toList(growable: false);
  return {
    'byteSignature': header
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' '),
    'detectedImageFormat': _detectImageFormat(bytes),
  };
}

String _detectImageFormat(List<int> bytes) {
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) {
      return false;
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  String asciiAt(int start, int end) {
    if (bytes.length < end) {
      return '';
    }
    return String.fromCharCodes(bytes.sublist(start, end));
  }

  if (startsWith(const [0xff, 0xd8, 0xff])) {
    return 'jpeg';
  }
  if (startsWith(const [0x89, 0x50, 0x4e, 0x47])) {
    return 'png';
  }
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) {
    return 'gif';
  }
  if (asciiAt(0, 4) == 'RIFF' && asciiAt(8, 12) == 'WEBP') {
    return 'webp';
  }
  final boxType = asciiAt(4, 12);
  if (boxType.startsWith('ftypheic') ||
      boxType.startsWith('ftypheix') ||
      boxType.startsWith('ftyphevc') ||
      boxType.startsWith('ftyphevx') ||
      boxType.startsWith('ftypheim') ||
      boxType.startsWith('ftypheis') ||
      boxType.startsWith('ftypmif1') ||
      boxType.startsWith('ftypmsf1')) {
    return 'heic';
  }
  return 'unknown';
}

String _attachmentDiagnosticFileRef(String? filePath) {
  if (filePath == null || filePath.isEmpty) {
    return 'none';
  }
  if (filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
    final hash = filePath.substring(_remoteSyncAttachmentObjectPrefix.length);
    final shortHash = hash.length <= 12 ? hash : hash.substring(0, 12);
    return '$_remoteSyncAttachmentObjectPrefix$shortHash';
  }
  return path.basename(filePath);
}

Future<List<int>?> _readDisplayAttachmentBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final filePath = attachment.filePath;
  if (filePath == null || filePath.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'attachment display read skipped missing file path',
      source: 'display',
    );
    return null;
  }
  if (filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
    return _downloadRemoteSyncAttachmentBytes(ref, attachment);
  }
  final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
  final bytes = await attachmentStore.readAttachment(
    filePath,
    type: attachment.type,
  );
  if (bytes == null || bytes.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'local attachment read returned empty',
      source: 'display',
      data: await attachmentStore.storedPayloadDiagnostics(filePath),
    );
  }
  return bytes;
}

Future<List<int>?> _downloadRemoteSyncAttachmentBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) async {
  final filePath = attachment.filePath;
  if (filePath == null ||
      !filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
    return null;
  }
  final contentHash = filePath.substring(
    _remoteSyncAttachmentObjectPrefix.length,
  );
  if (contentHash.isEmpty) {
    return null;
  }
  final provider = ref.read(syncProviderControllerProvider);
  _logAttachmentDisplayDiagnostic(
    attachment,
    'remote attachment object display download start',
    source: 'remote',
    data: {'provider': provider.name, 'contentHash': contentHash},
  );
  Future<String?> download() => switch (provider) {
    SyncProvider.iCloud =>
      ref
          .read(iCloudSyncTransportProvider)
          .downloadAttachmentObject(contentHash),
    SyncProvider.googleDrive =>
      ref
          .read(googleDriveSyncTransportProvider)
          .downloadAttachmentObject(contentHash),
    SyncProvider.off => Future<String?>.value(),
  };
  var encodedPayload = await download();
  if ((encodedPayload == null || encodedPayload.isEmpty) &&
      provider == SyncProvider.iCloud) {
    for (final delay in const [
      Duration(milliseconds: 700),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ]) {
      await Future<void>.delayed(delay);
      encodedPayload = await download();
      if (encodedPayload != null && encodedPayload.isNotEmpty) {
        break;
      }
    }
  }
  if (encodedPayload == null || encodedPayload.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object unavailable for display',
      source: 'remote',
      data: {'provider': provider.name, 'contentHash': contentHash},
    );
    return null;
  }
  late final Map<String, dynamic> decoded;
  try {
    decoded = await ref
        .read(secureSyncBundleStoreProvider)
        .readAttachmentObjectPayload(encodedPayload);
  } catch (error) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object decrypt failed',
      source: 'remote',
      data: {
        'provider': provider.name,
        'contentHash': contentHash,
        'error': error,
      },
    );
    return null;
  }
  final payloadHash = decoded['contentHash'] as String? ?? contentHash;
  if (payloadHash != contentHash) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object hash mismatch',
      source: 'remote',
      data: {'expectedHash': contentHash, 'payloadHash': payloadHash},
    );
    return null;
  }
  final payloadType = decoded['type'] as String?;
  if (payloadType != null && payloadType != attachment.type.name) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object type mismatch',
      source: 'remote',
      data: {'expectedType': attachment.type.name, 'payloadType': payloadType},
    );
    return null;
  }
  final bytesBase64 = decoded['bytesBase64'] as String?;
  if (bytesBase64 == null || bytesBase64.isEmpty) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object bytes missing',
      source: 'remote',
      data: {'contentHash': contentHash},
    );
    return null;
  }
  late final _DecodedRemoteAttachmentBytes decodedBytes;
  try {
    decodedBytes = await _decodeRemoteAttachmentBytes(bytesBase64);
  } on FormatException catch (error) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object base64 decode failed',
      source: 'remote',
      data: {'contentHash': contentHash, 'error': error},
    );
    return null;
  }
  final bytes = decodedBytes.bytes;
  if (decodedBytes.contentHash != contentHash) {
    _logAttachmentDisplayDiagnostic(
      attachment,
      'remote attachment object clear hash mismatch',
      source: 'remote',
      data: {'contentHash': contentHash, 'bytes': bytes.length},
    );
    return null;
  }
  _logAttachmentDisplayDiagnostic(
    attachment,
    'remote attachment object display download completed',
    source: 'remote',
    data: {
      'provider': provider.name,
      'contentHash': contentHash,
      'bytes': bytes.length,
    },
  );
  return bytes;
}

class _DecodedRemoteAttachmentBytes {
  const _DecodedRemoteAttachmentBytes({
    required this.bytes,
    required this.contentHash,
  });

  final Uint8List bytes;
  final String contentHash;
}

Future<_DecodedRemoteAttachmentBytes> _decodeRemoteAttachmentBytes(
  String bytesBase64,
) async {
  if (kIsWeb || bytesBase64.length < 512 * 1024) {
    final bytes = Uint8List.fromList(base64Decode(bytesBase64));
    return _DecodedRemoteAttachmentBytes(
      bytes: bytes,
      contentHash: sha256.convert(bytes).toString(),
    );
  }
  final result = await Isolate.run(() {
    final bytes = Uint8List.fromList(base64Decode(bytesBase64));
    return <String, Object>{
      'bytes': TransferableTypedData.fromList([bytes]),
      'contentHash': sha256.convert(bytes).toString(),
    };
  });
  final transferable = result['bytes']! as TransferableTypedData;
  return _DecodedRemoteAttachmentBytes(
    bytes: transferable.materialize().asUint8List(),
    contentHash: result['contentHash']! as String,
  );
}

Future<List<int>?> _readPhotoAttachmentDetailBytes(
  WidgetRef ref,
  NoteAttachment attachment,
) {
  final previewBytesBase64 = attachment.previewBytesBase64;
  if (previewBytesBase64 != null && previewBytesBase64.isNotEmpty) {
    try {
      final bytes = base64Decode(previewBytesBase64);
      _logAttachmentDisplayDiagnostic(
        attachment,
        'detail preview bytes decoded',
        source: 'detail',
        data: {'bytes': bytes.length},
      );
      return Future<List<int>?>.value(bytes);
    } on FormatException catch (error) {
      _logAttachmentDisplayDiagnostic(
        attachment,
        'detail preview bytes decode failed',
        source: 'detail',
        data: {'error': error},
      );
      return Future<List<int>?>.value(null);
    }
  }
  return _readPhotoAttachmentBytes(ref, attachment);
}

String _attachmentCacheKey(NoteAttachment attachment) {
  final filePath = attachment.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    return '$filePath:${attachment.previewBytesBase64 ?? ''}';
  }
  return '${attachment.label}:${attachment.previewBytesBase64 ?? ''}';
}

const _photoAttachmentBytesCacheLimit = 24;
final _photoAttachmentBytesCache = <String, Future<List<int>?>>{};

Future<List<int>?> _readPhotoAttachmentBytesWithPerf(
  WidgetRef ref,
  NoteAttachment attachment, {
  required String source,
}) {
  final filePath = attachment.filePath;
  final cacheKey = _attachmentCacheKey(attachment);
  final cached = _photoAttachmentBytesCache[cacheKey];
  if (cached != null) {
    _debugNotePerf(
      '$source photo read cache-hit label="${attachment.label}" file=${filePath == null ? 'inline' : path.basename(filePath)}',
    );
    return cached;
  }
  if (_photoAttachmentBytesCache.length >= _photoAttachmentBytesCacheLimit) {
    _photoAttachmentBytesCache.remove(_photoAttachmentBytesCache.keys.first);
  }
  final future = _profileNotePerfFuture(
    '$source photo read label="${attachment.label}" file=${filePath == null ? 'inline' : path.basename(filePath)}',
    () => _readPhotoAttachmentDetailBytes(ref, attachment),
  );
  _photoAttachmentBytesCache[cacheKey] = future;
  future.then((bytes) {
    if (bytes == null || bytes.isEmpty) {
      _photoAttachmentBytesCache.remove(cacheKey);
    }
  });
  future.catchError((Object _) {
    _photoAttachmentBytesCache.remove(cacheKey);
    return null;
  });
  return future;
}

class _PhotoAttachmentViewer extends ConsumerWidget {
  const _PhotoAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<int>?>(
      future: _readPhotoAttachmentBytesWithPerf(
        ref,
        attachment,
        source: 'viewer',
      ),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (bytes == null || bytes.isEmpty) {
          return Center(child: Text(context.strings.unableToDecryptImage));
        }
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                _logAttachmentDisplayDiagnostic(
                  attachment,
                  'image decode failed',
                  source: 'viewer',
                  data: {
                    'error': error,
                    'bytes': bytes.length,
                    ..._attachmentByteDiagnosticData(bytes),
                  },
                );
                return const _AttachmentImageErrorPanel(height: 180);
              },
            ),
          ),
        );
      },
    );
  }
}

class _VideoAttachmentViewer extends ConsumerStatefulWidget {
  const _VideoAttachmentViewer({
    required this.attachment,
    this.fillAvailableHeight = false,
    this.autoLoad = false,
    this.onOpenFullScreen,
    this.showFullScreenAction = true,
    this.showShareAction = true,
  });

  final NoteAttachment attachment;
  final bool fillAvailableHeight;
  final bool autoLoad;
  final VoidCallback? onOpenFullScreen;
  final bool showFullScreenAction;
  final bool showShareAction;

  @override
  ConsumerState<_VideoAttachmentViewer> createState() =>
      _VideoAttachmentViewerState();
}

class _VideoAttachmentViewerState
    extends ConsumerState<_VideoAttachmentViewer> {
  VideoPlayerController? _controller;
  String? _tempFilePath;
  String? _webObjectUrl;
  String? _webVideoViewType;
  bool _webVideoAutoplay = false;
  String? _errorMessage;
  bool _wasPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _dragPosition;
  int _loadGeneration = 0;
  int _videoViewGeneration = 0;
  bool _loading = false;
  bool _playWhenLoaded = false;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _muted = ref.read(videoPlaybackMutedByDefaultControllerProvider);
    if (widget.autoLoad) {
      unawaited(_load(playWhenLoaded: false));
    }
  }

  @override
  void didUpdateWidget(covariant _VideoAttachmentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.filePath == widget.attachment.filePath &&
        oldWidget.attachment.type == widget.attachment.type &&
        oldWidget.attachment.label == widget.attachment.label) {
      return;
    }
    unawaited(_resetAndMaybeLoad());
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    final controller = _controller;
    controller?.removeListener(_handleControllerChanged);
    unawaited(controller?.dispose());
    final tempFilePath = _tempFilePath;
    final webObjectUrl = _webObjectUrl;
    if (tempFilePath != null) {
      unawaited(
        ref
            .read(encryptedAttachmentStoreProvider)
            .deleteMaterializedFile(tempFilePath),
      );
    }
    if (webObjectUrl != null) {
      revokeWebVideoObjectUrl(webObjectUrl);
    }
    super.dispose();
  }

  Future<void> _resetAndMaybeLoad() async {
    final generation = ++_loadGeneration;
    final controller = _controller;
    final tempFilePath = _tempFilePath;
    final webObjectUrl = _webObjectUrl;
    setState(() {
      _controller = null;
      _tempFilePath = null;
      _webObjectUrl = null;
      _webVideoViewType = null;
      _webVideoAutoplay = false;
      _errorMessage = null;
      _wasPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _dragPosition = null;
      _loading = false;
      _playWhenLoaded = false;
      _muted = ref.read(videoPlaybackMutedByDefaultControllerProvider);
    });
    controller?.removeListener(_handleControllerChanged);
    await controller?.dispose();
    if (tempFilePath != null) {
      await ref
          .read(encryptedAttachmentStoreProvider)
          .deleteMaterializedFile(tempFilePath);
    }
    if (webObjectUrl != null) {
      revokeWebVideoObjectUrl(webObjectUrl);
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    if (widget.autoLoad) {
      await _load(playWhenLoaded: false);
    }
  }

  Future<void> _load({required bool playWhenLoaded}) async {
    if (_loading || _controller != null) {
      return;
    }
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _playWhenLoaded = playWhenLoaded;
      _errorMessage = null;
    });
    await _loadAttachment(
      generation: generation,
      playWhenLoaded: playWhenLoaded,
    );
  }

  Future<void> _loadAttachment({
    required int generation,
    required bool playWhenLoaded,
  }) async {
    final filePath = widget.attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _errorMessage = context.strings.videoPreviewUnavailableWeb;
          _loading = false;
          _playWhenLoaded = false;
        });
      }
      return;
    }
    String? tempFilePath;
    String? webObjectUrl;
    try {
      final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
      final VideoPlayerController controller;
      if (kIsWeb) {
        final bytes = await _readDisplayAttachmentBytes(ref, widget.attachment);
        if (!mounted || generation != _loadGeneration) {
          return;
        }
        if (bytes == null || bytes.isEmpty) {
          setState(() {
            _errorMessage = context.strings.videoPreviewUnavailableWeb;
            _loading = false;
            _playWhenLoaded = false;
          });
          return;
        }
        final mimeType = _mimeTypeForVideoAttachment(widget.attachment);
        webObjectUrl = createWebVideoObjectUrl(
          Uint8List.fromList(bytes),
          mimeType,
        );
        if (webObjectUrl == null) {
          setState(() {
            _errorMessage = context.strings.videoPreviewUnavailableWeb;
            _loading = false;
            _playWhenLoaded = false;
          });
          return;
        }
        setState(() {
          _webObjectUrl = webObjectUrl;
          _webVideoViewType =
              'himemo-video-${DateTime.now().microsecondsSinceEpoch}';
          _webVideoAutoplay = playWhenLoaded;
          _loading = false;
          _playWhenLoaded = false;
        });
        return;
      } else {
        if (filePath.startsWith(_remoteSyncAttachmentObjectPrefix)) {
          final bytes = await _readDisplayAttachmentBytes(
            ref,
            widget.attachment,
          );
          if (bytes != null && bytes.isNotEmpty) {
            tempFilePath = await attachmentStore.materializeDecryptedBytes(
              bytes,
              type: widget.attachment.type,
              preferredFileName: widget.attachment.label,
            );
          }
        } else {
          tempFilePath = await attachmentStore.materializeDecryptedFile(
            filePath,
            type: widget.attachment.type,
            preferredFileName: widget.attachment.label,
          );
        }
        if (!mounted || generation != _loadGeneration) {
          if (tempFilePath != null) {
            await attachmentStore.deleteMaterializedFile(tempFilePath);
          }
          return;
        }
        if (tempFilePath == null) {
          setState(() {
            _errorMessage = context.strings.videoPreviewUnavailableWeb;
            _loading = false;
            _playWhenLoaded = false;
          });
          return;
        }
        controller = createLocalVideoController(tempFilePath);
      }
      await controller.initialize().timeout(const Duration(seconds: 15));
      await _applyMutedState(controller);
      controller.addListener(_handleControllerChanged);
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        await attachmentStore.deleteMaterializedFile(tempFilePath);
        return;
      }
      if (playWhenLoaded) {
        unawaited(controller.play());
      }
      setState(() {
        _tempFilePath = tempFilePath;
        _webObjectUrl = webObjectUrl;
        _controller = controller;
        _wasPlaying = controller.value.isPlaying;
        _position = controller.value.position;
        _duration = controller.value.duration;
        _loading = false;
        _playWhenLoaded = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Video playback load failed: $error\n$stackTrace');
      if (tempFilePath != null) {
        unawaited(
          ref
              .read(encryptedAttachmentStoreProvider)
              .deleteMaterializedFile(tempFilePath),
        );
      }
      if (webObjectUrl != null) {
        revokeWebVideoObjectUrl(webObjectUrl);
      }
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _errorMessage = context.strings.videoPreviewUnavailableWeb;
        _loading = false;
        _playWhenLoaded = false;
      });
    }
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    final isPlaying = controller.value.isPlaying;
    final position = controller.value.position;
    final duration = controller.value.duration;
    if (isPlaying == _wasPlaying &&
        (position - _position).abs() < const Duration(milliseconds: 250) &&
        duration == _duration) {
      return;
    }
    setState(() {
      _wasPlaying = isPlaying;
      _position = position;
      _duration = duration;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(child: Text(errorMessage));
    }
    if (kIsWeb && _webObjectUrl != null && _webVideoViewType != null) {
      return _buildWebVideo(
        context,
        _webObjectUrl!,
        _webVideoViewType!,
        muted: _muted,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return _buildDeferredPreview(context, loading: _loading);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 520.0;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        const controlsHeight = 96.0;
        final maxVideoHeight = math.max(96.0, availableHeight - controlsHeight);
        final aspectRatio = controller.value.aspectRatio <= 0
            ? 16 / 9
            : controller.value.aspectRatio;
        final duration = _duration <= Duration.zero
            ? controller.value.duration
            : _duration;
        final boundedPosition = _clampMediaPosition(_position, duration);
        final displayPosition = _dragPosition == null
            ? boundedPosition
            : _clampMediaPosition(_dragPosition!, duration);
        final controlsOnDark = widget.fillAvailableHeight;
        final controlColor = controlsOnDark ? Colors.white : null;
        final secondaryControlColor = controlsOnDark
            ? Colors.white70
            : _mutedTextColor(context);
        final videoTapHandler = widget.fillAvailableHeight
            ? () => _togglePlayback(controller)
            : _openFullScreen;
        final videoPane = SizedBox(
          height: maxVideoHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxVideoHeight,
              ),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AbsorbPointer(
                        child: VideoPlayer(
                          controller,
                          key: ValueKey(_videoViewGeneration),
                        ),
                      ),
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: videoTapHandler,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        return Column(
          mainAxisSize: widget.fillAvailableHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (widget.fillAvailableHeight)
              Expanded(child: videoPane)
            else
              videoPane,
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () => _togglePlayback(controller),
                  icon: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    color: controlColor,
                  ),
                ),
                IconButton(
                  onPressed: _toggleMuted,
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: controlColor,
                  ),
                  tooltip: _videoMuteTooltip(_muted),
                ),
                Expanded(
                  child: Slider(
                    value: duration <= Duration.zero
                        ? 0
                        : displayPosition.inMilliseconds
                              .clamp(0, duration.inMilliseconds)
                              .toDouble(),
                    max: duration <= Duration.zero
                        ? 1
                        : duration.inMilliseconds.toDouble(),
                    onChanged: duration <= Duration.zero
                        ? null
                        : (value) {
                            setState(() {
                              _dragPosition = Duration(
                                milliseconds: value.round(),
                              );
                            });
                          },
                    onChangeEnd: duration <= Duration.zero
                        ? null
                        : (value) {
                            unawaited(
                              _seekFromSlider(controller, value, duration),
                            );
                          },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '${_formatAudioDuration(displayPosition)} / '
                  '${_formatAudioDuration(duration)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: secondaryControlColor,
                  ),
                ),
                const Spacer(),
                if (widget.showFullScreenAction &&
                    widget.onOpenFullScreen != null)
                  IconButton(
                    onPressed: _openFullScreen,
                    icon: Icon(Icons.open_in_full_rounded, color: controlColor),
                  ),
                if (widget.showShareAction)
                  IconButton(
                    onPressed: () =>
                        _shareAttachment(context, ref, widget.attachment),
                    icon: Icon(Icons.ios_share_outlined, color: controlColor),
                    tooltip: context.strings.share,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildWebVideo(
    BuildContext context,
    String objectUrl,
    String viewType, {
    required bool muted,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 520.0;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        final maxVideoHeight = widget.fillAvailableHeight
            ? availableHeight
            : math.max(96.0, availableHeight - 56.0);
        final videoPane = SizedBox(
          height: maxVideoHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxVideoHeight,
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: buildWebVideoElementView(
                    viewType: viewType,
                    objectUrl: objectUrl,
                    autoplay: _webVideoAutoplay,
                    muted: muted,
                    fillAvailableHeight: widget.fillAvailableHeight,
                  ),
                ),
              ),
            ),
          ),
        );
        final controlColor = widget.fillAvailableHeight ? Colors.white : null;
        return Column(
          mainAxisSize: widget.fillAvailableHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (widget.fillAvailableHeight)
              Expanded(child: videoPane)
            else
              videoPane,
            if (!widget.fillAvailableHeight) const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: _toggleMuted,
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: controlColor,
                  ),
                  tooltip: _videoMuteTooltip(_muted),
                ),
                const Spacer(),
                if (widget.showFullScreenAction &&
                    widget.onOpenFullScreen != null)
                  IconButton(
                    onPressed: _openFullScreen,
                    icon: Icon(Icons.open_in_full_rounded, color: controlColor),
                  ),
                if (widget.showShareAction)
                  IconButton(
                    onPressed: () =>
                        _shareAttachment(context, ref, widget.attachment),
                    icon: Icon(Icons.ios_share_outlined, color: controlColor),
                    tooltip: context.strings.share,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeferredPreview(BuildContext context, {required bool loading}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 520.0;
        final availableHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 420.0;
        const controlsHeight = 96.0;
        final maxVideoHeight = math.max(96.0, availableHeight - controlsHeight);
        final controlsOnDark = widget.fillAvailableHeight;
        final controlColor = controlsOnDark ? Colors.white : null;
        final secondaryControlColor = controlsOnDark
            ? Colors.white70
            : _mutedTextColor(context);
        final previewBytes = _decodeVideoPreviewBytes();
        final playAction = loading
            ? null
            : () => unawaited(_load(playWhenLoaded: true));
        final videoPane = SizedBox(
          height: maxVideoHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxVideoHeight,
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: InkWell(
                      onTap: playAction,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (previewBytes != null)
                            Image.memory(
                              previewBytes,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.videocam_outlined,
                                  size: 56,
                                  color: Theme.of(context).colorScheme.primary,
                                );
                              },
                            )
                          else
                            Icon(
                              Icons.videocam_outlined,
                              size: 56,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.18),
                          ),
                          Center(
                            child: loading
                                ? const SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  )
                                : Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.56,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 38,
                                    ),
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
        );

        return Column(
          mainAxisSize: widget.fillAvailableHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (widget.fillAvailableHeight)
              Expanded(child: videoPane)
            else
              videoPane,
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: playAction,
                  icon: Icon(Icons.play_circle_outline, color: controlColor),
                ),
                Expanded(
                  child: Text(
                    loading && _playWhenLoaded
                        ? context.strings.localized(
                            en: 'Loading video...',
                            ja: '動画を読み込み中...',
                            zh: '正在加载视频...',
                            ko: '동영상을 불러오는 중...',
                            es: 'Cargando video...',
                            de: 'Video wird geladen...',
                          )
                        : context.strings.tapToPlayVideo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: secondaryControlColor,
                    ),
                  ),
                ),
                if (widget.showShareAction)
                  IconButton(
                    onPressed: () =>
                        _shareAttachment(context, ref, widget.attachment),
                    icon: Icon(Icons.ios_share_outlined, color: controlColor),
                    tooltip: context.strings.share,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Uint8List? _decodeVideoPreviewBytes() {
    final encoded = widget.attachment.previewBytesBase64;
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> _openFullScreen() async {
    final strings = context.strings;
    final sizeBytes = await _attachmentSizeFuture(ref, widget.attachment);
    if (!mounted) {
      return;
    }
    final sizeLabel = sizeBytes == null || sizeBytes <= 0
        ? null
        : strings.byteCount(sizeBytes);
    if (kIsWeb && _webObjectUrl != null) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.88),
        pageBuilder: (context, _, _) => _WebVideoLightboxDialog(
          attachment: widget.attachment,
          objectUrl: _webObjectUrl!,
          muted: _muted,
          sizeLabel: sizeLabel,
          onMutedChanged: _handleMutedChanged,
          onShare: widget.showShareAction
              ? () => _shareAttachment(context, ref, widget.attachment)
              : null,
        ),
        transitionBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      widget.onOpenFullScreen?.call();
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (context, _, _) => _VideoControllerLightboxDialog(
        attachment: widget.attachment,
        controller: controller,
        initialMuted: _muted,
        sizeLabel: sizeLabel,
        onMutedChanged: _handleMutedChanged,
        onShare: widget.showShareAction
            ? () => _shareAttachment(context, ref, widget.attachment)
            : null,
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
    if (mounted) {
      setState(() {
        _videoViewGeneration += 1;
        _wasPlaying = controller.value.isPlaying;
        _position = controller.value.position;
        _duration = controller.value.duration;
      });
    }
  }

  Future<void> _applyMutedState(VideoPlayerController controller) async {
    final desiredVolume = _muted ? 0.0 : 1.0;
    if ((controller.value.volume - desiredVolume).abs() < 0.01) {
      return;
    }
    await controller.setVolume(desiredVolume);
  }

  void _togglePlayback(VideoPlayerController controller) {
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      final duration = controller.value.duration;
      if (duration > Duration.zero &&
          controller.value.position >=
              duration - const Duration(milliseconds: 250)) {
        unawaited(
          controller.seekTo(Duration.zero).then((_) => controller.play()),
        );
      } else {
        unawaited(controller.play());
      }
    }
    setState(() {});
  }

  void _toggleMuted() {
    _handleMutedChanged(!_muted);
  }

  void _handleMutedChanged(bool muted) {
    if (kIsWeb && _webVideoViewType != null) {
      updateWebVideoElementMuted(_webVideoViewType!, muted);
    }
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.setVolume(muted ? 0.0 : 1.0));
    }
    if (!mounted) {
      _muted = muted;
      return;
    }
    setState(() {
      _muted = muted;
    });
  }

  Future<void> _seekFromSlider(
    VideoPlayerController controller,
    double value,
    Duration duration,
  ) async {
    final target = _clampMediaPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
    await controller.seekTo(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _position = target;
      _dragPosition = null;
    });
  }
}

Duration _clampMediaPosition(Duration value, Duration duration) {
  if (duration <= Duration.zero) {
    return Duration.zero;
  }
  if (value < Duration.zero) {
    return Duration.zero;
  }
  if (value > duration) {
    return duration;
  }
  return value;
}

String _mimeTypeForVideoAttachment(NoteAttachment attachment) {
  final label = attachment.label.toLowerCase();
  if (label.endsWith('.webm')) {
    return 'video/webm';
  }
  if (label.endsWith('.ogv') || label.endsWith('.ogg')) {
    return 'video/ogg';
  }
  if (label.endsWith('.mov')) {
    return 'video/quicktime';
  }
  if (label.endsWith('.m4v')) {
    return 'video/x-m4v';
  }
  return 'video/mp4';
}

Future<MediaImportResult> _showAudioRecordingDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showDialog<MediaImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AudioRecordingDialog(
      attachmentStore: ref.read(encryptedAttachmentStoreProvider),
    ),
  );
  return result ?? const MediaImportResult.cancelled();
}

class _RecordingFormat {
  const _RecordingFormat({
    required this.encoder,
    required this.extension,
    required this.mimeType,
  });

  final AudioEncoder encoder;
  final String extension;
  final String mimeType;
}

class _AudioRecordingDialog extends StatefulWidget {
  const _AudioRecordingDialog({required this.attachmentStore});

  final EncryptedAttachmentStore attachmentStore;

  @override
  State<_AudioRecordingDialog> createState() => _AudioRecordingDialogState();
}

class _AudioRecordingDialogState extends State<_AudioRecordingDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _isRecording = false;
  bool _isBusy = false;
  String? _errorMessage;
  String? _fileName;
  _RecordingFormat? _format;
  StreamSubscription<Uint8List>? _webRecordingSubscription;
  final List<int> _webRecordingPcmBytes = <int>[];

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_webRecordingSubscription?.cancel());
    if (_isRecording) {
      unawaited(_recorder.cancel());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      final strings = context.strings;
      final hasPermission = await _recorder.hasPermission().timeout(
        kIsWeb ? const Duration(seconds: 30) : const Duration(seconds: 10),
        onTimeout: () =>
            throw TimeoutException(strings.microphonePermissionRequestTimedOut),
      );
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = kIsWeb
              ? '${strings.microphonePermissionNotGranted} ${strings.microphonePermissionBrowserHelp}'
              : strings.microphonePermissionNotGranted;
        });
        return;
      }

      final format = await _resolveRecordingFormat();
      debugPrint(
        'Audio recording start: encoder=${format.encoder.name}, '
        'extension=${format.extension}, web=$kIsWeb',
      );
      final timestamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final fileName = 'audio_note_$timestamp.${format.extension}';
      final outputPath = kIsWeb
          ? fileName
          : path.join((await getTemporaryDirectory()).path, fileName);

      if (kIsWeb) {
        _webRecordingPcmBytes.clear();
        final stream = await _recorder
            .startStream(_recordConfig(AudioEncoder.pcm16bits))
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () =>
                  throw TimeoutException(strings.microphoneStartTimedOut),
            );
        _webRecordingSubscription = stream.listen(_webRecordingPcmBytes.addAll);
      } else {
        await _recorder.start(_recordConfig(format.encoder), path: outputPath);
      }
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _elapsed += const Duration(seconds: 1);
          });
        }
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _format = format;
        _fileName = fileName;
        _elapsed = Duration.zero;
        _isRecording = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Audio recording failed: $error\n$stackTrace');
      if (kIsWeb) {
        unawaited(_webRecordingSubscription?.cancel());
        _webRecordingSubscription = null;
        unawaited(_recorder.cancel());
      }
      if (!mounted) {
        return;
      }
      final diagnostic = _recordingStartDiagnostic(error, context.strings);
      setState(() {
        _errorMessage = context.strings.audioRecordingStartFailed(diagnostic);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  String _recordingStartDiagnostic(Object error, AppStrings strings) {
    if (!kIsWeb) {
      return '';
    }
    if (error is TimeoutException && error.message != null) {
      return ' ${error.message}';
    }
    final message = error.toString().toLowerCase();
    if (message.contains('notallowed') ||
        message.contains('permission') ||
        message.contains('denied')) {
      return ' ${strings.microphonePermissionBrowserHelp}';
    }
    return '';
  }

  RecordConfig _recordConfig(AudioEncoder encoder) {
    return RecordConfig(
      encoder: encoder,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(
        service: AndroidService(
          title: context.strings.audioRecordingNotificationTitle,
          content: context.strings.audioRecordingNotificationContent,
        ),
      ),
      audioInterruption: AudioInterruptionMode.none,
    );
  }

  Future<void> _stopAndAttach() async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      _timer?.cancel();
      await _webRecordingSubscription?.cancel();
      _webRecordingSubscription = null;
      final recordedPath = await _recorder.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
      });
      final fileName = _fileName;
      final format = _format;
      if (fileName == null || format == null) {
        setState(() {
          _errorMessage = context.strings.audioRecordingSaveFailed;
        });
        return;
      }
      if (!kIsWeb && recordedPath == null) {
        setState(() {
          _errorMessage = context.strings.audioRecordingSaveFailed;
        });
        return;
      }
      if (kIsWeb && _webRecordingPcmBytes.isEmpty) {
        setState(() {
          _errorMessage = context.strings.audioRecordingEmpty;
        });
        return;
      }
      final file = kIsWeb
          ? XFile.fromData(
              Uint8List.fromList(
                _wavBytesFromPcm16(
                  _webRecordingPcmBytes,
                  sampleRate: 44100,
                  numChannels: 1,
                ),
              ),
              name: fileName,
              mimeType: format.mimeType,
            )
          : XFile(recordedPath!, name: fileName, mimeType: format.mimeType);
      final filePath = await widget.attachmentStore.storeAttachment(
        file,
        type: AttachmentType.audio,
      );
      if (!mounted) {
        return;
      }
      if (filePath == null) {
        setState(() {
          _errorMessage = context.strings.audioRecordingAttachFailed;
        });
        return;
      }
      Navigator.of(context).pop(
        MediaImportResult.success(
          NoteAttachment(
            type: AttachmentType.audio,
            label: fileName,
            filePath: filePath,
            durationMs: _elapsed.inMilliseconds,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = context.strings.audioRecordingStoreFailed;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_isRecording) {
      await _recorder.cancel();
    }
    if (mounted) {
      Navigator.of(context).pop(const MediaImportResult.cancelled());
    }
  }

  Future<_RecordingFormat> _resolveRecordingFormat() async {
    if (kIsWeb) {
      return const _RecordingFormat(
        encoder: AudioEncoder.wav,
        extension: 'wav',
        mimeType: 'audio/wav',
      );
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return const _RecordingFormat(
        encoder: AudioEncoder.aacLc,
        extension: 'm4a',
        mimeType: 'audio/mp4',
      );
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      return const _RecordingFormat(
        encoder: AudioEncoder.wav,
        extension: 'wav',
        mimeType: 'audio/wav',
      );
    }
    return const _RecordingFormat(
      encoder: AudioEncoder.aacLc,
      extension: 'm4a',
      mimeType: 'audio/mp4',
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.audioMemoRecordingTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isRecording
                  ? Icons.fiber_manual_record_rounded
                  : Icons.mic_none_rounded,
              size: 56,
              color: _isRecording
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              _formatRecordingDuration(_elapsed),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : _cancel,
          child: Text(strings.cancel),
        ),
        if (_isRecording)
          FilledButton.icon(
            onPressed: _isBusy ? null : _stopAndAttach,
            icon: const Icon(Icons.stop_rounded),
            label: Text(strings.stopAndAttachRecording),
          )
        else
          FilledButton.icon(
            onPressed: _isBusy ? null : _start,
            icon: const Icon(Icons.mic_rounded),
            label: Text(strings.startRecording),
          ),
      ],
    );
  }
}

List<int> _wavBytesFromPcm16(
  List<int> pcmBytes, {
  required int sampleRate,
  required int numChannels,
}) {
  final byteRate = sampleRate * numChannels * 2;
  final blockAlign = numChannels * 2;
  final dataLength = pcmBytes.length;
  final totalLength = 44 + dataLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.view(bytes.buffer);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i += 1) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, numChannels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  bytes.setRange(44, totalLength, pcmBytes);
  return bytes;
}

String _formatRecordingDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _AudioAttachmentViewer extends ConsumerStatefulWidget {
  const _AudioAttachmentViewer({required this.attachment});

  final NoteAttachment attachment;

  @override
  ConsumerState<_AudioAttachmentViewer> createState() =>
      _AudioAttachmentViewerState();
}

class _AudioAttachmentViewerState
    extends ConsumerState<_AudioAttachmentViewer> {
  final AudioPlayer _player = AudioPlayer();
  String? _tempFilePath;
  bool _ready = false;
  String? _errorMessage;
  Duration? _dragPosition;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    final tempFilePath = _tempFilePath;
    if (tempFilePath != null) {
      unawaited(
        ref
            .read(encryptedAttachmentStoreProvider)
            .deleteMaterializedFile(tempFilePath),
      );
    }
    super.dispose();
  }

  Future<void> _load() async {
    final filePath = widget.attachment.filePath;
    if (filePath == null || filePath.isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage = context.strings.audioPlaybackFailed;
        });
      }
      return;
    }
    try {
      final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
      if (kIsWeb) {
        final bytes = await attachmentStore.readAttachment(
          filePath,
          type: widget.attachment.type,
        );
        if (!mounted) {
          return;
        }
        if (bytes == null || bytes.isEmpty) {
          setState(() {
            _errorMessage = context.strings.audioPlaybackFailed;
          });
          return;
        }
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.dataFromBytes(
              Uint8List.fromList(bytes),
              mimeType: _mimeTypeForAudioAttachment(widget.attachment),
            ),
          ),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _ready = true;
        });
        return;
      }

      final tempFilePath = await attachmentStore.materializeDecryptedFile(
        filePath,
        type: widget.attachment.type,
        preferredFileName: widget.attachment.label,
      );
      if (!mounted) {
        return;
      }
      if (tempFilePath == null) {
        setState(() {
          _errorMessage = context.strings.audioPlaybackFailed;
        });
        return;
      }
      await _player
          .setFilePath(tempFilePath)
          .timeout(const Duration(seconds: 15));
      setState(() {
        _tempFilePath = tempFilePath;
        _ready = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Audio playback load failed: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = context.strings.audioPlaybackFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(child: Text(errorMessage));
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final isPlaying = playerState?.playing ?? false;
        final isCompleted =
            playerState?.processingState == ProcessingState.completed;
        return StreamBuilder<Duration?>(
          stream: _player.durationStream,
          builder: (context, durationSnapshot) {
            final duration =
                durationSnapshot.data ?? _player.duration ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final boundedPosition =
                    position > duration && duration > Duration.zero
                    ? duration
                    : position;
                final displayPosition =
                    _dragPosition == null || duration == Duration.zero
                    ? boundedPosition
                    : _clampAudioPosition(_dragPosition!, duration);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.audiotrack_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: duration == Duration.zero
                            ? 0
                            : displayPosition.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble(),
                        max: duration == Duration.zero
                            ? 1
                            : duration.inMilliseconds.toDouble(),
                        onChanged: duration == Duration.zero
                            ? null
                            : (value) {
                                setState(() {
                                  _dragPosition = Duration(
                                    milliseconds: value.round(),
                                  );
                                });
                              },
                        onChangeEnd: duration == Duration.zero
                            ? null
                            : (value) {
                                unawaited(_seekFromSlider(value, duration));
                              },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatAudioDuration(displayPosition)),
                          Text(_formatAudioDuration(duration)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          if (isPlaying) {
                            await _player.pause();
                          } else {
                            if (isCompleted) {
                              await _player.seek(Duration.zero);
                            }
                            await _player.play();
                          }
                        },
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        label: Text(
                          isPlaying
                              ? context.strings.pauseAudio
                              : context.strings.playAudio,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _seekFromSlider(double value, Duration duration) async {
    final target = _clampAudioPosition(
      Duration(milliseconds: value.round()),
      duration,
    );
    try {
      await _player.seek(target);
    } catch (error, stackTrace) {
      debugPrint('Audio seek failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = context.strings.audioPlaybackFailed;
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _dragPosition = null;
    });
  }
}

Duration _clampAudioPosition(Duration value, Duration duration) {
  if (duration <= Duration.zero) {
    return Duration.zero;
  }
  if (value < Duration.zero) {
    return Duration.zero;
  }
  if (value > duration) {
    return duration;
  }
  return value;
}

String _formatAudioDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String _mimeTypeForAudioAttachment(NoteAttachment attachment) {
  final label = attachment.label.toLowerCase();
  if (label.endsWith('.wav')) {
    return 'audio/wav';
  }
  if (label.endsWith('.m4a') || label.endsWith('.mp4')) {
    return 'audio/mp4';
  }
  if (label.endsWith('.webm')) {
    return 'audio/webm';
  }
  if (label.endsWith('.ogg') || label.endsWith('.opus')) {
    return 'audio/ogg';
  }
  return 'audio/mpeg';
}
