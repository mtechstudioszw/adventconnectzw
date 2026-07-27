import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';
import 'create_sheet.dart';

/// The "what would you like to share?" card at the top of Home.
///
/// Tapping the row opens the full [showCreateSheet] chooser. Underneath sit
/// exactly two shortcuts: **Event** — the thing members create most often
/// after a plain post — and **Donate**.
///
/// It used to carry three (Story / Event / Prayer). Story is already a
/// one-tap action in the stories rail directly below, and Prayer has its own
/// entry on the Stories section header, so two of the three shortcuts were
/// duplicating a control that was already on screen.
class ComposerEntry extends StatelessWidget {
  const ComposerEntry({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.onCreate,
    required this.onDonate,
  });

  final String? photoUrl;
  final String name;

  /// Fires with whatever the member picked — either from the sheet or from
  /// the Event shortcut.
  final void Function(CreateKind) onCreate;

  /// Opens the Donate screen. Not a [CreateKind]: giving isn't authoring, and
  /// it must not appear in the create chooser.
  final VoidCallback onDonate;

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
        child: Column(
          children: [
            Pressable(
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
                      child: Container(
                        width: 40,
                        height: 40,
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.card, width: 2),
                        ),
                        child: photoUrl == null || photoUrl!.isEmpty
                            ? fallback
                            : CachedImage(
                                photoUrl!,
                                fit: BoxFit.cover,
                                width: 40,
                                height: 40,
                                errorBuilder: (_, _, _) => fallback,
                              ),
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
            Divider(height: 1, color: palette.divider),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: AppSpace.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _Shortcut(
                      icon: Icons.event_outlined,
                      label: 'Event',
                      tint: AppColors.primaryBlue,
                      onTap: () => onCreate(CreateKind.event),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 22,
                    color: palette.divider,
                  ),
                  Expanded(
                    child: _Shortcut(
                      icon: Icons.favorite_rounded,
                      label: 'Donate',
                      // Home's single gold moment on an ordinary day. On
                      // Sabbath the header takes the gold instead; the two
                      // never compete for attention because the header's is
                      // a whole warm gradient and this is one 17dp glyph.
                      tint: AppColors.goldAccent,
                      onTap: onDonate,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: tint),
            const SizedBox(width: AppSpace.sm - 2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
