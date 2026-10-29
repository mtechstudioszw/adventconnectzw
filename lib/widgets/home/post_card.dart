import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_version.dart';
import '../../config/share_config.dart';
import '../../models/post_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../services/feed_service.dart';
import '../../services/follow_service.dart';
import '../cached_image.dart';
import '../expandable_text.dart';
import '../motion/pressable.dart';
import '../moderation_appeal_sheet.dart';

/// One card in the home feed.
///
/// The media is FULL-BLEED at its natural aspect ratio (capped to 4:5 tall /
/// 1.91:1 wide) rather than inset and force-cropped to a square. The old
/// treatment put card padding around a rounded image inside a rounded card —
/// a card inside a card — and centre-cropped portrait photos through people's
/// heads. This deliberately relaxes CLAUDE.md's "all uploaded images square"
/// rule for feed media; the rule still holds for avatars and covers.
///
/// The parent owns the [Post] and receives optimistic-update callbacks.
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.viewerId,
    required this.onLikeToggled,
    required this.onCommentsTapped,
    required this.onImageTapped,
    this.onReactionSelected,
    this.onAuthorTapped,
    this.onAuthorAvatarTapped,
    this.hasStory = false,
    this.storyViewed = false,
    this.onStoryRingTapped,
    this.onEdit,
    this.onDelete,
    this.onToggleVisibility,
    this.onReport,
    this.onSaveImage,
    this.onAdminModerate,
  });

  final Post post;
  final String? viewerId;

  /// Plain like/unlike toggle. Always required so screens that don't opt into
  /// reactions (the profile tabs) keep a working heart.
  final VoidCallback onLikeToggled;

  /// Opt-in richer path: Like / Amen / Praying. When provided, the reaction
  /// button long-presses into a tray and this fires with the chosen
  /// reaction, or null to clear it.
  final void Function(PostReaction?)? onReactionSelected;

  final VoidCallback onCommentsTapped;

  /// Fires with the index of the photo that was tapped, so multi-photo posts
  /// open the viewer on the right one.
  final void Function(int index) onImageTapped;

  final VoidCallback? onAuthorTapped;
  // Tapping the avatar opens a quick profile preview (vs the name, which
  // opens the full profile). Story ring: brand gradient when the author has
  // an unviewed story, grey once viewed; tapping asks story-or-profile.
  final VoidCallback? onAuthorAvatarTapped;
  final bool hasStory;
  final bool storyViewed;
  final VoidCallback? onStoryRingTapped;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onReport;

  /// Super admins only (null for everyone else): hide this post from the
  /// feed, or restore it if it is already hidden. patch_272.
  final VoidCallback? onAdminModerate;
  // Owner menu shows "Save to gallery" when this is wired AND the
  // post actually has an image. Non-owner cards get the same option
  // via the viewer menu.
  final VoidCallback? onSaveImage;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  static const int _bodyCollapsedLines = 6;

  int _photo = 0;
  late final AnimationController _bloom;

  @override
  void initState() {
    super.initState();
    _bloom = AnimationController(vsync: this, duration: AppMotion.celebrate);
  }

  @override
  void dispose() {
    _bloom.dispose();
    super.dispose();
  }

  Post get post => widget.post;
  bool get _isOwner =>
      widget.viewerId != null && widget.viewerId == post.authorId;
  List<String> get _images => post.imageUrls;

  void _select(PostReaction? reaction) {
    final handler = widget.onReactionSelected;
    if (handler != null) {
      handler(reaction);
    } else {
      // Screens that didn't opt into reactions just get a like toggle.
      widget.onLikeToggled();
    }
  }

  /// Double-tap always ADDS a reaction, never removes one — an accidental
  /// second double-tap shouldn't silently undo the first (Instagram's rule).
  void _onDoubleTapMedia() {
    if (post.viewerReaction == null) {
      HapticFeedback.mediumImpact();
      _select(PostReaction.like);
    }
    _bloom.forward(from: 0);
  }

  void _onReactionPressed() {
    HapticFeedback.mediumImpact();
    _select(post.viewerReaction == null ? PostReaction.like : null);
  }

  Future<void> _openReactionTray() async {
    if (widget.onReactionSelected == null) return;
    HapticFeedback.selectionClick();
    final chosen = await showReactionTray(
      context,
      current: post.viewerReaction,
    );
    if (!mounted || chosen == null) return;
    // `clear` comes back as a sentinel so "tapped my current reaction" can
    // mean remove rather than re-apply.
    _select(chosen == post.viewerReaction ? null : chosen);
  }

  Future<void> _share() async {
    final text = (post.body ?? '').trim();
    final author = post.isPagePost
        ? post.pageName!.trim()
        : post.isChurchPost
        ? post.churchName!.trim()
        : post.authorName;
    // A PUBLIC post now shares a real link that unfurls an OG preview card in
    // WhatsApp, the way event and product links already do (the phase-2 TODO
    // that used to sit here).
    //
    // Anything not public keeps the store link on purpose. The worker only
    // resolves public rows — deliberately, so a friends-only post cannot be
    // unfurled by whoever the link reaches — so pointing a private post at it
    // would share a link that 404s. A store link is not a preview, but it is
    // never broken and it never leaks.
    final link = post.visibility == PostVisibility.public
        ? postShareUrl(post.id)
        : 'https://play.google.com/store/apps/details?id=$kAndroidPackageId';
    final body = text.isEmpty
        ? '$author shared a post on Adventist Super App.\n$link'
        : '"$text"\n\n— $author on Adventist Super App\n$link';
    await Share.share(body, subject: 'Adventist Super App');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          // Only the author and admins can still read a hidden post, so
          // this is their notice — with the way to appeal.
          if (post.isModerated)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                0,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: ModeratedBanner(
                kind: ModeratedKind.post,
                itemId: post.id,
                title: post.body,
                reason: post.moderationReason,
                ownerView: _isOwner,
              ),
            ),
          if ((post.body ?? '').isNotEmpty) _buildBody(context),
          if (_images.isNotEmpty) _buildMedia(context),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.sm,
        AppSpace.sm,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: post.isPagePost
                ? _openPage
                : widget.hasStory
                ? widget.onStoryRingTapped
                : (widget.onAuthorAvatarTapped ?? widget.onAuthorTapped),
            child: _StoryRing(
              hasStory: widget.hasStory && !post.isPagePost,
              viewed: widget.storyViewed,
              child: post.isPagePost
                  ? _PageAvatar(name: post.pageName!, logoUrl: post.pageLogoUrl)
                  : post.isChurchPost
                  ? _ChurchAvatar(photoUrl: post.churchPhotoUrl)
                  : _Avatar(
                      name: post.authorName,
                      photoUrl: post.authorPhotoUrl,
                    ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: GestureDetector(
              onTap: post.isPagePost ? _openPage : widget.onAuthorTapped,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          // Church- and Page-branded posts show the
                          // organization, not the admin who wrote them.
                          post.isPagePost
                              ? post.pageName!.trim()
                              : post.isChurchPost
                              ? post.churchName!.trim()
                              : post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // Gold tick for church posts (always) or verified authors.
                      // A Page's tick is the Page's own verification —
                      // a verified admin doesn't lend theirs to it.
                      if (post.isPagePost
                          ? post.pageVerified
                          : (post.isChurchPost || post.authorIsVerified)) ...[
                        const SizedBox(width: AppSpace.xs),
                        const Icon(
                          Icons.verified,
                          size: 14,
                          color: AppColors.goldAccent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Text(
                        _formatTimeAgo(post.createdAt),
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      Text(
                        '  ·  ',
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      Icon(
                        post.visibility == PostVisibility.friendsOnly
                            ? Icons.people_alt_outlined
                            : Icons.public,
                        size: 11,
                        color: palette.textMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<Set<String>>(
            valueListenable: FeedService.savedPostIds,
            builder: (context, savedIds, _) =>
                ValueListenableBuilder<Set<String>?>(
                  valueListenable: FollowService.followingIds,
                  builder: (context, followingIds, _) => _PostMenu(
                    isOwner: _isOwner,
                    authorFirstName: _authorFirstName,
                    // Null = not known yet (or following isn't available), and
                    // the item is left out rather than guessed.
                    // Not on Page posts: the writer is an admin, and
                    // following them isn't following the Page.
                    followsAuthor:
                        _isOwner || followingIds == null || post.isPagePost
                        ? null
                        : followingIds.contains(post.authorId),
                    onToggleFollow: _toggleFollow,
                    isFriendsOnly:
                        post.visibility == PostVisibility.friendsOnly,
                    saved: savedIds.contains(post.id),
                    onToggleSaved: _toggleSaved,
                    onCopyLink: _copyLink,
                    onHide: _isOwner ? null : _hide,
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                    onToggleVisibility: widget.onToggleVisibility,
                    onSaveImage: _images.isNotEmpty ? widget.onSaveImage : null,
                    photoCount: _images.length,
                    onReport: widget.onReport,
                    onAdminModerate: widget.onAdminModerate,
                    isModerated: post.isModerated,
                  ),
                ),
          ),
        ],
      ),
    );
  }

  String get _authorFirstName {
    final first = post.authorName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'this member' : first;
  }

  /// One-way follow from the post itself (patch_274). A private account
  /// answers "requested", and the toast says so.
  Future<void> _toggleFollow() async {
    final following =
        FollowService.followingIds.value?.contains(post.authorId) ?? false;
    try {
      if (following) {
        await FollowService.unfollow(post.authorId);
        _toast('Unfollowed $_authorFirstName.');
      } else {
        final state = await FollowService.follow(post.authorId);
        _toast(
          state == FollowState.requested
              ? 'Follow request sent to $_authorFirstName.'
              : 'Following $_authorFirstName.',
        );
      }
    } on FollowNotAllowed {
      // Their "who can follow me" setting (patch_282).
      _toast("$_authorFirstName isn't taking followers.");
    } catch (_) {
      _toast(
        FollowService.available
            ? "Couldn't update. Try again."
            : 'Following needs a database update (patch_274).',
      );
    }
  }

  void _openPage() {
    final id = post.pageId;
    if (id == null) return;
    context.pushNamed('page_details', pathParameters: {'id': id});
  }

  void _toast(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  /// Saved posts live in the member's private collection (patch_273), not
  /// a local icon flip.
  Future<void> _toggleSaved() async {
    final saving = !FeedService.savedPostIds.value.contains(post.id);
    try {
      await FeedService.setSaved(post.id, saving);
      _toast(
        saving ? 'Saved. Find it in Profile → Saved.' : 'Removed from Saved.',
      );
    } catch (_) {
      _toast(
        !FeedService.savedPostsAvailable
            ? 'Saving posts needs a database update (patch_273).'
            : "Couldn't update Saved. Try again.",
      );
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: postShareUrl(post.id)));
    _toast('Link copied.');
  }

  /// "See less": out of this member's feed only, with Undo.
  Future<void> _hide() async {
    try {
      await FeedService.setHidden(post.id, true);
      _toast(
        "Post hidden. You won't see it in your feed.",
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => FeedService.setHidden(post.id, false),
        ),
      );
    } catch (_) {
      _toast(
        !FeedService.savedPostsAvailable
            ? 'Hiding posts needs a database update (patch_273).'
            : "Couldn't hide this post. Try again.",
      );
    }
  }

  Widget _buildBody(BuildContext context) {
    final palette = context.palette;
    final body = post.body!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.md,
      ),
      // The expand/collapse used to live here as a one-way "See more":
      // there was no way back, so an expanded 2,000-character post ate the
      // feed for as long as the card stayed alive. ExpandableText owns
      // both directions now, and it measures the text instead of guessing
      // from its length. See lib/widgets/expandable_text.dart.
      child: ExpandableText(
        text: body,
        collapsedLines: _bodyCollapsedLines,
        style: AppTextStyles.bodyMedium.copyWith(
          color: palette.text,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildMedia(BuildContext context) {
    return _NaturalMedia(
      urls: _images,
      page: _photo,
      onPageChanged: (i) => setState(() => _photo = i),
      onTap: () => widget.onImageTapped(_photo),
      onDoubleTap: _onDoubleTapMedia,
      bloom: _bloom,
      heroTag: 'post_image_${post.id}',
    );
  }

  Widget _buildFooter(BuildContext context) {
    final palette = context.palette;
    final reaction = post.viewerReaction;
    final hasCounts = post.likeCount > 0 || post.commentCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.xs,
      ),
      child: Column(
        children: [
          if (hasCounts)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.sm,
                0,
                AppSpace.sm,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  if (post.likeCount > 0) ...[
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _glyphFor(reaction ?? PostReaction.like),
                        size: 11,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    // Count rolls rather than snapping when it changes.
                    AnimatedSwitcher(
                      duration: AppMotion.maybe(context, AppMotion.quick),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SizeTransition(
                          sizeFactor: anim,
                          axis: Axis.vertical,
                          child: child,
                        ),
                      ),
                      child: Text(
                        '${post.likeCount}',
                        key: ValueKey(post.likeCount),
                        style: AppTextStyles.caption.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (post.commentCount > 0)
                    Text(
                      post.commentCount == 1
                          ? '1 comment'
                          : '${post.commentCount} comments',
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: reaction == null
                      ? Icons.favorite_border
                      : _glyphFor(reaction),
                  label: reaction?.label ?? 'Like',
                  highlighted: reaction != null,
                  onTap: _onReactionPressed,
                  onLongPress: widget.onReactionSelected == null
                      ? null
                      : _openReactionTray,
                ),
              ),
              Expanded(
                child: _ActionButton(
                  icon: Icons.mode_comment_outlined,
                  label: 'Comment',
                  onTap: widget.onCommentsTapped,
                ),
              ),
              Expanded(
                child: _ActionButton(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: _share,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _glyphFor(PostReaction r) => switch (r) {
    PostReaction.like => Icons.favorite,
    PostReaction.amen => Icons.volunteer_activism,
    PostReaction.praying => Icons.front_hand,
  };

  static String _formatTimeAgo(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return '${weeks}w';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '${months}mo';
    final years = (diff.inDays / 365).floor();
    return '${years}y';
  }
}

/// Full-bleed post media.
///
/// Aspect ratio is resolved from the first image and clamped to the range
/// [4:5 .. 1.91:1] — tall enough for portrait phone photos without letting
/// one post eat the whole screen, wide enough for landscape. It starts
/// square (matching the old fixed crop, so nothing jumps on cached images)
/// and settles into the true ratio once the decode reports back.
class _NaturalMedia extends StatefulWidget {
  const _NaturalMedia({
    required this.urls,
    required this.page,
    required this.onPageChanged,
    required this.onTap,
    required this.onDoubleTap,
    required this.bloom,
    required this.heroTag,
  });

  final List<String> urls;
  final int page;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final AnimationController bloom;
  final String heroTag;

  @override
  State<_NaturalMedia> createState() => _NaturalMediaState();
}

class _NaturalMediaState extends State<_NaturalMedia> {
  static const double _minRatio = 4 / 5; // tallest we allow
  static const double _maxRatio = 1.91; // widest we allow

  /// Aspect ratios we have already measured, keyed by image URL.
  ///
  /// **This is what stops the feed jumping while you scroll.**
  ///
  /// Without it every card began life at [_fallbackRatio] (square) and only
  /// learned its real shape when the image stream delivered — one frame
  /// later at best, a network round-trip later at worst — at which point
  /// `setState` changed the card's HEIGHT. A portrait phone photo clamps to
  /// 4:5, which is taller than square, so the card GREW after it had already
  /// been laid out.
  ///
  /// A card growing below the viewport is invisible. A card growing ABOVE it
  /// pushes everything down while the scroll offset stays where it was, so
  /// the reader is carried backwards — the reported "it takes you up like 3
  /// posts". And because a ListView rebuilds cards as they recycle, each one
  /// restarted at square and re-measured EVERY time it came back around,
  /// which is why it happened repeatedly and only while scrolling.
  ///
  /// Measuring is unavoidable (the natural aspect ratio is the whole point
  /// of this widget — see the class doc and CLAUDE.md), but measuring the
  /// same image twice is not. Once a URL's ratio is known, a rebuilt card
  /// gets the correct height in `initState`, before its first layout, and
  /// never resizes at all.
  ///
  /// Process-lifetime and unbounded-by-design: it holds one double per image
  /// URL seen this session, which is far smaller than the image cache that
  /// already holds those same pictures.
  static final Map<String, double> _ratioCache = <String, double>{};

  /// Square, used only for an image whose size we have never resolved.
  static const double _fallbackRatio = 1.0;

  final PageController _pc = PageController();
  ImageStream? _stream;
  ImageStreamListener? _listener;
  late double _ratio;

  /// True when [_ratio] was already correct at first build, so the size
  /// change [AnimatedSize] exists to smooth never happens.
  bool _ratioWasKnown = false;

  @override
  void initState() {
    super.initState();
    final cached = _ratioCache[widget.urls.first];
    _ratioWasKnown = cached != null;
    _ratio = cached ?? _fallbackRatio;
    // Still resolve when it was cached — the listener returns early if the
    // measurement agrees, and this keeps the cache honest if a URL is ever
    // re-pointed at different bytes.
    _resolveRatio();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _pc.dispose();
    super.dispose();
  }

  /// Reads the intrinsic size off the first image. Goes through the shared
  /// cache manager, so for an already-cached photo this is a memory hit and
  /// resolves before the first frame is even visible.
  void _resolveRatio() {
    final provider = CachedNetworkImageProvider(
      widget.urls.first,
      cacheManager: adventImageCacheManager,
    );
    _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener((info, _) {
      final h = info.image.height;
      if (h == 0) return;
      final r = (info.image.width / h).clamp(_minRatio, _maxRatio);
      // Remember it even if this card is already gone — the next card to
      // show this image is the one that benefits, and during a fast scroll
      // that is exactly the card that got disposed mid-measurement.
      _ratioCache[widget.urls.first] = r;
      if (!mounted) return;
      if ((r - _ratio).abs() < 0.01) return;
      setState(() => _ratio = r);
    }, onError: (_, _) {});
    _stream!.addListener(_listener!);
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.urls.length > 1;
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: AnimatedSize(
        // Zero when the ratio was already known at first build. AnimatedSize
        // exists to soften the one-time settle from square to the photo's
        // real shape; if there is no settle, animating is not smoothing
        // anything — it is re-introducing the height change over 300ms on
        // every recycled card, which is the jitter itself.
        duration: _ratioWasKnown
            ? Duration.zero
            : AppMotion.maybe(context, AppMotion.standard),
        curve: AppMotion.ease,
        child: AspectRatio(
          aspectRatio: _ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!multi)
                Hero(tag: widget.heroTag, child: _photo(widget.urls.first))
              else
                PageView.builder(
                  controller: _pc,
                  itemCount: widget.urls.length,
                  onPageChanged: (i) {
                    HapticFeedback.selectionClick();
                    widget.onPageChanged(i);
                  },
                  itemBuilder: (context, i) => i == 0
                      ? Hero(tag: widget.heroTag, child: _photo(widget.urls[i]))
                      : _photo(widget.urls[i]),
                ),
              if (multi)
                Positioned(
                  top: AppSpace.md,
                  right: AppSpace.md,
                  child: _CountPill(
                    label: '${widget.page + 1}/${widget.urls.length}',
                  ),
                ),
              if (multi)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpace.md,
                  child: _PageDots(
                    count: widget.urls.length,
                    index: widget.page,
                  ),
                ),
              // Double-tap bloom.
              Center(
                child: AnimatedBuilder(
                  animation: widget.bloom,
                  builder: (context, _) {
                    final v = widget.bloom.value;
                    if (v == 0) return const SizedBox.shrink();
                    // Grow fast, hold, then fade.
                    final scale = v < 0.35
                        ? Curves.easeOutBack.transform(v / 0.35) * 1.2
                        : 1.2;
                    final opacity = v < 0.6 ? 1.0 : 1.0 - (v - 0.6) / 0.4;
                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale,
                        child: Icon(
                          Icons.favorite,
                          size: 92,
                          color: AppColors.white.withValues(alpha: 0.92),
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
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

  Widget _photo(String url) => CachedImage(
    url,
    fit: BoxFit.cover,
    errorBuilder: (ctx, _, _) => Container(
      color: ctx.palette.cardMuted,
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: AppColors.primaryBlue,
      ),
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppMotion.maybe(context, AppMotion.quick),
            curve: AppMotion.ease,
            width: i == index ? 16 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: i == index ? 0.95 : 0.5),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Like / Amen / Praying picker.
///
/// A sheet rather than a floating tray on purpose: it can't mis-position on
/// any screen size, it handles dismissal and back-navigation correctly, and
/// it stays reachable one-handed on a tall phone.
///
/// Returns the chosen reaction, or null if dismissed. Choosing the one you
/// already have is returned as-is; the caller decides that means "remove".
Future<PostReaction?> showReactionTray(
  BuildContext context, {
  PostReaction? current,
}) {
  return showModalBottomSheet<PostReaction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ReactionTray(current: current),
  );
}

class _ReactionTray extends StatelessWidget {
  const _ReactionTray({required this.current});
  final PostReaction? current;

  static const _order = [
    PostReaction.like,
    PostReaction.amen,
    PostReaction.praying,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpace.md),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          boxShadow: AppShadows.floating(context),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < _order.length; i++)
              _TrayOption(
                reaction: _order[i],
                selected: _order[i] == current,
                index: i,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).pop(_order[i]);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TrayOption extends StatelessWidget {
  const _TrayOption({
    required this.reaction,
    required this.selected,
    required this.index,
    required this.onTap,
  });

  final PostReaction reaction;
  final bool selected;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = switch (reaction) {
      PostReaction.like => Icons.favorite,
      PostReaction.amen => Icons.volunteer_activism,
      PostReaction.praying => Icons.front_hand,
    };
    // Each option pops in slightly after the one before it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.maybe(
        context,
        Duration(milliseconds: 220 + index * 60),
      ),
      curve: AppMotion.spring,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.9,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.primaryGradient : null,
                  color: selected
                      ? null
                      : AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 26,
                  color: selected ? AppColors.white : AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                reaction.label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.text,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status ring around an avatar: brand gradient when there's an unviewed
/// story, grey once it's been viewed, nothing when no story.
class _StoryRing extends StatelessWidget {
  const _StoryRing({
    required this.hasStory,
    required this.viewed,
    required this.child,
  });
  final bool hasStory;
  final bool viewed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!hasStory) return child;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: viewed ? null : AppColors.primaryGradient,
        border: viewed
            ? Border.all(color: context.palette.divider, width: 2)
            : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.palette.card,
        ),
        child: child,
      ),
    );
  }
}

/// Avatar for a Page post: its logo as a rounded square — so an
/// organization never reads as a person — else its initials.
class _PageAvatar extends StatelessWidget {
  const _PageAvatar({required this.name, this.logoUrl});
  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.isEmpty
        ? '?'
        : words.take(2).map((w) => w[0].toUpperCase()).join();
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Center(
        child: Text(
          initials,
          style: AppTextStyles.labelLarge.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: 44,
        child: (logoUrl ?? '').isEmpty
            ? fallback
            : CachedImage(
                logoUrl!,
                fit: BoxFit.cover,
                width: 44,
                height: 44,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Avatar for a church-branded post. Shows the church's uploaded logo once
/// it's set; until then a church glyph on the brand gradient.
class _ChurchAvatar extends StatelessWidget {
  const _ChurchAvatar({this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: hasPhoto
          ? CachedImage(photoUrl!, fit: BoxFit.cover, width: 44, height: 44)
          : const Icon(Icons.church, color: AppColors.white, size: 22),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();
    final fallback = Text(
      initial,
      style: AppTextStyles.titleMedium.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
    );
    return Container(
      // 44 to match the church avatar — they were 42 vs 44 and the 2px
      // difference made church posts sit imperceptibly out of line.
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      alignment: Alignment.center,
      child: url == null || url.isEmpty
          ? fallback
          : CachedImage(
              url,
              fit: BoxFit.cover,
              width: 44,
              height: 44,
              errorBuilder: (context, _, _) => Center(child: fallback),
            ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.primaryBlue : context.palette.text;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      pressedScale: 0.92,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon swap (heart outline -> filled) lands with a spring pop
            // instead of an instant flip.
            AnimatedSwitcher(
              duration: AppMotion.maybe(context, AppMotion.quick),
              switchInCurve: AppMotion.spring,
              switchOutCurve: AppMotion.easeIn,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(icon, key: ValueKey(icon), size: 18, color: color),
            ),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one ⋯ menu for every post, owner or not (redesign brief, 28 Oct
/// 2026). Items depend on who is looking:
///   owner  → Save, Copy link, Edit, Audience, Save photos, Delete
///   others → Save, Copy link, Hide post, Save photos, Report (+ admin)
/// Save, Copy link and Hide are handled by the card itself so they behave
/// the same on every surface; the rest are the host's callbacks.
class _PostMenu extends StatelessWidget {
  const _PostMenu({
    required this.isOwner,
    required this.authorFirstName,
    required this.followsAuthor,
    required this.onToggleFollow,
    required this.isFriendsOnly,
    required this.saved,
    required this.onToggleSaved,
    required this.onCopyLink,
    this.onHide,
    this.onEdit,
    this.onDelete,
    this.onToggleVisibility,
    this.onSaveImage,
    this.photoCount = 0,
    this.onReport,
    this.onAdminModerate,
    this.isModerated = false,
  });

  final bool isOwner;
  final String authorFirstName;
  final bool? followsAuthor;
  final VoidCallback onToggleFollow;
  final bool isFriendsOnly;
  final bool saved;
  final VoidCallback onToggleSaved;
  final VoidCallback onCopyLink;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onSaveImage;

  /// Label only: on an album "Save to gallery" read as saving one photo.
  final int photoCount;
  final VoidCallback? onReport;
  final VoidCallback? onAdminModerate;
  final bool isModerated;

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label, {
    Color color = AppColors.primaryBlue,
    bool danger = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: danger ? AppColors.red : color),
          const SizedBox(width: 10),
          Text(
            label,
            style: danger ? const TextStyle(color: AppColors.red) : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photosLabel = photoCount > 1
        ? 'Save all $photoCount photos'
        : 'Save to gallery';
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: context.palette.textMuted, size: 20),
      tooltip: isOwner ? 'Manage post' : 'More',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      onSelected: (value) {
        switch (value) {
          case 'bookmark':
            onToggleSaved();
          case 'copy':
            onCopyLink();
          case 'hide':
            onHide?.call();
          case 'follow':
            onToggleFollow();
          case 'edit':
            onEdit?.call();
          case 'visibility':
            onToggleVisibility?.call();
          case 'save_image':
            onSaveImage?.call();
          case 'delete':
            onDelete?.call();
          case 'report':
            onReport?.call();
          case 'moderate':
            onAdminModerate?.call();
        }
      },
      itemBuilder: (ctx) => [
        _item(
          'bookmark',
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          saved ? 'Remove from Saved' : 'Save post',
        ),
        _item('copy', Icons.link_rounded, 'Copy link'),
        if (isOwner) ...[
          if (onEdit != null) _item('edit', Icons.edit_outlined, 'Edit post'),
          if (onToggleVisibility != null)
            _item(
              'visibility',
              isFriendsOnly ? Icons.public : Icons.people_alt_outlined,
              isFriendsOnly ? 'Make public' : 'Show friends only',
            ),
        ] else ...[
          if (followsAuthor != null)
            _item(
              'follow',
              followsAuthor!
                  ? Icons.person_remove_outlined
                  : Icons.person_add_alt_1_outlined,
              followsAuthor!
                  ? 'Unfollow $authorFirstName'
                  : 'Follow $authorFirstName',
            ),
          if (onHide != null)
            _item('hide', Icons.visibility_off_outlined, 'Hide post'),
        ],
        if (onSaveImage != null)
          _item('save_image', Icons.download_outlined, photosLabel),
        if (isOwner && onDelete != null)
          _item('delete', Icons.delete_outline, 'Delete post', danger: true),
        if (!isOwner && onReport != null)
          _item('report', Icons.flag_outlined, 'Report post', danger: true),
        if (!isOwner && onAdminModerate != null)
          _item(
            'moderate',
            isModerated
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            isModerated ? 'Restore post (admin)' : 'Hide post (admin)',
            danger: true,
          ),
      ],
    );
  }
}
