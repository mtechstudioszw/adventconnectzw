import 'package:flutter/material.dart';
import '../../config/platform_flags.dart';

import '../../services/hymn_service.dart';
import '../../services/music_player_service.dart';
import '../../services/usage_analytics.dart';
import '../../theme/app_text_styles.dart';
import 'bible_tab.dart';
import 'egw_tab.dart';
import 'hymnal_tab.dart';
import 'music_tab.dart';
import 'sabbath_school_tab.dart';

/// One Library section, on its own: Bible, Sabbath School, Hymnal, EGW or
/// Music — whichever [initialTab] names.
///
/// This used to be a five-tab screen with a "Library" title and a tab bar.
/// The Library tab's hub (library_hub_screen.dart) replaced that as the
/// way to move between sections, so the tab bar became a second, older
/// Library inside the new one (owner, 29 Oct 2026: "when you type Bible,
/// you should just open Bible … not that old library, that old ugly one").
/// Every caller already says which section it wants, so each opens straight
/// into it, titled with its own name, and Back returns to where you were.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  /// 0=Bible, 1=Sabbath School, 2=Hymnal, 3=EGW Books, 4=Music.
  final int initialTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// Music doesn't exist on iOS ([kHideMusic]); a stray link to it opens
  /// the Bible rather than a section that isn't there.
  int get _section {
    final i = widget.initialTab.clamp(0, 4);
    return (kHideMusic && i == 4) ? 0 : i;
  }

  static const _titles = [
    'Bible',
    'Sabbath School',
    'Hymnal',
    'Ellen G. White',
    'Music',
  ];

  @override
  void initState() {
    super.initState();
    // Sections are not separate routes, so the router's usage tracking
    // can't see which one is open — reported here instead.
    final feature = Feature.fromLibraryTab(_section);
    if (feature != null) {
      UsageAnalytics.open(feature, screen: '/library/$feature');
    }
    if (_section == 2) HymnService.warmUp();
    // Bring back the previous session's queue so the mini player reappears
    // where the user left it. Loads paused — never auto-plays on open.
    if (_section == 4 && !kHideMusic) {
      MusicPlayerService.instance.restoreLastQueue();
    }
  }

  Widget get _body => switch (_section) {
    // Audio Bible lives as a button INSIDE the Bible section.
    0 => const BibleTab(),
    1 => const SabbathSchoolTab(),
    // Structured, searchable hymns bundled as an asset — not PDFs.
    2 => const HymnalTab(),
    3 => const EgwTab(),
    _ => const MusicTab(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // No ads anywhere in the Library: devotional content stays ad-free.
      appBar: AppBar(
        title: Text(
          _titles[_section],
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
        ),
      ),
      body: SafeArea(top: false, child: _body),
    );
  }
}
