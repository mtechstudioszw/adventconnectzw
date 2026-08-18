import 'package:flutter/material.dart';

import '../config/countries.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// "🇿🇼 Zimbabwe | Worldwide" — the scope control on the marketplace, jobs
/// and the feed.
///
/// One widget for all three so the choice reads as the same decision
/// wherever it appears, and so a member who learns it once on Marketplace
/// does not have to find it again on Jobs.
///
/// **Country is the default, worldwide is the escape hatch.** This app is
/// never party to a sale or a hire: a listing hands off to WhatsApp and a
/// local pickup, so a result from another country is one the member cannot
/// act on. But the toggle stays one tap away rather than being a setting,
/// because the diaspora really does shop and hire back home, and a member
/// whose profile country is wrong needs a way out that is not "go and edit
/// your profile".
class CountryScopeToggle extends StatelessWidget {
  const CountryScopeToggle({
    super.key,
    required this.countryCode,
    required this.worldwide,
    required this.onChanged,
  });

  /// The member's own country. The left segment names it.
  final String? countryCode;

  /// True when the list is currently unscoped.
  final bool worldwide;

  /// Fires with the NEW worldwide value. Only on an actual change — tapping
  /// the segment already selected does nothing, so it cannot trigger a
  /// pointless refetch of a list the member is already reading.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final country = Countries.byCode(countryCode);
    // Falls back to a generic label rather than inventing a country: if we
    // genuinely do not know where they are, "My country" is honest and the
    // filter still works off whatever code was passed.
    final homeLabel = country == null
        ? 'My country'
        : '${country.flag}  ${country.name}';

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: homeLabel,
            selected: !worldwide,
            onTap: worldwide ? () => onChanged(false) : null,
          ),
          _Segment(
            label: 'Worldwide',
            selected: worldwide,
            onTap: worldwide ? null : () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// Null when this segment is already selected — see
  /// [CountryScopeToggle.onChanged].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? palette.card : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primaryBlue : palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
