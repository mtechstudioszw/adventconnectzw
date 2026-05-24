import 'package:flutter/material.dart';
import '../../models/story_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';

/// Full-screen story viewer modelled on Instagram / Facebook. Each
/// story plays for [_storyDuration] before advancing; tapping the
/// right edge jumps to the next story, tapping the left edge goes
/// back, and swiping down dismisses the viewer.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.stories});

  final List<Story> stories;

  static Future<void> show(BuildContext context, List<Story> stories) {
    if (stories.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => StoryViewer(stories: stories),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  // 15s per story to match WhatsApp Status. Long enough to read a
  // caption and admire the photo, short enough to keep the rail moving.
  static const Duration _storyDuration = Duration(seconds: 15);

  late final AnimationController _progress;
  int _index = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: _storyDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _advance() {
    if (_index >= widget.stories.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _index += 1);
    _progress
      ..reset()
      ..forward();
  }

  void _back() {
    if (_index == 0) {
      _progress
        ..reset()
        ..forward();
      return;
    }
    setState(() => _index -= 1);
    _progress
      ..reset()
      ..forward();
  }

  /// Hold-to-pause: only fires after the system long-press threshold,
  /// so a quick left/right tap still navigates. Release resumes from
  /// the same position — the timer is *paused*, not restarted, which
  /// is what users expect from WhatsApp Status.
  void _onHoldStart() {
    if (_paused) return;
    setState(() => _paused = true);
    _progress.stop();
  }

  void _onHoldEnd() {
    if (!_paused) return;
    setState(() => _paused = false);
    _progress.forward();
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: CachedImage(
                story.mediaUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            // Gesture layer — WhatsApp Status semantics.
            //   - Tap LEFT third  → previous story
            //   - Tap RIGHT third → next story
            //   - Long-press anywhere → pause + hide overlays. Release
            //     resumes from where the timer paused (not from zero).
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _back,
                    onLongPressStart: (_) => _onHoldStart(),
                    onLongPressEnd: (_) => _onHoldEnd(),
                    onLongPressCancel: _onHoldEnd,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (_) => _onHoldStart(),
                    onLongPressEnd: (_) => _onHoldEnd(),
                    onLongPressCancel: _onHoldEnd,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _advance,
                    onLongPressStart: (_) => _onHoldStart(),
                    onLongPressEnd: (_) => _onHoldEnd(),
                    onLongPressCancel: _onHoldEnd,
                  ),
                ),
              ],
            ),
            // Top overlays (progress bar + author header). Hide while
            // the user is holding to pause — matches WhatsApp's
            // photo-on-press behaviour.
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: IgnorePointer(
                ignoring: _paused,
                child: AnimatedOpacity(
                  opacity: _paused ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProgressRow(),
                      const SizedBox(height: 12),
                      _buildHeader(story),
                    ],
                  ),
                ),
              ),
            ),
            if ((story.caption ?? '').isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 32,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    story.caption!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.white,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow() {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        return Row(
          children: List.generate(widget.stories.length, (i) {
            final value = i < _index
                ? 1.0
                : i == _index
                    ? _progress.value
                    : 0.0;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildHeader(Story story) {
    final initial = story.authorName.trim().isEmpty
        ? '?'
        : story.authorName.trim().substring(0, 1).toUpperCase();
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient,
          ),
          alignment: Alignment.center,
          child: (story.authorPhotoUrl ?? '').isEmpty
              ? Text(
                  initial,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                )
              : CachedImage(
                  story.authorPhotoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text(
                    initial,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                story.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                _relativeTime(story.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.white.withValues(alpha: 0.75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: AppColors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
