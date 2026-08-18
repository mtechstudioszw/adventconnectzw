import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/bible_service.dart';
import '../../services/hymn_service.dart';
import '../../services/music_player_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import 'library_screen.dart';

/// Entry sequence for the Library.
///
/// Deliberately NOT a spinner over a fake delay. Each shelf lights up when
/// that source is genuinely ready, so the animation IS the loading state:
/// Bible and Hymnal are bundled assets and land almost immediately, while
/// Music restores the previous queue. Watching the shelves fill is what
/// tells you the library is yours and it works offline.
///
/// A GATE, not a route — it swaps itself for [LibraryScreen] in place, so
/// back still leaves the Library rather than returning here.
class LibraryBootScreen extends StatefulWidget {
  const LibraryBootScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<LibraryBootScreen> createState() => _LibraryBootScreenState();
}

/// A shelf and the work that makes it ready.
typedef _Shelf = (IconData icon, String label, Future<void> Function() warm);

class _LibraryBootScreenState extends State<LibraryBootScreen> {
  /// Floor on visibility. Bundled assets can finish in ~50ms and a screen
  /// that flashes reads as a glitch rather than a welcome.
  static const _minVisible = Duration(milliseconds: 950);

  late final List<_Shelf> _shelves = [
    // books() parses and caches the bundled KJV — reading it here is the
    // warm-up, so the Bible tab opens instantly instead of on first swipe.
    (Icons.menu_book_rounded, 'Bible', () => BibleService.books()),
    (Icons.school_rounded, 'Sabbath School', () async {}),
    (Icons.queue_music_rounded, 'Hymnal', () => HymnService.warmUp()),
    (Icons.auto_stories_rounded, 'EGW', () async {}),
    (
      Icons.headphones_rounded,
      'Music',
      () => MusicPlayerService.instance.restoreLastQueue(),
    ),
  ];

  final Set<int> _ready = {};
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    for (var i = 0; i < _shelves.length; i++) {
      try {
        await _shelves[i].$3();
      } catch (_) {
        // A shelf that can't warm still opens — the tab handles its own
        // empty/offline state. Never block entry on it.
      }
      if (!mounted) return;
      setState(() => _ready.add(i));
      // A short beat between shelves so the sequence reads as deliberate
      // rather than everything snapping on at once.
      await Future.delayed(const Duration(milliseconds: 90));
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minVisible) {
      await Future.delayed(_minVisible - elapsed);
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.maybe(context, AppMotion.entrance),
      child: _done
          ? LibraryScreen(
              key: const ValueKey('library'),
              initialTab: widget.initialTab,
            )
          : _bootUi(context),
    );
  }

  Widget _bootUi(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      key: const ValueKey('library_boot'),
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.sheet),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.30),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_library_rounded,
                    color: AppColors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(
                  'Your Adventist Library',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Bible, Sabbath School, hymns, EGW and music',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpace.xxl),
                for (var i = 0; i < _shelves.length; i++)
                  _ShelfRow(
                    icon: _shelves[i].$1,
                    label: _shelves[i].$2,
                    ready: _ready.contains(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.icon,
    required this.label,
    required this.ready,
  });

  final IconData icon;
  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
      child: AnimatedOpacity(
        opacity: ready ? 1 : 0.35,
        duration: AppMotion.maybe(context, AppMotion.standard),
        child: Row(
          children: [
            AnimatedContainer(
              duration: AppMotion.maybe(context, AppMotion.standard),
              curve: AppMotion.ease,
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ready
                    ? AppColors.primaryBlue.withValues(alpha: 0.12)
                    : palette.cardMuted,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 19,
                color: ready ? AppColors.primaryBlue : palette.textMuted,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.titleSmall.copyWith(
                  color: palette.text,
                  fontWeight: ready ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            // The tick pops in on a spring as each shelf reports ready.
            AnimatedScale(
              scale: ready ? 1 : 0,
              duration: AppMotion.maybe(context, AppMotion.standard),
              curve: AppMotion.spring,
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.successGreen,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
