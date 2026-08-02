import 'package:flutter/material.dart';
import '../../widgets/motion/brand_spinner.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/share_config.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/announcement_responses_card.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';

/// Church admin dashboard. The post-an-announcement composer lives
/// inline so admins can fire off updates without a route hop.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.role});

  final ChurchAdminRole role;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<ChurchAnnouncement> _items = const [];
  ChurchAdminStats _stats = const ChurchAdminStats();
  List<AnnouncementReach> _reach = const [];
  List<AnnouncementReactionStat> _responses = const [];
  List<AdminTask> _tasks = const [];
  List<ChurchAdminMember> _admins = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadSidecars();
  }

  /// Everything that decorates the dashboard but must never block it:
  /// stats, reach, the queue, the roster. Each is independently
  /// best-effort, so one failing RPC leaves the rest of the screen alive.
  Future<void> _loadSidecars() async {
    final churchId = widget.role.churchId;
    final results = await Future.wait([
      ChurchService.fetchAdminStats(churchId),
      ChurchService.fetchAnnouncementReach(churchId),
      ChurchService.fetchNeedsYou(churchId),
      ChurchService.fetchChurchAdmins(churchId),
      ChurchService.fetchAnnouncementReactionStats(churchId),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as ChurchAdminStats;
      _reach = results[1] as List<AnnouncementReach>;
      _tasks = results[2] as List<AdminTask>;
      _admins = results[3] as List<ChurchAdminMember>;
      _responses = results[4] as List<AnnouncementReactionStat>;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_load(), _loadSidecars()]);
  }

  AnnouncementReach? _reachFor(String id) {
    for (final r in _reach) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Unqueue an announcement that hasn't gone out yet. Deletes the row —
  /// there is nothing to keep, since nobody was ever notified.
  Future<void> _cancelScheduled(ChurchAnnouncement item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: const Text('Cancel this announcement?'),
        content: Text(
          'It hasn\'t been sent, so nobody has seen it. This deletes it.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: ctx.palette.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel it',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChurchService.cancelScheduledAnnouncement(item.id);
      if (mounted) _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not cancel it. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// Nominate another member as a standard admin (patch_175). Primary
  /// admins only — the RPC enforces it too, this just hides the door.
  Future<void> _openAdminsSheet() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AdminsSheet(role: widget.role, admins: _admins),
    );
    if (changed == true) _loadSidecars();
  }

  /// Share the app's Play Store link so the admin can invite members
  /// (WhatsApp, SMS, etc.). The OS share sheet lets them pick WhatsApp.
  Future<void> _inviteMembers() async {
    await Share.share(
      'Join ${widget.role.churchName} on Advent Connect ZW — '
      'church announcements, events and our community in one app.\n\n'
      'Download it here: $appDownloadUrl',
      subject: 'Join us on Advent Connect ZW',
    );
  }

  /// Post a church-BRANDED update to the general home feed (shows the church
  /// name + gold tick to everyone, members or not). patch_141 validates that
  /// only this church's admin can attribute to it.
  Future<void> _postUpdate() async {
    final post = await showPostComposer(context, churchId: widget.role.churchId);
    if (post != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text('Posted to the feed as ${widget.role.churchName}.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
        ),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChurchService.fetchAnnouncements(
        churchId: widget.role.churchId,
        // The admin sees what they've queued; members don't (patch_174).
        includeScheduled: true,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load announcements.';
      });
    }
  }

  Future<void> _openComposer() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ComposerSheet(churchId: widget.role.churchId),
    );
    if (result == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openComposer,
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        elevation: 6,
        icon: const Icon(Icons.campaign_outlined),
        label: Text(
          'New announcement',
          style: AppTextStyles.buttonText.copyWith(fontSize: 14),
        ),
      ),
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              ScreenHero(
                title: widget.role.churchName,
                tagline: 'Church admin · ${widget.role.role}',
                subtitle:
                    'Post announcements, see your members, manage church info.',
                fallbackRoute: 'admin_login',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatsCard(
                      stats: _stats,
                      reach: _reach,
                      onMembers: () => context.pushNamed(
                        'church_members',
                        extra: widget.role,
                      ),
                    ),
                    // The queue comes SECOND, above every action. If
                    // somebody is waiting on this admin, that outranks
                    // anything the admin might have opened the dashboard
                    // to do. It self-hides when the queue is empty.
                    if (_tasks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _NeedsYouCard(
                        tasks: _tasks,
                        onReviewAll: () async {
                          await context.pushNamed(
                            'pending_approvals',
                            extra: widget.role,
                          );
                          if (mounted) _loadSidecars();
                        },
                      ),
                    ],
                    if (_reach.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _ReachCard(reach: _reach),
                    ],
                    // Reach says whether it was opened; this says how it
                    // landed. They sit together because one is the
                    // denominator of the other.
                    if (_responses.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      AnnouncementResponsesCard(stats: _responses),
                    ],
                    const SizedBox(height: 16),
                    _AdminsCard(
                      admins: _admins,
                      canManage: widget.role.role == 'primary',
                      onManage: _openAdminsSheet,
                    ),
                    const SizedBox(height: 16),
                    _QuickActionsCard(
                      pendingCount: _tasks.length,
                      onPost: _openComposer,
                      onPostUpdate: _postUpdate,
                      onApprovals: () async {
                        await context.pushNamed(
                          'pending_approvals',
                          extra: widget.role,
                        );
                        if (mounted) _loadSidecars();
                      },
                      onMembers: () => context.pushNamed(
                        'church_members',
                        extra: widget.role,
                      ),
                      onPostEvent: () => context.pushNamed('post_event',
                          extra: widget.role.churchId),
                      onManageInfo: () => context.pushNamed(
                        'edit_church',
                        extra: widget.role,
                      ),
                      onInvite: _inviteMembers,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'RECENT ANNOUNCEMENTS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: BrandSpinner(size: 30)),
                      )
                    else if (_error != null)
                      ErrorBanner(message: _error!, onRetry: _load)
                    else if (_items.isEmpty)
                      EmptyStateCard(
                        icon: Icons.campaign_outlined,
                        title: 'No announcements yet',
                        message:
                            'Tap the button below to post the first one.',
                      )
                    else
                      for (final item in _items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AnnouncementSummary(
                            item: item,
                            reach: _reachFor(item.id),
                            onCancel: item.isScheduled
                                ? () => _cancelScheduled(item)
                                : null,
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// KPI strip. Members / announcements / events, plus the open rate of the
/// most recent announcement — the one number that tells an admin whether
/// anybody is actually reading them.
class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.stats,
    required this.reach,
    required this.onMembers,
  });

  final ChurchAdminStats stats;
  final List<AnnouncementReach> reach;
  final VoidCallback onMembers;

  @override
  Widget build(BuildContext context) {
    // fetchAnnouncementReach returns oldest → newest for the sparkline,
    // so the latest announcement is the LAST entry.
    final latest = reach.isEmpty ? null : reach.last;
    return ScreenCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onMembers,
                  borderRadius: BorderRadius.circular(10),
                  child: _Stat(
                    icon: Icons.groups_outlined,
                    value: '${stats.members}',
                    label: 'Members',
                  ),
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _Stat(
                  icon: Icons.campaign_outlined,
                  value: '${stats.announcements}',
                  label: 'Announcements',
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _Stat(
                  icon: Icons.event_outlined,
                  value: '${stats.events}',
                  label: 'Events',
                ),
              ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 18,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Last announcement reached ${latest.sentCount} '
                    '${latest.sentCount == 1 ? "member" : "members"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Text(
                  '${(latest.openRate * 100).round()}% opened',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: AppTextStyles.headlineSmall
                .copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMuted)),
      ],
    );
  }
}

/// "Needs you" — everything waiting on this admin, longest wait first.
///
/// Shows the top three with how long each has been sitting. The wait time
/// is the whole point: a queue sorted newest-first hides exactly the
/// requests that have been ignored longest.
class _NeedsYouCard extends StatelessWidget {
  const _NeedsYouCard({required this.tasks, required this.onReviewAll});

  final List<AdminTask> tasks;
  final VoidCallback onReviewAll;

  IconData _iconFor(AdminTaskKind kind) {
    switch (kind) {
      case AdminTaskKind.event:
        return Icons.event_outlined;
      case AdminTaskKind.edit:
        return Icons.edit_note_outlined;
      case AdminTaskKind.admin:
        return Icons.shield_outlined;
    }
  }

  String _labelFor(AdminTaskKind kind) {
    switch (kind) {
      case AdminTaskKind.event:
        return 'Event';
      case AdminTaskKind.edit:
        return 'Edit';
      case AdminTaskKind.admin:
        return 'Admin';
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = tasks.take(3).toList();
    final overdue = tasks.where((t) => t.isOverdue).length;
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'NEEDS YOU',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: overdue > 0 ? AppColors.red : AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${tasks.length}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (overdue > 0) ...[
            const SizedBox(height: 6),
            Text(
              overdue == 1
                  ? '1 has been waiting over a week.'
                  : '$overdue have been waiting over a week.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: 6),
          for (final t in shown) ...[
            const _Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (t.isOverdue ? AppColors.red : AppColors.primaryBlue)
                          .withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFor(t.kind),
                      size: 17,
                      color:
                          t.isOverdue ? AppColors.red : AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_labelFor(t.kind)} · waiting ${t.waitedLabel}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: t.isOverdue
                                ? AppColors.red
                                : AppColors.textMuted,
                            fontWeight:
                                t.isOverdue ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          PrimaryGradientButton(
            label: tasks.length > 3
                ? 'Review all ${tasks.length}'
                : 'Review',
            icon: Icons.fact_check_outlined,
            onTap: onReviewAll,
          ),
        ],
      ),
    );
  }
}

/// Announcement reach: sent vs opened, most recent last.
///
/// Two stacked bars per announcement — the pale full bar is how many
/// members it was delivered to, the solid part is how many opened it
/// (patch_173). A bar chart rather than a line: these are discrete
/// events days apart, and a line between them would imply a trend
/// through time that the data doesn't have.
class _ReachCard extends StatelessWidget {
  const _ReachCard({required this.reach});

  final List<AnnouncementReach> reach;

  @override
  Widget build(BuildContext context) {
    final maxSent = reach.fold<int>(1, (m, r) => r.sentCount > m ? r.sentCount : m);
    final totalSent = reach.fold<int>(0, (s, r) => s + r.sentCount);
    final totalRead = reach.fold<int>(0, (s, r) => s + r.readCount);
    final rate = totalSent == 0 ? 0 : (totalRead / totalSent * 100).round();
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ANNOUNCEMENT REACH',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                '$rate% opened',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last ${reach.length} announcements, oldest first.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 84,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final r in reach)
                  Expanded(
                    child: Tooltip(
                      message: '${r.title}\n'
                          '${r.readCount} of ${r.sentCount} opened',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _ReachBar(
                          sentFraction: r.sentCount / maxSent,
                          openRate: r.openRate,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendDot(
                color: AppColors.primaryBlue,
                label: '$totalRead opened',
              ),
              const SizedBox(width: 14),
              _LegendDot(
                color: AppColors.primaryBlue.withValues(alpha: 0.18),
                label: '$totalSent delivered',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReachBar extends StatelessWidget {
  const _ReachBar({required this.sentFraction, required this.openRate});

  /// This announcement's delivery count as a fraction of the biggest in
  /// the window — so the bars are comparable to each other.
  final double sentFraction;
  final double openRate;

  @override
  Widget build(BuildContext context) {
    // A floor of 6% so an announcement that reached almost nobody still
    // renders as a visible stub rather than vanishing.
    final h = (sentFraction.clamp(0.06, 1.0));
    return FractionallySizedBox(
      heightFactor: h,
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: openRate.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Container(
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: value,
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// The church's admin roster (patch_175). Multiple admins were always
/// legal in the schema — `church_admins` is UNIQUE (church_id, user_id),
/// and only `primary` is capped at one — there was simply no way to add
/// one, and no screen that showed who they were.
class _AdminsCard extends StatelessWidget {
  const _AdminsCard({
    required this.admins,
    required this.canManage,
    required this.onManage,
  });

  final List<ChurchAdminMember> admins;
  final bool canManage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final approved = admins.where((a) => a.isApproved).toList();
    final pending = admins.where((a) => !a.isApproved).length;
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CHURCH ADMINS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              if (canManage)
                TextButton(
                  onPressed: onManage,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Manage',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (approved.isEmpty)
            Text(
              'No approved admins listed yet.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in approved)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          a.isPrimary
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
                          size: 14,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          a.fullName,
                          style: AppTextStyles.labelMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (a.isPrimary) ...[
                          const SizedBox(width: 5),
                          Text(
                            'PRIMARY',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primaryBlue,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          if (pending > 0) ...[
            const SizedBox(height: 10),
            Text(
              pending == 1
                  ? '1 nomination awaiting approval.'
                  : '$pending nominations awaiting approval.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 44, color: AppColors.divider);
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.pendingCount,
    required this.onPost,
    required this.onPostUpdate,
    required this.onApprovals,
    required this.onMembers,
    required this.onPostEvent,
    required this.onManageInfo,
    required this.onInvite,
  });

  final int pendingCount;
  final VoidCallback onPost;
  final VoidCallback onPostUpdate;
  final VoidCallback onApprovals;
  final VoidCallback onMembers;
  final VoidCallback onPostEvent;
  final VoidCallback onManageInfo;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK ACTIONS',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _Row(
            icon: Icons.campaign_outlined,
            title: 'Post announcement',
            // patch_171: the fan-out is followers UNION members now, so
            // this line was understating it by exactly the people who
            // never tapped Follow on their own congregation.
            subtitle: 'Reaches your members and followers. Can be scheduled.',
            onTap: onPost,
          ),
          const _Divider(),
          // The pending_approvals screen has existed all along with
          // nothing linking to it — this is that entry point.
          _Row(
            icon: Icons.fact_check_outlined,
            title: 'Approvals',
            subtitle: pendingCount == 0
                ? 'Events and edit suggestions from members.'
                : '$pendingCount waiting on you.',
            badge: pendingCount,
            onTap: onApprovals,
          ),
          const _Divider(),
          _Row(
            icon: Icons.dynamic_feed_outlined,
            title: 'Share an update',
            subtitle: 'Post to the home feed as your church (everyone sees it).',
            onTap: onPostUpdate,
          ),
          const _Divider(),
          _Row(
            icon: Icons.event_outlined,
            title: 'Post an event',
            subtitle: 'Goes live instantly, featured on Home.',
            onTap: onPostEvent,
          ),
          const _Divider(),
          _Row(
            icon: Icons.edit_note_outlined,
            title: 'Manage church info',
            subtitle: 'Edit photos, about, location and contact.',
            onTap: onManageInfo,
          ),
          const _Divider(),
          _Row(
            icon: Icons.groups_outlined,
            title: 'Members',
            subtitle: 'See who follows your church, by name.',
            onTap: onMembers,
          ),
          const _Divider(),
          _Row(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Invite members',
            subtitle: 'Share the app link on WhatsApp.',
            onTap: onInvite,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Count pill in place of the chevron. Zero shows the chevron.
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return  Divider(
      height: 1,
      color: AppColors.divider,
    );
  }
}

class _AnnouncementSummary extends StatelessWidget {
  const _AnnouncementSummary({
    required this.item,
    this.reach,
    this.onCancel,
  });

  final ChurchAnnouncement item;

  /// Per-announcement sent/opened, when this one is inside the reach
  /// window. Null for older announcements — the card just omits the line.
  final AnnouncementReach? reach;

  /// Only set for announcements that haven't gone out yet.
  final VoidCallback? onCancel;

  String _scheduleLabel(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month} at $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final scheduled = item.isScheduled;
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.category.toUpperCase(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (item.isPinned) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.push_pin,
                  color: AppColors.goldAccent,
                  size: 14,
                ),
              ],
              if (scheduled) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.goldAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_send_outlined,
                        size: 11,
                        color: AppColors.goldAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'SENDS ${_scheduleLabel(item.publishAt!)}',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.goldAccent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              if (onCancel != null)
                IconButton(
                  tooltip: 'Cancel',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onPressed: onCancel,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          if (reach != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 14,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  '${reach!.readCount} of ${reach!.sentCount} opened',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Manage who else can administer this church (patch_175).
///
/// Nominations land as `pending` — the super-admin approval queue is
/// still the only route to actual power, so a primary admin can propose
/// but not appoint. That is deliberate: church admin rights carry the
/// ability to notify a whole congregation.
class _AdminsSheet extends StatefulWidget {
  const _AdminsSheet({required this.role, required this.admins});

  final ChurchAdminRole role;
  final List<ChurchAdminMember> admins;

  @override
  State<_AdminsSheet> createState() => _AdminsSheetState();
}

class _AdminsSheetState extends State<_AdminsSheet> {
  late List<ChurchAdminMember> _admins = widget.admins;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  Future<void> _refresh() async {
    final list = await ChurchService.fetchChurchAdmins(widget.role.churchId);
    if (mounted) setState(() => _admins = list);
  }

  Future<void> _nominate() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MemberPickerSheet(churchId: widget.role.churchId),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ChurchService.nominateChurchAdmin(
        churchId: widget.role.churchId,
        userId: picked,
      );
      _changed = true;
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(ChurchAdminMember a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: const Text('Remove admin?'),
        content: Text(
          '${a.fullName} will lose access to this dashboard.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: ctx.palette.textMuted,
          ),
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
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ChurchService.revokeChurchAdmin(a.id);
      _changed = true;
      await _refresh();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Church admins',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, _changed),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'Nominations need super-admin approval before they take effect.',
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in _admins)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.10),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                a.isPrimary
                                    ? Icons.shield_rounded
                                    : Icons.shield_outlined,
                                size: 18,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.titleSmall.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    a.isPrimary
                                        ? 'Primary admin'
                                        : a.isApproved
                                            ? 'Admin'
                                            : 'Awaiting approval',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: a.isApproved
                                          ? palette.textMuted
                                          : AppColors.goldAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!a.isPrimary)
                              IconButton(
                                tooltip: 'Remove',
                                onPressed:
                                    _busy ? null : () => _revoke(a),
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                  size: 19,
                                  color: AppColors.red,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 14),
            PrimaryGradientButton(
              label: 'Nominate an admin',
              icon: Icons.person_add_alt_1_outlined,
              busy: _busy,
              onTap: _busy ? null : _nominate,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick one of this church's members to nominate. Returns their user id.
class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.churchId});
  final String churchId;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final _search = TextEditingController();
  List<ChurchMember> _members = const [];
  bool _loading = true;

  /// A failed member fetch, so the picker says so rather than looking
  /// like a church with no members.
  String? _membersError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ChurchService.fetchMembers(widget.churchId);
      if (mounted) {
        setState(() {
          _members = list;
          _loading = false;
          _membersError = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _membersError = 'Could not load members.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _members
        : _members
            .where((m) => m.fullName.toLowerCase().contains(q))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: ctx.palette.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search members',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: ctx.palette.inputFill,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: BrandSpinner(size: 28)))
          else if (_membersError != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ErrorBanner(
                  message: _membersError!,
                  onRetry: _load,
                ),
              ),
            )
          else if (filtered.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No members to show. Only people who follow this church '
                    'or have it set as their home church appear here.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: ctx.palette.textMuted),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: filtered.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(
                    Icons.person_outline,
                    color: AppColors.primaryBlue,
                  ),
                  title: Text(filtered[i].fullName),
                  onTap: () => Navigator.pop(context, filtered[i].userId),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({required this.churchId});

  final String churchId;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _category = 'general';
  bool _pinned = false;
  bool _saving = false;
  String? _error;

  /// When to publish. Null = now. patch_174's cron job posts anything
  /// dated forward, and members don't see it until then.
  DateTime? _publishAt;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// Date then time. Capped at 60 days out: further than that and an
  /// admin has forgotten they queued it.
  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _publishAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _publishAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // A time in the past would publish on the very next cron tick, which
    // is "now" with extra steps — say so rather than silently doing it.
    if (picked.isBefore(now)) {
      setState(() {
        _publishAt = null;
        _error = 'That time has passed. It will post immediately instead.';
      });
      return;
    }
    setState(() {
      _publishAt = picked;
      _error = null;
    });
  }

  String _scheduleLabel(DateTime d) {
    const days = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${d.day}/${d.month} at $hh:$mm';
  }

  Future<void> _post() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ChurchService.postAnnouncement(
        churchId: widget.churchId,
        title: _titleController.text,
        body: _bodyController.text,
        category: _category,
        isPinned: _pinned,
        publishAt: _publishAt,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'New announcement',
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in const [
                        'general',
                        'urgent',
                        'event',
                        'program',
                        'obituary',
                      ])
                        _CategoryChip(
                          label: c,
                          active: _category == c,
                          onTap: () => setState(() => _category = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      return null;
                    },
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: _dec(hint: 'Title', icon: Icons.title),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bodyController,
                    maxLines: 5,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length < 10) return 'A little longer please';
                      return null;
                    },
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                    decoration: _dec(
                      hint: 'Body',
                      icon: Icons.notes_outlined,
                    ).copyWith(counterText: ''),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.push_pin_outlined,
                        color: AppColors.primaryBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pin this announcement',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _pinned,
                        onChanged: (v) => setState(() => _pinned = v),
                        activeThumbColor: AppColors.primaryBlue,
                      ),
                    ],
                  ),
                  // Schedule (patch_174). The column `publish_at` has
                  // been in the schema since patch_002 and nothing ever
                  // wrote to it; this is the control it was named for.
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _pickSchedule,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              _publishAt == null
                                  ? Icons.schedule_outlined
                                  : Icons.schedule_send_outlined,
                              color: AppColors.primaryBlue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _publishAt == null
                                    ? 'Post now'
                                    : 'Scheduled · ${_scheduleLabel(_publishAt!)}',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_publishAt != null)
                              IconButton(
                                tooltip: 'Post now instead',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    setState(() => _publishAt = null),
                              )
                            else
                              Text(
                                'Schedule',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 16),
                  PrimaryGradientButton(
                    label: _saving
                        ? 'Posting...'
                        : _publishAt == null
                            ? 'Post announcement'
                            : 'Schedule announcement',
                    busy: _saving,
                    onTap: _saving ? null : _post,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: AppColors.lightGrey,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:  BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:  BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? AppColors.primaryGradient : null,
          color: active ? null : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppColors.primaryBlue
                : AppColors.divider,
          ),
        ),
        child: Text(
          label[0].toUpperCase() + label.substring(1),
          style: AppTextStyles.labelMedium.copyWith(
            color: active ? AppColors.white : AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}
