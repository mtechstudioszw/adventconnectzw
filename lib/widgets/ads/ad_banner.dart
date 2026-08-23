import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

import '../../services/ads/ad_view_slot.dart';
import '../../services/ads/ads_service.dart';
import '../../services/premium_service.dart';

/// The anchored 320x50 banner. Drop it anywhere that's allowed to show ads
/// (lists, detail screens) — **NEVER in Chat or anything to do with
/// messaging**, and never in auth/onboarding or prayer. Renders nothing
/// (zero height) until an ad is actually available, so layouts never
/// reserve empty space for an ad that didn't arrive.
///
/// Premium subscribers never reach the request at all, and a banner already
/// on screen when a purchase completes disappears on the spot.
///
/// ## Two things Appodeal changes here
///
/// * **The widget no longer owns an ad object.** `AppodealBanner` is a
///   platform view onto the SDK's single shared banner, and it *always*
///   occupies 320x50 once mounted — there is no per-instance "did it load"
///   callback to hide it. So availability comes from
///   [AdsService.bannerAvailable], which the global banner callbacks feed.
/// * **Only one of these may be mounted at a time.** See [AdViewSlot]; a
///   second platform view steals the native view from the first. Pushing
///   Jobs on top of Home leaves both mounted, and both place a banner.
const double kAdBannerWidth = 320;
const double kAdBannerHeight = 50;

class AdBanner extends StatefulWidget {
  const AdBanner({super.key, this.padding});

  /// Optional padding applied only once an ad is actually showing.
  final EdgeInsetsGeometry? padding;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  AdViewClaim? _claim;

  @override
  void initState() {
    super.initState();
    PremiumService.isPremium.addListener(_onPremiumChanged);
    _claimIfAllowed();
  }

  /// A subscriber never even asks for an ad — that, not hiding the widget,
  /// is what they paid for.
  void _claimIfAllowed() {
    if (PremiumService.isActive || _claim != null) return;
    _claim = AdViewSlot.banner.claim();
    // A banner cached before this screen existed fires no callback, so the
    // notifier would sit false waiting on an event that already happened.
    unawaited(AdsService.refreshAvailability());
  }

  /// Premium started: give the slot up so a free user's screen elsewhere in
  /// the stack can take the banner back. Premium lapsed: start asking again,
  /// since this widget may never rebuild from the top otherwise.
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
          valueListenable: AdsService.bannerAvailable,
          builder: (context, hasAd, _) {
            if (!hasAd) return const SizedBox.shrink();
            return AdBannerFrame(
              width: kAdBannerWidth,
              height: kAdBannerHeight,
              padding: widget.padding,
              child: const AppodealBanner(adSize: AppodealBannerSize.BANNER),
            );
          },
        );
      },
    );
  }
}

/// The banner's footprint: full width, and **exactly** the ad's height.
///
/// Split out of [AdBanner] so the layout can be tested without an ad SDK or
/// a real fill — the bug below is pure layout, and with the plugin in the
/// way it was untestable and shipped twice. It is deliberately
/// provider-agnostic: the AdMob → Appodeal swap did not touch it.
///
/// `heightFactor: 1` is the whole fix. This used to be a bare
/// `Center(child: banner)`, and a bare [Center] only shrink-wraps when its
/// incoming height constraint is unbounded. Inside a `Column` it is — which
/// is why Home and Marketplace were always fine. But `Scaffold` lays
/// `bottomNavigationBar` out with a LOOSE constraint whose max is the whole
/// scaffold height, and that counts as bounded, so `Center` took all of it:
/// a 50dp ad in a full-screen bar, with the screen behind it unreachable.
///
/// Every screen that placed the banner directly in `bottomNavigationBar`
/// had it — Events and Churches (pushed, so `MainScaffold.showNav` is
/// false), Jobs, and Job details. The earlier fix added `HideOnScroll` to
/// that branch, which made the full-height bar *collapsible* and so looked
/// like progress, but it never touched why it was full height.
class AdBannerFrame extends StatelessWidget {
  const AdBannerFrame({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.padding,
  });

  final double width;
  final double height;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final banner = Center(
      // Fill the width so the ad stays centred; hug the height so no
      // parent's spare vertical space can ever be claimed.
      heightFactor: 1,
      child: SizedBox(width: width, height: height, child: child),
    );
    return padding == null
        ? banner
        : Padding(padding: padding!, child: banner);
  }
}
