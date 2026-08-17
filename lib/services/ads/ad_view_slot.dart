import 'dart:async';

import 'package:flutter/foundation.dart';

/// Decides which widget currently owns Appodeal's single native ad view.
///
/// ## Why this exists
///
/// Appodeal does not hand out one ad view per request the way AdMob's
/// `BannerAd` did. Reading the plugin's own Android source
/// (`AppodealAdView.kt` in stack_appodeal_flutter 4.2.0) there is exactly
/// **one** banner view and **one** MREC view per process, held in a static
/// `WeakReference`, and every new platform view starts with:
///
/// ```kotlin
/// (adView.parent as? ViewGroup)?.removeView(adView)
/// Appodeal.show(activity, bannerType, placement)
/// ```
///
/// So a second `AppodealBanner` of the same size does not get a second ad —
/// it **rips the view out of the first one**, which then renders an empty
/// box. That is not a hypothetical: pushing Jobs on top of Home leaves both
/// routes mounted (Navigator keeps the covered route alive), and both of
/// those screens place a banner.
///
/// ## The rule
///
/// At most one widget per size may mount the platform view, and it should
/// be the **newest** claimant, because that is the one the user is looking
/// at. When it goes away the previous claimant takes the view back.
///
/// Widgets do not enforce this themselves; they [claim] a slot and render
/// the ad only while their claim [AdViewClaim.isActive].
class AdViewSlot {
  AdViewSlot._(this.debugName);

  /// The 320x50 anchored banner (`Appodeal.BANNER_VIEW`).
  static final AdViewSlot banner = AdViewSlot._('banner');

  /// The 300x250 in-feed rectangle (`Appodeal.MREC`).
  static final AdViewSlot mrec = AdViewSlot._('mrec');

  final String debugName;

  /// Oldest first; the last entry is the active one.
  final List<AdViewClaim> _claims = <AdViewClaim>[];

  bool _settleScheduled = false;

  /// Take a claim on this slot. The caller MUST [AdViewClaim.release] it in
  /// `dispose`, or the slot stays wedged and every later screen renders a
  /// blank ad.
  AdViewClaim claim() {
    final claim = AdViewClaim._(this);
    _claims.add(claim);
    _scheduleSettle();
    return claim;
  }

  void _release(AdViewClaim claim) {
    if (!_claims.remove(claim)) return;
    _scheduleSettle();
  }

  /// Deferred by a microtask on purpose.
  ///
  /// A widget claims in `initState`, which runs inside the build phase.
  /// Flipping another widget's notifier synchronously there would call
  /// `setState` on an element that is already building — the classic
  /// "setState() or markNeedsBuild() called during build" crash. Flutter's
  /// build phase is one synchronous call stack, so a microtask is
  /// guaranteed to run after it unwinds and before the next frame.
  void _scheduleSettle() {
    if (_settleScheduled) return;
    _settleScheduled = true;
    scheduleMicrotask(() {
      _settleScheduled = false;
      for (var i = 0; i < _claims.length; i++) {
        _claims[i]._setActive(i == _claims.length - 1);
      }
    });
  }

  @visibleForTesting
  int get debugClaimCount => _claims.length;

  @visibleForTesting
  static void debugResetAll() {
    for (final slot in [banner, mrec]) {
      slot._claims.clear();
      slot._settleScheduled = false;
    }
  }
}

/// One widget's stake in an [AdViewSlot].
class AdViewClaim {
  AdViewClaim._(this._slot);

  final AdViewSlot _slot;

  /// True only while this claim owns the slot. Widgets should render the
  /// platform view when true and nothing at all when false — an inactive
  /// claim that still mounted the view would steal it straight back.
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  bool _released = false;

  void _setActive(bool value) {
    if (_released) return;
    isActive.value = value;
  }

  /// Give the slot up. Safe to call twice.
  void release() {
    if (_released) return;
    // Remove from the slot BEFORE disposing, so the settle pass that this
    // triggers can never write to the notifier we are about to dispose.
    _slot._release(this);
    _released = true;
    isActive.dispose();
  }
}
