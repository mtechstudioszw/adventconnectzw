import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/share_config.dart';
import '../../../models/library_item_model.dart';
import '../../../services/music_download_service.dart';
import '../../../services/music_player_service.dart';
import '../../../services/music_prefs_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import 'music_visuals.dart';

/// Full-screen now-playing surface.
///
/// Deliberately does NOT use the app's light scaffold — a player is an
/// immersive moment, so it runs on the blurred cover art over navy with
/// white type. Dismiss by dragging down (like every music app) or the chevron.
class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  final _service = MusicPlayerService.instance;

  @override
  void initState() {
    super.initState();
    // Stand the app-wide mini bar down while we're up.
    MusicPlayerService.fullPlayerOpen.value = true;
  }

  @override
  void dispose() {
    MusicPlayerService.fullPlayerOpen.value = false;
    super.dispose();
  }

  /// Live drag offset for the pull-down-to-dismiss gesture.
  double _dragY = 0;

  /// While the user drags the seek bar we show THEIR value, not the stream's,
  /// otherwise the thumb fights the finger.
  double? _scrubValue;

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _dragY = (_dragY + d.delta.dy).clamp(0.0, 400.0));
  }

  void _onDragEnd(DragEndDetails d) {
    final fling = d.velocity.pixelsPerSecond.dy > 700;
    if (_dragY > 140 || fling) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _dragY = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
      stream: _service.player.currentIndexStream,
      builder: (context, _) {
        final item = _service.current;
        if (item == null) {
          return const Scaffold(
            backgroundColor: AppColors.darkNavy,
            body: Center(
              child: Text(
                'Nothing playing',
                style: TextStyle(color: AppColors.white),
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.darkNavy,
          body: GestureDetector(
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BlurredArtBackdrop(coverUrl: item.coverUrl),
                  SafeArea(child: _content(context, item)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, LibraryItem item) {
    return Column(
      children: [
        _topBar(context, item),
        const Spacer(flex: 2),
        _artwork(item),
        const Spacer(flex: 2),
        _titleBlock(item),
        const SizedBox(height: 18),
        _seekBar(),
        const SizedBox(height: 6),
        _transport(),
        const SizedBox(height: 10),
        _secondaryActions(context, item),
        const SizedBox(height: 14),
      ],
    );
  }

  // ---- Top bar ------------------------------------------------------------

  Widget _topBar(BuildContext context, LibraryItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.white, size: 30),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  item.kind == 'audio_bible' ? 'AUDIO BIBLE' : 'NOW PLAYING',
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.white.withValues(alpha: 0.65),
                    letterSpacing: 1.6,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                // Position in the queue — orients the listener the way a
                // "3 of 12" label does in a podcast app.
                Text(
                  _queuePositionLabel(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music_rounded, color: AppColors.white),
            onPressed: () => _openQueue(context),
          ),
        ],
      ),
    );
  }

  String _queuePositionLabel() {
    final i = _service.player.currentIndex;
    final total = _service.queue.length;
    if (i == null || total == 0) return '';
    return '${i + 1} of $total';
  }

  // ---- Artwork ------------------------------------------------------------

  Widget _artwork(LibraryItem item) {
    return StreamBuilder<PlayerState>(
      stream: _service.player.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        final side = MediaQuery.sizeOf(context).width * 0.72;
        return AnimatedScale(
          // Art breathes up slightly while playing — a small, cheap cue that
          // reads instantly as "this is live".
          scale: playing ? 1.0 : 0.92,
          duration: AppMotion.standard,
          curve: AppMotion.ease,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Hero(
              tag: 'now-playing-art',
              child: TrackArtwork(
                coverUrl: item.coverUrl,
                size: side.clamp(200.0, 320.0),
                radius: 24,
                icon: item.kind == 'audio_bible'
                    ? Icons.menu_book_rounded
                    : Icons.music_note_rounded,
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- Title + like -------------------------------------------------------

  Widget _titleBlock(LibraryItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (item.author?.isNotEmpty ?? false)
                      ? item.author!
                      : 'Adventist Super App',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<int>(
            valueListenable: MusicPrefsService.revision,
            builder: (context, _, _) {
              final liked = MusicPrefsService.isLiked(item.id);
              return IconButton(
                tooltip: liked ? 'Remove from liked' : 'Add to liked',
                iconSize: 28,
                icon: Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? AppColors.red : AppColors.white,
                ),
                onPressed: () => MusicPrefsService.toggleLike(item.id),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---- Seek ---------------------------------------------------------------

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: _service.player.positionStream,
      builder: (context, snap) {
        final duration = _service.player.duration ?? Duration.zero;
        final maxMs = duration.inMilliseconds.toDouble();
        final posMs = (snap.data ?? Duration.zero).inMilliseconds.toDouble();
        // Guard the degenerate "duration not known yet" case — a Slider with
        // max <= 0 throws.
        final safeMax = maxMs <= 0 ? 1.0 : maxMs;
        final value = (_scrubValue ?? posMs).clamp(0.0, safeMax);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: AppColors.goldAccent,
                inactiveTrackColor: AppColors.white.withValues(alpha: 0.22),
                thumbColor: AppColors.goldAccent,
                overlayColor: AppColors.goldAccent.withValues(alpha: 0.22),
              ),
              child: Slider(
                value: value,
                max: safeMax,
                onChanged: maxMs <= 0
                    ? null
                    : (v) => setState(() => _scrubValue = v),
                onChangeEnd: (v) async {
                  await _service.player
                      .seek(Duration(milliseconds: v.round()));
                  if (mounted) setState(() => _scrubValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(Duration(milliseconds: value.round())),
                    style: _timeStyle,
                  ),
                  Text(formatDuration(duration), style: _timeStyle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  TextStyle get _timeStyle => AppTextStyles.labelSmall.copyWith(
        color: AppColors.white.withValues(alpha: 0.7),
        fontSize: 11.5,
      );

  // ---- Transport ----------------------------------------------------------

  Widget _transport() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          StreamBuilder<bool>(
            stream: _service.player.shuffleModeEnabledStream,
            builder: (context, s) {
              final on = s.data ?? false;
              return IconButton(
                tooltip: 'Shuffle',
                icon: Icon(Icons.shuffle_rounded,
                    color: on
                        ? AppColors.goldAccent
                        : AppColors.white.withValues(alpha: 0.75)),
                onPressed: _service.toggleShuffle,
              );
            },
          ),
          IconButton(
            tooltip: 'Back 15 seconds',
            iconSize: 30,
            icon: const Icon(Icons.replay_10_rounded, color: AppColors.white),
            onPressed: () => _service.nudge(const Duration(seconds: -15)),
          ),
          _playButton(),
          IconButton(
            tooltip: 'Forward 15 seconds',
            iconSize: 30,
            icon: const Icon(Icons.forward_10_rounded, color: AppColors.white),
            onPressed: () => _service.nudge(const Duration(seconds: 15)),
          ),
          StreamBuilder<LoopMode>(
            stream: _service.player.loopModeStream,
            builder: (context, s) {
              final mode = s.data ?? LoopMode.off;
              return IconButton(
                tooltip: 'Repeat',
                icon: Icon(
                  mode == LoopMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: mode != LoopMode.off
                      ? AppColors.goldAccent
                      : AppColors.white.withValues(alpha: 0.75),
                ),
                onPressed: _service.cycleRepeat,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _playButton() {
    return StreamBuilder<PlayerState>(
      stream: _service.player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final loading = state?.processingState == ProcessingState.loading ||
            state?.processingState == ProcessingState.buffering;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous',
              iconSize: 34,
              icon: const Icon(Icons.skip_previous_rounded,
                  color: AppColors.white),
              onPressed: _service.previous,
            ),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2.6,
                      ),
                    )
                  : IconButton(
                      iconSize: 38,
                      // AnimatedSwitcher gives the play/pause swap a real
                      // morph instead of a hard cut.
                      icon: AnimatedSwitcher(
                        duration: AppMotion.quick,
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(playing),
                          color: AppColors.white,
                          size: 38,
                        ),
                      ),
                      onPressed: _service.togglePlayPause,
                    ),
            ),
            IconButton(
              tooltip: 'Next',
              iconSize: 34,
              icon: const Icon(Icons.skip_next_rounded, color: AppColors.white),
              onPressed: _service.next,
            ),
          ],
        );
      },
    );
  }

  // ---- Secondary row ------------------------------------------------------

  Widget _secondaryActions(BuildContext context, LibraryItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pill(
            icon: Icons.speed_rounded,
            label: '${_service.speed.toStringAsFixed(_service.speed == _service.speed.roundToDouble() ? 0 : 2)}×',
            active: _service.speed != 1.0,
            onTap: () => _openSpeedSheet(context),
          ),
          ValueListenableBuilder<DateTime?>(
            valueListenable: _service.sleepAt,
            builder: (context, at, _) => _pill(
              icon: Icons.bedtime_outlined,
              label: at == null ? 'Sleep' : _remaining(at),
              active: at != null,
              onTap: () => _openSleepSheet(context),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: MusicDownloadService.revision,
            builder: (context, _, _) {
              final saved = MusicDownloadService.isDownloaded(item.id);
              return _pill(
                icon: saved
                    ? Icons.download_done_rounded
                    : Icons.download_outlined,
                label: saved ? 'Saved' : 'Save',
                active: saved,
                onTap: () => _toggleDownload(context, item, saved),
              );
            },
          ),
          _pill(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            active: false,
            onTap: () => Share.share(
              '${item.title}'
              '${(item.author?.isNotEmpty ?? false) ? ' — ${item.author}' : ''}'
              '\n\nListening on Adventist Super App:\n$appDownloadUrl',
            ),
          ),
        ],
      ),
    );
  }

  static String _remaining(DateTime at) {
    final left = at.difference(DateTime.now());
    if (left.isNegative) return 'Sleep';
    final mins = left.inMinutes + 1;
    return mins >= 60 ? '${(mins / 60).floor()}h' : '${mins}m';
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? AppColors.goldAccent : AppColors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color.withValues(alpha: 0.9)),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color.withValues(alpha: 0.9),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleDownload(
    BuildContext context,
    LibraryItem item,
    bool saved,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (saved) {
      await MusicDownloadService.remove(item.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Removed from downloads.')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Downloading "${item.title}"…')),
    );
    final ok = await MusicDownloadService.download(item);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Saved for offline listening.'
            : 'Download failed. Check your connection.'),
      ),
    );
  }

  // ---- Sheets -------------------------------------------------------------

  Future<void> _openSpeedSheet(BuildContext context) async {
    const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.darkNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTitle('Playback speed'),
            for (final s in speeds)
              ListTile(
                title: Text(
                  s == 1.0 ? 'Normal' : '$s×',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.white),
                ),
                trailing: (_service.speed - s).abs() < 0.01
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.goldAccent)
                    : null,
                onTap: () async {
                  await _service.setSpeed(s);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) setState(() {});
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openSleepSheet(BuildContext context) async {
    const options = <(String, Duration?)>[
      ('15 minutes', Duration(minutes: 15)),
      ('30 minutes', Duration(minutes: 30)),
      ('45 minutes', Duration(minutes: 45)),
      ('1 hour', Duration(hours: 1)),
      ('Off', null),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.darkNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTitle('Sleep timer'),
            for (final (label, duration) in options)
              ListTile(
                leading: Icon(
                  duration == null
                      ? Icons.bedtime_off_outlined
                      : Icons.bedtime_outlined,
                  color: AppColors.white.withValues(alpha: 0.8),
                ),
                title: Text(
                  label,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.white),
                ),
                onTap: () {
                  _service.setSleepTimer(duration);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openQueue(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.darkNavy,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.6,
          child: Column(
            children: [
              _sheetTitle('Up next'),
              Expanded(
                child: StreamBuilder<int?>(
                  stream: _service.player.currentIndexStream,
                  builder: (context, snap) {
                    final currentIndex = snap.data ?? 0;
                    final queue = _service.queue;
                    return ListView.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, i) {
                        final track = queue[i];
                        final isCurrent = i == currentIndex;
                        return ListTile(
                          leading: TrackArtwork(
                            coverUrl: track.coverUrl,
                            size: 42,
                            radius: 8,
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: isCurrent
                                  ? AppColors.goldAccent
                                  : AppColors.white,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            (track.author?.isNotEmpty ?? false)
                                ? track.author!
                                : 'Adventist Super App',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          trailing: isCurrent
                              ? const EqualizerBars(
                                  playing: true,
                                  color: AppColors.goldAccent,
                                  size: 16,
                                )
                              : null,
                          onTap: () {
                            _service.jumpTo(i);
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Row(
          children: [
            Text(
              text,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
