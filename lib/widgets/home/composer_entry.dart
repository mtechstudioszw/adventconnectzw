import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/platform_flags.dart';
import '../../theme/app_colors.dart';
import '../../utils/photo_url.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';
import 'create_sheet.dart';

/// The "what would you like to share?" card at the top of Home.
///
/// Tapping the row opens the full [showCreateSheet] chooser. That is ALL
/// this card does now.
///
/// Event and Donate used to live inside this card, under a divider — which
/// put "give money to the church" and "go to the churches directory" inside
/// the box for writing a post, and made both read as kinds of posting.
/// They are navigation, not authoring, so they moved out into
/// [HomeShortcutChips] directly below (2026-07-28).
class ComposerEntry extends StatelessWidget {
  const ComposerEntry({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.onCreate,
  });

  final String? photoUrl;
  final String name;

  /// Fires with whatever the member picked in the sheet.
  final void Function(CreateKind) onCreate;

  Future<void> _openSheet(BuildContext context) async {
    final choice = await showCreateSheet(context);
    if (choice != null) onCreate(choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();
    final fallback = Text(
      initial,
      style: AppTextStyles.titleMedium.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w700,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.divider),
          boxShadow: AppShadows.card(context),
          // Sheen blended into the card colour — `gradient` would otherwise
          // shadow `color` entirely and paint the card white.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                AppColors.white.withValues(alpha: dark ? 0.05 : 0.55),
                palette.card,
              ),
              palette.card,
            ],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Pressable(
              onTap: () => _openSheet(context),
              pressedScale: 0.985,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(
                  children: [
                    // Gradient ring around the avatar so the member's own face
                    // is the first thing with weight on the card.
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      // DecorationImage, not a clipped child — same pattern
                      // as edit_profile_screen, which is the one that has
                      // always looked right.
                      //
                      // A decoration paints its image THROUGH its own shape,
                      // giving an exact circle. Putting the image inside as a
                      // child and rounding it with `clipBehavior` only
                      // approximates the curve, and with a 2px border drawn
                      // over the top the flat segments show — the founder's
                      // "it doesn't fit" on this avatar specifically, while
                      // the one in the header a few pixels away looked fine.
                      //
                      // The initials stay as the child: a DecorationImage
                      // paints over its child, so they show while the photo
                      // loads and remain if it never arrives, which is what
                      // the errorBuilder used to do.
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.card, width: 2),
                          image: (photoUrl ?? '').isEmpty
                              ? null
                              : DecorationImage(
                                  image: CachedNetworkImageProvider(
                                    photoUrlAtSize(photoUrl, 120),
                                    cacheManager: adventImageCacheManager,
                                  ),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: (photoUrl ?? '').isEmpty ? fallback : null,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    // A recessed pill, so the row reads as a field waiting for
                    // words rather than a line of grey text.
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: palette.cardMuted,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: palette.divider),
                        ),
                        child: Text(
                          'Share something…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.32,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: AppColors.white,
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

/// The three shortcuts that used to be buried inside the composer card:
/// **Churches**, **Events**, **Donate**.
///
/// They sit on the scaffold as their own row, not inside a card, because
/// none of them is a kind of post. Under the composer they read as "and
/// here are the other places to go", which is what they are.
///
/// Equal thirds rather than a scrolling rail: three is few enough to fit
/// any phone, and a rail would hide Donate off the right edge on a small
/// screen — the one shortcut the church most wants found.
class HomeShortcutChips extends StatelessWidget {
  const HomeShortcutChips({
    super.key,
    required this.onChurches,
    required this.onEvents,
    required this.onDonate,
  });

  final VoidCallback onChurches;

  /// Named for the destination, not for a post kind. It was `onEvent`
  /// once, and Home duly wired it to the *create an event* composer
  /// while its two neighbours navigated — the chip said "Events" and
  /// opened a form. Plural, like the screen it opens.
  final VoidCallback onEvents;
  final VoidCallback onDonate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: _ShortcutChip(
              icon: Icons.church_outlined,
              label: 'Churches',
              tint: AppColors.primaryBlue,
              onTap: onChurches,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: _ShortcutChip(
              icon: Icons.event_outlined,
              label: 'Events',
              // `AppColors.text`, not `AppColors.darkNavy`.
              //
              // Both are the same #0D1B3E in light mode, so this looks
              // identical there — but darkNavy is a `const` and never flips,
              // while `text` is reassigned by AppTextStyles.applyBrightness.
              // The chip's glyph and its tinted disc were therefore drawn in
              // near-black on a dark surface and the Events shortcut simply
              // was not there in dark mode. Its neighbours survived only
              // because primaryBlue and goldAccent happen to read on both.
              tint: AppColors.text,
              onTap: onEvents,
            ),
          ),
          // Hidden on iOS: Apple requires In-App Purchase for anything that
          // asks users to send money. Churches and Events then share the row.
          if (!kHidePayments) ...[
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: _ShortcutChip(
                icon: Icons.favorite_rounded,
                label: 'Donate',
                // Home's single gold moment on an ordinary day. On Sabbath
                // the header takes the gold instead; the two never compete
                // because the header's is a whole warm gradient and this is
                // one 16dp glyph in a tinted disc.
                tint: AppColors.goldAccent,
                onTap: onDonate,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      haptics: true,
      onTap: onTap,
      pressedScale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.sm + 1,
        ),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: palette.divider),
          boxShadow: AppShadows.card(context),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: tint),
            ),
            const SizedBox(width: AppSpace.sm - 2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}