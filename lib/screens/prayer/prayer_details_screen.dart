import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/prayer_model.dart';
import '../../services/prayer_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/prayer_card.dart';

class PrayerDetailsScreen extends StatefulWidget {
  const PrayerDetailsScreen({
    super.key,
    required this.prayerId,
    this.initialPrayer,
  });

  final String prayerId;
  final Prayer? initialPrayer;

  @override
  State<PrayerDetailsScreen> createState() => _PrayerDetailsScreenState();
}

class _PrayerDetailsScreenState extends State<PrayerDetailsScreen>
    with SingleTickerProviderStateMixin {
  Prayer? _prayer;
  List<PrayerComment> _comments = [];
  List<PrayingUser> _prayingUsers = [];
  bool _loading = true;
  bool _isPraying = false;
  bool _prayBusy = false;
  String? _error;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  final _commentController = TextEditingController();
  bool _commentBusy = false;
  // patch_035: when the viewer taps "Reply" on a comment we stash the
  // target here so the next post becomes a reply rather than a new
  // top-level comment. Cleared after a successful send or when the
  // user taps the "×" on the reply chip.
  PrayerComment? _replyTo;

  @override
  void initState() {
    super.initState();
    _prayer = widget.initialPrayer;
    _loading = widget.initialPrayer == null;
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _commentController.dispose();
    super.dispose();
  }

  bool _isAuthor(Prayer prayer) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return uid != null && prayer.authorId == uid;
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        PrayerService.fetchPrayerById(widget.prayerId),
        PrayerService.hasPrayed(widget.prayerId),
        PrayerService.fetchComments(widget.prayerId),
        PrayerService.fetchPrayingUsers(widget.prayerId),
      ]);
      if (!mounted) return;
      setState(() {
        _prayer = (results[0] as Prayer?) ?? _prayer;
        _isPraying = results[1] as bool;
        _comments = results[2] as List<PrayerComment>;
        _prayingUsers = results[3] as List<PrayingUser>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this prayer.';
        _loading = false;
      });
    }
  }

  Future<void> _togglePray() async {
    final prayer = _prayer;
    if (prayer == null) return;
    setState(() => _prayBusy = true);
    try {
      // Service returns the authoritative prayer_count after the
      // trigger has fired — trust that instead of doing local +/-1.
      final newCount = _isPraying
          ? await PrayerService.unpray(prayer.id)
          : await PrayerService.pray(prayer.id);
      if (!mounted) return;
      setState(() {
        _isPraying = !_isPraying;
        _prayer = prayer.copyWith(prayerCount: newCount);
      });
      final users = await PrayerService.fetchPrayingUsers(prayer.id);
      if (mounted) setState(() => _prayingUsers = users);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update prayer status.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _prayBusy = false);
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _commentBusy = true);
    final parentId = _replyTo?.id;
    try {
      final comment = await PrayerService.postComment(
        widget.prayerId,
        text,
        parentCommentId: parentId,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, comment];
        _commentController.clear();
        _replyTo = null;
        if (_prayer != null) {
          _prayer = _prayer!.copyWith(commentCount: _prayer!.commentCount + 1);
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not post comment.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _commentBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.goNamed('prayer'),
        ),
        title: Text(
          'Prayer request',
          style: AppTextStyles.appBarTitle,
        ),
        actions: [
          if (_prayer != null && _isAuthor(_prayer!))
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppColors.white),
              tooltip: 'Edit prayer',
              onPressed: () async {
                final updated = await context.pushNamed<bool>(
                  'edit_prayer',
                  extra: _prayer,
                );
                if (updated == true) _bootstrap();
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _prayer == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null && _prayer == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.red),
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _bootstrap();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final prayer = _prayer!;
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: child,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _buildAuthorCard(prayer),
                const SizedBox(height: 12),
                _buildContentCard(prayer),
                const SizedBox(height: 12),
                _buildPrayingButton(),
                const SizedBox(height: 16),
                _buildPrayingList(),
                const SizedBox(height: 16),
                _buildComments(),
              ],
            ),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildAuthorCard(Prayer prayer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          PrayerAvatar(name: prayer.authorName, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prayer.authorName,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatTimeAgo(prayer.createdAt)}  •  ${prayer.prayerCount} praying',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard(Prayer prayer) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        prayer.content,
        style: AppTextStyles.bodyLarge.copyWith(
          fontSize: 15.5,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildPrayingButton() {
    return Center(
      child: PrayingButton(
        isPraying: _isPraying,
        busy: _prayBusy,
        count: _prayer?.prayerCount ?? 0,
        onTap: _togglePray,
      ),
    );
  }

  Widget _buildPrayingList() {
    if (_prayingUsers.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = _prayingUsers.take(8).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Praying together',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: Stack(
              children: [
                for (var i = 0; i < visible.length; i++)
                  Positioned(
                    left: i * 32.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2.5),
                      ),
                      child: PrayerAvatar(
                        name: visible[i].userName,
                        size: 40,
                      ),
                    ),
                  ),
                if (_prayingUsers.length > visible.length)
                  Positioned(
                    left: visible.length * 32.0,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.lightGrey,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2.5),
                      ),
                      child: Text(
                        '+${_prayingUsers.length - visible.length}',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComments() {
    final ownerId = _prayer?.authorId ?? '';
    final tree = PrayerComment.buildTree(_comments);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Words of encouragement',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (tree.isEmpty)
            Text(
              'No comments yet. Be the first to encourage them.',
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.55),
              ),
            )
          else
            for (var i = 0; i < tree.length; i++) ...[
              _CommentTile(
                comment: tree[i],
                isOwner: tree[i].authorId.isNotEmpty &&
                    tree[i].authorId == ownerId,
                onReply: () =>
                    setState(() => _replyTo = tree[i]),
              ),
              for (final reply in tree[i].replies) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 36, top: 10),
                  child: _CommentTile(
                    comment: reply,
                    isOwner: reply.authorId.isNotEmpty &&
                        reply.authorId == ownerId,
                    onReply: () => setState(() => _replyTo = tree[i]),
                    isReply: true,
                  ),
                ),
              ],
              if (i < tree.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    color: Color.fromRGBO(26, 26, 46, 0.06),
                  ),
                ),
            ],
        ],
      ),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.reply,
                        size: 16,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Replying to ${_replyTo!.authorName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: AppColors.primaryBlue,
                        tooltip: 'Cancel reply',
                        onPressed: () => setState(() => _replyTo = null),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  hintText: _replyTo == null
                      ? 'Write encouragement...'
                      : 'Reply to ${_replyTo!.authorName}...',
                  filled: true,
                  fillColor: AppColors.lightGrey,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(
              busy: _commentBusy,
              onTap: _commentBusy ? null : _postComment,
            ),
          ],
        ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isOwner,
    required this.onReply,
    this.isReply = false,
  });
  final PrayerComment comment;
  final bool isOwner;
  final bool isReply;
  final VoidCallback onReply;

  void _openProfile(BuildContext context) {
    if (comment.authorId.isEmpty) return;
    context.pushNamed(
      'user_profile',
      pathParameters: {'userId': comment.authorId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = comment.authorPhotoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final size = isReply ? 30.0 : 36.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openProfile(context),
          child: hasPhoto
              ? ClipOval(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: CachedImage(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) =>
                          PrayerAvatar(name: comment.authorName, size: size),
                    ),
                  ),
                )
              : PrayerAvatar(name: comment.authorName, size: size),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () => _openProfile(context),
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (isOwner) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.goldAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Author',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.goldAccent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text(
                    formatTimeAgo(comment.createdAt),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                comment.content,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.85),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: onReply,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Reply',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null && !busy ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: AppColors.white,
                      size: 18,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
