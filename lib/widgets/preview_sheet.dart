import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'motion/pressable.dart';

/// "See it before you send it", for anything a member can publish.
///
/// The post composer already had a preview and it was the most-praised
/// thing on that screen — so stories, events, products and news get the
/// same deal rather than one privileged content type.
///
/// The rule that makes a preview worth having: **render the REAL card**,
/// on the real background it will sit on. A lookalike drifts from the
/// thing it stands in for the moment either changes, and then it quietly
/// lies about the two things people actually check — where the text wraps
/// and how the photos crop.
///
/// Returns `true` when the member confirms from here, so the composer can
/// publish without making them go back first.
Future<bool> showEntityPreview(
  BuildContext context, {
  /// What is being previewed — "How your event will look".
  required String title,

  /// The real card, built from what's in the composer right now.
  required Widget child,

  /// The confirm button. "Post it" / "List it" / "Publish".
  required String confirmLabel,

  /// Background behind the card. Defaults to the feed's scaffold colour;
  /// pass the surface the card will really sit on if it differs.
  Color? canvasColor,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PreviewSheet(
      title: title,
      confirmLabel: confirmLabel,
      canvasColor: canvasColor,
      child: child,
    ),
  );
  return result ?? false;
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.title,
    required this.confirmLabel,
    required this.child,
    this.canvasColor,
  });

  final String title;
  final String confirmLabel;
  final Widget child;
  final Color? canvasColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: AppRadius.sheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.md),
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'PREVIEW',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: AppTextStyles.titleLarge.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to editing',
                    icon: Icon(Icons.close_rounded, color: palette.text),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Container(
                width: double.infinity,
                color: canvasColor ?? palette.scaffoldBg,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  // Deliberately NOT wrapped in IgnorePointer. Blanket-
                  // blocking pointers here is what stopped a multi-photo
                  // post's carousel from paging — the preview showed photo
                  // one and there was no way to reach the rest, which is
                  // precisely what the preview exists to check.
                  child: child,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(false),
                      pressedScale: 0.97,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.card,
                          borderRadius: AppRadius.buttonAll,
                          border: Border.all(color: palette.divider),
                        ),
                        child: Text(
                          'Keep editing',
                          style: AppTextStyles.buttonText.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(true),
                      haptics: true,
                      pressedScale: 0.97,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: AppRadius.buttonAll,
                          boxShadow: AppShadows.glow(context),
                        ),
                        child: Text(
                          confirmLabel,
                          style: AppTextStyles.buttonText.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
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
