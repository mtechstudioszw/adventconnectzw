import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';
import 'create_sheet.dart';

/// Home's floating "create" button — the composer card's replacement.
///
/// Founder call, 27 Oct 2026: the "Share something…" card left the top of
/// Home and became a floating gold "+". It opens the same [showCreateSheet]
/// chooser the card did, so every kind of post is still one tap away
/// without the card taking a row above the live banner and chips.
///
/// Gold is this screen's single gold moment now (the Donate chip that held
/// it is gone). The glyph is navy, not white: white on #C8A951 is ~2.2:1
/// and fails contrast; navy on it is ~7:1.
class HomeComposeFab extends StatelessWidget {
  const HomeComposeFab({super.key, required this.onCreate});

  /// Fires with whatever the member picked in the sheet.
  final void Function(CreateRequest) onCreate;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'home-compose',
      tooltip: 'Create a post',
      backgroundColor: AppColors.goldAccent,
      foregroundColor: AppColors.darkNavy,
      shape: const CircleBorder(),
      onPressed: () async {
        final choice = await showCreateSheet(context);
        if (choice != null) onCreate(choice);
      },
      child: const Icon(Icons.add_rounded, size: 30),
    );
  }
}

/// Home's shortcut row: **Churches**, **Events**, **Prayer**.
///
/// They sit on the scaffold as their own row, not inside a card, because
/// none of them is a kind of post.
///
/// Prayer replaced Donate on 27 Oct 2026 (founder). The prayer wall was
/// otherwise reachable only through the small "Prayer" link on the Stories
/// header. Unlike Donate it asks nobody for money, so it shows on iOS too.
///
/// Equal thirds rather than a scrolling rail: three is few enough to fit
/// any phone.
class HomeShortcutChips extends StatelessWidget {
  const HomeShortcutChips({
    super.key,
    required this.onChurches,
    required this.onEvents,
    required this.onPrayer,
  });

  final VoidCallback onChurches;

  /// Named for the destination, not for a post kind. It was `onEvent`
  /// once, and Home duly wired it to the *create an event* composer
  /// while its two neighbours navigated — the chip said "Events" and
  /// opened a form. Plural, like the screen it opens.
  final VoidCallback onEvents;
  final VoidCallback onPrayer;

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
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: _ShortcutChip(
              icon: Icons.volunteer_activism_rounded,
              label: 'Prayer',
              tint: AppColors.primaryBlue,
              onTap: onPrayer,
            ),
          ),
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
