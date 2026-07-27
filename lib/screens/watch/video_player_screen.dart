import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../models/youtube_video.dart';
import '../../services/ads/interstitial_ad_manager.dart';
import '../../services/mini_player_service.dart';
import '../../services/youtube_prefs.dart';
import '../../services/youtube_service.dart';
import '../../services/verse_ref_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/youtube/live_chat_panel.dart';
import '../../widgets/youtube/watch_cards.dart';
import '../../widgets/youtube/youtube_video_card.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Full in-app player for a YouTube video. Official IFrame player (the only
/// compliant way to play) + a faith-safe endless "Up next" built from OUR
/// library. Premium extras: save, share-a-moment, timestamped notes,
/// resume, and autoplay-next.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    this.initialVideo,
  });

  final String videoId;
  final YoutubeVideo? initialVideo;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _sub;
  Timer? _progressTimer;

  YoutubeVideo? _video;
  bool _ready = false;
  bool _saved = false;
  bool _descExpanded = false;
  bool _ended = false;
  bool _showChat = false; // live-chat vs up-next toggle (live videos only)
  bool _playerStarted = false; // player webview has come alive
  bool _loadTimedOut = false; // slow/no network — show retry
  bool _isFullscreen = false; // player is in fullscreen (landscape)
  Timer? _loadTimer;
  // Scripture references detected in the title/description (tap-a-verse).
  List<VerseRef> _verses = const [];

  final List<YoutubeVideo> _upNext = [];
  final ScrollController _scroll = ScrollController();
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _page = 20;

  String get _videoId => _video?.videoId ?? widget.videoId;

  @override
  void initState() {
    super.initState();
    _video = widget.initialVideo;
    _scroll.addListener(_onScroll);
    _maybeShowInterstitial();
    // The app is locked to portrait globally; allow landscape WHILE the
    // player is open so the YouTube fullscreen button can rotate. Restored
    // to portrait-only in dispose.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _init();
  }

  Future<void> _init() async {
    // Opening a video always dismisses the docked bar — two players would
    // otherwise talk over each other. If the bar was showing THIS video,
    // its position wins over the database's (which only gets written
    // every 10s, so it lags by up to ten seconds).
    final mini = MiniPlayerService.instance;
    int? handoff;
    if (mini.isActive) {
      final sameVideo = mini.video?.videoId == widget.videoId;
      final at = await mini.takeOver();
      if (sameVideo) handoff = at;
    }

    _video ??= await YoutubeService.fetchVideo(widget.videoId);
    final resume =
        handoff ?? await YoutubeService.resumePosition(widget.videoId);
    final saved = await YoutubeService.fetchBookmarkIds();

    final controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      startSeconds: resume.toDouble(),
      params: const YoutubePlayerParams(
        showControls: true,
        enableCaption: true,
        strictRelatedVideos: true, // keep YouTube's own end-screen on-channel
        showFullscreenButton: true,
      ),
    );
    _sub = controller.stream.listen(_onValue);
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
    _armLoadWatchdog();

    final subs = YoutubeService.cachedSubscriptionIds();

    if (!mounted) return;
    setState(() {
      _controller = controller;
      _saved = saved.contains(widget.videoId);
      _subscribed = subs.contains(_video?.channelId ?? '');
      _ready = true;
    });
    // Correct the follow state from the server without blocking first paint.
    YoutubeService.fetchSubscriptionIds().then((ids) {
      if (!mounted) return;
      setState(() => _subscribed = ids.contains(_video?.channelId ?? ''));
    });
    _loadUpNext();
    _parseVerses();
  }

  /// How many videos have been opened this session — drives the ad cadence.
  static int _opensThisSession = 0;

  /// The Watch tab used to fire a full-screen interstitial the moment you
  /// opened it, which landed on the exact moment the tab needs to feel
  /// instant. It now runs here instead, on every third video, where an ad
  /// break is a convention people already accept. Still globally capped by
  /// InterstitialAdManager, and the player itself stays ad-free once the
  /// video is up.
  void _maybeShowInterstitial() {
    _opensThisSession++;
    if (_opensThisSession % 3 != 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InterstitialAdManager.maybeShow();
    });
  }

  Future<void> _parseVerses() async {
    final v = _video;
    if (v == null) return;
    final refs = await VerseRefService.parse(
      '${v.title}\n${v.description ?? ''}',
    );
    if (mounted) setState(() => _verses = refs);
  }

  void _onValue(YoutubePlayerValue value) {
    final s = value.playerState;
    // The player has "come alive" once it reaches any real state — until
    // then we keep a thumbnail + spinner over it so a slow webview boot /
    // poor network reads as "loading", not a broken black box.
    if (!_playerStarted &&
        (s == PlayerState.playing ||
            s == PlayerState.paused ||
            s == PlayerState.buffering ||
            s == PlayerState.cued)) {
      _loadTimer?.cancel();
      setState(() {
        _playerStarted = true;
        _loadTimedOut = false;
      });
    }
    if (s == PlayerState.ended && !_ended) {
      _ended = true;
      _saveProgress(completed: true);
      if (YoutubePrefs.autoplayNext && _upNext.isNotEmpty) {
        _startAutoplayCountdown();
      }
    } else if (s == PlayerState.playing) {
      _ended = false;
      _cancelAutoplayCountdown();
    }
    _wasPlaying = s == PlayerState.playing || s == PlayerState.buffering;
    // Force landscape + immersive when the player enters fullscreen (the
    // bare YoutubePlayer overlay doesn't rotate on its own with the app's
    // portrait lock); restore on exit.
    final fs = value.fullScreenOption.enabled;
    if (fs != _isFullscreen) {
      _isFullscreen = fs;
      if (fs) {
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  /// Start (or restart) the "still loading?" watchdog — if the player hasn't
  /// come alive in ~12s it's almost certainly the network, so we surface a
  /// friendly retry instead of an endless spinner.
  void _armLoadWatchdog() {
    _loadTimer?.cancel();
    _playerStarted = false;
    _loadTimedOut = false;
    _loadTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && !_playerStarted) setState(() => _loadTimedOut = true);
    });
  }

  void _retryLoad() {
    final v = _video;
    if (v == null) return;
    _armLoadWatchdog();
    setState(() {});
    _controller?.loadVideoById(videoId: v.videoId);
  }

  /// Last position we managed to read, in seconds. [dispose] can't await
  /// the controller, so the docked bar resumes from here.
  int _lastPosition = 0;

  /// Whether playback was running when we last heard from the player —
  /// leaving a PAUSED video shouldn't start a bar playing behind you.
  bool _wasPlaying = false;

  Future<void> _saveProgress({bool completed = false}) async {
    final c = _controller;
    final v = _video;
    if (c == null || v == null) return;
    try {
      final pos = await c.currentTime;
      _lastPosition = pos.round();
      await YoutubeService.recordProgress(
        v.videoId,
        positionSeconds: pos.round(),
        durationSeconds: v.durationSeconds,
        completed: completed,
      );
    } catch (_) {
      /* best effort */
    }
  }

  Future<void> _loadUpNext() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final rows = await YoutubeService.upNext(
      _videoId,
      limit: _page,
      offset: _offset,
    );
    if (!mounted) return;
    setState(() {
      _upNext.addAll(rows);
      _offset += rows.length;
      _hasMore = rows.length == _page;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadUpNext();
    }
  }

  // -------------------------- Autoplay countdown ----------------------
  /// Seconds left before the next video starts itself. Null when no
  /// countdown is running.
  int? _autoplayIn;
  Timer? _autoplayTimer;

  static const _autoplaySeconds = 5;

  /// A visible, cancellable run-up to the next video.
  ///
  /// Autoplay used to swap videos the instant one ended, which is how you
  /// end up three sermons deep without meaning to. Five seconds and a
  /// Cancel makes it the viewer's choice — and the countdown card is also
  /// what tells them a next video exists at all.
  void _startAutoplayCountdown() {
    _autoplayTimer?.cancel();
    setState(() => _autoplayIn = _autoplaySeconds);
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = (_autoplayIn ?? 1) - 1;
      if (left <= 0) {
        t.cancel();
        final next = _upNext.isNotEmpty ? _upNext.first : null;
        setState(() => _autoplayIn = null);
        if (next != null) _switchTo(next);
      } else {
        setState(() => _autoplayIn = left);
      }
    });
  }

  void _cancelAutoplayCountdown() {
    if (_autoplayTimer == null && _autoplayIn == null) return;
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    if (_autoplayIn != null && mounted) setState(() => _autoplayIn = null);
  }

  /// Swap the playing video in place (tap an up-next card or autoplay-next).
  Future<void> _switchTo(YoutubeVideo next) async {
    _cancelAutoplayCountdown();
    await _saveProgress();
    setState(() {
      _video = next;
      _ended = false;
      _upNext.clear();
      _offset = 0;
      _hasMore = true;
      _verses = const [];
    });
    _armLoadWatchdog();
    await _controller?.loadVideoById(videoId: next.videoId);
    final saved = await YoutubeService.fetchBookmarkIds();
    if (mounted) setState(() => _saved = saved.contains(next.videoId));
    _loadUpNext();
    _parseVerses();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// End-screen: what's next, how long until it starts, and a way out.
  Widget _autoplayOverlay(YoutubeVideo next) {
    final left = _autoplayIn ?? 0;
    return Container(
      color: AppColors.darkNavy.withValues(alpha: 0.90),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Ring that drains as the countdown runs.
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey(left),
                  tween: Tween(
                    begin: left / _autoplaySeconds,
                    end: (left - 1) / _autoplaySeconds,
                  ),
                  duration: const Duration(seconds: 1),
                  builder: (_, value, _) => SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      value: value.clamp(0.0, 1.0),
                      strokeWidth: 3,
                      backgroundColor: AppColors.white.withValues(alpha: 0.22),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.white,
                      ),
                    ),
                  ),
                ),
                Text(
                  '$left',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Up next',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  next.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _EndScreenButton(
                      label: 'Play now',
                      filled: true,
                      onTap: () => _switchTo(next),
                    ),
                    const SizedBox(width: 8),
                    _EndScreenButton(
                      label: 'Cancel',
                      filled: false,
                      onTap: _cancelAutoplayCountdown,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSave() async {
    final v = _video;
    if (v == null) return;
    setState(() => _saved = !_saved);
    await YoutubeService.setBookmarked(v.videoId, _saved);
  }

  /// Whether the viewer follows this video's channel (patch_164).
  bool _subscribed = false;

  Future<void> _toggleSubscribe() async {
    final v = _video;
    if (v == null || v.channelId.isEmpty) return;
    final next = !_subscribed;
    setState(() => _subscribed = next);
    await YoutubeService.setSubscribed(v.channelId, next);
  }

  Future<void> _shareMoment() async {
    final c = _controller;
    final v = _video;
    if (v == null) return;
    int secs = 0;
    try {
      secs = (await c?.currentTime ?? 0).round();
    } catch (_) {}
    final url =
        'https://www.youtube.com/watch?v=${v.videoId}'
        '${secs > 5 ? '&t=${secs}s' : ''}';
    await Share.share('${v.title}\n\nWatch on Advent Connect ZW:\n$url');
  }

  Future<void> _openInYouTube() async {
    final v = _video;
    if (v == null) return;
    final uri = Uri.parse('https://www.youtube.com/watch?v=${v.videoId}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _saveProgress();
    // Leaving mid-sermon docks it rather than stopping it. Only when it
    // was actually playing — and the service itself refuses live streams,
    // which have no position worth carrying.
    final v = _video;
    if (v != null && _wasPlaying && !_ended) {
      MiniPlayerService.instance.dock(v, atSeconds: _lastPosition);
    }
    _loadTimer?.cancel();
    _autoplayTimer?.cancel();
    _progressTimer?.cancel();
    _sub?.cancel();
    _controller?.close();
    _scroll.dispose();
    // Restore the app's portrait-only lock + normal system UI on exit.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!_ready || _controller == null) {
      // Show the tapped video's thumbnail + a loading bar instantly (the
      // card passed it via `extra`), so there's never a blank/frozen gap
      // between tapping and the player booting.
      return Scaffold(
        backgroundColor: AppColors.darkNavy,
        body: Column(
          children: [
            Stack(
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: _loadingOverlay()),
                Positioned(
                  left: 4,
                  top: MediaQuery.of(context).padding.top + 4,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.white,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    // YoutubePlayer handles fullscreen internally (via OverlayPortal) in
    // 6.x, so no YoutubePlayerScaffold wrapper is needed.
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      // No top SafeArea — the player runs full-bleed under the status bar
      // (YouTube-style) so it isn't "cut" by a navy strip. The back button
      // respects the status-bar inset.
      body: Column(
        children: [
          Stack(
            children: [
              YoutubePlayer(controller: _controller!, aspectRatio: 16 / 9),
              if (!_playerStarted) Positioned.fill(child: _loadingOverlay()),
              if (_autoplayIn != null && _upNext.isNotEmpty)
                Positioned.fill(child: _autoplayOverlay(_upNext.first)),
              Positioned(
                left: 4,
                top: MediaQuery.of(context).padding.top + 4,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          ),
          if (_video?.isLive ?? false) _chatToggle(palette),
          Expanded(
            child: (_showChat && (_video?.isLive ?? false))
                ? LiveChatPanel(videoId: _videoId)
                : _details(palette),
          ),
        ],
      ),
    );
  }

  Widget _chatToggle(AppPalette palette) {
    Widget seg(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? AppColors.primaryBlue : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? AppColors.primaryBlue : palette.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: selected ? AppColors.primaryBlue : palette.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg(
          'Up next',
          Icons.video_library_outlined,
          !_showChat,
          () => setState(() => _showChat = false),
        ),
        seg(
          'Live chat',
          Icons.forum_outlined,
          _showChat,
          () => setState(() => _showChat = true),
        ),
      ],
    );
  }

  /// Thumbnail + spinner over the player while the webview boots / buffers,
  /// switching to a friendly retry if the network is too slow. Stops the
  /// "click a video → black glitch" feeling on poor connections.
  Widget _loadingOverlay() {
    final v = _video;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.darkNavy),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (v?.thumbnailUrl != null)
            CachedImage(v!.thumbnailUrl!, fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
          // Indeterminate top progress bar — the clear "it's loading on your
          // network, not frozen" signal while the player buffers.
          if (!_loadTimedOut)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Color(0x33FFFFFF),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryBlue,
                ),
              ),
            ),
          Center(
            child: _loadTimedOut
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: AppColors.white,
                        size: 34,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Slow connection',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Check your network and try again.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                        ),
                        onPressed: _retryLoad,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Branded comet spinner — unmistakably "the video
                      // is being fetched from YouTube", so the ~2s iframe
                      // boot never reads as the app freezing.
                      const BrandSpinner(size: 38, color: AppColors.white),
                      const SizedBox(height: 12),
                      Text(
                        'Loading video…',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Streaming from YouTube',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _details(AppPalette palette) {
    final v = _video;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: [
        if (v != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (v.isLive) ...[
                  const LivePill(),
                  const SizedBox(height: AppSpace.sm),
                ],
                // The title gets the screen's strongest type. It used to
                // share a row with the LIVE pill, which squeezed it into a
                // narrow column beside a badge.
                Text(
                  v.title,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                    height: 1.25,
                    fontSize: 19,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    if (v.isLive)
                      _MetaChip(
                        icon: Icons.visibility_outlined,
                        label: v.viewsLabel.isEmpty
                            ? 'Live now'
                            : v.viewsLabel.replaceAll('views', 'watching'),
                      )
                    else ...[
                      if (v.viewsLabel.isNotEmpty)
                        _MetaChip(
                          icon: Icons.visibility_outlined,
                          label: v.viewsLabel,
                        ),
                      if (v.publishedLabel.isNotEmpty) ...[
                        const SizedBox(width: AppSpace.sm),
                        _MetaChip(
                          icon: Icons.schedule_rounded,
                          label: v.publishedLabel,
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          _channelRow(v, palette),
          const SizedBox(height: AppSpace.md),
          _actionBar(palette),
          if (_verses.isNotEmpty) _scriptureChips(palette),
          if ((v.description ?? '').trim().isNotEmpty) _description(v, palette),
          const SizedBox(height: AppSpace.lg),
          Divider(height: 1, color: palette.divider),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.sm,
          ),
          child: Text(
            'Up next',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
        ),
        ..._upNext.map(
          (u) => YoutubeVideoCard(video: u, onTap: () => _switchTo(u)),
        ),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: BrandSpinner(size: 30)),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Who made this, and a way to follow them.
  ///
  /// The channel used to be one word in a grey metadata line — the single
  /// most useful thing on the screen for finding more of what you're
  /// watching, rendered as the least important. It gets an avatar, a tap
  /// target through to the channel, and the Follow control.
  Widget _channelRow(YoutubeVideo v, AppPalette palette) {
    final url = v.channelThumbUrl;
    final letter = v.channelTitle.trim().isEmpty
        ? '?'
        : v.channelTitle.trim().substring(0, 1).toUpperCase();
    final fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Text(
        letter,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onTap: v.channelId.isEmpty
                  ? null
                  : () => context.pushNamed(
                        'watch_channel',
                        pathParameters: {'channelId': v.channelId},
                      ),
              pressedScale: 0.98,
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: url == null || url.isEmpty
                          ? fallback
                          : CachedImage(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => fallback,
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      v.channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          SubscribeButton(
            subscribed: _subscribed,
            compact: true,
            onTap: _toggleSubscribe,
          ),
        ],
      ),
    );
  }

  Widget _actionBar(AppPalette palette) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: Row(
        children: [
          _action(
            icon: _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            label: _saved ? 'Saved' : 'Save',
            active: _saved,
            palette: palette,
            onTap: _toggleSave,
          ),
          _action(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            palette: palette,
            onTap: _shareMoment,
          ),
          _action(
            icon: Icons.note_alt_outlined,
            label: 'Notes',
            palette: palette,
            onTap: _openNotes,
          ),
          _action(
            icon: Icons.open_in_new_rounded,
            label: 'YouTube',
            palette: palette,
            onTap: _openInYouTube,
          ),
        ],
      ),
    );
  }

  /// Pill action, not a bare TextButton.
  ///
  /// Four naked text buttons in a row read as a debug menu — nothing about
  /// them said "tappable surface". A filled pill with a hairline edge is
  /// the same vocabulary as the filter chips in the Watch tab.
  Widget _action({
    required IconData icon,
    required String label,
    required AppPalette palette,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final fg = active ? AppColors.white : palette.text;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.94,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md + 2,
            vertical: AppSpace.sm + 1,
          ),
          decoration: BoxDecoration(
            color: active ? AppColors.primaryBlue : palette.chipBg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: active ? AppColors.primaryBlue : palette.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: AppSpace.xs + 2),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _description(YoutubeVideo v, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: GestureDetector(
        onTap: () => setState(() => _descExpanded = !_descExpanded),
        behavior: HitTestBehavior.opaque,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Text(
            v.description!.trim(),
            maxLines: _descExpanded ? null : 3,
            overflow: _descExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.textMuted,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------- Tap-a-verse ---------------------------
  Widget _scriptureChips(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final ref in _verses)
            ActionChip(
              avatar: const Icon(
                Icons.menu_book_outlined,
                size: 16,
                color: AppColors.primaryBlue,
              ),
              label: Text(ref.display),
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.10),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onPressed: () => _openPassage(ref),
            ),
        ],
      ),
    );
  }

  Future<void> _openPassage(VerseRef ref) async {
    final lines = await VerseRefService.passage(ref);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final palette = ctx.palette;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (c, scroll) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_book, color: AppColors.primaryBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ref.display,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: palette.text,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.pushNamed('library');
                      },
                      child: const Text('Open Bible'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: lines.isEmpty
                      ? Center(
                          child: Text(
                            'Passage unavailable.',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: lines.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${lines[i].number} ',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  TextSpan(
                                    text: lines[i].text,
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      color: palette.text,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------ Notes ------------------------------
  Future<void> _openNotes() async {
    final v = _video;
    if (v == null) return;
    int currentSecs = 0;
    try {
      currentSecs = (await _controller?.currentTime ?? 0).round();
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NotesSheet(
        videoId: v.videoId,
        atSeconds: currentSecs,
        onSeek: (secs) {
          _controller?.seekTo(seconds: secs.toDouble());
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}

/// Quiet metadata pill — views, age — under the title.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm + 2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.textMuted),
          const SizedBox(width: AppSpace.xs + 1),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill button used on the autoplay end screen.
class _EndScreenButton extends StatelessWidget {
  const _EndScreenButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: filled
                ? AppColors.primaryBlue
                : AppColors.white.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Timestamped sermon notes for the current video.
class _NotesSheet extends StatefulWidget {
  const _NotesSheet({
    required this.videoId,
    required this.atSeconds,
    required this.onSeek,
  });
  final String videoId;
  final int atSeconds;
  final void Function(int seconds) onSeek;

  @override
  State<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<_NotesSheet> {
  final _ctrl = TextEditingController();
  List<YoutubeNote> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await YoutubeService.fetchNotes(widget.videoId);
    if (!mounted) return;
    setState(() {
      _notes = n;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    await YoutubeService.addNote(widget.videoId, widget.atSeconds, text);
    _ctrl.clear();
    _load();
  }

  static String _stamp(int s) {
    final m = s ~/ 60, sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sermon notes',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '@ ${_stamp(widget.atSeconds)}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 3,
                  style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                  decoration: InputDecoration(
                    hintText: 'Add a note at this moment…',
                    filled: true,
                    fillColor: palette.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: AppColors.primaryBlue),
                onPressed: _add,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No notes yet. Tap a moment to remember it.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _notes.length,
                separatorBuilder: (_, _) => Divider(color: palette.divider),
                itemBuilder: (_, i) {
                  final n = _notes[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: GestureDetector(
                      onTap: () => widget.onSeek(n.positionSeconds),
                      child: Text(
                        _stamp(n.positionSeconds),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      n.note,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.text,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: palette.textMuted,
                      ),
                      onPressed: () async {
                        await YoutubeService.deleteNote(n.id);
                        _load();
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
