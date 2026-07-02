import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// In-app notification inbox. DB triggers populate `notifications` when
/// people interact with the user's content (RSVPs, prayers, messages,
/// approvals). FCM push (later) will read the same table.
class NotificationCentreScreen extends StatefulWidget {
  const NotificationCentreScreen({super.key});

  @override
  State<NotificationCentreScreen> createState() =>
      _NotificationCentreScreenState();
}

class _NotificationCentreScreenState extends State<NotificationCentreScreen> {
  bool _loading = true;
  String? _error;
  List<AppNotification> _items = const [];

  /// Categories the user has tapped "See more" on. Collapsed by default.
  final Set<_NotifCategory> _expanded = <_NotifCategory>{};

  /// Active category filter chip. Null = "All".
  _NotifCategory? _filter;

  @override
  void initState() {
    super.initState();
    // Paint the last-known inbox instantly; only show a spinner when
    // there's nothing cached yet.
    final cached = NotificationService.cached();
    if (cached.isNotEmpty) {
      _items = cached;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final items = await NotificationService.fetchAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load notifications. Pull to retry.';
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_items.every((n) => n.isRead)) return;
    try {
      await NotificationService.markAllRead();
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (n) => AppNotification(
                id: n.id,
                title: n.title,
                body: n.body,
                type: n.type,
                referenceId: n.referenceId,
                referenceType: n.referenceType,
                isRead: true,
                createdAt: n.createdAt,
              ),
            )
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not mark all read.', isError: true);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.isRead) {
      // Optimistic: flip in UI first, persist after.
      setState(() {
        _items = _items
            .map(
              (x) => x.id == n.id
                  ? AppNotification(
                      id: x.id,
                      title: x.title,
                      body: x.body,
                      type: x.type,
                      referenceId: x.referenceId,
                      referenceType: x.referenceType,
                      isRead: true,
                      createdAt: x.createdAt,
                    )
                  : x,
            )
            .toList();
      });
      // Fire-and-forget. The optimistic UI is already in place, so a
      // failed mark-read isn't worth a snackbar.
      NotificationService.markRead(n.id).ignore();
    }
    // Announcements / suspensions carry their whole message in the body
    // and have no screen to open — show it in a reader sheet instead of
    // a dead tap. Everything else routes to the relevant screen.
    if (_hasRoute(n)) {
      _routeFor(n);
    } else {
      _openReader(n);
    }
  }

  /// True when [_routeFor] can actually take the user somewhere. Used to
  /// decide between routing and opening the in-place reader sheet.
  bool _hasRoute(AppNotification n) {
    final hasId = (n.referenceId ?? '').isNotEmpty;
    switch (n.referenceType) {
      case 'event':
      case 'prayer':
      case 'conversation':
      case 'job':
      case 'post':
        return hasId;
      case 'friend_request':
      case 'seller':
      case 'church_admin':
        return true;
    }
    return false;
  }

  void _openReader(AppNotification n) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NotificationReaderSheet(item: n),
    );
  }

  void _routeFor(AppNotification n) {
    final id = n.referenceId ?? '';
    switch (n.referenceType) {
      case 'event':
        if (id.isNotEmpty) {
          context.pushNamed('event_details', pathParameters: {'id': id});
        }
        break;
      case 'prayer':
        if (id.isNotEmpty) {
          context.pushNamed('prayer_details', pathParameters: {'id': id});
        }
        break;
      case 'conversation':
        if (id.isNotEmpty) {
          context.pushNamed('chat', pathParameters: {'id': id});
        }
        break;
      case 'job':
        if (id.isNotEmpty) {
          context.pushNamed('job_details', pathParameters: {'id': id});
        }
        break;
      case 'post':
        // Likes & comments all carry the post id — open the post's
        // discussion (the same comments sheet used in the feed).
        if (id.isNotEmpty) {
          showCommentsSheet(context, postId: id, onCommentCountChanged: (_) {});
        }
        break;
      case 'friend_request':
        context.pushNamed('messages', queryParameters: {'tab': 'requests'});
        break;
      case 'seller':
        context.pushNamed('seller_dashboard');
        break;
      case 'church_admin':
        context.pushNamed('admin_login');
        break;
    }
  }

  Future<void> _dismiss(AppNotification n) async {
    final removed = n;
    setState(() => _items = _items.where((x) => x.id != n.id).toList());
    try {
      await NotificationService.delete(n.id);
    } catch (_) {
      if (!mounted) return;
      // Restore on failure so the user isn't lied to.
      setState(
        () =>
            _items = [..._items, removed]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
      _toast('Could not dismiss. Try again.', isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.red : AppColors.successGreen,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.isRead);
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              ScreenHero(
                title: 'Notifications',
                tagline: 'Inbox',
                subtitle: hasUnread
                    ? '${_items.where((n) => !n.isRead).length} new in your inbox.'
                    : 'You\'re all caught up.',
                fallbackRoute: 'home',
                trailing: hasUnread
                    ? ScreenHeroTrailing(
                        icon: Icons.done_all,
                        onTap: _markAllRead,
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) return ErrorBanner(message: _error!);
    if (_items.isEmpty) {
      return EmptyStateCard(
        icon: Icons.notifications_none_outlined,
        title: 'No notifications yet',
        message:
            'When someone RSVPs your event, prays for your request or messages you, you\'ll see it here.',
      );
    }
    // Group by source so the inbox reads as sections rather than one
    // long undifferentiated stream (tester feedback #4).
    final grouped = <_NotifCategory, List<AppNotification>>{};
    for (final n in _items) {
      grouped.putIfAbsent(_categoryFor(n), () => []).add(n);
    }
    // Announcements lead — they're the most important and the founder
    // wants them prioritised (their chip sits right after "All" and their
    // section renders first).
    const order = [
      _NotifCategory.announcements,
      _NotifCategory.messages,
      _NotifCategory.social,
      _NotifCategory.engagement,
      _NotifCategory.activity,
    ];
    final present = order
        .where((c) => grouped[c]?.isNotEmpty ?? false)
        .toList();
    // Categories with at least one UNREAD notification — their chip shows
    // a dot.
    final unreadCats = <_NotifCategory>{
      for (final c in present)
        if (grouped[c]!.any((n) => !n.isRead)) c,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterChips(present, unreadCats),
        for (final cat in order)
          if ((grouped[cat]?.isNotEmpty ?? false) &&
              (_filter == null || _filter == cat))
            ..._buildSection(cat, grouped[cat]!),
      ],
    );
  }

  /// Horizontal category filter chips (All + each present category).
  /// Hidden when there's only one category — nothing to filter. Chips for
  /// categories with unread notifications show a dot.
  Widget _buildFilterChips(
    List<_NotifCategory> present,
    Set<_NotifCategory> unreadCats,
  ) {
    if (present.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: [
            _notifChip(
              label: 'All',
              selected: _filter == null,
              hasUnread: unreadCats.isNotEmpty,
              onTap: () => setState(() => _filter = null),
            ),
            for (final c in present) ...[
              const SizedBox(width: 8),
              _notifChip(
                label: _categoryLabel(c),
                selected: _filter == c,
                hasUnread: unreadCats.contains(c),
                onTap: () => setState(() => _filter = c),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notifChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool hasUnread = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue : context.palette.chipBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : context.palette.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.white : context.palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (hasUnread) ...[
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.white : AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One category block: a header with an unread badge, up to four rows
  /// collapsed, and a See-more / Show-less toggle when there are more.
  List<Widget> _buildSection(_NotifCategory cat, List<AppNotification> items) {
    const collapsedCount = 4;
    final expanded = _expanded.contains(cat);
    final unreadInCat = items.where((n) => !n.isRead).length;
    final visible = expanded ? items : items.take(collapsedCount).toList();
    final hiddenCount = items.length - visible.length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(
          children: [
            Icon(_categoryIcon(cat), size: 17, color: AppColors.primaryBlue),
            const SizedBox(width: 8),
            Text(
              _categoryLabel(cat),
              style: AppTextStyles.titleSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (unreadInCat > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unreadInCat',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      for (final n in visible)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey('notif-${n.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.white),
            ),
            onDismissed: (_) => _dismiss(n),
            child: _NotificationRow(item: n, onTap: () => _open(n)),
          ),
        ),
      if (hiddenCount > 0 || expanded)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() {
              if (expanded) {
                _expanded.remove(cat);
              } else {
                _expanded.add(cat);
              }
            }),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              expanded ? 'Show less' : 'See $hiddenCount more',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      const SizedBox(height: 10),
    ];
  }

  _NotifCategory _categoryFor(AppNotification n) {
    final ref = n.referenceType ?? '';
    final type = n.type;
    if (ref == 'conversation' || type.contains('message')) {
      return _NotifCategory.messages;
    }
    // Likes & comments on posts/comments — the engagement bucket.
    if (ref == 'post' ||
        type == 'post_like' ||
        type == 'post_comment' ||
        type == 'comment_reply' ||
        type == 'comment_like' ||
        type == 'reaction') {
      return _NotifCategory.engagement;
    }
    if (ref == 'friend_request' ||
        ref == 'friendship' ||
        type.contains('friend')) {
      return _NotifCategory.social;
    }
    if (ref == 'announcement' ||
        ref == 'account' ||
        type == 'admin_broadcast' ||
        type == 'urgent_banner' ||
        type.contains('announcement') ||
        type.contains('broadcast') ||
        type.contains('sabbath')) {
      return _NotifCategory.announcements;
    }
    return _NotifCategory.activity;
  }

  String _categoryLabel(_NotifCategory cat) {
    switch (cat) {
      case _NotifCategory.messages:
        return 'Messages';
      case _NotifCategory.social:
        return 'Friends & requests';
      case _NotifCategory.engagement:
        return 'Likes & comments';
      case _NotifCategory.announcements:
        return 'Announcements';
      case _NotifCategory.activity:
        return 'Activity';
    }
  }

  IconData _categoryIcon(_NotifCategory cat) {
    switch (cat) {
      case _NotifCategory.messages:
        return Icons.forum_outlined;
      case _NotifCategory.social:
        return Icons.people_outline;
      case _NotifCategory.engagement:
        return Icons.favorite_border;
      case _NotifCategory.announcements:
        return Icons.campaign_outlined;
      case _NotifCategory.activity:
        return Icons.notifications_active_outlined;
    }
  }
}

enum _NotifCategory { messages, social, engagement, announcements, activity }

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  IconData _iconFor(String type) {
    switch (type) {
      case 'event_rsvp':
        return Icons.event_available_outlined;
      case 'prayer_response':
        return Icons.volunteer_activism_outlined;
      case 'message':
        return Icons.mail_outline;
      case 'post_like':
      case 'comment_like':
      case 'reaction':
        return Icons.favorite_border;
      case 'post_comment':
        return Icons.mode_comment_outlined;
      case 'comment_reply':
        return Icons.reply_outlined;
      case 'seller_status':
        return Icons.storefront_outlined;
      case 'church_admin_status':
        return Icons.shield_outlined;
      default:
        return Icons.notifications_none_outlined;
    }
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 7) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}';
    }
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: unread
                ? AppColors.primaryBlue.withValues(alpha: 0.06)
                : context.palette.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unread
                  ? AppColors.primaryBlue.withValues(alpha: 0.25)
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: unread
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _iconFor(item.type),
                    color: AppColors.primaryBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: AppTextStyles.titleSmall.copyWith(
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _relative(item.createdAt),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: context.palette.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.text,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-text reader for notifications that have no screen to open —
/// admin broadcasts, urgent banners, suspensions. The list truncates the
/// body to three lines; this shows the whole thing (tester feedback #4).
class _NotificationReaderSheet extends StatelessWidget {
  const _NotificationReaderSheet({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: AppColors.primaryBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  item.body,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.text,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Close',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
