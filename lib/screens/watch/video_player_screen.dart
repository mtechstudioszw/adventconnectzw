import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../models/youtube_video.dart';
import '../../services/youtube_prefs.dart';
import '../../services/youtube_service.dart';
import '../../services/verse_ref_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/youtube/live_chat_panel.dart';
import '../../widgets/youtube/youtube_video_card.dart';

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
    _video ??= await YoutubeService.fetchVideo(widget.videoId);
    final resume = await YoutubeService.resumePosition(widget.videoId);
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
    _progressTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    _armLoadWatchdog();

    if (!mounted) return;
    setState(() {
      _controller = controller;
      _saved = saved.contains(widget.videoId);
      _ready = true;
    });
    _loadUpNext();
    _parseVerses();
  }

  Future<void> _parseVerses() async {
    final v = _video;
    if (v == null) return;
    final refs =
        await VerseRefService.parse('${v.title}\n${v.description ?? ''}');
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
        _switchTo(_upNext.first);
      }
    } else if (s == PlayerState.playing) {
      _ended = false;
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

  Future<void> _saveProgress({bool completed = false}) async {
    final c = _controller;
    final v = _video;
    if (c == null || v == null) return;
    try {
      final pos = await c.currentTime;
      await YoutubeService.recordProgress(
        v.videoId,
        positionSeconds: pos.round(),
        durationSeconds: v.durationSeconds,
        completed: completed,
      );
    } catch (_) {/* best effort */}
  }

  Future<void> _loadUpNext() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final rows =
        await YoutubeService.upNext(_videoId, limit: _page, offset: _offset);
    if (!mounted) return;
    setState(() {
      _upNext.addAll(rows);
      _offset += rows.length;
      _hasMore = rows.length == _page;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 600) {
      _loadUpNext();
    }
  }

  /// Swap the playing video in place (tap an up-next card or autoplay-next).
  Future<void> _switchTo(YoutubeVideo next) async {
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

  Future<void> _toggleSave() async {
    final v = _video;
    if (v == null) return;
    setState(() => _saved = !_saved);
    await YoutubeService.setBookmarked(v.videoId, _saved);
  }

  Future<void> _shareMoment() async {
    final c = _controller;
    final v = _video;
    if (v == null) return;
    int secs = 0;
    try {
      secs = (await c?.currentTime ?? 0).round();
    } catch (_) {}
    final url = 'https://www.youtube.com/watch?v=${v.videoId}'
        '${secs > 5 ? '&t=${secs}s' : ''}';
    await Share.share(
      '${v.title}\n\nWatch on Advent Connect ZW:\n$url',
    );
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
    _loadTimer?.cancel();
    _progressTimer?.cancel();
    _sub?.cancel();
    _controller?.close();
    _scroll.dispose();
    // Restore the app's portrait-only lock when leaving the player.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!_ready || _controller == null) {
      return Scaffold(
        backgroundColor: AppColors.darkNavy,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.white),
        ),
      );
    }
    // YoutubePlayer handles fullscreen internally (via OverlayPortal) in
    // 6.x, so no YoutubePlayerScaffold wrapper is needed.
    return Scaffold(
          backgroundColor: palette.scaffoldBg,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Pinned player with a back affordance over it.
                Stack(
                  children: [
                    YoutubePlayer(
                      controller: _controller!,
                      aspectRatio: 16 / 9,
                    ),
                    if (!_playerStarted)
                      Positioned.fill(child: _loadingOverlay()),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: AppColors.white),
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
                Icon(icon,
                    size: 17,
                    color: selected ? AppColors.primaryBlue : palette.textMuted),
                const SizedBox(width: 6),
                Text(label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color:
                          selected ? AppColors.primaryBlue : palette.textMuted,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg('Up next', Icons.video_library_outlined, !_showChat,
            () => setState(() => _showChat = false)),
        seg('Live chat', Icons.forum_outlined, _showChat,
            () => setState(() => _showChat = true)),
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
            decoration:
                BoxDecoration(color: Colors.black.withValues(alpha: 0.5)),
          ),
          Center(
            child: _loadTimedOut
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: AppColors.white, size: 34),
                      const SizedBox(height: 10),
                      Text('Slow connection',
                          style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Check your network and try again.',
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.white.withValues(alpha: 0.8))),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue),
                        onPressed: _retryLoad,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                          color: AppColors.white, strokeWidth: 2.5),
                      const SizedBox(height: 12),
                      Text('Loading…',
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.white.withValues(alpha: 0.85))),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (v.isLive) ...[const LivePill(), const SizedBox(width: 8)],
                    Expanded(
                      child: Text(
                        v.title,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    v.channelTitle,
                    if (v.isLive) 'LIVE now' else v.publishedLabel,
                    if (!v.isLive) v.viewsLabel,
                  ].where((e) => e.isNotEmpty).join('  ·  '),
                  style: AppTextStyles.bodySmall
                      .copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _actionBar(palette),
          if (_verses.isNotEmpty) _scriptureChips(palette),
          if ((v.description ?? '').trim().isNotEmpty) _description(v, palette),
          const Divider(height: 28),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'Up next',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
        ),
        ..._upNext.map((u) => YoutubeVideoCard(
              video: u,
              onTap: () => _switchTo(u),
            )),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue)),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _actionBar(AppPalette palette) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _action(
            icon: _saved ? Icons.bookmark : Icons.bookmark_border,
            label: _saved ? 'Saved' : 'Save',
            color: _saved ? AppColors.primaryBlue : palette.text,
            onTap: _toggleSave,
          ),
          _action(
            icon: Icons.ios_share,
            label: 'Share',
            color: palette.text,
            onTap: _shareMoment,
          ),
          _action(
            icon: Icons.note_alt_outlined,
            label: 'Notes',
            color: palette.text,
            onTap: _openNotes,
          ),
          _action(
            icon: Icons.open_in_new,
            label: 'YouTube',
            color: palette.text,
            onTap: _openInYouTube,
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: color),
        label: Text(label,
            style: AppTextStyles.bodySmall
                .copyWith(color: color, fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            overflow: _descExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall
                .copyWith(color: palette.textMuted, height: 1.45),
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
              avatar: const Icon(Icons.menu_book_outlined,
                  size: 16, color: AppColors.primaryBlue),
              label: Text(ref.display),
              labelStyle: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primaryBlue, fontWeight: FontWeight.w700),
              backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.10),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
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
                      child: Text(ref.display,
                          style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w800, color: palette.text)),
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
                          child: Text('Passage unavailable.',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: palette.textMuted)))
                      : ListView.builder(
                          controller: scroll,
                          itemCount: lines.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                  text: '${lines[i].number} ',
                                  style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w800),
                                ),
                                TextSpan(
                                  text: lines[i].text,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                      color: palette.text, height: 1.5),
                                ),
                              ]),
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
          Text('Sermon notes',
              style: AppTextStyles.titleMedium
                  .copyWith(fontWeight: FontWeight.w800, color: palette.text)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('@ ${_stamp(widget.atSeconds)}',
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700)),
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
                        horizontal: 12, vertical: 10),
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
              child: Text('No notes yet. Tap a moment to remember it.',
                  style:
                      AppTextStyles.bodySmall.copyWith(color: palette.textMuted)),
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
                      child: Text(_stamp(n.positionSeconds),
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700)),
                    ),
                    title: Text(n.note,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: palette.text)),
                    trailing: IconButton(
                      icon: Icon(Icons.close, size: 18, color: palette.textMuted),
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
