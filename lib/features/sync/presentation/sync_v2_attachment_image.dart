import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Displays one in-memory v2 attachment without writing plaintext to disk.
///
/// Keep [key] stable for the attachment's session/profile/reference identity.
/// The widget owns and clears the bytes returned by [loadBytes].
class SyncV2AttachmentImage extends StatefulWidget {
  const SyncV2AttachmentImage({
    super.key,
    required this.loadBytes,
    required this.isActive,
    required this.label,
    this.thumbnail = true,
    this.onTap,
    this.onUnsupported,
    this.size,
    this.decodeWidth,
  });

  final Future<Uint8List> Function(bool Function() isCurrent) loadBytes;
  final bool Function() isActive;
  final String label;
  final bool thumbnail;
  final VoidCallback? onTap;
  final VoidCallback? onUnsupported;
  final double? size;
  final int? decodeWidth;

  @override
  State<SyncV2AttachmentImage> createState() => _SyncV2AttachmentImageState();
}

class _SyncV2AttachmentImageState extends State<SyncV2AttachmentImage>
    with WidgetsBindingObserver {
  Uint8List? _bytes;
  MemoryImage? _memoryImage;
  ImageProvider<Object>? _imageProvider;
  bool _foreground = true;
  bool _loading = false;
  bool _loadFailed = false;
  int _generation = 0;
  bool _clearScheduled = false;
  bool _decodeFailureScheduled = false;

  bool get _active {
    try {
      return widget.isActive();
    } catch (_) {
      return false;
    }
  }

  String _text(BuildContext context, String japanese, String english) =>
      Localizations.localeOf(context).languageCode == 'ja' ? japanese : english;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  @override
  void didUpdateWidget(covariant SyncV2AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent callbacks are often recreated on each build. Only the stable
    // widget key identifies a different attachment; compare active state here.
    final wasActive = _safeActive(oldWidget.isActive);
    final isActive = _active;
    if (wasActive && !isActive) {
      _clearSensitiveBytes();
    } else if (!wasActive && isActive && _foreground && !_loadFailed) {
      _maybeLoad();
    }
  }

  bool _safeActive(bool Function() callback) {
    try {
      return callback();
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (mounted) setState(() {});
      if (_active && !_loadFailed) _maybeLoad();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      _clearSensitiveBytes();
    }
  }

  void _maybeLoad() {
    if (!mounted || !_foreground || !_active || _loading || _bytes != null) {
      return;
    }
    if (_loadFailed) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    unawaited(_load(generation));
  }

  bool _requestIsCurrent(int generation) =>
      mounted && _foreground && _active && generation == _generation;

  Future<void> _load(int generation) async {
    Uint8List? bytes;
    try {
      bytes = await widget.loadBytes(() => _requestIsCurrent(generation));
      if (bytes.isEmpty) throw const FormatException('empty attachment');
      if (!mounted ||
          generation != _generation ||
          !_requestIsCurrent(generation)) {
        _zero(bytes);
        return;
      }
      setState(() {
        _bytes = bytes;
        _memoryImage = MemoryImage(bytes!);
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (bytes != null) _zero(bytes);
      if (!mounted || generation != _generation) return;
      if (!_foreground || !_active) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _zero(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }

  void _evictImages() {
    final provider = _imageProvider;
    final memoryImage = _memoryImage;
    _imageProvider = null;
    _memoryImage = null;
    // ImageProvider.evict delegates to ImageCache.evict, whose default
    // includeLive=true also drops the active completer for this owned image.
    if (provider != null) unawaited(provider.evict());
    if (memoryImage != null) unawaited(memoryImage.evict());
  }

  void _clearSensitiveBytes() {
    ++_generation;
    final bytes = _bytes;
    if (bytes != null) _zero(bytes);
    _bytes = null;
    _loading = false;
    _evictImages();
    if (mounted) setState(() {});
  }

  void _scheduleClearIfInactive() {
    if (_clearScheduled) return;
    _clearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearScheduled = false;
      if (mounted && (!_foreground || !_active)) _clearSensitiveBytes();
    });
  }

  void _retry() {
    if (!mounted || !_foreground || !_active) return;
    _clearSensitiveBytes();
    setState(() => _loadFailed = false);
    _maybeLoad();
  }

  void _scheduleDecodeFailure() {
    if (_decodeFailureScheduled) return;
    _decodeFailureScheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _decodeFailureScheduled = false;
      if (!mounted || generation != _generation) return;
      _clearSensitiveBytes();
      setState(() => _loadFailed = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_generation;
    final bytes = _bytes;
    if (bytes != null) _zero(bytes);
    _bytes = null;
    _evictImages();
    super.dispose();
  }

  int _cacheWidth(BuildContext context) {
    if (widget.decodeWidth != null) return widget.decodeWidth!.clamp(1, 4096);
    if (widget.thumbnail) return 256;
    return 2048;
  }

  Widget _frame(BuildContext context, Widget child) {
    final dimension = widget.size ?? 88.0;
    if (widget.thumbnail) {
      return SizedBox.square(dimension: dimension, child: child);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            widget.size ??
            (constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0);
        final height =
            widget.size ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 360.0);
        return SizedBox(
          width: math.max(1, width),
          height: math.max(1, height),
          child: child,
        );
      },
    );
  }

  Widget _placeholder(BuildContext context, {required bool failed}) {
    final scheme = Theme.of(context).colorScheme;
    final message = failed
        ? _text(context, '画像を表示できません', 'Could not display image')
        : (!_foreground || !_active
              ? _text(context, '画像はロック中です', 'Image is locked')
              : _text(context, '画像を読み込み中', 'Loading image'));
    if (failed && widget.thumbnail) {
      return _frame(
        context,
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: message,
                child: Tooltip(
                  message: message,
                  child: Icon(Icons.broken_image_outlined, color: scheme.error),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(24, 24),
                      maximumSize: const Size(24, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: _text(context, '再試行', 'Retry'),
                    onPressed: _foreground && _active ? _retry : null,
                    icon: const Icon(Icons.refresh_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (widget.onUnsupported != null)
                    IconButton(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(24, 24),
                        maximumSize: const Size(24, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: _text(context, '別の方法で開く', 'Open another way'),
                      onPressed: widget.onUnsupported,
                      icon: const Icon(Icons.open_in_new_rounded),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return _frame(
      context,
      DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: failed
              ? SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, color: scheme.error),
                      const SizedBox(height: 4),
                      Text(message, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: _foreground && _active ? _retry : null,
                        child: Text(_text(context, '再試行', 'Retry')),
                      ),
                      if (widget.onUnsupported != null)
                        TextButton(
                          onPressed: widget.onUnsupported,
                          child: Text(
                            _text(context, '別の方法で開く', 'Open another way'),
                          ),
                        ),
                    ],
                  ),
                )
              : (_loading && _foreground && _active
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Flexible(
                            child: Text(message, textAlign: TextAlign.center),
                          ),
                        ],
                      )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_foreground || !_active) {
      if (_bytes != null || _loading) _scheduleClearIfInactive();
      return _placeholder(context, failed: false);
    }
    final bytes = _bytes;
    if (bytes == null) return _placeholder(context, failed: _loadFailed);

    _imageProvider ??= ResizeImage.resizeIfNeeded(
      _cacheWidth(context),
      null,
      _memoryImage!,
    );
    Widget image = Image(
      key: const ValueKey('sync-v2-attachment-image-data'),
      image: _imageProvider!,
      fit: widget.thumbnail ? BoxFit.cover : BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      semanticLabel: widget.label,
      errorBuilder: (context, error, stackTrace) {
        _scheduleDecodeFailure();
        return const SizedBox.shrink();
      },
    );
    if (!widget.thumbnail) {
      image = InteractiveViewer(minScale: 1, maxScale: 5, child: image);
    }
    image = _frame(context, image);
    if (widget.thumbnail && widget.onTap != null) {
      image = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: image,
          ),
        ),
      );
    }
    return image;
  }
}
