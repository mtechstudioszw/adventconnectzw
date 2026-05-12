import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ads_service.dart';
import '../theme/app_colors.dart';

/// Adaptive banner ad. Mounts a fixed 60-px-tall slot immediately so
/// the surrounding scroll position doesn't jump when the ad arrives,
/// then swaps in the real banner once it loads. Used on Home, Churches,
/// Events, Marketplace and Jobs (Part 24 of the master reference).
///
/// Skips itself on desktop/web (where AdMob is unavailable) and on
/// unsupported platforms — never blocks layout.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  bool get _supported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_supported) _load();
  }

  void _load() {
    final unitId = AdsService.bannerUnitId();
    if (unitId == null) return;
    final ad = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdBanner load failed: $error');
          ad.dispose();
        },
      ),
    );
    ad.load();
    _ad = ad;
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    return Container(
      height: 60,
      width: double.infinity,
      alignment: Alignment.center,
      color: AppColors.lightGrey,
      child: _loaded && _ad != null
          ? SizedBox(
              width: _ad!.size.width.toDouble(),
              height: _ad!.size.height.toDouble(),
              child: AdWidget(ad: _ad!),
            )
          : const SizedBox.shrink(),
    );
  }
}
