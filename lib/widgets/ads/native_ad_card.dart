import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ads/ad_config.dart';
import '../../services/ads/ads_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';

/// A native ad rendered with Google's built-in medium template (no
/// platform-specific factory code needed) and themed to match the app's
/// cards so it reads as "sponsored" without jarring the feed. Used for
/// the home feed and list screens — NEVER in Advent Chat / auth / prayer.
///
/// Renders nothing until the ad loads and removes itself on failure, so
/// the feed never shows an empty slot.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key, this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 8)});

  final EdgeInsetsGeometry margin;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _requested = false;
  int _retries = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _load();
    }
  }

  Future<void> _load() async {
    if (!AdsService.isReady) {
      if (_retries++ > 5) return;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) _load();
      return;
    }
    final p = context.palette;
    final ad = NativeAd(
      adUnitId: AdConfig.nativeUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: p.card,
        cornerRadius: 16,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.white,
          backgroundColor: AppColors.primaryBlue,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: p.text,
          backgroundColor: p.card,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: p.textMuted,
          backgroundColor: p.card,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: p.textMuted,
          backgroundColor: p.card,
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    unawaited(ad.load());
    _ad = ad;
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          // Medium template needs a bounded height; ~320 fits it snugly.
          constraints: const BoxConstraints(minHeight: 300, maxHeight: 360),
          color: context.palette.card,
          child: AdWidget(ad: _ad!),
        ),
      ),
    );
  }
}
