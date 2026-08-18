import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/feed_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/verified_tick.dart';

/// Everyone the viewer is actually friends with.
///
/// The Friends number on Profile has always been a dead figure — the code
/// there said so: "the app has no friends-list screen, and routing this to
/// the member directory would be a different thing wearing the same
/// label". This is that screen, so the number finally goes somewhere.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _search = TextEditingController();

  List<FriendSummary> _friends = const [];
  bool _loading = true;
  String? _error;

  /// Guards the message button against a double-tap opening two threads.
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Unfriending from a profile elsewhere should empty the row here too.
    FeedService.friendshipsChanged.addListener(_load);
  }

  @override
  void dispose() {
    FeedService.friendshipsChanged.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final list = await FeedService.fetchMyFriends();
      if (!mounted) return;
      setState(() {
        _friends = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your friends. Pull to retry.';
      });
    }
  }

  List<FriendSummary> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _friends;
    return _friends
        .where((f) =>
            f.fullName.toLowerCase().contains(q) ||
            (f.churchName ?? '').toLowerCase().contains(q))
        .toList();
  }

  /// Opens (or reuses) the 1:1 thread with this friend.
  ///
  /// This used to push `new_chat` — the people-picker — so tapping the
  /// message icon on a specific friend dumped you on a list of all your
  /// friends and made you find them again. Same primitive every other
  /// "message this person" entry point uses: create-or-reuse, then push
  /// `chat` with the conversation as `extra` so the header renders from
  /// the object we already hold instead of blanking while it refetches.
  Future<void> _openChat(FriendSummary f) async {
    if (_opening) return;
    setState(() => _opening = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: f.userId,
        otherUserName: f.fullName,
        source: 'direct',
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      router.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not open the chat. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _unfriend(FriendSummary f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(
          'Remove ${f.fullName}?',
          style: AppTextStyles.titleMedium
              .copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You\'ll stop seeing each other\'s stories. Your chat history '
          'stays.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: ctx.palette.textMuted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Optimistic — the row leaves immediately, and _load() reconciles.
    setState(() =>
        _friends = _friends.where((x) => x.userId != f.userId).toList());
    try {
      await FeedService.removeFriendship(f.friendshipId);
    } catch (_) {
      if (!mounted) return;
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not remove them. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final visible = _visible;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHero(
                title: 'Friends',
                tagline: 'Your people',
                subtitle: _loading
                    ? 'Loading…'
                    : _friends.length == 1
                        ? '1 friend on Adventist Super App.'
                        : '${_friends.length} friends on Adventist Super App.',
                fallbackRoute: 'profile',
                trailing: ScreenHeroTrailing(
                  icon: Icons.person_add_alt_1_outlined,
                  onTap: () => context.pushNamed('search'),
                ),
              ),
            ),
            // Search only earns its space once the list is long enough to
            // need it.
            if (_friends.length > 8)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: AppTextStyles.bodyLarge,
                    decoration: InputDecoration(
                      hintText: 'Search your friends',
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.primaryBlue,
                      ),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(
                                Icons.close,
                                color: palette.textMuted,
                              ),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                      filled: true,
                      fillColor: palette.inputFill,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 72),
                  child: Center(child: BrandSpinner(size: 30)),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(message: _error!),
                ),
              )
            else if (_friends.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyStateCard(
                    icon: Icons.people_outline,
                    title: 'No friends yet',
                    message:
                        'Find members from your church and around the globe, '
                        'and their stories will show up on your home screen.',
                    action: PrimaryGradientButton(
                      label: 'Find people',
                      icon: Icons.person_search_outlined,
                      onTap: () => context.pushNamed('search'),
                    ),
                  ),
                ),
              )
            else if (visible.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Center(
                    child: Text(
                      'No friend matches "${_search.text.trim()}".',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: palette.textMuted),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final row = _FriendRow(
                      friend: visible[i],
                      onOpen: () => context.pushNamed(
                        'user_profile',
                        pathParameters: {'userId': visible[i].userId},
                      ),
                      onMessage: () => _openChat(visible[i]),
                      onRemove: () => _unfriend(visible[i]),
                    );
                    if (i >= 8) return row;
                    return StaggeredReveal(index: i, rise: 16, child: row);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.onOpen,
    required this.onMessage,
    required this.onRemove,
  });

  final FriendSummary friend;
  final VoidCallback onOpen;
  final VoidCallback onMessage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.divider),
        ),
        child: Row(
          children: [
            _FriendAvatar(photoUrl: friend.photoUrl, name: friend.fullName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          friend.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (friend.isVerified) const VerifiedTick(size: 13),
                    ],
                  ),
                  if ((friend.churchName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      friend.churchName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: palette.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Message',
              icon: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 19,
                color: AppColors.primaryBlue,
              ),
              onPressed: onMessage,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert, size: 19, color: palette.textMuted),
              color: palette.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (v) {
                if (v == 'profile') onOpen();
                if (v == 'remove') onRemove();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'profile', child: Text('View profile')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove friend',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.photoUrl, required this.name});

  final String? photoUrl;
  final String name;

  String get _initials {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials,
        style: AppTextStyles.titleSmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return Container(
      width: 46,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: CachedImage(
        photoUrl!,
        fit: BoxFit.cover,
        width: 46,
        height: 46,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
