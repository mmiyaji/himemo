import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../l10n/app_strings.dart';
import '../data/ad_mob_config.dart';

const _adHorizontalPadding = 12.0;
const _adVerticalPadding = 8.0;
const _adHeaderHeight = 20.0;
const _adBodyGap = 6.0;
const _adChromeHeight = (_adVerticalPadding * 2) + _adHeaderHeight + _adBodyGap;

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
        if (!availableWidth.isFinite) {
          return const SizedBox.shrink();
        }
        final contentWidth = availableWidth - (_adHorizontalPadding * 2);
        if (contentWidth < 280) {
          return const SizedBox.shrink();
        }
        final width = contentWidth.floor();
        _scheduleLoad(width);

        final ad = _ad;
        final loadedSize = _loadedSize;
        final colorScheme = Theme.of(context).colorScheme;
        final slotHeight = widget.maxHeight + _adChromeHeight;
        final adChild = ad == null || loadedSize == null
            ? _InlineAdPlaceholder(failed: _failedWidth == width)
            : SizedBox(
                width: math.min(loadedSize.width.toDouble(), contentWidth),
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
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            _adHorizontalPadding,
            _adVerticalPadding,
            _adHorizontalPadding,
            _adVerticalPadding,
          ),
          child: Column(
            children: [
              const SizedBox(height: _adHeaderHeight, child: _InlineAdHeader()),
              const SizedBox(height: _adBodyGap),
              Expanded(child: Center(child: adChild)),
            ],
          ),
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

class _InlineAdHeader extends StatelessWidget {
  const _InlineAdHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    return Row(
      children: [
        Icon(Icons.campaign_outlined, size: 14, color: labelColor),
        const SizedBox(width: 5),
        Text(
          context.strings.localized(
            en: 'Ad',
            ja: '広告',
            zh: '广告',
            ko: '광고',
            es: 'Anuncio',
            de: 'Anzeige',
          ),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: labelColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _InlineAdPlaceholder extends StatelessWidget {
  const _InlineAdPlaceholder({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = context.strings;
    final message = failed
        ? strings.localized(
            en: 'Ad is temporarily unavailable',
            ja: '広告を一時的に表示できません',
            zh: '广告暂时无法显示',
            ko: '광고를 일시적으로 표시할 수 없습니다',
            es: 'El anuncio no esta disponible temporalmente',
            de: 'Anzeige voruebergehend nicht verfuegbar',
          )
        : strings.localized(
            en: 'Loading ad',
            ja: '広告を読み込み中',
            zh: '正在加载广告',
            ko: '광고를 불러오는 중',
            es: 'Cargando anuncio',
            de: 'Anzeige wird geladen',
          );
    return Text(
      message,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}
