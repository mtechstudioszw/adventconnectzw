import 'package:flutter/material.dart';
import '../../models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
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
        pageBuilder: (context, animation, secondaryAnimation) => StoryViewer(stories: stories),
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

  // Cached viewer counts for the author's own stories, keyed by story
  // id. Populated on first display + after the "Viewed by" sheet opens.
  final Map<String, int> _viewerCounts = <String, int>{};

  // Whether the current viewer has liked each story (non-owner view),
  // and the like tally for the author's own stories.
  final Map<String, bool> _liked = <String, bool>{};
  final Map<String, int> _likeCounts = <String, int>{};

  // Reply-to-status composer.
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  bool _sendingReply = false;

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
    _onStoryShown();
    // Pause the timer while the reply field is focused so the story
    // doesn't advance mid-typing; resume when focus leaves.
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _progress.stop();
      } else if (!_paused && mounted) {
        _progress.forward();
      }
    });
  }

  Future<void> _sendReply(Story story) async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: story.authorId,
        otherUserName: story.authorName,
      );
      await MessagingService.sendMessage(
        conversationId: convo.id,
        content: text,
        messageType: 'story_reply',
        meta: {
          'story_id': story.id,
          'story_image': story.mediaUrl,
          if ((story.caption ?? '').isNotEmpty) 'caption': story.caption,
        },
      );
      _replyController.clear();
      _replyFocus.unfocus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply sent.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send reply.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  bool _isMyStory(Story s) => s.authorId == AuthService.currentUser?.id;

  /// Called when a new story is brought on screen (initial + advance +
  /// back). Marks it as viewed for non-owners, refreshes the viewer
  /// count for owners.
  void _onStoryShown() {
    if (_index < 0 || _index >= widget.stories.length) return;
    final story = widget.stories[_index];
    if (_isMyStory(story)) {
      _loadViewerCount(story.id);
      _loadLikeCount(story.id);
    } else {
      // Fire-and-forget — viewer rows are idempotent on (story, viewer).
      FeedService.markStoryViewed(story.id);
      _loadLikedState(story.id);
    }
  }

  Future<void> _loadViewerCount(String storyId) async {
    final list = await FeedService.fetchStoryViewers(storyId);
    if (!mounted) return;
    setState(() => _viewerCounts[storyId] = list.length);
  }

  Future<void> _loadLikeCount(String storyId) async {
    final list = await FeedService.fetchStoryLikers(storyId);
    if (!mounted) return;
    setState(() => _likeCounts[storyId] = list.length);
  }

  Future<void> _loadLikedState(String storyId) async {
    final liked = await FeedService.isStoryLiked(storyId);
    if (!mounted) return;
    setState(() => _liked[storyId] = liked);
  }

  /// Toggle the viewer's like with an optimistic flip, reconciling with
  /// the state the service actually persisted.
  Future<void> _toggleLike(Story story) async {
    final current = _liked[story.id] ?? false;
    setState(() => _liked[story.id] = !current);
    final applied = await FeedService.toggleStoryLike(
      story.id,
      currentlyLiked: current,
    );
    if (!mounted) return;
    setState(() => _liked[story.id] = applied);
  }

  Future<void> _openLikersSheet(Story story) async {
    _onHoldStart();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _StoryPeopleSheet(storyId: story.id, kind: _PeopleKind.likers),
    );
    if (!mounted) return;
    _onHoldEnd();
    _loadLikeCount(story.id);
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocus.dispose();
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
    _onStoryShown();
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
    _onStoryShown();
  }

  Future<void> _confirmDeleteStory(Story story) async {
    _onHoldStart(); // pause the timer while the dialog is up
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this story?'),
        content: const Text(
          'It will be removed immediately and viewers will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _onHoldEnd();
      return;
    }
    try {
      await FeedService.deleteStory(story.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      _onHoldEnd();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete story. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _openViewersSheet(Story story) async {
    _onHoldStart();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _StoryPeopleSheet(storyId: story.id, kind: _PeopleKind.viewers),
    );
    if (!mounted) return;
    _onHoldEnd();
    // Refresh count after the sheet closes (covers the rare case
    // someone watches it WHILE the sheet is open).
    _loadViewerCount(story.id);
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

  /// Absolute clock time per the user's preference — stories should
  /// show "14:32" not "2h ago". Stories age out after 24h so a 24h
  /// clock is always enough (no date fallbacks needed).
  String _relativeTime(DateTime when) {
    final local = when.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
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
                errorBuilder: (context, error, stackTrace) => const Center(
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
                right: _isMyStory(story) ? 16 : 72,
                bottom: _isMyStory(story) ? 78 : 86,
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
            // Viewer reaction — a heart that toggles a like on someone
            // else's story. Hidden on your own stories (you can't like
            // yourself; the owner footer shows the tally instead).
            if (!_isMyStory(story))
              Positioned(
                right: 16,
                bottom: 24,
                child: IgnorePointer(
                  ignoring: _paused,
                  child: AnimatedOpacity(
                    opacity: _paused ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: GestureDetector(
                      onTap: () => _toggleLike(story),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (_liked[story.id] ?? false)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: (_liked[story.id] ?? false)
                              ? AppColors.red
                              : AppColors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Reply-to-status bar (non-own stories). Sits left of the
            // heart; focusing it pauses the story timer.
            if (!_isMyStory(story))
              Positioned(
                left: 12,
                right: 68,
                // Lift above the keyboard — the viewer is a full-screen
                // Stack (no Scaffold resize), so without this the reply
                // field sits BEHIND the keyboard and you can't see what
                // you type.
                bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
                child: AnimatedOpacity(
                  // Stay visible while typing (keyboard up) even though the
                  // story is paused; only hide on a tap-and-hold pause.
                  opacity: (_paused && !_replyFocus.hasFocus) ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                          color: AppColors.white.withValues(alpha: 0.25)),
                    ),
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            focusNode: _replyFocus,
                            style: const TextStyle(color: AppColors.white),
                            cursorColor: AppColors.white,
                            minLines: 1,
                            maxLines: 3,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendReply(story),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Reply to status…',
                              hintStyle: TextStyle(
                                  color:
                                      AppColors.white.withValues(alpha: 0.7)),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: _sendingReply
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.white),
                                )
                              : const Icon(Icons.send,
                                  color: AppColors.white, size: 20),
                          onPressed:
                              _sendingReply ? null : () => _sendReply(story),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Own-story footer — tappable "likes" and "viewed by" pills
            // that open their respective people sheets. Hidden for
            // stories the viewer doesn't own (RLS blocks the fetch too).
            if (_isMyStory(story))
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: IgnorePointer(
                  ignoring: _paused,
                  child: AnimatedOpacity(
                    opacity: _paused ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _statPill(
                          icon: Icons.favorite,
                          label: () {
                            final n = _likeCounts[story.id];
                            if (n == null) return 'Likes…';
                            return n == 1 ? '1 like' : '$n likes';
                          }(),
                          onTap: () => _openLikersSheet(story),
                        ),
                        const SizedBox(width: 10),
                        _statPill(
                          icon: Icons.visibility_outlined,
                          label: () {
                            final n = _viewerCounts[story.id];
                            if (n == null) return 'Viewed by…';
                            return n == 1 ? 'Viewed by 1' : 'Viewed by $n';
                          }(),
                          onTap: () => _openViewersSheet(story),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A translucent, tappable count pill used in the owner footer.
  Widget _statPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
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
                  errorBuilder: (context, error, stackTrace) => Text(
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
        if (_isMyStory(story))
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.white),
            tooltip: 'Delete story',
            onPressed: () => _confirmDeleteStory(story),
          ),
        IconButton(
          icon: const Icon(Icons.close, color: AppColors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

enum _PeopleKind { viewers, likers }

class _StoryPeopleSheet extends StatefulWidget {
  const _StoryPeopleSheet({required this.storyId, required this.kind});
  final String storyId;
  final _PeopleKind kind;
  @override
  State<_StoryPeopleSheet> createState() => _StoryPeopleSheetState();
}

class _StoryPeopleSheetState extends State<_StoryPeopleSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _viewers = const [];

  bool get _isLikers => widget.kind == _PeopleKind.likers;
  IconData get _icon =>
      _isLikers ? Icons.favorite : Icons.visibility_outlined;

  String _heading() {
    final n = _viewers.length;
    if (_isLikers) {
      if (_loading) return 'Likes…';
      return n == 1 ? '1 like' : '$n likes';
    }
    return _loading ? 'Viewed by…' : 'Viewed by $n';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = _isLikers
        ? await FeedService.fetchStoryLikers(widget.storyId)
        : await FeedService.fetchStoryViewers(widget.storyId);
    if (!mounted) return;
    setState(() {
      _viewers = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Icon(_icon, color: AppColors.primaryBlue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _heading(),
                    style: AppTextStyles.titleMedium.copyWith(
                      color: ctx.palette.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : _viewers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _isLikers ? 'No likes yet.' : 'No views yet.',
                              style: TextStyle(color: ctx.palette.text),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: controller,
                          itemCount: _viewers.length,
                          itemBuilder: (_, i) {
                            final v = _viewers[i];
                            final name =
                                (v['full_name'] as String?) ?? 'Member';
                            final photo =
                                (v['profile_photo_url'] as String?) ?? '';
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor: context.palette.cardMuted,
                                child: photo.isNotEmpty
                                    ? ClipOval(
                                        child: CachedImage(
                                          photo,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => _InitialBadge(
                                            name: name,
                                          ),
                                        ),
                                      )
                                    : _InitialBadge(name: name),
                              ),
                              title: Text(
                                name,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: ctx.palette.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialBadge extends StatelessWidget {
  const _InitialBadge({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initial = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : parts.first.substring(0, 1).toUpperCase();
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
