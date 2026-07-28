import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Pill button for the in-place actions that let a member act on a result
/// without opening it — Add a person, Follow a church, RSVP to an event.
///
/// Filled while the action is available, outlined once it has been taken,
/// so "done" is legible without reading the label.
///
/// Lifted out of search_screen.dart (2026-07-28) when the home "People you
/// may meet" cards needed the same affordance. One implementation, so Add
/// can never mean two different things in two places.
class InlineAction extends StatelessWidget {
  const InlineAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = true,
    this.busy = false,
    this.expand = false,
    this.tint,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final bool busy;

  /// Stretch to the width of the parent. The search rows want a compact
  /// pill at the end of a row; the home cards want a full-width button.
  final bool expand;

  /// Overrides the filled colour. Used for states that aren't "primary
  /// action available" — a green Friends, say.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? AppColors.primaryBlue;
    final fg = filled ? AppColors.white : (tint ?? context.palette.textMuted);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: expand ? 9 : 7,
          ),
          decoration: BoxDecoration(
            color: filled ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            border: filled
                ? null
                : Border.all(color: tint ?? context.palette.divider),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
                )
              else if (icon != null)
                Icon(icon, size: 13, color: fg),
              if (busy || icon != null) const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: fg,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
