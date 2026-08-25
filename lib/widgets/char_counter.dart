import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// "142/1000" — how much you have typed, and the ceiling.
///
/// The founder's rule (25 Aug 2026): **every field you can type into tells
/// you its limit.** Before this, most fields either had no limit in the
/// client at all — so the database rejected the insert afterwards with an
/// unexplained failure — or had one with `counterText: ''` hiding it, so
/// the field simply stopped accepting letters with no explanation.
///
/// Two ways to show it:
///
///   * Form fields keep Flutter's own counter, which draws under the
///     input. Those just stop suppressing it — there is nothing to add.
///   * Chat-style composers (the chat bar, the comment box) are round
///     pills with no room underneath, so they use this instead and place
///     it themselves.
///
/// It stays out of the way until there is something to say: nothing at all
/// on an empty field, muted while you have room, red once you are inside
/// the last [_warnWithin] characters or have hit the wall. [alwaysShow]
/// forces it on for a field where the limit is the point.
class CharCounter extends StatelessWidget {
  const CharCounter({
    super.key,
    required this.used,
    required this.max,
    this.alwaysShow = false,
  });

  final int used;
  final int max;
  final bool alwaysShow;

  /// How close to the ceiling before the counter turns red.
  static const int _warnWithin = 40;

  @override
  Widget build(BuildContext context) {
    if (used == 0 && !alwaysShow) return const SizedBox.shrink();
    final urgent = max - used <= _warnWithin;
    return Text(
      '$used/$max',
      style: AppTextStyles.labelSmall.copyWith(
        color: urgent ? AppColors.red : context.palette.textMuted,
        fontSize: 11,
        fontWeight: urgent ? FontWeight.w700 : FontWeight.w600,
      ),
    );
  }
}
