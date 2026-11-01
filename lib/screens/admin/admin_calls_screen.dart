// =====================================================================
//  PRIVACY — read this before adding anything to this screen.
//
//  This screen shows COUNTS AND DURATIONS ONLY.
//
//  There is no call audio anywhere in this system to show: WebRTC media
//  never touches Supabase, nothing is recorded, transcribed, proxied or
//  stored (patch_260, §"No audio, ever"), and there is no storage bucket
//  a recording could live in.
//
//  Nothing here may ever render message content, SDP, ICE candidates, or
//  a `room_token`. The token is not an identifier — it IS the Realtime
//  signalling capability (`call:<room_token>`), so printing one on an
//  admin screen would hand whoever reads it the ability to join the
//  channel. Never log it, never show it, never derive it.
//
//  patch_264's `top_users` list returns a user_id alongside each name.
//  CallAdminTopUser drops that id on purpose, so the heaviest-users
//  section can show a display name and aggregate minutes and nothing
//  else. It shows WHO IS SPENDING BANDWIDTH — never who called whom,
//  never when, never for how long on any single call.
//
//  The screen being hard to reach is not the access control either. The
//  RPC is SECURITY DEFINER and calls assert_super_admin() itself; see
//  the header of call_admin_service.dart.
// =====================================================================

import 'package:flutter/material.dart';

import '../../services/calls/call_admin_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';

/// Super-admin "Calls" — the operational health of the calling system
/// (patch_264 §34).
///
/// The number an operator is really here for is the outcomes section: a
/// rising `failed` count, or an answer rate that has fallen, means the
/// push pipeline or TURN is broken and every member is experiencing it
/// as "the app does not ring any more" — a complaint that arrives days
/// late, if it arrives at all.
class AdminCallsScreen extends StatefulWidget {
  const AdminCallsScreen({super.key});

  @override
  State<AdminCallsScreen> createState() => _AdminCallsScreenState();
}

class _AdminCallsScreenState extends State<AdminCallsScreen> {
  late Future<CallAdminMetrics> _future;

  @override
  void initState() {
    super.initState();
    _future = CallAdminService.metrics();
  }

  // Braces, not an arrow body: an arrow returns the assigned Future and
  // setState asserts its callback returns null, so the arrow form throws
  // instead of reloading. Same trap as user_insights_screen.
  void _reload() => setState(() {
        _future = CallAdminService.metrics();
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      // Transparent: the app-wide AmbientBackground paints the ground
      // behind every screen. Setting palette.scaffoldBg here would punch
      // an opaque hole in the particle field.
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Calls',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
        ),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<CallAdminMetrics>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: BrandSpinner(size: 30));
            }
            // CallAdminService never throws — it answers with
            // `error` set — but a snapshot error would otherwise render
            // as a blank screen, so it is folded into the same state.
            final data = snap.hasError
                ? CallAdminMetrics(error: '${snap.error}')
                : (snap.data ?? CallAdminMetrics.empty);
            if (data.hasError) {
              return _Error(message: data.error!, onRetry: _reload);
            }
            if (data.isEmpty) {
              return _Empty(palette: palette, onRetry: _reload);
            }
            return BrandedRefreshIndicator(
              color: AppColors.primaryBlue,
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _HeadlineCard(metrics: data),
                  const SizedBox(height: 14),
                  _SplitCard(metrics: data),
                  const SizedBox(height: 14),
                  _OutcomesCard(metrics: data),
                  const SizedBox(height: 14),
                  _TrendCard(metrics: data),
                  const SizedBox(height: 14),
                  _RelayCard(metrics: data),
                  const SizedBox(height: 14),
                  _PressureCard(metrics: data),
                  if (data.topUsers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _TopUsersCard(users: data.topUsers),
                  ],
                  const SizedBox(height: 18),
                  _PrivacyNote(palette: palette),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Shared pieces
// ---------------------------------------------------------------------

/// Thousands separators without pulling `intl` into this screen — the
/// only formatting this file needs, and "1543 minutes" is genuinely
/// harder to read at a glance than "1,543".
String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return n < 0 ? '-$out' : out.toString();
}

/// Average call length, in the units a person would say it in.
String _duration(int seconds) {
  if (seconds <= 0) return '—';
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        // `?trailing` — the null-aware element form; an `if (x != null) x!`
        // is the same thing with a bang the analyzer will not accept here.
        ?trailing,
      ],
    );
  }
}

/// One headline number. Local copy of the dashboard's `_Stat` so this
/// screen matches the metric-tile look without either file importing the
/// other's private widgets.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.headlineSmall.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 44, color: AppColors.divider);
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

// ---------------------------------------------------------------------
//  Sections
// ---------------------------------------------------------------------

/// Today, right now, and the shape of the week behind it.
class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.metrics});
  final CallAdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return ScreenCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.call_outlined,
                  value: _grouped(m.callsToday),
                  label: 'Calls today',
                ),
              ),
              const _TileDivider(),
              Expanded(
                child: _MetricTile(
                  icon: Icons.graphic_eq_rounded,
                  value: _grouped(m.activeNow),
                  label: 'Live now',
                ),
              ),
              const _TileDivider(),
              Expanded(
                child: _MetricTile(
                  icon: Icons.timer_outlined,
                  value: _grouped(m.minutesToday),
                  label: 'Minutes today',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          // "Live now" counts every call that has not ended, which
          // includes the ones still ringing — worth spelling out, because
          // an operator reading "3 live" while three phones are merely
          // buzzing would think the app is busier than it is.
          Text(
            '${_grouped(m.ringingNow)} ringing · '
            '${_grouped(m.calls7d)} calls this week · '
            '${_grouped(m.totalCalls)} all time',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Average connected call ${_duration(m.avgSeconds)} · '
            '${_grouped(m.totalMinutes)} minutes all time',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 1:1 versus group, as one proportional bar.
class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.metrics});
  final CallAdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final direct = metrics.directCalls;
    final group = metrics.groupCalls;
    final total = direct + group;
    final groupPct = total == 0 ? 0 : ((group / total) * 100).round();

    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('1:1 VS GROUP'),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  // Flex weights ARE the proportions — no arithmetic, so
                  // the bar cannot drift out of sync with the labels.
                  // Zero-count segments are omitted because Expanded
                  // requires a positive flex.
                  if (direct > 0)
                    Expanded(
                      flex: direct,
                      child: const ColoredBox(color: AppColors.primaryBlue),
                    ),
                  if (group > 0)
                    Expanded(
                      flex: group,
                      child: ColoredBox(
                        color: AppColors.primaryBlue.withValues(alpha: 0.22),
                      ),
                    ),
                  if (total == 0)
                    Expanded(child: ColoredBox(color: palette.cardMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendDot(
                color: AppColors.primaryBlue,
                label: '${_grouped(direct)} one-to-one',
              ),
              const SizedBox(width: 14),
              _LegendDot(
                color: AppColors.primaryBlue.withValues(alpha: 0.22),
                label: '${_grouped(group)} group',
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Why this split is worth its own section: media is a MESH, so
          // every extra member multiplies the upstream each phone carries
          // (patch_260 caps groups at 5 for exactly this reason). Group
          // share creeping up is the early warning that an SFU is needed,
          // long before anyone reports bad audio.
          Text(
            'Group calls are $groupPct% of all calls. Audio is a mesh: each '
            'extra member adds an upstream leg to every other phone, which '
            'is why groups are capped at five.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
          if (metrics.peakParticipants > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Largest call so far: ${metrics.peakParticipants} people.',
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

/// The health signal. Failed is the row to watch.
class _OutcomesCard extends StatelessWidget {
  const _OutcomesCard({required this.metrics});
  final CallAdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final pct = (m.answerRate * 100).round();
    // A status badge, not a verdict: below half of all calls reaching
    // audio, something upstream is broken far more often than members
    // are simply declining.
    final healthy = m.answerRate >= 0.5;
    final badgeColor = healthy ? AppColors.successGreen : AppColors.red;

    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            'OUTCOMES',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$pct% ANSWERED',
                style: AppTextStyles.labelSmall.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _OutcomeRow(
            label: 'Answered',
            count: m.answered,
            total: m.totalCalls,
          ),
          _OutcomeRow(label: 'Missed', count: m.missed, total: m.totalCalls),
          _OutcomeRow(
            label: 'Rejected',
            count: m.rejected,
            total: m.totalCalls,
          ),
          _OutcomeRow(label: 'Busy', count: m.busy, total: m.totalCalls),
          // The only urgent row on the screen, so the only red one.
          _OutcomeRow(
            label: 'Failed',
            count: m.failed,
            total: m.totalCalls,
            urgent: true,
          ),
          _OutcomeRow(
            label: 'Swept',
            count: m.swept,
            total: m.totalCalls,
          ),
          const SizedBox(height: 6),
          Text(
            'Failed counts calls where media never came up or no device '
            'could be rung — a rising figure here is infrastructure, not '
            'members changing their minds. Swept are calls the janitor '
            'closed after a phone went silent or hit the duration ceiling.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          // Said out loud so nobody spends an evening reconciling it:
          // cancelled, quota-blocked and admin-ended calls have no
          // counter in patch_264, and calls still ringing have no outcome
          // yet.
          Text(
            'These are each a share of all ${_grouped(m.totalCalls)} calls '
            'and do not add up to it — cancelled and still-ringing calls '
            'have no outcome bucket.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  const _OutcomeRow({
    required this.label,
    required this.count,
    required this.total,
    this.urgent = false,
  });

  final String label;
  final int count;
  final int total;

  /// Paints the row red. Reserved for 'Failed' — red means "act on this",
  /// and a screen where four rows are red means none of them are.
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = total == 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    final tint = urgent && count > 0 ? AppColors.red : AppColors.primaryBlue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${_grouped(count)}  ·  ${(fraction * 100).round()}%',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              // A visible stub for a non-zero count that rounds to
              // nothing, but a true zero stays empty — "a sliver of
              // failures" and "no failures" must not look the same.
              value: count == 0 ? 0.0 : fraction.clamp(0.02, 1.0),
              minHeight: 8,
              backgroundColor: palette.cardMuted,
              valueColor: AlwaysStoppedAnimation<Color>(tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calls per day for patch_264's 30-day window.
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.metrics});
  final CallAdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = metrics.daily;
    // Days with zero calls have no row in the RPC's series, so the axis
    // is "days that had calls", not a calendar. Labelling both ends is
    // what keeps that honest — a gap-free bar run over a sparse month
    // would otherwise read as daily activity.
    final peak = days.fold<int>(0, (a, d) => d.calls > a ? d.calls : a);
    final callsInWindow = days.fold<int>(0, (a, d) => a + d.calls);

    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('LAST 30 DAYS'),
          const SizedBox(height: 14),
          if (days.isEmpty)
            Text(
              'No calls in the last 30 days.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            )
          else ...[
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: _DayBar(
                          fraction: peak == 0 ? 0 : d.calls / peak,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _label(days.first.day),
                  style: AppTextStyles.caption,
                ),
                const Spacer(),
                Text(
                  'peak ${_grouped(peak)}/day',
                  style: AppTextStyles.caption,
                ),
                const Spacer(),
                Text(
                  _label(days.last.day),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: palette.divider),
            const SizedBox(height: 10),
            Text(
              '${_grouped(callsInWindow)} calls · '
              '${_grouped(metrics.minutes30d)} minutes in the window. '
              'Bars are days that had calls, not every calendar day.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _label(DateTime d) => '${d.day}/${d.month}';
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    // Floor of 8% so a one-call day is a visible stub rather than a bar
    // that looks like a day with nothing in it.
    final h = fraction.clamp(0.08, 1.0);
    return FractionallySizedBox(
      heightFactor: h,
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => FractionallySizedBox(
          heightFactor: value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(4),
          ),
          // A childless DecoratedBox collapses to zero height and paints
          // nothing — the trap that ate the Watch header's gradient. The
          // SizedBox.expand is what gives it a box to paint.
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The only figure on this screen that maps to money.
class _RelayCard extends StatelessWidget {
  const _RelayCard({required this.metrics});
  final CallAdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final pct = (m.relayShare * 100).round();
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('RELAYED MINUTES · 30 DAYS'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The screen's single gold accent, spent here because this
              // is the one number with a bill attached.
              const Icon(
                Icons.router_outlined,
                size: 26,
                color: AppColors.goldAccent,
              ),
              const SizedBox(width: 12),
              Text(
                _grouped(m.relayedMinutes30d),
                style: AppTextStyles.displayMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'of ${_grouped(m.minutes30d)} min · $pct% relayed',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Relayed legs are the only per-minute infrastructure cost in '
            'calling: a call that found a peer-to-peer path costs nothing '
            'to carry, while a TURN-relayed one is bandwidth we pay for. '
            'Treat this as the TURN-cost proxy — it is self-reported by '
            'each device, so it estimates the bill rather than being it.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Rate-limit and push pressure over the last 24 hours.
class _PressureCard extends StatelessWidget {
  const _PressureCard({required this.metrics});
  final CallAdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    // Push failures are the quiet one: the callee's phone never rings,
    // the call is recorded as 'missed', and nothing in the members'
    // experience says "the system is broken" — they just think nobody
    // picked up. Any non-zero value deserves the urgent colour.
    final pushColor =
        m.pushFailures24h > 0 ? AppColors.red : AppColors.primaryBlue;
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('LAST 24 HOURS'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.speed_outlined,
                  value: _grouped(m.rateLimitEvents24h),
                  label: 'Rate-limited\nor quota-blocked',
                ),
              ),
              const _TileDivider(),
              Expanded(
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      color: pushColor,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _grouped(m.pushFailures24h),
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pushColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Push failures',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A push failure means the phone was never told to ring, so the '
            'call is logged as missed and nobody reports a bug. Rate-limit '
            'events are counts only — either abuse, or a ceiling set too '
            'low.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Heaviest users by minutes. Names and totals — nothing else.
class _TopUsersCard extends StatelessWidget {
  const _TopUsersCard({required this.users});
  final List<CallAdminTopUser> users;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final peak = users.fold<int>(0, (a, u) => u.minutes > a ? u.minutes : a);
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('HEAVIEST USERS · 30 DAYS'),
          const SizedBox(height: 12),
          for (final u in users)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${_grouped(u.minutes)} min',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: peak == 0
                          ? 0.0
                          : (u.minutes / peak).clamp(0.02, 1.0),
                      minHeight: 8,
                      backgroundColor: palette.cardMuted,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  if (u.relayedMinutes > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_grouped(u.relayedMinutes)} min relayed',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
          Text(
            'Totals only. This answers who is using the most bandwidth — '
            'never who they called.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

/// Stated on the screen, not just in the source, because the person
/// reading it is the person who would be asked "can you hear my calls?".
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 15, color: palette.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Counts and durations only. Calls are never recorded, stored or '
            'transcribed anywhere in this system, and no screen — this one '
            'included — can show what was said or who called whom.',
            style: AppTextStyles.caption,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
//  Empty / error
// ---------------------------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty({required this.palette, required this.onRetry});
  final AppPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_disabled_outlined, size: 60, color: palette.textMuted),
            const SizedBox(height: 16),
            Text(
              'No calls yet.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Metrics appear here as soon as the first call is placed.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              onPressed: onRetry,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
