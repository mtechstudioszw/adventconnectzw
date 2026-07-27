import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';
import 'create_sheet.dart';

/// The "what would you like to share?" row at the top of Home.
///
/// Tapping anywhere on the row opens the full [showCreateSheet] chooser, and
/// the three shortcut chips underneath jump straight to the most-used kinds
/// so the common path stays one tap.
class ComposerEntry extends StatelessWidget {
  const ComposerEntry({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.onCreate,
  });

  final String? photoUrl;
  final String name;

  /// Fires with whatever the member picked — either from the sheet or from
  /// one of the shortcut chips.
  final void Function(CreateKind) onCreate;

  static const _shortcuts = <(CreateKind, IconData, String)>[
    (CreateKind.story, Icons.auto_awesome_outlined, 'Story'),
    (CreateKind.event, Icons.event_outlined, 'Event'),
    (CreateKind.prayer, Icons.volunteer_activism_outlined, 'Prayer'),
  ];

  Future<void> _openSheet(BuildContext context) async {
    final choice = await showCreateSheet(context);
    if (choice != null) onCreate(choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
          color: palette.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: palette.divider),
          boxShadow: AppShadows.card(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Pressable(
              onTap: () => _openSheet(context),
              pressedScale: 0.985,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
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
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        'What would you like to share?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 18,
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
                  for (final (kind, icon, label) in _shortcuts)
                    Expanded(
                      child: Pressable(
                        haptics: true,
                        onTap: () => onCreate(kind),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpace.sm + 2,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                size: 17,
                                color: AppColors.primaryBlue,
                              ),
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
