import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import '../../services/ads/ad_view_slot.dart';
import '../../services/ads/ads_service.dart';
import '../../services/premium_service.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';

/// The in-feed sponsored card, for the Home and Watch feeds. **Never in
/// Chat or anything to do with messaging**, and never in auth or
/// prayer.
///
/// ## This replaced NativeAdCard, and had to
///
/// The AdMob version rendered a *native* ad through Google's medium
/// template, styled to match the app's cards. **Appodeal's Flutter plugin
/// has no native format** — `AppodealAdType.NativeAd` is marked "In
/// progress" in the SDK's own enum and there is no widget for it. The
/// closest real format is the MREC, a fixed 300x250 rectangle, so that is
/// what sits in the card now, inside the app's own chrome with an explicit
/// "Sponsored" label doing the attribution the native template used to.
///
/// ## Only one of these can exist at a time
///
/// Appodeal keeps a single shared MREC view per process, so two cards
/// mounted at once fight over it and one goes blank — see [AdViewSlot].
/// The feeds are capped to one card each for that reason; the slot is the
/// safety net for the case where two feeds are alive in the tab stack.
class FeedAdCard extends StatefulWidget {
  const FeedAdCard({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });

  final EdgeInsetsGeometry margin;

  @override
  State<FeedAdCard> createState() => _FeedAdCardState();
}

class _FeedAdCardState extends State<FeedAdCard> {
  /// The MREC's fixed size. Not negotiable — the SDK renders at exactly
  /// this and the platform view is sized to match.
  static const double _mrecWidth = 300;
  static const double _mrecHeight = 250;

  AdViewClaim? _claim;

  @override
  void initState() {
    super.initState();
    PremiumService.isPremium.addListener(_onPremiumChanged);
    _claimIfAllowed();
  }

  void _claimIfAllowed() {
    if (PremiumService.isActive || _claim != null) return;
    _claim = AdViewSlot.mrec.claim();
    unawaited(AdsService.refreshAvailability());
  }

  /// Premium started: pull the card out of the feed immediately. Premium
  /// lapsed: start asking again.
  void _onPremiumChanged() {
    if (!mounted) return;
    if (PremiumService.isActive) {
      _claim?.release();
      _claim = null;
    } else {
      _claimIfAllowed();
    }
    setState(() {});
  }

  @override
  void dispose() {
    PremiumService.isPremium.removeListener(_onPremiumChanged);
    _claim?.release();
    _claim = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (PremiumService.isActive) return const SizedBox.shrink();
    final claim = _claim;
    if (claim == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: claim.isActive,
      builder: (context, isActive, _) {
        if (!isActive) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: AdsService.mrecAvailable,
          builder: (context, hasAd, _) {
            if (!hasAd) return const SizedBox.shrink();
            return _card(context);
          },
        );
      },
    );
  }

  Widget _card(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: widget.margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: p.card,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The native template used to carry its own attribution. It
              // is gone, so we say it ourselves rather than letting an ad
              // sit in the feed looking like a post.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  0,
                  AppSpace.md,
                  AppSpace.xs,
                ),
                child: Text(
                  'Sponsored',
                  style: AppTextStyles.labelSmall.copyWith(color: p.textMuted),
                ),
              ),
              // Centre horizontally only. A bare Center would take every
              // spare pixel of height it was offered — the 50dp banner that
              // became a full-screen bar three times was exactly this.
              const Center(
                heightFactor: 1,
                child: SizedBox(
                  width: _mrecWidth,
                  height: _mrecHeight,
                  child: AppodealBanner(
                    adSize: AppodealBannerSize.MEDIUM_RECTANGLE,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
