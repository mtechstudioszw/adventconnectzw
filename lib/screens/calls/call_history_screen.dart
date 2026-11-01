import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/call_model.dart';
import '../../services/calls/call_api.dart';
import '../../services/billing/premium_tier.dart';
import '../../services/calls/missed_call_badge.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/calls/call_action.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/user_avatar.dart';

/// The Calls tab — this member's own call log.
///
/// ## Whose history this is
///
/// Strictly the signed-in member's. `call_history` takes no user
/// parameter and reads `auth.uid()` as the only identity in the query,
/// so there is no shape of request that returns somebody else's calls.
/// Clearing a row deletes only this member's participant row for an
/// ENDED call, which is why the other person's log is untouched: history
/// is reconstructed per participant rather than read from one shared
/// list.
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  static const _pageSize = 40;

  final _scroll = ScrollController();
  final List<CallHistoryEntry> _entries = [];

  CallUsage _usage = CallUsage.empty;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load());
    // Looking at the log IS reading the missed calls — there is no
    // per-row unread state, and the list shows everything at once.
    // Cleared here rather than in dispose so the dot is gone the moment
    // they arrive, not when they leave.
    unawaited(MissedCallBadge.markSeen());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) unawaited(_loadMore());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Both in flight together — the usage strip and the list are
      // independent, and serialising them doubles the time this screen
      // spends empty on a slow connection.
      final results = await Future.wait([
        CallApi.history(limit: _pageSize),
        CallApi.usage(),
      ]);
      if (!mounted) return;
      final history = results[0] as List<CallHistoryEntry>;
      setState(() {
        _entries
          ..clear()
          ..addAll(history);
        _usage = results[1] as CallUsage;
        _exhausted = history.length < _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your calls.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    // Three guards, and all three are load-bearing: the scroll listener
    // fires on every frame of a fling, so without them one flick issues
    // a dozen identical requests and appends the same page repeatedly.
    if (_loadingMore || _exhausted || _loading || _entries.isEmpty) return;
    _loadingMore = true;
    try {
      final next = await CallApi.history(
        limit: _pageSize,
        before: _entries.last.startedAt,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(next);
        _exhausted = next.length < _pageSize;
      });
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _clearOne(CallHistoryEntry entry) async {
    await CallApi.clearHistory(callId: entry.id);
    if (!mounted) return;
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear call log?', style: AppTextStyles.titleMedium),
        content: Text(
          'This removes every call from your own list. It does not remove '
          'them from anyone else\'s.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CallApi.clearHistory();
    if (!mounted) return;
    setState(_entries.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHero(
              title: 'Calls',
              tagline: 'Voice calls with people you know',
              fallbackRoute: '/home',
              trailing: _entries.isEmpty
                  ? null
                  : ScreenHeroTrailing(
                      icon: Icons.delete_sweep_outlined,
                      onTap: () => unawaited(_clearAll()),
                    ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: BrandSpinner(size: 30));
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(message: _error!, onRetry: () => unawaited(_load())),
      );
    }

    return BrandedRefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        // +1 for the usage strip, +1 for the empty state or the tail.
        itemCount: _entries.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return _UsageStrip(usage: _usage);
          if (index == _entries.length + 1) {
            if (_entries.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyStateCard(
                  icon: Icons.phone_disabled_rounded,
                  title: 'No calls yet',
                  message:
                      'Voice calls you make and receive will show up here.',
                ),
              );
            }
            return _exhausted
                ? const SizedBox(height: 8)
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: BrandSpinner(size: 22)),
                  );
          }
          return _CallRow(
            entry: _entries[index - 1],
            onClear: () => unawaited(_clearOne(_entries[index - 1])),
          );
        },
      ),
    );
  }
}

/// Minutes used today against the ceiling in force for this member.
///
/// Deliberately quiet until it matters. A quota bar that shouts at 3%
/// used is noise, and noise on a limit nobody is near teaches people to
/// ignore it — so the colour only changes once [CallUsage.nearDailyLimit]
/// is true.
class _UsageStrip extends StatelessWidget {
  const _UsageStrip({required this.usage});

  final CallUsage usage;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final minutes = usage.todaySeconds ~/ 60;
    final limit = usage.dailyLimitSeconds ~/ 60;

    final accent = usage.dailyExhausted
        ? AppColors.red
        : usage.nearDailyLimit
        ? AppColors.goldAccent
        : AppColors.primaryBlue;

    // The upgrade line, and it only appears when it is TRUE and USEFUL.
    //
    // Founder question, 25 Aug 2026: "in call log it gives u the minutes
    // u have per day — is it possible to upgrade to get more minutes in
    // premium". It already was: premium has been 360 minutes a day
    // against free's 120 since patch_260. Nothing anywhere said so, so
    // nobody could buy it — which is the actual missed revenue, not the
    // absence of a feature.
    //
    // Shown only to a free member who has USED enough of the day's
    // allowance to feel it. An upgrade prompt on a bar sitting at 3% is
    // the noise this card's own doc comment exists to refuse, and it is
    // also the least persuasive moment to ask — the member has no
    // problem yet. At 60%+ the sentence describes something they are
    // actually experiencing.
    final showUpgrade = !usage.premium && usage.dailyFraction >= 0.6;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ScreenCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  '$minutes of $limit minutes today',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (usage.premium)
                  Text(
                    'Premium',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.goldAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: usage.dailyFraction,
                minHeight: 5,
                backgroundColor: palette.cardMuted,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            if (usage.dailyExhausted) ...[
              const SizedBox(height: 10),
              Text(
                'You have used today\'s call minutes. They reset at midnight.',
                style: AppTextStyles.caption.copyWith(color: AppColors.red),
              ),
            ],
            if (showUpgrade) ...[
              const SizedBox(height: 10),
              _UpgradeForMinutes(exhausted: usage.dailyExhausted),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Premium gives you 6 hours a day" — the one place in the app that
/// says so where somebody is in a position to want it.
///
/// The numbers come from [TierBenefits], not from a string, so they
/// cannot drift from the allowance the server actually enforces.
class _UpgradeForMinutes extends StatelessWidget {
  const _UpgradeForMinutes({required this.exhausted});

  /// Out of minutes entirely, rather than merely close. Changes the
  /// verb — "get more" against "they reset at midnight, or get more
  /// now" — and nothing else. No countdown, no invented scarcity.
  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final plus = TierBenefits.plus;
    final pro = TierBenefits.pro;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.pushNamed('premium'),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  exhausted
                      ? 'Premium members get ${plus.callAllowanceLabel} a '
                            'day, and Pro gets ${pro.callAllowanceLabel}.'
                      : 'Need longer calls? Premium is '
                            '${plus.callAllowanceLabel} a day, Pro '
                            '${pro.callAllowanceLabel}.',
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textMuted,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'See plans',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.entry, required this.onClear});

  final CallHistoryEntry entry;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final peer = entry.peer;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: () => unawaited(_showRowActions(context)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                UserAvatar(
                  photoUrl: entry.isGroup
                      ? null
                      : (peer?.photoUrl ?? entry.others.firstOrNull?.photoUrl),
                  size: 46,
                  name: entry.title,
                  fallbackIcon: entry.isGroup ? Icons.groups_rounded : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: entry.missed ? AppColors.red : palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            _directionIcon,
                            size: 14,
                            // Red is for the one state that needs
                            // attention. An unanswered call *I* placed is
                            // not a missed call — colouring it red would
                            // leave a permanent alarm on my own history
                            // for something nobody did wrong.
                            color: entry.missed
                                ? AppColors.red
                                : palette.textMuted,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (peer != null)
                  CallIconButton(
                    // Does NOT navigate. main.dart listens to
                    // CallService.onShowCallScreen and opens the call
                    // screen for every route in — a push, a Realtime
                    // invite, a lock-screen accept and this button all
                    // arrive the same way, so there is exactly one
                    // navigation path and no way to stack two screens.
                    onTap: () => CallActions.callUser(
                      context,
                      userId: peer.userId,
                      displayName: peer.name,
                      photoUrl: peer.photoUrl,
                      conversationId: entry.conversationId,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _directionIcon {
    if (entry.missed) return Icons.call_missed_rounded;
    return entry.outgoing
        ? Icons.call_made_rounded
        : Icons.call_received_rounded;
  }

  String get _subtitle {
    final parts = <String>[];
    if (entry.isGroup) parts.add('${entry.others.length + 1} people');
    if (entry.declined) {
      parts.add('Declined');
    } else if (entry.missed) {
      parts.add('Missed');
    } else if (!entry.answered) {
      parts.add('No answer');
    }
    parts.add(_formatWhen(entry.startedAt.toLocal()));
    if (entry.answered && entry.durationSeconds > 0) {
      parts.add(_formatDuration(Duration(seconds: entry.durationSeconds)));
    }
    return parts.join(' · ');
  }

  Future<void> _showRowActions(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.red,
              ),
              title: Text(
                'Remove from my call log',
                style: AppTextStyles.bodyMedium,
              ),
              subtitle: Text(
                'Only yours — the other person keeps theirs.',
                style: AppTextStyles.caption.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onClear();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _formatWhen(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(when.year, when.month, when.day);
  final hh = when.hour.toString().padLeft(2, '0');
  final mm = when.minute.toString().padLeft(2, '0');

  if (that == today) return '$hh:$mm';
  if (that == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (when.year == now.year) return '${when.day}/${when.month}';
  return '${when.day}/${when.month}/${when.year}';
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}
