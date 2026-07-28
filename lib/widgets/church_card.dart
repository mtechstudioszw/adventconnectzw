import 'package:flutter/material.dart';
import '../models/church_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'cached_image.dart';
import 'motion/pressable.dart';

class ChurchCard extends StatelessWidget {
  const ChurchCard({
    super.key,
    required this.church,
    required this.onTap,
    this.distanceLabel,
    this.friendCount = 0,
    this.isHomeChurch = false,
    this.onSetHome,
  });

  final Church church;
  final VoidCallback onTap;
  final String? distanceLabel;

  /// How many of the viewer's friends belong to this church (patch_176).
  /// Zero hides the chip — "0 friends here" is not information.
  final int friendCount;

  /// This is the viewer's `profiles.church_id`. Gets a badge, and the
  /// set-home affordance flips to "remove".
  final bool isHomeChurch;

  /// Tapping the home glyph. Null hides it entirely — the search screen
  /// and church details reuse this card without the setting.
  final VoidCallback? onSetHome;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _CoverImage(url: church.coverPhotoUrl),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              church.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleLarge,
                            ),
                          ),
                          if (church.isVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              size: 16,
                              color: AppColors.goldAccent,
                            ),
                          ],
                          if (isHomeChurch) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'MINE',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              church.city.isEmpty
                                  ? 'Unknown city'
                                  : church.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // When the church meets — the single most useful
                      // fact to someone deciding whether to visit, and
                      // the reason patch_176 added the column. It takes
                      // the slot the conference name used to hold: which
                      // conference a church belongs to is administrative
                      // trivia to a member looking for somewhere to
                      // worship on Sabbath.
                      if (church.serviceTimes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _serviceSummary(church),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if ((church.conference ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                church.conference!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Wrap so the members + distance chips re-flow to a
                      // second line on narrow phones / large font scaling
                      // instead of clipping. Previously a long city +
                      // verified badge + members + distance overflowed
                      // when system font size was bumped to large.
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people_outline,
                                size: 14,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                // Honest label: this is the exact count of
                                // app users following this church — NOT
                                // congregation membership, which the app
                                // has no data for.
                                '${_formatCount(church.membersCount)} on Advent',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          // Social proof that actually helps someone
                          // choose: people you already know worship here.
                          // Counts only — never a name (patch_176).
                          if (friendCount > 0)
                            _MiniChip(
                              icon: Icons.people_alt_rounded,
                              label: friendCount == 1
                                  ? '1 friend here'
                                  : '$friendCount friends here',
                            ),
                          if (distanceLabel != null)
                            _MiniChip(
                              icon: Icons.near_me_outlined,
                              label: distanceLabel!,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onSetHome != null)
                  _HomeChurchButton(
                    isHome: isHomeChurch,
                    onTap: onSetHome!,
                  )
                else
                  Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      final k = (count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1);
      return '${k}k';
    }
    return '$count';
  }

  /// One line for a row: "Sabbath School · 08:30", plus "+2 more" when
  /// the church listed several. The full list lives on church details.
  static String _serviceSummary(Church church) {
    final first = church.serviceTimes.first;
    final head = [
      if (first.label.trim().isNotEmpty) first.label.trim(),
      if (first.whenLabel.isNotEmpty) first.whenLabel,
    ].join(' · ');
    final extra = church.serviceTimes.length - 1;
    return extra > 0 ? '$head  +$extra more' : head;
  }
}

/// Small tinted pill used for the row's secondary facts.
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.primaryBlue),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryBlue,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Set / unset this church as the viewer's home church.
///
/// It replaces the chevron rather than sitting beside it: the whole row
/// already opens the church, so a chevron was decoration, and the row
/// has no width to spare on a small phone.
class _HomeChurchButton extends StatelessWidget {
  const _HomeChurchButton({required this.isHome, required this.onTap});

  final bool isHome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isHome ? 'Your home church' : 'Set as my church',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              isHome ? Icons.home_rounded : Icons.home_outlined,
              size: 20,
              color: isHome ? AppColors.primaryBlue : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: const Icon(Icons.church, color: AppColors.white, size: 32),
      );
    }
    return CachedImage(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: context.palette.cardMuted,
        child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: context.palette.cardMuted,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}
