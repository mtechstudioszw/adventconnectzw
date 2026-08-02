import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemUiOverlayStyle;
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../models/youtube_video.dart';
import '../../services/connectivity_service.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/youtube/watch_cards.dart';

/// Route arguments for the vertical Shorts feed.
class ShortsArgs {
  const ShortsArgs({required this.shorts, this.initialIndex = 0});

  final List<YoutubeVideo> shorts;
  final int initialIndex;
}

/// Full-screen vertical Shorts feed.
///
/// ~4.7k of the synced videos are a minute or under and were previously
/// flattened into the same 16:9 cards as a 47-minute sermon. This gives
/// them the format they were shot in.
///
/// Only ONE player exists — it is moved to whichever page is centred,
/// rather than one controller per page. A YouTube IFrame player is a
/// WebView; a PageView of them will exhaust memory on a mid-range Android
/// within a dozen swipes. Neighbouring pages show their thumbnail, which
/// is what the player is about to cover anyway.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key, required this.args});

  final ShortsArgs args;

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  late final PageController _pager;
  late final YoutubePlayerController _player;

  /// Stable identity for the one player widget.
  ///
  /// The player moves between PageView children as you swipe. Without a
  /// GlobalKey, Flutter treats that as "destroy the widget at the old index,
  /// create a new one at the new index" — which tears down and re-attaches
  /// the underlying WebView every single swipe, and that is the flash people
  /// see. With it, the element is *re-parented* and the WebView survives.
  final GlobalKey _playerKey = GlobalKey(debugLabel: 'shorts-player');

  final List<YoutubeVideo> _shorts = [];
  late int _index;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _muted = false;
  bool _paused = false;

  /// True once the current clip is actually rendering a frame. Until then the
  /// still stays over the player, because a cueing WebView paints black.
  bool _ready = false;

  /// The clip is taking unusually long — show a spinner and a way out
  /// rather than a frozen-looking still.
  bool _stalled = false;

  /// No connection at all. Distinct from [_stalled]: one is worth waiting
  /// out, the other isn't.
  bool _offline = false;

  StreamSubscription<YoutubePlayerValue>? _stateSub;
  StreamSubscription<bool>? _connSub;
  Timer? _cueDebounce;
  Timer? _historyTimer;
  Timer? _stallTimer;

  @override
  void initState() {
    super.initState();
    _shorts.addAll(widget.args.shorts);
    _index = widget.args.initialIndex.clamp(
      0,
      _shorts.isEmpty ? 0 : _shorts.length - 1,
    );
    _pager = PageController(initialPage: _index);
    _player = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        showVideoAnnotations: false,
        enableCaption: false,
        // Shorts loop — the format's defining behaviour.
        loop: true,
        mute: false,
      ),
    );
    _stateSub = _player.stream.listen(_onPlayerValue);
    _offline = !ConnectivityService.isOnline;
    _connSub = ConnectivityService.onChanged.listen((online) {
      if (!mounted) return;
      setState(() => _offline = !online);
      // Coming back online with a clip that never started: re-cue it
      // rather than leaving the viewer on a dead still.
      if (online && !_ready && _shorts.isNotEmpty) _cue(_shorts[_index]);
    });
    if (_shorts.isNotEmpty) _cue(_shorts[_index]);
    _maybeLoadMore();
  }

  /// Only a frame actually being painted counts as ready.
  ///
  /// This used to also flip ready on a blind 1.6s timer, which is the
  /// "glitching on shorts" people see on slow data: the thumbnail fades
  /// out on schedule and uncovers a WebView that is still black because
  /// nothing has downloaded yet. The still now stays until the player says
  /// it is playing, and a stall gets its own honest indicator.
  void _onPlayerValue(YoutubePlayerValue value) {
    final s = value.playerState;
    final live = s == PlayerState.playing || s == PlayerState.paused;
    if (live && !_ready && mounted) {
      _stallTimer?.cancel();
      setState(() {
        _ready = true;
        _stalled = false;
      });
    }
  }

  @override
  void dispose() {
    _cueDebounce?.cancel();
    _historyTimer?.cancel();
    _stallTimer?.cancel();
    _stateSub?.cancel();
    _connSub?.cancel();
    _pager.dispose();
    _player.close();
    super.dispose();
  }

  /// Point the one player at [v].
  ///
  /// Debounced: a fling crosses several pages and `onPageChanged` fires for
  /// each one, so loading on every callback thrashed the WebView with cue
  /// requests it would never finish. We only load the clip you actually
  /// stopped on.
  void _cue(YoutubeVideo v) {
    if (mounted && (_ready || _stalled)) {
      setState(() {
        _ready = false;
        _stalled = false;
      });
    }
    _cueDebounce?.cancel();
    _cueDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _player.loadVideoById(videoId: v.videoId);
      // If the clip hasn't started after a generous window, say so. We do
      // NOT reveal the player — an unloaded WebView is a black rectangle,
      // and showing that instead of the thumbnail is what made a slow
      // connection look like a broken app.
      _stallTimer?.cancel();
      _stallTimer = Timer(const Duration(seconds: 12), () {
        if (mounted && !_ready) setState(() => _stalled = true);
      });
    });

    // History was written on every page change, so a fling through twenty
    // clips wrote twenty rows — and marked each one completed. Only count it
    // once you've actually stayed on the clip.
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(seconds: 2), () {
      YoutubeService.recordProgress(
        v.videoId,
        positionSeconds: 0,
        durationSeconds: v.durationSeconds,
        completed: true,
      );
    });
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore || !_hasMore) return;
    if (_index < _shorts.length - 4) return;
    _loadingMore = true;
    final rows = await YoutubeService.fetchShorts(
      limit: 20,
      offset: _shorts.length,
    );
    if (!mounted) return;
    setState(() {
      final existing = {for (final v in _shorts) v.videoId};
      _shorts.addAll(rows.where((v) => existing.add(v.videoId)));
      _hasMore = rows.length == 20;
      _loadingMore = false;
    });
  }

  void _onPageChanged(int i) {
    HapticFeedback.selectionClick();
    // A new clip always starts playing — carrying the paused flag across a
    // swipe would land you on a still frame with no obvious way out.
    setState(() {
      _index = i;
      _paused = false;
    });
    _cue(_shorts[i]);
    _maybeLoadMore();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _muted ? _player.mute() : _player.unMute();
  }

  /// Tap anywhere to pause/resume — the gesture every short-form feed has,
  /// and the only way to hold on a verse long enough to read it.
  void _togglePlay() {
    setState(() => _paused = !_paused);
    _paused ? _player.pauseVideo() : _player.playVideo();
  }

  Future<void> _share(YoutubeVideo v) async {
    await Share.share(
      '${v.title}\n\nWatch on Advent Connect ZW:\n'
      'https://www.youtube.com/watch?v=${v.videoId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_shorts.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No shorts yet.', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pager,
              scrollDirection: Axis.vertical,
              itemCount: _shorts.length,
              onPageChanged: _onPageChanged,
              // Build the neighbouring pages so their stills are already
              // decoded when they slide in — a swipe onto an undecoded image
              // is the other half of the "glitchy" feel.
              allowImplicitScrolling: true,
              itemBuilder: (context, i) => _ShortPage(
                video: _shorts[i],
                // Only the centred page gets the live player.
                player: i == _index ? _player : null,
                playerKey: _playerKey,
                ready: _ready,
                stalled: i == _index && _stalled,
                offline: i == _index && _offline,
                onRetry: () => _cue(_shorts[i]),
                paused: _paused && i == _index,
                onTogglePlay: _togglePlay,
                muted: _muted,
                onToggleMute: _toggleMute,
                onShare: () => _share(_shorts[i]),
                onOpenFull: () => context.pushNamed(
                  'watch_video',
                  pathParameters: {'id': _shorts[i].videoId},
                  extra: _shorts[i],
                ),
              ),
            ),
            // Close affordance, clear of the status bar.
            Positioned(
              top: MediaQuery.paddingOf(context).top + AppSpace.sm,
              left: AppSpace.sm,
              child: Pressable(
                onTap: () => Navigator.of(context).maybePop(),
                pressedScale: 0.9,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.darkNavy.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortPage extends StatelessWidget {
  const _ShortPage({
    required this.video,
    required this.player,
    required this.playerKey,
    required this.ready,
    required this.stalled,
    required this.offline,
    required this.onRetry,
    required this.paused,
    required this.onTogglePlay,
    required this.muted,
    required this.onToggleMute,
    required this.onShare,
    required this.onOpenFull,
  });

  final YoutubeVideo video;
  final YoutubePlayerController? player;
  final GlobalKey playerKey;
  final bool ready;

  /// This clip has been loading far longer than it should.
  final bool stalled;

  /// The device has no connection.
  final bool offline;

  /// Re-cue the clip.
  final VoidCallback onRetry;
  final bool paused;
  final VoidCallback onTogglePlay;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onShare;
  final VoidCallback onOpenFull;

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbnailUrl;

    final still = (thumb != null && thumb.isNotEmpty)
        ? CachedImage(
            thumb,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ThumbFallback(),
          )
        : const ThumbFallback();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (player != null)
          Center(
            // Keyed so swiping re-parents this player instead of rebuilding
            // it — see _ShortsScreenState._playerKey.
            child: YoutubePlayer(
              key: playerKey,
              controller: player!,
              aspectRatio: 9 / 16,
            ),
          ),

        // The still sits OVER the player, not under it: a WebView that is
        // still cueing paints solid black, which is what covered the
        // thumbnail and made every open flash. Fade it out only once the
        // player reports a frame.
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: (player != null && ready) ? 0 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: still,
          ),
        ),

        // Tap anywhere to pause/resume. Sits above the player so the WebView
        // can't swallow the tap, but below the caption and rail so their
        // buttons still win.
        if (player != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTogglePlay,
              child: const SizedBox.expand(),
            ),
          ),

        // Scrim only where the caption and buttons sit.
        const IgnorePointer(
          child: MediaScrim(topAlpha: 0x40, bottomAlpha: 0xC0),
        ),

        // Loading / stalled / offline state for the CENTRED clip.
        //
        // A short-form feed lives or dies on whether a swipe lands on
        // something moving. When it doesn't, the viewer needs to know
        // which of the three it is — still fetching, struggling, or no
        // signal — instead of staring at a motionless thumbnail and
        // concluding the app is broken.
        if (player != null && !ready)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !(stalled || offline),
              child: Center(
                child: (stalled || offline)
                    ? Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpace.xl,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.lg,
                          vertical: AppSpace.lg,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.darkNavy.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                            color: AppColors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              offline
                                  ? Icons.wifi_off_rounded
                                  : Icons.hourglass_bottom_rounded,
                              color: AppColors.white,
                              size: 28,
                            ),
                            const SizedBox(height: AppSpace.sm),
                            Text(
                              offline
                                  ? 'You\'re offline'
                                  : 'Slow connection',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              offline
                                  ? 'This short will start when you\'re back.'
                                  : 'This short is taking a while to load.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.white.withValues(alpha: 0.78),
                                height: 1.35,
                              ),
                            ),
                            if (!offline) ...[
                              const SizedBox(height: AppSpace.md),
                              Pressable(
                                onTap: onRetry,
                                pressedScale: 0.94,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.lg,
                                    vertical: AppSpace.sm + 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text(
                                    'Try again',
                                    style: AppTextStyles.labelMedium.copyWith(
                                      color: AppColors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    // Ordinary buffering: a quiet ring, no words. The
                    // thumbnail is still doing the visual work.
                    : const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.white,
                          ),
                        ),
                      ),
              ),
            ),
          ),

        // Paused affordance — without it a tapped-to-pause clip is
        // indistinguishable from one that has stalled on a bad connection.
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: paused ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.darkNavy.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.white.withValues(alpha: 0.28),
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ),

        // Caption block.
        Positioned(
          left: AppSpace.lg,
          right: 76,
          bottom: AppSpace.xl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                video.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      video.channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                  if (video.viewsLabel.isNotEmpty) ...[
                    const SizedBox(width: AppSpace.sm),
                    Text(
                      '· ${video.viewsLabel}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Action rail.
        Positioned(
          right: AppSpace.md,
          bottom: AppSpace.xl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RailButton(
                icon: muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                label: muted ? 'Muted' : 'Sound',
                onTap: onToggleMute,
              ),
              const SizedBox(height: AppSpace.lg),
              _RailButton(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: onShare,
              ),
              const SizedBox(height: AppSpace.lg),
              _RailButton(
                icon: Icons.open_in_full_rounded,
                label: 'Full',
                onTap: onOpenFull,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.darkNavy.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(icon, color: AppColors.white, size: 22),
          ),
          const SizedBox(height: AppSpace.xs + 1),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
