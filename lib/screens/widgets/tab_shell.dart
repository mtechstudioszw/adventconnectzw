import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/messaging_service.dart';
import '../../widgets/ads/ad_banner.dart';
import '../../widgets/motion/hide_on_scroll.dart';
import '../../widgets/home/composer_entry.dart';
import '../../widgets/home/island_create_fab.dart';
import '../../widgets/home/create_sheet.dart' show CreateRequest;
import 'main_bottom_nav.dart';

/// The frame around the five tab destinations — Home, Watch, Chat,
/// Marketplace, Profile — built by the `StatefulShellRoute` in
/// router_config.dart.
///
/// # Why this exists (27 Oct 2026)
///
/// Each tab used to be its own top-level route, and switching tabs was a
/// `goNamed` that DISPOSED the screen being left. Home → Watch → Home
/// rebuilt Home from nothing: the feed re-fetched and the scroll position
/// was gone. The shell keeps each tab mounted in an IndexedStack instead.
///
/// It also owns what every tab used to draw for itself: the floating
/// island, its hide-on-scroll behaviour, and Marketplace's banner slot.
/// A tab screen must NOT add its own `MainBottomNav` any more — it would
/// render a second island.
class TabShell extends StatefulWidget {
  const TabShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Branch indices. Must match the branch order in router_config.dart and
  /// the tab order in [MainBottomNav].
  static const int homeIndex = 0;
  static const int marketplaceIndex = 3;
  static const int profileIndex = 4;

  /// The branch on screen. Kept-alive tabs only run `initState` once a
  /// session, so a tab whose data goes stale while you are elsewhere (the
  /// post you just made, a friend you just added) listens here and
  /// refreshes when it comes back. Updated after the frame — never
  /// notified mid-build.
  static final ValueNotifier<int> activeIndex = ValueNotifier(homeIndex);

  /// Re-tap handlers, keyed by branch index. A tab that wants "tap the
  /// active tab again → scroll to top" registers here in initState and
  /// unregisters in dispose (Home does).
  static final Map<int, VoidCallback> _reselect = {};

  static void registerReselect(int index, VoidCallback handler) =>
      _reselect[index] = handler;

  static void unregisterReselect(int index, VoidCallback handler) {
    if (identical(_reselect[index], handler)) _reselect.remove(index);
  }

  /// Friend requests waiting in Chat. Added to the app-wide unread total on
  /// the Chat badge — both are answered from inside Chat. Home publishes it
  /// when it loads its counts; it used to pass the sum straight to its own
  /// island, which meant only Home's island ever showed it.
  static final ValueNotifier<int> pendingFriendRequests = ValueNotifier(0);

  @override
  State<TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<TabShell> with NavVisibilityMixin {
  void _select(int index) {
    final shell = widget.shell;
    // A tab you arrive at should show its island; one hidden by scrolling
    // a different tab must not stay hidden.
    if (!navVisible) setState(() => navVisible = true);
    shell.goBranch(index);
  }

  void _reselect() => TabShell._reselect[widget.shell.currentIndex]?.call();

  @override
  Widget build(BuildContext context) {
    final index = widget.shell.currentIndex;
    // Every route into a tab ends up here — the island, `goNamed` from a
    // deep screen, a notification — so this is the one place that sees
    // all of them.
    if (TabShell.activeIndex.value != index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) TabShell.activeIndex.value = widget.shell.currentIndex;
      });
    }
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      // Home's feed runs full-height under the frosted island and reserves
      // its own 96dp at the end. The other tabs lay out above the island,
      // as they did when each drew its own — so their FABs and last rows
      // are never trapped beneath it.
      extendBody: index == TabShell.homeIndex,
      body: NotificationListener<UserScrollNotification>(
        // Only the visible branch can scroll, so one listener here serves
        // every tab. handleNavScroll never swallows the notification.
        onNotification: handleNavScroll,
        child: widget.shell,
      ),
      bottomNavigationBar: HideOnScroll(
        visible: navVisible,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Marketplace is the only tab that carried a banner above the
            // island. AdBanner self-hides until an ad loads.
            if (index == TabShell.marketplaceIndex) const AdBanner(),
            ValueListenableBuilder<int>(
              valueListenable: MessagingService.unreadTotal,
              builder: (context, unread, _) => ValueListenableBuilder<int>(
                valueListenable: TabShell.pendingFriendRequests,
                builder: (context, requests, _) => MainBottomNav(
                  currentIndex: index,
                  onTabSelected: _select,
                  onReselect: _reselect,
                  badges: {MainBottomNav.chatIndex: unread + requests},
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Home's floating "+" (3 Nov 2026): above the island, draggable, and
    // dropping into the island's place while it is hidden. Stacked over
    // the whole Scaffold rather than inside the body, because the body's
    // MediaQuery already counts the island's height (extendBody).
    return Stack(
      children: [
        scaffold,
        if (index == TabShell.homeIndex)
          Positioned.fill(
            child: ValueListenableBuilder<void Function(CreateRequest)?>(
              valueListenable: HomeCreateBridge.handler,
              builder: (context, create, _) => create == null
                  ? const SizedBox.shrink()
                  : IslandCreateFab(
                      islandVisible: navVisible,
                      onTap: () => HomeCreateBridge.open(context),
                    ),
            ),
          ),
      ],
    );
  }
}
