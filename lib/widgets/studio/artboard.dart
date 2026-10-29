import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

/// The dot-grid board the creative surfaces sit on — the create studio's
/// canvas and the publish preview. A design tool's canvas, so "you are
/// making something" reads before any label does.
class StudioArtboard extends StatelessWidget {
  const StudioArtboard({
    super.key,
    required this.child,
    this.background,
    this.padding = const EdgeInsets.all(AppSpace.md),
  });

  final Widget child;

  /// Defaults to the page colour.
  final Color? background;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? context.palette.scaffoldBg;
    final darkBg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sheet),
      child: CustomPaint(
        painter: StudioDotGridPainter(
          background: bg,
          dot: (darkBg ? Colors.white : const Color(0xFF0D1B3E)).withValues(
            alpha: darkBg ? 0.10 : 0.12,
          ),
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            border: Border.all(color: context.palette.divider),
          ),
          child: child,
        ),
      ),
    );
  }
}

class StudioDotGridPainter extends CustomPainter {
  const StudioDotGridPainter({required this.background, required this.dot});

  final Color background;
  final Color dot;

  static const _gap = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()..color = dot;
    for (var y = _gap / 2; y < size.height; y += _gap) {
      for (var x = _gap / 2; x < size.width; x += _gap) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(StudioDotGridPainter old) =>
      old.background != background || old.dot != dot;
}
