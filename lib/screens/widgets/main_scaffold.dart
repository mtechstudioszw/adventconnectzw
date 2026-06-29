import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ads/ad_banner.dart';
import 'main_bottom_nav.dart';

class MainScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        title: Text(title, style: AppTextStyles.appBarTitle),
        elevation: 0,
      ),
      body: SafeArea(child: body),
      // Banner sits directly above the main bottom nav. AdBanner self-hides
      // (zero height) until an ad loads, so the nav never shifts on a miss.
      bottomNavigationBar: showNav
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showAd) const AdBanner(),
                MainBottomNav(currentIndex: currentIndex),
              ],
            )
          : (showAd
              ? const SafeArea(top: false, child: AdBanner())
              : null),
      floatingActionButton: floatingActionButton,
    );
  }
}
