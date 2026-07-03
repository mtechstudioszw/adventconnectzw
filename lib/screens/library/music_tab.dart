import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/library_item_model.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../services/music_player_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';

/// Full-screen Audio Bible — opened from a button inside the Bible tab
/// (founder preference: not its own Library tab). Reuses [MusicTab] with the
/// 'audio_bible' kind so it plays through the same background player.
class AudioBibleScreen extends StatelessWidget {
  const AudioBibleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text('Audio Bible',
            style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 18)),
      ),
      body: const SafeArea(
        top: false,
        child: MusicTab(
          kind: 'audio_bible',
          emptyText: 'Audio Bible will appear here once it\'s added.',
        ),
      ),
    );
  }
}

/// Library → Music tab. Lists uploaded tracks; tapping plays via the shared
/// [MusicPlayerService] (background playback + notification controls). A
/// now-playing bar sits at the bottom and opens the full player.
class MusicTab extends StatefulWidget {
  const MusicTab({
    super.key,
    this.kind = 'music',
    this.emptyText = 'Music will appear here once it\'s added.',
  });

  /// Library content kind to list — 'music' or 'audio_bible'. Both play
  /// through the same shared [MusicPlayerService].
  final String kind;
  final String emptyText;

  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab>
    with AutomaticKeepAliveClientMixin {
  final _player = MusicPlayerService.instance;
  late Future<List<LibraryItem>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = LibraryService.fetchItems(widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Expanded(
          child: BrandedRefreshIndicator(
            color: AppColors.primaryBlue,
            onRefresh: () async {
              final items = LibraryService.fetchItems(widget.kind);
              setState(() => _future = items);
              await items;
            },
            child: FutureBuilder<List<LibraryItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: BrandSpinner(size: 30));
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) return _empty(context);
                return StreamBuilder<int?>(
                  stream: _player.player.currentIndexStream,
                  builder: (context, idxSnap) {
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final isCurrent = _player.current?.id == item.id;
                        return _trackTile(context, items, i, item, isCurrent);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
        const NowPlayingBar(),
      ],
    );
  }

  Widget _trackTile(BuildContext context, List<LibraryItem> all, int i,
      LibraryItem item, bool isCurrent) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          try {
            await _player.setQueueAndPlay(all, i);
            if (mounted) setState(() {});
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: AppColors.red,
              content: Text('Could not play this track: $e',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.white)),
            ));
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent ? AppColors.primaryBlue : palette.divider,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: (item.coverUrl != null && item.coverUrl!.isNotEmpty)
                      ? CachedImage(item.coverUrl!, fit: BoxFit.cover)
                      : const DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient),
                          child: Icon(Icons.music_note_rounded,
                              color: AppColors.white, size: 26),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall
                            .copyWith(fontWeight: FontWeight.w700)),
                    if (item.author != null && item.author!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: palette.textMuted)),
                    ],
                  ],
                ),
              ),
              Icon(
                isCurrent ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                color: isCurrent ? AppColors.primaryBlue : palette.textMuted,
              ),
              IconButton(
                tooltip: 'Download',
                icon: Icon(Icons.download_outlined,
                    color: palette.textMuted, size: 20),
                onPressed: () async {
                  final ok = await DownloadService.downloadAndShare(
                    url: item.fileUrl,
                    suggestedName: item.title,
                    mimeType: 'audio/mpeg',
                  );
                  if (context.mounted) DownloadService.toast(context, ok);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final palette = context.palette;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(Icons.library_music_outlined, size: 60, color: palette.textMuted),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(widget.emptyText,
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: palette.textMuted)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Now-playing bar — persistent mini player; opens the full player.
// ---------------------------------------------------------------------------

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = MusicPlayerService.instance;
    return StreamBuilder<int?>(
      stream: player.player.currentIndexStream,
      builder: (context, _) {
        final item = player.current;
        if (item == null) return const SizedBox.shrink();
        return Material(
          color: AppColors.darkNavy,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const FullPlayerScreen(),
            )),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: (item.coverUrl != null &&
                              item.coverUrl!.isNotEmpty)
                          ? CachedImage(item.coverUrl!, fit: BoxFit.cover)
                          : const DecoratedBox(
                              decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient),
                              child: Icon(Icons.music_note,
                                  color: AppColors.white, size: 20),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                  StreamBuilder<PlayerState>(
                    stream: player.player.playerStateStream,
                    builder: (context, snap) {
                      final playing = snap.data?.playing ?? false;
                      return Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous,
                                color: AppColors.white),
                            onPressed: player.previous,
                          ),
                          IconButton(
                            icon: Icon(
                                playing
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_fill,
                                color: AppColors.white, size: 34),
                            onPressed: player.togglePlayPause,
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next,
                                color: AppColors.white),
                            onPressed: player.next,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
//  Full player — art, seek bar, shuffle/repeat, prev/play/next.
// ---------------------------------------------------------------------------

class FullPlayerScreen extends StatelessWidget {
  const FullPlayerScreen({super.key});

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final player = MusicPlayerService.instance;
    return Scaffold(
      backgroundColor: AppColors.darkNavy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: Text('Now Playing',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 16)),
      ),
      body: SafeArea(
        child: StreamBuilder<int?>(
          stream: player.player.currentIndexStream,
          builder: (context, _) {
            final item = player.current;
            if (item == null) {
              return const Center(
                child: Text('Nothing playing',
                    style: TextStyle(color: AppColors.white)),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 260,
                      height: 260,
                      child: (item.coverUrl != null &&
                              item.coverUrl!.isNotEmpty)
                          ? CachedImage(item.coverUrl!, fit: BoxFit.cover)
                          : const DecoratedBox(
                              decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient),
                              child: Icon(Icons.music_note_rounded,
                                  color: AppColors.white, size: 90),
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(item.title,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(item.author ?? 'Advent Connect ZW',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.white.withValues(alpha: 0.7))),
                  const SizedBox(height: 24),
                  // Seek bar.
                  StreamBuilder<Duration>(
                    stream: player.player.positionStream,
                    builder: (context, posSnap) {
                      final pos = posSnap.data ?? Duration.zero;
                      final dur = player.player.duration ?? Duration.zero;
                      final max = dur.inMilliseconds.toDouble();
                      final value = pos.inMilliseconds
                          .clamp(0, max <= 0 ? 1 : max)
                          .toDouble();
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7),
                              activeTrackColor: AppColors.goldAccent,
                              inactiveTrackColor:
                                  AppColors.white.withValues(alpha: 0.2),
                              thumbColor: AppColors.goldAccent,
                              overlayColor:
                                  AppColors.goldAccent.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: max <= 0 ? 0 : value,
                              max: max <= 0 ? 1 : max,
                              onChanged: (v) => player.player
                                  .seek(Duration(milliseconds: v.round())),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmt(pos),
                                    style: TextStyle(
                                        color: AppColors.white
                                            .withValues(alpha: 0.7),
                                        fontSize: 12)),
                                Text(_fmt(dur),
                                    style: TextStyle(
                                        color: AppColors.white
                                            .withValues(alpha: 0.7),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Controls.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      StreamBuilder<bool>(
                        stream: player.player.shuffleModeEnabledStream,
                        builder: (context, s) {
                          final on = s.data ?? false;
                          return IconButton(
                            icon: Icon(Icons.shuffle,
                                color: on
                                    ? AppColors.goldAccent
                                    : AppColors.white),
                            onPressed: player.toggleShuffle,
                          );
                        },
                      ),
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(Icons.skip_previous,
                            color: AppColors.white),
                        onPressed: player.previous,
                      ),
                      StreamBuilder<PlayerState>(
                        stream: player.player.playerStateStream,
                        builder: (context, snap) {
                          final state = snap.data;
                          final playing = state?.playing ?? false;
                          final loading = state?.processingState ==
                                  ProcessingState.loading ||
                              state?.processingState ==
                                  ProcessingState.buffering;
                          return Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.primaryGradient,
                            ),
                            child: IconButton(
                              iconSize: 46,
                              icon: loading
                                  ? const SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CircularProgressIndicator(
                                          color: AppColors.white,
                                          strokeWidth: 2.6),
                                    )
                                  : Icon(
                                      playing
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: AppColors.white),
                              onPressed: player.togglePlayPause,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        iconSize: 40,
                        icon: const Icon(Icons.skip_next,
                            color: AppColors.white),
                        onPressed: player.next,
                      ),
                      StreamBuilder<LoopMode>(
                        stream: player.player.loopModeStream,
                        builder: (context, s) {
                          final mode = s.data ?? LoopMode.off;
                          final icon = mode == LoopMode.one
                              ? Icons.repeat_one
                              : Icons.repeat;
                          final active = mode != LoopMode.off;
                          return IconButton(
                            icon: Icon(icon,
                                color: active
                                    ? AppColors.goldAccent
                                    : AppColors.white),
                            onPressed: player.cycleRepeat,
                          );
                        },
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
