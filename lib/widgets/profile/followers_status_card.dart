import 'package:flutter/material.dart';

import '../../services/cache_service.dart';
import '../../services/follow_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import 'who_can_follow_change.dart';

/// Tells a member, in plain words, that their account is personal —
/// friends only, no followers — and lets them turn followers on in one tap
/// (owner, 29 Oct 2026: "people may not even know that the app allows a
/// follow system").
///
/// Used on the member's own profile, and once on Home as an announcement
/// ([FollowersStatusCard.announcement]) until they act on it or dismiss it.
class FollowersStatusCard extends StatefulWidget {
  const FollowersStatusCard({
    super.key,
    required this.current,
    required this.onChanged,
    this.announcement = false,
    this.onDismiss,
  });

  final WhoCanFollow current;
  final ValueChanged<WhoCanFollow> onChanged;

  /// Home's one-time version: headed "New", with "Got it".
  final bool announcement;
  final VoidCallback? onDismiss;

  /// Home shows the announcement once per member. User-scoped (no
  /// `pref:`), so the next person on a shared phone sees it too.
  static const seenKey = 'followers_intro_seen_v1';

  static bool seen() => CacheService.readPref(seenKey) == '1';
  static Future<void> markSeen() => CacheService.writePref(seenKey, '1');

  @override
  State<FollowersStatusCard> createState() => _FollowersStatusCardState();
}

class _FollowersStatusCardState extends State<FollowersStatusCard> {
  bool _busy = false;

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    final now = await changeWhoCanFollow(
      context,
      current: widget.current,
      picked: WhoCanFollow.everyone,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (now != widget.current) {
      widget.onChanged(now);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Followers on. Anyone can follow your public posts. Turn it off '
            'any time in Settings > Privacy.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (widget.current.allowsFollowers) {
      if (widget.announcement) return const SizedBox.shrink();
      return _shell(
        context,
        icon: Icons.campaign_outlined,
        title: 'Followers on',
        body:
            'Anyone can follow your public posts. You can turn this off in '
            'Settings > Privacy.',
        actions: const [],
      );
    }
    return _shell(
      context,
      icon: Icons.person_outline_rounded,
      eyebrow: widget.announcement ? 'NEW' : null,
      title: widget.announcement
          ? 'Your account is personal'
          : 'Personal account',
      body:
          'People connect with you by adding you as a friend — nobody can '
          'follow you. If you share publicly (a pastor, leader, musician or '
          'ministry), turn on followers so people can follow your public '
          'posts without being your friend.',
      actions: [
        FilledButton(
          onPressed: _busy ? null : _turnOn,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
          child: Text(_busy ? 'Turning on…' : 'Allow followers'),
        ),
        if (widget.onDismiss != null)
          TextButton(
            onPressed: widget.onDismiss,
            style: TextButton.styleFrom(foregroundColor: palette.textMuted),
            child: Text(widget.announcement ? 'Got it' : 'Not now'),
          ),
      ],
    );
  }

  Widget _shell(
    BuildContext context, {
    required IconData icon,
    String? eyebrow,
    required String title,
    required String body,
    required List<Widget> actions,
  }) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: palette.brandBlue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Text(
                        eyebrow,
                        style: AppTextStyles.overline.copyWith(
                          color: palette.brandBlue,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    Text(
                      title,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.textMuted,
              height: 1.45,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final a in actions) ...[a, const SizedBox(width: 8)],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
