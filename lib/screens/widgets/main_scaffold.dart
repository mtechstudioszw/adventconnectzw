import 'package:flutter/material.dart';
import '../../widgets/ads/ad_banner.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import 'main_bottom_nav.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({
    super.key,
    required this.title,
    required this.currentIndex,
    required this.body,
    this.floatingActionButton,
    this.showAd = true,
    this.showNav = true,
    this.showAppBar = true,
  });

  final String title;
  final int currentIndex;
  final Widget body;
  final Widget? floatingActionButton;

  /// Anchored banner above the bottom nav. Default on; pass false for
  /// faith-sensitive tabs (Prayer) that must stay ad-free.
  final bool showAd;

  /// Show the bottom nav. Default on. Pass false for screens that are
  /// PUSHED (not top-level tabs) — e.g. Events, which moved off the nav
  /// bar but still uses this scaffold; it then shows the AppBar back
  /// button instead of a tab highlight.
  final bool showNav;

  /// Suppress the themed AppBar so the screen can render its own flat
  /// header inside [body] — a hero with a subtitle and its own actions,
  /// the ScreenHero language used everywhere else. Still flat, still on
  /// `palette.scaffoldBg`; this only moves who draws it. The screen must
  /// then wrap its header in [FlatStatusBar] and handle its own top
  /// SafeArea (this scaffold stops insetting the top when it has no bar).
  final bool showAppBar;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> with NavVisibilityMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Flat, single-colour header — matches the scaffold background so the
      // screen reads as one continuous colour (styling comes from the themed
      // AppBarTheme; the back button is auto-added on pushed routes).
      appBar: widget.showAppBar ? AppBar(title: Text(widget.title)) : null,
      // Scroll direction drives nav visibility (YouTube-style hide).
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        // With no AppBar there is nothing between the body and the status
        // bar, so the top inset becomes the screen's own problem — its
        // header does the SafeArea, the way ScreenHero does.
        child: SafeArea(top: widget.showAppBar, child: widget.body),
      ),
      // Banner sits directly above the main bottom nav. AdBanner self-hides
      // (zero height) until an ad loads, so the nav never shifts on a miss.
      //
      // BOTH branches scroll away. They didn't used to: HideOnScroll was
      // only on the showNav branch, so on a PUSHED screen (Events,
      // Churches) the banner was pinned to the bottom permanently and
      // never gave the space back. Those two screens already spend ~170dp
      // on a search bar, a date filter and pill tabs, so a banner that
      // never leaves is most of what's left — "the ads are not allowing
      // me to use the screen" (founder, 3 Aug 2026).
      //
      // HideOnScroll collapses by height factor, a real layout collapse,
      // so scrolling down hands those pixels back to the list and any
      // scroll up returns the ad.
      bottomNavigationBar: widget.showNav
          ? HideOnScroll(
              visible: navVisible,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.showAd) const AdBanner(),
                  MainBottomNav(currentIndex: widget.currentIndex),
                ],
              ),
            )
          : (widget.showAd
                ? HideOnScroll(
                    visible: navVisible,
                    child: const SafeArea(top: false, child: AdBanner()),
                  )
                : null),
      floatingActionButton: widget.floatingActionButton,
    );
  }
}
