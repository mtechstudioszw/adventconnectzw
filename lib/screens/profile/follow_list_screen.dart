import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/photo_url.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/verified_tick.dart';

enum FollowListTab { followers, following, requests }

/// Followers / Following for any member, and — on your own account — the
/// follow requests waiting for approval (patch_274).
///
/// Every list comes from a server function that applies the privacy rule,
/// so a private profile's lists come back empty for people who may not see
/// them; this screen says so rather than implying nobody follows them.
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    this.initialTab = FollowListTab.followers,
    this.name,
  }) : requestsOnly = false;

  /// Your pending follow requests (opened from a notification or your
  /// own Followers list).
  const FollowListScreen.requests({super.key})
    : userId = '',
      initialTab = FollowListTab.requests,
      name = null,
      requestsOnly = true;

  final String userId;
  final FollowListTab initialTab;
  final String? name;
  final bool requestsOnly;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  late FollowListTab _tab = widget.initialTab;
  final Map<FollowListTab, List<FollowPerson>> _lists = {};
  final Map<FollowListTab, String?> _errors = {};
  final Set<String> _busy = {};
  bool _loading = true;

  String? get _me => AuthService.currentUser?.id;
  bool get _isMine => widget.requestsOnly || widget.userId == _me;

  List<FollowListTab> get _tabs => widget.requestsOnly
      ? const [FollowListTab.requests]
      : [
          FollowListTab.followers,
          FollowListTab.following,
          if (_isMine) FollowListTab.requests,
        ];

  @override
  void initState() {
    super.initState();
    _load(_tab);
  }

  Future<void> _load(FollowListTab tab) async {
    setState(() {
      _loading = true;
      _errors[tab] = null;
    });
    try {
      final people = switch (tab) {
        FollowListTab.followers => await FollowService.list(
          widget.userId,
          'followers',
        ),
        FollowListTab.following => await FollowService.list(
          widget.userId,
          'following',
        ),
        FollowListTab.requests => await FollowService.myRequests(),
      };
      if (!mounted) return;
      setState(() {
        _lists[tab] = people;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errors[tab] = FollowService.available
            ? 'Could not load this list. Pull down to try again.'
            : 'Following needs a database update (patch_274) before it '
                  'can be used.';
      });
    }
  }

  void _select(FollowListTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (!_lists.containsKey(tab)) _load(tab);
  }

  Future<void> _run(
    FollowPerson p,
    Future<void> Function() action,
    String failMsg,
  ) async {
    setState(() => _busy.add(p.userId));
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busy.remove(p.userId);
        _lists[_tab] = [
          for (final x in _lists[_tab] ?? const <FollowPerson>[])
            if (x.userId != p.userId) x,
        ];
        // An approved request is now a follower; reload that tab next time.
        if (_tab == FollowListTab.requests) {
          _lists.remove(FollowListTab.followers);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy.remove(p.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.red, content: Text(failMsg)),
      );
    }
  }

  String _title() {
    if (widget.requestsOnly) return 'Follow requests';
    final n = (widget.name ?? '').trim();
    if (_isMine || n.isEmpty) return 'Connections';
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final people = _lists[_tab];
    final error = _errors[_tab];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: () => _load(_tab),
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ScreenHero(
              title: _title(),
              tagline: widget.requestsOnly ? 'PROFILE' : 'FOLLOWERS',
              fallbackRoute: 'profile',
            ),
            if (_tabs.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    for (final t in _tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TabChip(
                          label: switch (t) {
                            FollowListTab.followers => 'Followers',
                            FollowListTab.following => 'Following',
                            FollowListTab.requests => 'Requests',
                          },
                          selected: t == _tab,
                          onTap: () => _select(t),
                        ),
                      ),
                  ],
                ),
              ),
            if (_loading && people == null)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: BrandSpinner(size: 30)),
              )
            else if (error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStateCard(
                  icon: Icons.people_outline,
                  title: "Can't show this list",
                  message: error,
                ),
              )
            else if ((people ?? const []).isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStateCard(
                  icon: _tab == FollowListTab.requests
                      ? Icons.how_to_reg_outlined
                      : Icons.people_outline,
                  title: switch (_tab) {
                    FollowListTab.followers => 'No followers to show',
                    FollowListTab.following => 'Not following anyone',
                    FollowListTab.requests => 'No requests',
                  },
                  message: switch (_tab) {
                    FollowListTab.requests =>
                      'When your account is private, people who ask to '
                          'follow you appear here for approval.',
                    _ when _isMine =>
                      _tab == FollowListTab.followers
                          ? 'When people follow you, they appear here.'
                          : 'Follow members to see their public posts in '
                                'your feed.',
                    _ =>
                      'Nothing to show. If this account is private, only '
                          'approved followers and friends can see its lists.',
                  },
                ),
              )
            else ...[
              for (final p in people!)
                _PersonRow(
                  person: p,
                  busy: _busy.contains(p.userId),
                  onOpen: () => context.pushNamed(
                    'user_profile',
                    pathParameters: {'userId': p.userId},
                  ),
                  trailing: _trailingFor(p, palette),
                ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  /// Owner-only actions. Viewing someone else's lists is read-only.
  List<Widget> _trailingFor(FollowPerson p, AppPalette palette) {
    if (!_isMine) return const [];
    switch (_tab) {
      case FollowListTab.requests:
        return [
          _SmallButton(
            label: 'Approve',
            primary: true,
            onTap: () => _run(
              p,
              () => FollowService.approve(p.userId),
              'Could not approve the request.',
            ),
          ),
          const SizedBox(width: 6),
          _SmallButton(
            label: 'Decline',
            onTap: () => _run(
              p,
              () => FollowService.removeFollower(p.userId),
              'Could not decline the request.',
            ),
          ),
        ];
      case FollowListTab.followers:
        return [
          _SmallButton(
            label: 'Remove',
            onTap: () => _run(
              p,
              () => FollowService.removeFollower(p.userId),
              'Could not remove this follower.',
            ),
          ),
        ];
      case FollowListTab.following:
        return [
          _SmallButton(
            label: 'Unfollow',
            onTap: () => _run(
              p,
              () => FollowService.unfollow(p.userId),
              'Could not unfollow.',
            ),
          ),
        ];
    }
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? AppColors.primaryBlue : palette.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: selected ? null : Border.all(color: palette.divider),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelLarge.copyWith(
              color: selected ? AppColors.white : palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.onOpen,
    required this.trailing,
    required this.busy,
  });
  final FollowPerson person;
  final VoidCallback onOpen;
  final List<Widget> trailing;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final initial = person.fullName.isEmpty
        ? '?'
        : person.fullName.substring(0, 1).toUpperCase();
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Center(
        child: Text(
          initial,
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: (person.photoUrl ?? '').isEmpty
                    ? fallback
                    : CachedNetworkImage(
                        imageUrl: photoUrlAtSize(person.photoUrl, 144),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => fallback,
                        errorWidget: (_, _, _) => fallback,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          person.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (person.isVerified) const VerifiedTick(size: 14),
                    ],
                  ),
                  if ((person.username ?? '').isNotEmpty)
                    Text(
                      '@${person.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              ...trailing,
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: primary ? AppColors.primaryBlue : palette.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: primary ? null : Border.all(color: palette.divider),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: primary ? AppColors.white : palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
