import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ads/ad_config.dart';
import '../../services/ads/ad_impression_counter.dart';
import '../../services/ads/ads_service.dart';
import '../../services/premium_service.dart';

/// A self-contained anchored adaptive banner. Drop it anywhere that's
/// allowed to show ads (lists, detail screens) — NEVER in Advent Chat,
/// auth/onboarding or prayer screens. Renders nothing (zero height) until
/// an ad loads, and quietly removes itself if loading fails, so layouts
/// never reserve empty space for an ad that didn't arrive.
///
/// Premium subscribers never reach the request at all, and a banner
/// already on screen when a purchase completes disappears on the spot.
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
  void initState() {
    super.initState();
    PremiumService.isPremium.addListener(_onPremiumChanged);
  }

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

  /// Premium started: bin the ad mid-flight. Premium lapsed: start asking
  /// again, since this widget may never rebuild from the top otherwise.
  void _onPremiumChanged() {
    if (!mounted) return;
    if (PremiumService.isActive) {
      _ad?.dispose();
      _ad = null;
      setState(() => _loaded = false);
    } else if (_ad == null) {
      _retries = 0;
      _load();
    }
  }

  Future<void> _load() async {
    // A subscriber never even asks for an ad — that, not hiding the
    // widget, is what they paid for.
    if (PremiumService.isActive) return;
    // AdsService may still be initialising on a cold start — retry a few
    // times before giving up.
    if (!AdsService.canRequestAds) {
      if (_retries++ > 5) return;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) _load();
      return;
    }

    if (!mounted) return;
    // Use the fixed STANDARD banner (320×50), not the LARGE adaptive one
    // (~90–100dp). The large banner sat right above the action buttons on the
    // product / event / church detail screens, so users kept mis-tapping it
    // and getting launched into a full-screen ad they couldn't skip. (The
    // small anchored-adaptive size was dropped in google_mobile_ads 9 — only
    // the "large" variant remains adaptive — so we pin the standard banner to
    // keep that low, non-intrusive height.)
    const size = AdSize.banner;

    final ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          // Counted on FILL, not on request — an ad that never arrived
          // was never seen, and the Premium screen quotes this number
          // back to the user.
          unawaited(AdImpressionCounter.record());
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
    PremiumService.isPremium.removeListener(_onPremiumChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (PremiumService.isActive) return const SizedBox.shrink();
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
