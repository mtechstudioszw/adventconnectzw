import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
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

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> with NavVisibilityMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      // Flat, single-colour header — matches the scaffold background so the
      // screen reads as one continuous colour (styling comes from the themed
      // AppBarTheme; the back button is auto-added on pushed routes).
      appBar: AppBar(
        title: Text(widget.title),
      ),
      // Scroll direction drives nav visibility (YouTube-style hide).
      body: NotificationListener<UserScrollNotification>(
        onNotification: handleNavScroll,
        child: SafeArea(child: widget.body),
      ),
      // Banner sits directly above the main bottom nav. AdBanner self-hides
      // (zero height) until an ad loads, so the nav never shifts on a miss.
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
                ? const SafeArea(top: false, child: AdBanner())
                : null),
      floatingActionButton: widget.floatingActionButton,
    );
  }
}
