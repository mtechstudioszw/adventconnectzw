import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/countries.dart';
import '../../config/share_config.dart';
import '../../models/org_page_model.dart';
import '../../models/post_model.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/follow_service.dart';
import '../../services/page_service.dart';
import '../../services/seller_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/date_format.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/home/report_sheet.dart';
import '../../widgets/moderation_appeal_sheet.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/profile/post_alerts.dart';
import '../../widgets/profile/profile_header.dart';
import '../../widgets/screen_shell.dart';

/// An organization Page (brief §9): cover + logo, name, category,
/// verification, Follow / Contact, follower count, Posts / About / Photos,
/// and — for its admins — Post, Edit and Manage admins.
///
/// Reuses the profile header and the shared post card so a Page reads as
/// part of the same app, while the category line and logo make it clear
/// this is an organization, not a person.
class PageDetailsScreen extends StatefulWidget {
  const PageDetailsScreen({super.key, required this.pageId, this.initial});

  final String pageId;
  final OrgPage? initial;

  @override
  State<PageDetailsScreen> createState() => _PageDetailsScreenState();
}

enum _Tab { posts, about, photos }

class _PageDetailsScreenState extends State<PageDetailsScreen> {
  OrgPage? _page;
  PageStats _stats = PageStats.empty;
  List<Post> _posts = const [];
  bool _loading = true;
  bool _followBusy = false;
  bool _isSuperAdmin = false;
  String? _error;
  _Tab _tab = _Tab.posts;

  @override
  void initState() {
    super.initState();
    _page = widget.initial;
    _load();
    if (FollowService.mutedAlerts.value == null) {
      FollowService.loadAlertMutes();
    }
    SellerService.isCurrentUserSuperAdmin().then((v) {
      if (mounted && v) setState(() => _isSuperAdmin = true);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = _page == null;
      _error = null;
    });
    try {
      final page = await PageService.fetch(widget.pageId);
      if (!mounted) return;
      if (page == null) {
        setState(() {
          _loading = false;
          _error = 'This Page is unavailable.';
        });
        return;
      }
      setState(() {
        _page = page;
        _loading = false;
      });
      final results = await Future.wait([
        PageService.stats(widget.pageId),
        PageService.posts(widget.pageId),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as PageStats;
        _posts = results[1] as List<Post>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error ??= _page == null
            ? (PageService.messageFor(e) ?? 'Could not load this Page.')
            : null;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? AppColors.red : null,
        content: Text(msg),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    final was = _stats;
    setState(() => _followBusy = true);
    try {
      if (was.iFollow) {
        await PageService.unfollow(widget.pageId);
      } else {
        await PageService.follow(widget.pageId);
      }
      if (!mounted) return;
      setState(() {
        _followBusy = false;
        _stats = PageStats(
          followers: (was.followers + (was.iFollow ? -1 : 1)).clamp(0, 1 << 30),
          iFollow: !was.iFollow,
          myRole: was.myRole,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      _snack(
        PageService.messageFor(e) ?? "Couldn't update. Try again.",
        error: true,
      );
    }
  }

  Future<void> _compose() async {
    final page = _page;
    if (page == null) return;
    final post = await showPostComposer(context, page: page);
    if (post == null || !mounted) return;
    setState(() => _posts = [post, ..._posts]);
  }

  Future<void> _share() async {
    final page = _page;
    if (page == null) return;
    // No web preview exists for Pages yet, so share the app link with the
    // Page named — never a link that 404s.
    await Share.share(
      '${page.name} on Adventist Super App\n$appDownloadUrl',
      subject: page.name,
    );
  }

  Future<void> _contact() async {
    final page = _page!;
    final palette = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (page.contactPhone != null) ...[
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: const Text('Call'),
                subtitle: Text(page.contactPhone!),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri(scheme: 'tel', path: page.contactPhone));
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: const Text('WhatsApp'),
                onTap: () {
                  Navigator.pop(ctx);
                  final digits = page.contactPhone!.replaceAll(
                    RegExp(r'[^0-9]'),
                    '',
                  );
                  launchUrl(
                    Uri.parse('https://wa.me/$digits'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ],
            if (page.contactEmail != null)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('Email'),
                subtitle: Text(page.contactEmail!),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri(scheme: 'mailto', path: page.contactEmail));
                },
              ),
            if (page.website != null)
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: const Text('Website'),
                subtitle: Text(websiteLabel(page.website!)),
                onTap: () {
                  Navigator.pop(ctx);
                  openProfileWebsite(page.website!);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool get _hasContact {
    final p = _page;
    return p != null &&
        (p.contactPhone != null || p.contactEmail != null || p.website != null);
  }

  Future<void> _more() async {
    final page = _page!;
    final palette = context.palette;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Share Page'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            if (_stats.canEdit) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Page'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Page admins'),
                onTap: () => Navigator.pop(ctx, 'admins'),
              ),
            ] else ...[
              if (_stats.iFollow && alertsMuted('page', page.id) != null)
                ListTile(
                  leading: Icon(
                    alertsMuted('page', page.id)!
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                  ),
                  title: Text(
                    alertsMuted('page', page.id)!
                        ? 'Turn post alerts back on'
                        : 'Mute post alerts',
                  ),
                  subtitle: const Text(
                    "Notifications when this Page posts. You'll still follow "
                    'it.',
                  ),
                  onTap: () => Navigator.pop(ctx, 'alerts'),
                ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.red),
                title: const Text(
                  'Report Page',
                  style: TextStyle(color: AppColors.red),
                ),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
            ],
            if (_isSuperAdmin) ...[
              ListTile(
                leading: Icon(
                  page.isVerified
                      ? Icons.remove_moderator_outlined
                      : Icons.verified_outlined,
                ),
                title: Text(
                  page.isVerified
                      ? 'Remove verification (admin)'
                      : 'Verify organization (admin)',
                ),
                onTap: () => Navigator.pop(ctx, 'verify'),
              ),
              ListTile(
                leading: Icon(
                  page.isHidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.red,
                ),
                title: Text(
                  page.isHidden ? 'Restore Page (admin)' : 'Hide Page (admin)',
                  style: const TextStyle(color: AppColors.red),
                ),
                onTap: () => Navigator.pop(ctx, 'hide'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'share':
        await _share();
      case 'alerts':
        await toggleAlertMute(
          context,
          type: 'page',
          id: page.id,
          name: page.name,
        );
      case 'edit':
        await context.pushNamed(
          'page_edit',
          pathParameters: {'id': page.id},
          extra: page,
        );
        if (mounted) _load();
      case 'admins':
        await context.pushNamed(
          'page_admins',
          pathParameters: {'id': page.id},
          extra: _stats.isOwner,
        );
      case 'report':
        await showReportSheet(
          context,
          contentType: 'page',
          contentId: page.id,
          contentLabel: 'this Page',
        );
      case 'verify':
        await _adminSet(verified: !page.isVerified, hidden: page.isHidden);
      case 'hide':
        String? reason;
        if (!page.isHidden) {
          reason = await showModerationReasonDialog(
            context,
            what: 'Page',
            defaultReason: 'This Page breaks the community guidelines.',
          );
          if (reason == null) return;
        }
        await _adminSet(
          verified: page.isVerified,
          hidden: !page.isHidden,
          reason: reason,
        );
    }
  }

  Future<void> _adminSet({
    required bool verified,
    required bool hidden,
    String? reason,
  }) async {
    try {
      await PageService.adminSetState(
        widget.pageId,
        verified: verified,
        hidden: hidden,
        reason: reason,
      );
      if (mounted) _load();
    } catch (_) {
      if (mounted) _snack("Couldn't update the Page.", error: true);
    }
  }

  Future<void> _toggleLike(Post post) async {
    final liked = !post.viewerLiked;
    void apply(Post p) => setState(() {
      _posts = [for (final x in _posts) x.id == p.id ? p : x];
    });
    apply(
      post.copyWith(
        viewerReaction: liked ? PostReaction.like : null,
        likeCount: (post.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
      ),
    );
    try {
      if (liked) {
        await FeedService.likePost(post.id);
      } else {
        await FeedService.unlikePost(post.id);
      }
    } catch (_) {
      if (mounted) apply(post);
    }
  }

  Future<void> _deletePost(Post post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this update?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FeedService.deletePost(post.id);
      if (!mounted) return;
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
    } catch (_) {
      if (mounted) _snack("Couldn't delete it.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: _loading
            ? const Center(child: BrandSpinner(size: 30))
            : Column(
                children: [
                  const ScreenHero(title: 'Page', fallbackRoute: 'pages'),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateCard(
                      icon: Icons.apartment_rounded,
                      title: 'Page unavailable',
                      message: _error ?? 'This Page is unavailable.',
                    ),
                  ),
                ],
              ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ProfileGlow(
              photoUrl: page.logoUrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_topBar(page), _header(page)],
              ),
            ),
            if (page.isHidden) _hiddenBanner(page),
            const SizedBox(height: 16),
            _tabs(),
            const SizedBox(height: 8),
            ..._tabContent(page),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _topBar(OrgPage page) => FlatStatusBar(
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
        child: Row(
          children: [
            const ScreenHeroBackButton(),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                page.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header(OrgPage page) {
    final place = [
      page.city,
      if (page.country != null) Countries.nameOf(page.country),
    ].where((s) => (s ?? '').isNotEmpty).join(', ');
    return ProfileHeader(
      name: page.name,
      initials: page.initials,
      photoUrl: page.logoUrl,
      coverUrl: page.coverUrl,
      bio: page.description,
      verified: page.isVerified,
      relationNote: page.category.label,
      squareAvatar: true,
      facts: [
        if (place.isNotEmpty)
          ProfileFact(
            Icons.location_on_outlined,
            '${Countries.flagOf(page.country)} $place'.trim(),
          ),
        if (page.serviceArea != null)
          ProfileFact(Icons.map_outlined, page.serviceArea!),
        if (page.website != null)
          ProfileFact(
            Icons.link_rounded,
            websiteLabel(page.website!),
            onTap: () => openProfileWebsite(page.website!),
          ),
      ],
      stats: [
        ProfileStat('Followers', _stats.followers),
        ProfileStat(_posts.length == 1 ? 'Update' : 'Updates', _posts.length),
      ],
      onAvatarTap: page.logoUrl == null
          ? null
          : () => FullImageViewer.show(context, page.logoUrl),
      onCoverTap: page.coverUrl == null
          ? null
          : () => FullImageViewer.show(context, page.coverUrl),
      actions: _stats.canEdit
          ? [
              ProfileActionButton(
                label: 'Post update',
                icon: Icons.edit_note_rounded,
                primary: true,
                onTap: page.isHidden ? null : _compose,
              ),
              // Edit lives in the studio and the ⋯ menu now.
              ProfileActionButton(
                label: 'Studio',
                icon: Icons.dashboard_customize_outlined,
                onTap: () async {
                  await context.pushNamed(
                    'page_studio',
                    pathParameters: {'id': page.id},
                    extra: page,
                  );
                  if (mounted) _load();
                },
              ),
              ProfileActionButton.icon(
                icon: Icons.more_horiz,
                label: 'More',
                onTap: _more,
              ),
            ]
          : [
              ProfileActionButton(
                label: _stats.iFollow ? 'Following' : 'Follow',
                icon: _stats.iFollow ? Icons.check_rounded : Icons.add_rounded,
                primary: !_stats.iFollow,
                busy: _followBusy,
                onTap: _toggleFollow,
              ),
              if (_hasContact)
                ProfileActionButton(
                  label: 'Contact',
                  icon: Icons.call_outlined,
                  onTap: _contact,
                ),
              ProfileActionButton.icon(
                icon: Icons.more_horiz,
                label: 'More',
                onTap: _more,
              ),
            ],
    );
  }

  Widget _hiddenBanner(OrgPage page) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Hidden by the moderators — only this Page\'s admins can see it.'
        '${page.moderationReason == null ? '' : '\nReason: ${page.moderationReason}'}'
        '\nIf you think this is a mistake, contact support from Settings.',
        style: AppTextStyles.bodySmall.copyWith(
          color: context.palette.text,
          height: 1.4,
        ),
      ),
    ),
  );

  Widget _tabs() {
    final palette = context.palette;
    Widget tab(_Tab t, String label) {
      final selected = _tab == t;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = t),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          tab(_Tab.posts, 'Posts'),
          tab(_Tab.about, 'About'),
          tab(_Tab.photos, 'Photos'),
        ],
      ),
    );
  }

  List<Widget> _tabContent(OrgPage page) {
    final palette = context.palette;
    switch (_tab) {
      case _Tab.posts:
        if (_posts.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: Icons.campaign_outlined,
                title: 'No updates yet',
                message: _stats.canEdit
                    ? 'Share news, events and announcements as ${page.name}. '
                          'Followers see them in their feed.'
                    : 'Follow this Page to see its updates when they post.',
              ),
            ),
          ];
        }
        final me = AuthService.currentUser?.id;
        return [
          for (final post in _posts)
            PostCard(
              post: post,
              viewerId: me,
              onLikeToggled: () => _toggleLike(post),
              onCommentsTapped: () => showCommentsSheet(
                context,
                postId: post.id,
                postAuthorId: post.authorId,
                onCommentCountChanged: (n) => setState(() {
                  _posts = [
                    for (final x in _posts)
                      x.id == post.id ? x.copyWith(commentCount: n) : x,
                  ];
                }),
              ),
              onImageTapped: (i) {
                final images = post.imageUrls;
                if (images.isEmpty) return;
                final safe = i.clamp(0, images.length - 1);
                PostImageViewer.show(
                  context,
                  imageUrl: images[safe],
                  heroTag: 'page_${post.id}_$safe',
                );
              },
              onDelete: post.authorId == me ? () => _deletePost(post) : null,
              onReport: () => showReportSheet(
                context,
                contentType: 'post',
                contentId: post.id,
                contentLabel: 'this post',
              ),
            ),
        ];
      case _Tab.about:
        final rows = <(IconData, String, String)>[
          (page.category.icon, 'Category', page.category.label),
          if (page.serviceArea != null)
            (Icons.map_outlined, 'Serves', page.serviceArea!),
          if (page.city != null || page.country != null)
            (
              Icons.location_on_outlined,
              'Based in',
              [
                page.city,
                if (page.country != null) Countries.nameOf(page.country),
              ].where((s) => (s ?? '').isNotEmpty).join(', '),
            ),
          if (page.contactEmail != null)
            (Icons.mail_outline, 'Email', page.contactEmail!),
          if (page.contactPhone != null)
            (Icons.call_outlined, 'Phone', page.contactPhone!),
          if (page.website != null)
            (Icons.language_rounded, 'Website', websiteLabel(page.website!)),
          if (page.createdAt != null)
            (
              Icons.calendar_today_outlined,
              'On the app since',
              formatJoinDate(page.createdAt!),
            ),
          (
            page.isVerified ? Icons.verified_outlined : Icons.info_outline,
            'Verification',
            page.isVerified
                ? 'Verified organization — reviewed by the app team'
                : 'Not verified. Verification is a review of the '
                      'organization, not a paid feature.',
          ),
        ];
        return [
          if (page.description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                page.description!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.text,
                  height: 1.5,
                ),
              ),
            ),
          for (final r in rows)
            ListTile(
              leading: Icon(r.$1, color: AppColors.primaryBlue),
              title: Text(
                r.$2,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.textMuted,
                ),
              ),
              subtitle: Text(
                r.$3,
                style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
              ),
            ),
        ];
      case _Tab.photos:
        final photos = [for (final p in _posts) ...p.imageUrls];
        if (photos.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: Icons.photo_library_outlined,
                title: 'No photos yet',
                message: 'Photos from this Page\'s updates appear here.',
              ),
            ),
          ];
        }
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < photos.length; i++)
                  GestureDetector(
                    onTap: () => PostImageViewer.show(
                      context,
                      imageUrl: photos[i],
                      heroTag: 'page_photo_$i',
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.network(
                          photos[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: palette.cardMuted),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ];
    }
  }
}
