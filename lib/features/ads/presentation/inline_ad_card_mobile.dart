import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../data/ad_mob_config.dart';

class HiMemoInlineAdCard extends StatefulWidget {
  const HiMemoInlineAdCard({super.key, this.maxHeight = 96});

  final double maxHeight;

  @override
  State<HiMemoInlineAdCard> createState() => _HiMemoInlineAdCardState();
}

class _HiMemoInlineAdCardState extends State<HiMemoInlineAdCard> {
  BannerAd? _ad;
  AdSize? _loadedSize;
  int? _requestedWidth;
  int? _loadingWidth;
  int? _failedWidth;
  bool _loadScheduled = false;
  int _loadGeneration = 0;

  @override
  Widget build(BuildContext context) {
    if (!AdMobConfig.canShowInlineBanner) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        if (!availableWidth.isFinite || availableWidth < 280) {
          return const SizedBox.shrink();
        }
        final width = availableWidth.floor();
        _scheduleLoad(width);

        final ad = _ad;
        final loadedSize = _loadedSize;
        final colorScheme = Theme.of(context).colorScheme;
        final slotHeight = widget.maxHeight + 16;
        final adChild = ad == null || loadedSize == null
            ? const SizedBox.shrink()
            : SizedBox(
                width: math.min(loadedSize.width.toDouble(), availableWidth),
                height: math.min(
                  loadedSize.height.toDouble(),
                  widget.maxHeight,
                ),
                child: AdWidget(ad: ad),
              );

        return Container(
          key: const Key('himemo-inline-ad-card'),
          width: double.infinity,
          height: slotHeight,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(child: adChild),
        );
      },
    );
  }

  void _scheduleLoad(int width) {
    if (_requestedWidth == width &&
        (_ad != null || _loadingWidth == width || _loadScheduled)) {
      return;
    }
    if (_failedWidth == width) {
      return;
    }
    _requestedWidth = width;
    if (_loadScheduled) {
      return;
    }
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      final requestedWidth = _requestedWidth;
      if (!mounted || requestedWidth == null) {
        return;
      }
      _loadAd(requestedWidth);
    });
  }

  Future<void> _loadAd(int width) async {
    final adUnitId = AdMobConfig.inlineBannerAdUnitId;
    if (adUnitId == null) {
      return;
    }

    final generation = ++_loadGeneration;
    final oldAd = _ad;
    setState(() {
      _ad = null;
      _loadedSize = null;
      _loadingWidth = width;
      _failedWidth = null;
    });
    await oldAd?.dispose();
    if (!mounted || generation != _loadGeneration) {
      return;
    }

    final adSize = AdSize.getInlineAdaptiveBannerAdSize(
      width,
      widget.maxHeight.round(),
    );
    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) async {
          final loadedAd = ad as BannerAd;
          final platformSize = await loadedAd.getPlatformAdSize();
          if (!mounted || generation != _loadGeneration) {
            await loadedAd.dispose();
            return;
          }
          if (platformSize == null) {
            await loadedAd.dispose();
            setState(() {
              _loadingWidth = null;
              _failedWidth = width;
            });
            return;
          }
          setState(() {
            _ad = loadedAd;
            _loadedSize = platformSize;
            _loadingWidth = null;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted || generation != _loadGeneration) {
            return;
          }
          setState(() {
            _loadingWidth = null;
            _failedWidth = width;
          });
        },
      ),
    );
    try {
      await bannerAd.load();
    } catch (_) {
      await bannerAd.dispose();
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _loadingWidth = null;
        _failedWidth = width;
      });
    }
  }

  @override
  void didUpdateWidget(covariant HiMemoInlineAdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxHeight != widget.maxHeight) {
      _failedWidth = null;
      _requestedWidth = null;
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ad?.dispose();
    super.dispose();
  }
}
