import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ads/ad_config.dart';
import '../../services/ads/ads_service.dart';

/// A self-contained anchored adaptive banner. Drop it anywhere that's
/// allowed to show ads (lists, detail screens) — NEVER in Advent Chat,
/// auth/onboarding or prayer screens. Renders nothing (zero height) until
/// an ad loads, and quietly removes itself if loading fails, so layouts
/// never reserve empty space for an ad that didn't arrive.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, this.padding});

  /// Optional padding applied only once an ad is actually showing.
  final EdgeInsetsGeometry? padding;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;
  int _retries = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Width comes from MediaQuery, so load here (not initState) and only
    // once.
    if (!_requested) {
      _requested = true;
      _load();
    }
  }

  Future<void> _load() async {
    // AdsService may still be initialising on a cold start — retry a few
    // times before giving up.
    if (!AdsService.isReady) {
      if (_retries++ > 5) return;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) _load();
      return;
    }

    final width = MediaQuery.of(context).size.width.truncate();
    // Use the STANDARD anchored adaptive banner (~50dp), not the LARGE one
    // (~90–100dp). The large banner sat right above the action buttons on the
    // product / event / church detail screens, so users kept mis-tapping it
    // and getting launched into a full-screen ad they couldn't skip. The
    // smaller banner is far less intrusive and harder to hit by accident.
    final size = await AdSize.getAnchoredAdaptiveBannerAdSize(
      Orientation.portrait,
      width,
    );
    if (size == null || !mounted) return;

    final ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
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
    final banner = SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
    final centered = Center(child: banner);
    return widget.padding == null
        ? centered
        : Padding(padding: widget.padding!, child: centered);
  }
}
