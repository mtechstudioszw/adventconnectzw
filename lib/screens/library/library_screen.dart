import 'package:flutter/material.dart';

import '../../services/hymn_service.dart';
import '../../services/music_player_service.dart';
import '../../services/usage_analytics.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'bible_tab.dart';
import 'egw_tab.dart';
import 'hymnal_tab.dart';
import 'music_tab.dart';
import 'sabbath_school_tab.dart';

/// The in-app Library: Bible (bundled offline KJV), Sabbath School (Adventech
/// lessons in ~90 languages, Shona by default), Hymnal (bundled, fully
/// offline), EGW Books (uploaded PDFs) and Music (background audio player).
///
/// Reached from the "Bible · Hymnal · EGW · Music" launcher under the devotion
/// card on Home.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  /// 0=Bible, 1=Sabbath School, 2=Hymnal, 3=EGW Books, 4=Music.
  final int initialTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 5;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _tabCount - 1),
    );
    // The five library sections are TABS, not routes, so the router's
    // usage tracking cannot see which one is open — without this, Bible,
    // Sabbath School, Hymnal, EGW and Music would all read as "nobody
    // uses this" on the admin dashboard. Reported here instead.
    _trackTab();
    _tabs.addListener(() {
      // Fires twice per swipe (start + settle); only count the landing.
      if (!_tabs.indexIsChanging) _trackTab();
    });
    // Parse the bundled hymnal off the critical path so swiping to the Hymnal
    // tab is instant rather than showing a first-open spinner.
    HymnService.warmUp();
    // Bring back the previous session's queue so the mini player reappears
    // where the user left it. Loads paused — never auto-plays on open.
    MusicPlayerService.instance.restoreLastQueue();
  }

  void _trackTab() {
    final feature = Feature.fromLibraryTab(_tabs.index);
    if (feature != null) {
      UsageAnalytics.open(feature, screen: '/library/$feature');
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      // No ads anywhere in the Library. It's devotional content — Bible,
      // Sabbath School, hymns, EGW writings and worship music — so it stays
      // ad-free like the prayer screens (the tester reported the bottom
      // banner was covering the catalog). Revenue stays on the home feed,
      // stories and detail pages.
      appBar: AppBar(
        title: Text(
          'Library',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
        ),
        bottom: TabBar(
          controller: _tabs,
          dividerColor: Colors.transparent,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.primaryBlue,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.primaryBlue,
          unselectedLabelColor: const Color(0xFF7C8698),
          labelStyle: AppTextStyles.labelMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.menu_book_rounded, size: 19), text: 'Bible'),
            Tab(
              icon: Icon(Icons.school_rounded, size: 19),
              text: 'Sabbath School',
            ),
            Tab(icon: Icon(Icons.queue_music_rounded, size: 19), text: 'Hymnal'),
            Tab(icon: Icon(Icons.auto_stories_rounded, size: 19), text: 'EGW'),
            Tab(icon: Icon(Icons.headphones_rounded, size: 19), text: 'Music'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  // Audio Bible lives as a button INSIDE the Bible tab, not
                  // its own tab (founder preference).
                  BibleTab(),
                  SabbathSchoolTab(),
                  // Hymnal = structured, searchable hymns (number/title/
                  // lyrics), bundled as an asset. NOT PDFs.
                  HymnalTab(),
                  EgwTab(),
                  MusicTab(),
                ],
              ),
            ),
            // The shell-level mini player was removed: the founder wants the
            // now-playing card confined to the Music tab (which mounts its
            // own). Everywhere else — other Library tabs, Home, and outside
            // the app entirely — playback is controlled from the Android
            // media notification and the iOS lock screen / Control Centre.
          ],
        ),
      ),
    );
  }
}
