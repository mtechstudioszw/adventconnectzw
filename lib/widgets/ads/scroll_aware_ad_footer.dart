import 'package:flutter/material.dart';

import 'ad_banner.dart';
import '../motion/hide_on_scroll.dart';

/// A bottom banner that gets out of the way.
///
/// Wrap a screen's body in this and the ad collapses as the user scrolls
/// down, returning on any scroll up — the same behaviour the bottom nav
/// has had all along.
///
/// ```dart
/// Scaffold(body: ScrollAwareAdFooter(child: myScrollingBody))
/// ```
///
/// WHY THIS EXISTS
/// Ads were added to the product / event / church detail screens
/// ("Expand ad placement to maximise revenue", c18cd7f) and ripped out a
/// few commits later ("intrusive detail-screen ads", 13d55c0). The
/// founder confirmed on 3 Aug 2026 that the reason was the same one that
/// made Events unusable: the banner was **pinned**. It sat at the bottom
/// forever, never gave the pixels back, and on a detail screen it landed
/// right on top of the action buttons.
///
/// So the placement was never the problem — permanence was. This makes a
/// banner behave like every other chrome element in the app, which is
/// what lets those placements come back without the complaint that
/// removed them.
///
/// Deliberately a body wrapper rather than a `bottomNavigationBar`: the
/// detail screens draw their own Scaffolds around Stacks and heroes, and
/// this drops into any of them without restructuring.
///
/// Renders nothing at all for premium subscribers and when no ad fills —
/// [AdBanner] handles both, and it never even requests one while premium.
class ScrollAwareAdFooter extends StatefulWidget {
  const ScrollAwareAdFooter({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// Pass false to opt a screen out entirely (Chat, auth, Prayer).
  /// Kept as a flag so the exclusion is visible at the call site rather
  /// than being an absence someone later "fixes" by adding an ad.
  final bool enabled;

  @override
  State<ScrollAwareAdFooter> createState() => _ScrollAwareAdFooterState();
}

class _ScrollAwareAdFooterState extends State<ScrollAwareAdFooter>
    with NavVisibilityMixin {
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return NotificationListener<UserScrollNotification>(
      onNotification: handleNavScroll,
      child: Column(
        children: [
          Expanded(child: widget.child),
          HideOnScroll(
            visible: navVisible,
            child: const SafeArea(top: false, child: AdBanner()),
          ),
        ],
      ),
    );
  }
}
