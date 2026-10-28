import 'package:flutter/material.dart';

import '../models/product_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import '../widgets/motion/brand_spinner.dart';
import '../widgets/motion/pressable.dart';

// The marketplace's shared building blocks — the product page and the
// storefront are built from these so they read as one experience
// (owner, 28 Oct 2026). Colours that vary per product or shop come in as
// arguments (from ProductTheme); everything else is the app's own.

/// A titled band: generous space above, a hairline, then the content.
class MarketSection extends StatelessWidget {
  const MarketSection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: palette.divider),
          const SizedBox(height: 20),
          Text(
            title,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class StageHeaderButton extends StatelessWidget {
  const StageHeaderButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.solid,
    this.tint,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool solid;
  final Color? tint;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final button = Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: solid ? palette.card : Colors.black.withValues(alpha: 0.32),
          shape: BoxShape.circle,
          border: solid ? Border.all(color: palette.divider) : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: tint ?? (solid ? palette.text : AppColors.white),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class MarketContactOption extends StatelessWidget {
  const MarketContactOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Price set the way premium shops set it: a smaller currency mark, the
/// whole amount large, cents small. Reads as a price at a glance.
class PriceText extends StatelessWidget {
  const PriceText({
    super.key,
    required this.product,
    required this.size,
    required this.color,
    this.amount,
  });
  final Product product;
  final double size;
  final Color color;

  /// Overrides the product's price — a size or colour with its own price.
  final double? amount;

  @override
  Widget build(BuildContext context) {
    final symbol = product.currency == 'USD' ? r'$' : '${product.currency} ';
    final price = amount ?? product.price;
    final whole = price.truncate();
    final cents = ((price - whole) * 100).round();
    final base = AppTextStyles.displayMedium.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
      fontSize: size,
      height: 1,
      letterSpacing: -0.5,
    );
    final small = base.copyWith(fontSize: size * 0.52, letterSpacing: 0);
    return Semantics(
      label: amount == null
          ? product.formatPrice()
          : '$symbol${price.toStringAsFixed(cents > 0 ? 2 : 0)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: size * 0.08),
            child: Text(symbol, style: small),
          ),
          Text(_group(whole), style: base),
          if (cents > 0)
            Padding(
              padding: EdgeInsets.only(top: size * 0.08),
              child: Text(cents.toString().padLeft(2, '0'), style: small),
            ),
        ],
      ),
    );
  }

  static String _group(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class MarketPill extends StatelessWidget {
  const MarketPill({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.trailingText,
    this.trailing,
    this.leading,
    this.busy = false,
    this.raised = false,
  });
  final String label;
  final String? trailingText;
  final Widget? trailing;
  final IconData? leading;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  final bool busy;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.labelLarge.copyWith(
      color: fg,
      fontWeight: FontWeight.w700,
      fontSize: 15.5,
    );
    return Semantics(
      button: true,
      label: [label, ?trailingText].join(', '),
      excludeSemantics: true,
      child: Pressable(
        onTap: busy ? null : onTap,
        haptics: true,
        pressedScale: 0.97,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: raised
                ? [
                    BoxShadow(
                      color: bg.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: busy
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  ),
                )
              : Row(
                  children: [
                    if (leading != null) ...[
                      Icon(leading, size: 18, color: fg),
                      const SizedBox(width: 8),
                    ],
                    // Expanded, not Flexible + Spacer: those split the free
                    // space in half and cut "Add to basket" short.
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (trailingText != null) ...[
                      Container(
                        width: 1,
                        height: 18,
                        color: fg.withValues(alpha: 0.28),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        trailingText!,
                        style: text.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (trailing != null)
                      IconTheme(
                        data: IconThemeData(color: fg),
                        child: trailing!,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The quiet secondary action next to a [MarketPill]: a labelled chat
/// squircle that opens the seller-contact sheet.
class MarketChatButton extends StatelessWidget {
  const MarketChatButton({
    super.key,
    required this.onTap,
    this.busy = false,
    this.label = 'Chat',
    this.semanticLabel = 'Contact the seller',
  });
  final VoidCallback? onTap;
  final bool busy;
  final String label;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: Pressable(
          onTap: busy ? null : onTap,
          pressedScale: 0.92,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.scaffoldBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.divider),
            ),
            child: busy
                ? const Center(child: BrandSpinner(size: 18))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 20,
                        color: palette.text,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 10.5,
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

/// The pinned bottom bar shell both screens share: hairline on top, safe
/// area, a [MarketChatButton] (optional) and one primary [MarketPill].
class MarketActionBar extends StatelessWidget {
  const MarketActionBar({super.key, required this.primary, this.chat});
  final Widget primary;
  final Widget? chat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (chat != null) ...[chat!, const SizedBox(width: 10)],
              Expanded(child: primary),
            ],
          ),
        ),
      ),
    );
  }
}
