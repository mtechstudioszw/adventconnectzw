import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../utils/photo_url.dart';
import '../cached_image.dart';
import '../verified_tick.dart';

/// One number in the profile's stat row. [value] null = not available
/// (e.g. followers before patch_274 runs) and the cell is left out rather
/// than showing a made-up zero.
class ProfileStat {
  const ProfileStat(this.label, this.value, {this.onTap});
  final String label;
  final int? value;
  final VoidCallback? onTap;
}

/// The profile header shared by your own profile and everyone else's
/// (redesign brief, 28 Oct 2026, section 7).
///
/// Left-aligned and compact on purpose: the old header centred a 132px
/// avatar under a full-width cover, and identity filled the whole first
/// screen. Here the cover is 3:1 and only shown when there is one (a
/// missing cover is never a navy slab — CLAUDE.md), the avatar is 88px and
/// overlaps it, and name → handle → bio → facts → stats → actions read top
/// to bottom so content starts sooner.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    required this.initials,
    required this.stats,
    required this.actions,
    this.username,
    this.photoUrl,
    this.coverUrl,
    this.bio,
    this.verified = false,
    this.badges = const [],
    this.facts = const [],
    this.completion,
    this.onAvatarTap,
    this.onCoverTap,
    this.relationNote,
  });

  final String name;
  final String initials;
  final String? username;
  final String? photoUrl;
  final String? coverUrl;
  final String? bio;
  final bool verified;

  /// Extra marks after the name (e.g. the premium badge).
  final List<Widget> badges;

  /// One-line facts with icons: church, place, link, joined.
  final List<ProfileFact> facts;
  final List<ProfileStat> stats;

  /// The action row (Edit profile / Follow / Message / ⋯), built by the host
  /// because the actions differ by viewer.
  final List<Widget> actions;

  /// 0..1 profile completeness for the owner; draws a ring when < 1.
  final double? completion;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onCoverTap;

  /// "Follows you", "Friends" — a small note under the handle.
  final String? relationNote;

  static const double _avatar = 88;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasCover = coverUrl != null && coverUrl!.trim().isNotEmpty;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    final avatar = GestureDetector(
      onTap: onAvatarTap,
      child: SizedBox(
        width: _avatar + 8,
        height: _avatar + 8,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ring around the photo in the page colour, so it reads as cut
            // out of the cover rather than pasted on it.
            Container(
              width: _avatar + 8,
              height: _avatar + 8,
              decoration: BoxDecoration(
                color: palette.scaffoldBg,
                shape: BoxShape.circle,
              ),
            ),
            if (completion != null && completion! < 1)
              SizedBox(
                width: _avatar + 6,
                height: _avatar + 6,
                child: CircularProgressIndicator(
                  value: completion,
                  strokeWidth: 3,
                  backgroundColor: palette.divider,
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.primaryBlue,
                  ),
                ),
              ),
            ClipOval(
              child: SizedBox(
                width: _avatar,
                height: _avatar,
                child: (photoUrl ?? '').isEmpty
                    ? _Initials(initials)
                    : CachedNetworkImage(
                        imageUrl: photoUrlAtSize(
                          photoUrl,
                          (_avatar * dpr).round(),
                        ),
                        cacheManager: adventImageCacheManager,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _Initials(initials),
                        errorWidget: (_, _, _) => _Initials(initials),
                      ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasCover)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: GestureDetector(
              onTap: onCoverTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: AspectRatio(
                  aspectRatio: 3,
                  child: CachedNetworkImage(
                    imageUrl: coverUrl!,
                    cacheManager: adventImageCacheManager,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        ColoredBox(color: palette.cardMuted),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg + 4,
            hasCover ? 0 : AppSpace.sm,
            AppSpace.lg,
            0,
          ),
          child: Transform.translate(
            offset: Offset(0, hasCover ? -(_avatar / 2) : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [avatar],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg + 4,
            hasCover ? 0 : AppSpace.md,
            AppSpace.lg + 4,
            0,
          ),
          child: Transform.translate(
            offset: Offset(0, hasCover ? -(_avatar / 2) + 8 : 0),
            child: _identity(context, palette),
          ),
        ),
      ],
    );
  }

  Widget _identity(BuildContext context, AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.headlineMedium.copyWith(
                  color: palette.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            if (verified) const VerifiedTick(size: 19, leftGap: 6),
            for (final b in badges) ...[const SizedBox(width: 6), b],
          ],
        ),
        if ((username ?? '').isNotEmpty || relationNote != null) ...[
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if ((username ?? '').isNotEmpty)
                Text(
                  '@$username',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              if (relationNote != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.cardMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    relationNote!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if ((bio ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            bio!.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.text,
              height: 1.45,
            ),
          ),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [for (final f in facts) _FactChip(fact: f)],
          ),
        ],
        const SizedBox(height: AppSpace.md),
        _StatRow(stats: stats),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpace.sm),
              actions[i],
            ],
          ],
        ),
      ],
    );
  }
}

/// "https://www.example.org/path" → "example.org/path", for the link fact.
String websiteLabel(String url) {
  var s = url.trim().replaceFirst(
    RegExp(r'^https?://', caseSensitive: false),
    '',
  );
  if (s.toLowerCase().startsWith('www.')) s = s.substring(4);
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  return s;
}

/// Opens a member's public link in the browser. Only http(s) — the column
/// is constrained to that server-side too (patch_274).
Future<void> openProfileWebsite(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A fact under the bio: an icon and short text, optionally tappable.
class ProfileFact {
  const ProfileFact(this.icon, this.text, {this.onTap, this.highlight = false});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  /// Blue text — for calls to action like "Add your church".
  final bool highlight;
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.fact});
  final ProfileFact fact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = fact.highlight || fact.onTap != null
        ? AppColors.primaryBlue
        : palette.textMuted;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(fact.icon, size: 15, color: color),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            fact.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: fact.highlight ? AppColors.primaryBlue : palette.textMuted,
              fontWeight: fact.highlight ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
    if (fact.onTap == null) return row;
    return InkWell(
      onTap: fact.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      ),
    );
  }
}

/// Numbers as numbers, left-aligned, each a tap target with its list.
/// Separated by space, not boxed: four stat "cards" in a row was exactly
/// the rounded-rectangle sameness the brief asks to move away from.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});
  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final shown = [
      for (final s in stats)
        if (s.value != null) s,
    ];
    return Row(
      children: [
        for (final s in shown)
          Expanded(
            child: InkWell(
              onTap: s.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _compact(s.value!),
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k < 10 ? 1 : 0)}K';
    }
    final m = n / 1000000;
    return '${m.toStringAsFixed(m < 10 ? 1 : 0)}M';
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Center(
        child: Text(
          text,
          style: AppTextStyles.headlineMedium.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
            fontSize: 30,
          ),
        ),
      ),
    );
  }
}

/// The header's action buttons. Primary = solid blue (one per header),
/// secondary = outlined, icon = square outlined. One shape family, so the
/// row reads as a set rather than a run of pills.
class ProfileActionButton extends StatelessWidget {
  const ProfileActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.busy = false,
  }) : iconOnly = false;

  const ProfileActionButton.icon({
    super.key,
    required IconData this.icon,
    required this.onTap,
    required this.label,
    this.busy = false,
  }) : primary = false,
       iconOnly = true;

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = primary ? AppColors.white : palette.text;
    final child = busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : iconOnly
        ? Icon(icon, size: 20, color: fg)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
    final button = Semantics(
      button: true,
      label: label,
      child: Material(
        color: primary ? AppColors.primaryBlue : palette.card,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            height: 42,
            width: iconOnly ? 46 : null,
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: primary ? null : Border.all(color: palette.divider),
            ),
            child: child,
          ),
        ),
      ),
    );
    return iconOnly ? button : Expanded(child: button);
  }
}
