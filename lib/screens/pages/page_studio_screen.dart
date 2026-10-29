import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/share_config.dart';
import '../../models/org_page_model.dart';
import '../../models/post_model.dart';
import '../../services/page_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../utils/date_format.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/verified_tick.dart';

/// Page Studio (28 Oct 2026, owner: "how does he manage it — do u have a
/// page studio").
///
/// Managing a Page used to mean finding the Page, then hunting through its
/// ⋯ menu for Edit and Admins. This puts everything an owner or editor does
/// on one screen:
///
/// - **Numbers** — followers (page_stats), and updates, reactions and
///   comments added up from the Page's recent updates. Those three are
///   counted on the device from the same posts the Page shows, so the
///   caption says which updates they cover rather than implying all-time.
/// - **Tools** — post as the Page, edit, admins, share, view.
/// - **Page strength** — what's still missing (logo, cover, about,
///   location, contact, a first update, a second admin), each one a tap
///   away from the screen that fixes it.
/// - **Top update** and **recent updates**, with their reactions/comments.
///
/// No new backend: page_stats, list_page_admins and the Page's posts are
/// all reads that already existed (patch_275).
class PageStudioScreen extends StatefulWidget {
  const PageStudioScreen({super.key, required this.pageId, this.initial});

  final String pageId;
  final OrgPage? initial;

  @override
  State<PageStudioScreen> createState() => _PageStudioScreenState();
}

class _PageStudioScreenState extends State<PageStudioScreen> {
  OrgPage? _page;
  PageStats _stats = PageStats.empty;
  List<Post> _posts = const [];
  List<PageAdmin> _admins = const [];
  bool _loading = true;
  String? _error;

  /// How many recent updates the numbers are added up from.
  static const _window = 50;

  @override
  void initState() {
    super.initState();
    _page = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        PageService.fetch(widget.pageId),
        PageService.stats(widget.pageId),
      ]);
      final page = results[0] as OrgPage?;
      final stats = results[1] as PageStats;
      if (!mounted) return;
      if (page == null) {
        setState(() {
          _loading = false;
          _error = 'This Page no longer exists.';
        });
        return;
      }
      setState(() {
        _page = page;
        _stats = stats;
      });
      if (!stats.canEdit) {
        setState(() => _loading = false);
        return;
      }
      // Each fails alone: a studio without its admin list is still useful.
      final more = await Future.wait<Object?>([
        PageService.posts(
          widget.pageId,
          limit: _window,
        ).catchError((_) => const <Post>[]),
        PageService.admins(
          widget.pageId,
        ).catchError((_) => const <PageAdmin>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _posts = more[0] as List<Post>;
        _admins = more[1] as List<PageAdmin>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load this Page. Pull down to try again.";
      });
    }
  }

  Future<void> _compose() async {
    final page = _page;
    if (page == null || page.isHidden) return;
    final post = await showPostComposer(context, page: page);
    if (post == null || !mounted) return;
    setState(() => _posts = [post, ..._posts]);
  }

  Future<void> _edit() async {
    final page = _page;
    if (page == null) return;
    await context.pushNamed(
      'page_edit',
      pathParameters: {'id': page.id},
      extra: page,
    );
    if (mounted) _load();
  }

  Future<void> _openAdmins() async {
    await context.pushNamed(
      'page_admins',
      pathParameters: {'id': widget.pageId},
      extra: _stats.isOwner,
    );
    if (mounted) _load();
  }

  void _view() => context.pushNamed(
    'page_details',
    pathParameters: {'id': widget.pageId},
    extra: _page,
  );

  Future<void> _share() async {
    final page = _page;
    if (page == null) return;
    // Same link the Page itself shares — no web preview exists for Pages
    // yet, so never a link that 404s.
    await Share.share(
      '${page.name} on Adventist Super App\n$appDownloadUrl',
      subject: page.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: BrandedRefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpace.xxl),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ScreenHero(
                title: 'Page Studio',
                tagline: 'MANAGE',
                subtitle: page?.name,
                fallbackRoute: 'pages',
              ),
              if (_loading && page == null)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: BrandSpinner(size: 30)),
                )
              else if (_error != null)
                _Message(icon: Icons.error_outline_rounded, text: _error!)
              else if (page != null && !_loading && !_stats.canEdit)
                const _Message(
                  icon: Icons.lock_outline_rounded,
                  text:
                      "Only this Page's owners and editors can open its "
                      'studio.',
                )
              else if (page != null)
                ..._body(page),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(OrgPage page) {
    final reactions = _posts.fold<int>(0, (n, p) => n + p.likeCount);
    final comments = _posts.fold<int>(0, (n, p) => n + p.commentCount);
    Post? top;
    for (final p in _posts) {
      final score = p.likeCount + p.commentCount;
      if (score > 0 &&
          (top == null || score > top.likeCount + top.commentCount)) {
        top = p;
      }
    }
    final checks = _strength(page);

    return [
      Padding(
        padding: AppSpace.screenH,
        child: _IdentityCard(page: page, role: _stats.myRole, onView: _view),
      ),
      if (page.isHidden)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _HiddenBanner(reason: page.moderationReason),
        ),
      const SizedBox(height: AppSpace.lg),
      Padding(
        padding: AppSpace.screenH,
        child: _StatsGrid(
          followers: _stats.followers,
          updates: _posts.length,
          reactions: reactions,
          comments: comments,
          loading: _loading,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(
          _posts.length >= _window
              ? 'Reactions and comments from your last $_window updates.'
              : 'Reactions and comments across all your updates.',
          style: AppTextStyles.caption.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ),
      const SizedBox(height: AppSpace.xl),
      const _Label('TOOLS'),
      Padding(
        padding: AppSpace.screenH,
        child: _ToolRow(
          tools: [
            _Tool(
              Icons.edit_note_rounded,
              'Post update',
              page.isHidden ? null : _compose,
              primary: true,
            ),
            _Tool(Icons.edit_outlined, 'Edit Page', _edit),
            _Tool(Icons.admin_panel_settings_outlined, 'Admins', _openAdmins),
            _Tool(Icons.ios_share_rounded, 'Share', _share),
            _Tool(Icons.visibility_outlined, 'View', _view),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.xl),
      const _Label('PAGE STRENGTH'),
      Padding(
        padding: AppSpace.screenH,
        child: _StrengthCard(checks: checks),
      ),
      if (top != null) ...[
        const SizedBox(height: AppSpace.xl),
        const _Label('TOP UPDATE'),
        Padding(
          padding: AppSpace.screenH,
          child: _UpdateRow(post: top, highlight: true, onTap: _view),
        ),
      ],
      const SizedBox(height: AppSpace.xl),
      const _Label('RECENT UPDATES'),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: BrandSpinner(size: 24)),
        )
      else if (_posts.isEmpty)
        Padding(
          padding: AppSpace.screenH,
          child: _EmptyUpdates(onPost: page.isHidden ? null : _compose),
        )
      else
        for (final p in _posts.take(10))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _UpdateRow(post: p, onTap: _view),
          ),
    ];
  }

  List<_Check> _strength(OrgPage page) {
    bool has(String? v) => v != null && v.trim().isNotEmpty;
    return [
      _Check('Add a logo', has(page.logoUrl), _edit),
      _Check('Add a cover photo', has(page.coverUrl), _edit),
      _Check('Say what the Page is about', has(page.description), _edit),
      _Check('Add your town or city', has(page.city), _edit),
      _Check(
        'Add a way to contact you',
        has(page.contactPhone) || has(page.contactEmail) || has(page.website),
        _edit,
      ),
      _Check(
        'Post your first update',
        _posts.isNotEmpty,
        page.isHidden ? null : _compose,
      ),
      // A Page with one admin is locked out the day that person loses
      // their phone.
      _Check('Add a second admin', _admins.length >= 2, _openAdmins),
    ];
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
      child: Column(
        children: [
          Icon(icon, size: 40, color: context.palette.textMuted),
          const SizedBox(height: AppSpace.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, AppSpace.sm),
      child: Row(
        children: [
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Container(height: 1, color: context.palette.divider)),
        ],
      ),
    );
  }
}

BoxDecoration _card(BuildContext context) => BoxDecoration(
  color: context.palette.card,
  borderRadius: BorderRadius.circular(AppRadius.lg),
  border: Border.all(color: context.palette.divider),
  boxShadow: AppShadows.card(context),
);

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.page,
    required this.role,
    required this.onView,
  });

  final OrgPage page;
  final String? role;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final place = [
      page.category.label,
      if (page.city != null) page.city!,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: _card(context),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.button),
                child: page.logoUrl == null
                    ? DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: AppColors.primaryGradient,
                        ),
                        child: Center(
                          child: Text(
                            page.initials,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : CachedImage(page.logoUrl!, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        page.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (page.isVerified) const VerifiedTick(size: 16),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (role != null)
                      _Pill(role == 'owner' ? 'Owner' : 'Editor'),
                    if (page.createdAt != null)
                      _Pill('Since ${formatJoinDate(page.createdAt!)}'),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'View Page',
            onPressed: onView,
            icon: Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.palette.chipBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          color: context.palette.brandBlue,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _HiddenBanner extends StatelessWidget {
  const _HiddenBanner({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    // Red: this is the one urgent thing on the screen — nobody but the
    // Page's admins can see it right now.
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_off_outlined, color: AppColors.red),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Hidden by the moderators — only admins can see it.'
              '${reason == null ? '' : '\nReason: $reason'}',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.text,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.followers,
    required this.updates,
    required this.reactions,
    required this.comments,
    required this.loading,
  });

  final int followers;
  final int updates;
  final int reactions;
  final int comments;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    Widget cell(IconData icon, String label, int value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: _card(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: context.palette.brandBlue),
            const SizedBox(height: AppSpace.sm),
            Text(
              loading ? '–' : _compact(value),
              style: AppTextStyles.headlineMedium.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            cell(Icons.people_outline_rounded, 'Followers', followers),
            const SizedBox(width: AppSpace.md),
            cell(Icons.article_outlined, 'Updates', updates),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            cell(Icons.favorite_border_rounded, 'Reactions', reactions),
            const SizedBox(width: AppSpace.md),
            cell(Icons.mode_comment_outlined, 'Comments', comments),
          ],
        ),
      ],
    );
  }
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 10000) return '${(n / 1000).round()}K';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

@immutable
class _Tool {
  const _Tool(this.icon, this.label, this.onTap, {this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tools});

  final List<_Tool> tools;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      decoration: _card(context),
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final cols = scale > 1.3 ? 3 : tools.length;
          final w = box.maxWidth / cols;
          return Wrap(
            alignment: WrapAlignment.center,
            runSpacing: AppSpace.md,
            children: [
              for (final t in tools)
                SizedBox(
                  width: w,
                  child: _ToolButton(tool: t),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final enabled = tool.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tool.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Pressable(
          onTap: tool.onTap,
          haptics: true,
          pressedScale: 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: tool.primary ? AppColors.primaryGradient : null,
                  color: tool.primary
                      ? null
                      : AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                alignment: Alignment.center,
                child: Icon(
                  tool.icon,
                  size: 22,
                  color: tool.primary
                      ? AppColors.white
                      : context.palette.brandBlue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tool.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _Check {
  const _Check(this.label, this.done, this.onFix);
  final String label;
  final bool done;
  final VoidCallback? onFix;
}

class _StrengthCard extends StatelessWidget {
  const _StrengthCard({required this.checks});

  final List<_Check> checks;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final done = checks.where((c) => c.done).length;
    final all = done == checks.length;
    // Unfinished first: the list is a to-do, not a trophy shelf.
    final ordered = [
      ...checks.where((c) => !c.done),
      ...checks.where((c) => c.done),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: _card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  all
                      ? 'Your Page is all set up'
                      : '$done of ${checks.length} done',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(done * 100 / checks.length).round()}%',
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.brandBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done / checks.length,
              minHeight: 6,
              backgroundColor: palette.chipBg,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final c in ordered)
            InkWell(
              onTap: c.done ? null : c.onFix,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      c.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: c.done
                          ? AppColors.successGreen
                          : palette.textMuted,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        c.label,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: c.done ? palette.textMuted : palette.text,
                          decoration: c.done
                              ? TextDecoration.lineThrough
                              : null,
                          fontWeight: c.done
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!c.done && c.onFix != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: palette.textMuted,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.post,
    required this.onTap,
    this.highlight = false,
  });

  final Post post;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = post.body?.trim() ?? '';
    final photos = post.imageUrls.isNotEmpty
        ? post.imageUrls
        : [if (post.imageUrl != null) post.imageUrl!];
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: _card(context).copyWith(
          border: Border.all(
            color: highlight ? AppColors.primaryBlue : palette.divider,
            width: highlight ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photos.isNotEmpty) ...[
              SizedBox(
                width: 52,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: CachedImage(photos.first, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    body.isNotEmpty
                        ? body
                        : (photos.length > 1
                              ? '${photos.length} photos'
                              : 'Photo update'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.text,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpace.md,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatTimeAgo(post.createdAt),
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      _Count(Icons.favorite_border_rounded, post.likeCount),
                      _Count(Icons.mode_comment_outlined, post.commentCount),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.icon, this.n);

  final IconData icon;
  final int n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.palette.textMuted),
        const SizedBox(width: 3),
        Text(
          _compact(n),
          style: AppTextStyles.caption.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _EmptyUpdates extends StatelessWidget {
  const _EmptyUpdates({required this.onPost});

  final VoidCallback? onPost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: _card(context),
      child: Column(
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 32,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'No updates yet — post one to get your Page going.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
            ),
          ),
          if (onPost != null) ...[
            const SizedBox(height: AppSpace.md),
            Pressable(
              onTap: onPost,
              haptics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Text(
                  'Post your first update',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
