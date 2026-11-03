import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';
import 'create_sheet.dart';

/// Home's "create" handler, handed to the floating island.
///
/// Owner, 3 Nov 2026: the "+" joins the island — a round frosted button
/// beside the bar, same height and glass, hiding and returning with it on
/// scroll. The island is drawn once by `TabShell` for all five tabs, so
/// Home registers what "+" should do here and the island shows the button
/// only while Home is the active tab and a handler is registered.
class HomeCreateBridge {
  const HomeCreateBridge._();

  static final ValueNotifier<void Function(CreateRequest)?> handler =
      ValueNotifier(null);

  /// Opens the same chooser the old floating "+" did and passes the pick
  /// to Home.
  static Future<void> open(BuildContext context) async {
    final choice = await showCreateSheet(context);
    if (choice != null) handler.value?.call(choice);
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
