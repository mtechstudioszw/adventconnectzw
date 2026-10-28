import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// The buyer's size / colour picker on the product page (patch_280).
///
/// One row per option group: "Size: M" over its choices. A choice that is
/// sold out in every combination still open to the buyer is struck through
/// and can't be picked, so nobody chooses an L only to be told at checkout.
class ProductOptionPicker extends StatelessWidget {
  const ProductOptionPicker({
    super.key,
    required this.groups,
    required this.variants,
    required this.picked,
    required this.accent,
    required this.onPick,
  });

  final List<ProductOptionGroup> groups;
  final List<ProductVariant> variants;
  final Map<String, String> picked;
  final Color accent;
  final void Function(String group, String value) onPick;

  /// Whether [value] in [group] still has a combination that can be bought,
  /// given what's picked in the other groups.
  bool _open(String group, String value) {
    final matching = variants.where((v) {
      if (!v.isActive || v.options[group] != value) return false;
      for (final e in picked.entries) {
        if (e.key == group) continue;
        if (v.options[e.key] != e.value) return false;
      }
      return true;
    });
    if (matching.isEmpty) return false;
    return matching.any((v) => !v.isSoldOut);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups) ...[
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${g.name}: ',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                TextSpan(
                  text: picked[g.name] ?? 'Choose',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: picked[g.name] == null
                        ? palette.textMuted
                        : palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in g.values)
                _Choice(
                  label: v,
                  selected: picked[g.name] == v,
                  open: _open(g.name, v),
                  accent: accent,
                  onTap: () => onPick(g.name, v),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.open,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final bool open;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      enabled: open,
      label: open ? label : '$label, sold out',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: open ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          // Size to the label (an `alignment` here made each chip as wide
          // as the screen). 44dp tall for touch.
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : palette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : palette.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelLarge.copyWith(
              color: !open
                  ? palette.textMuted.withValues(alpha: 0.6)
                  : selected
                  ? palette.text
                  : palette.text,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              decoration: open ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Only 3 left" / "In stock" / "Sold out" — only when the seller counts.
class StockLine extends StatelessWidget {
  const StockLine({super.key, required this.stock});
  final int? stock;

  @override
  Widget build(BuildContext context) {
    final n = stock;
    if (n == null) return const SizedBox.shrink();
    final palette = context.palette;
    final (IconData icon, String text, Color color) = n == 0
        ? (Icons.remove_shopping_cart_outlined, 'Sold out', palette.textMuted)
        : n <= 5
        // CLAUDE.md: red is for urgent content — a last few is.
        ? (Icons.local_fire_department_outlined, 'Only $n left', AppColors.red)
        : (Icons.check_circle_outline, 'In stock', AppColors.successGreen);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: AppTextStyles.labelMedium.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
