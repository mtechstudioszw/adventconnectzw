import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Branded chat wallpaper — the WhatsApp/Telegram trick that makes a
/// conversation feel like a *place* instead of a list on a grey page.
///
/// A faint, deterministic doodle field (rings, crosses, sparkles, dots
/// and little arcs in brand navy — or white in dark mode) over a whisper
/// of blue gradient. Painted once into its own layer (RepaintBoundary +
/// shouldRepaint false), so it costs nothing while messages scroll
/// above it.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _WallpaperPainter(dark: dark)),
          ),
        ),
        child,
      ],
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // A breath of brand blue so the canvas isn't dead-flat grey.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primaryBlue.withValues(alpha: dark ? 0.05 : 0.035),
            AppColors.primaryBlue.withValues(alpha: 0.0),
            AppColors.goldAccent.withValues(alpha: dark ? 0.035 : 0.025),
          ],
        ).createShader(Offset.zero & size),
    );

    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = (dark ? AppColors.white : AppColors.darkNavy).withValues(
        alpha: dark ? 0.045 : 0.05,
      );
    final fill = Paint()..color = ink.color;

    // Deterministic doodle grid: every ~56px cell gets one small shape,
    // jittered and rotated by a cheap integer hash so the field looks
    // hand-scattered but never changes between frames.
    const cell = 56.0;
    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final h = _hash(c * 73856093 ^ r * 19349663);
        final jx = ((h & 0xFF) / 255 - 0.5) * cell * 0.6;
        final jy = (((h >> 8) & 0xFF) / 255 - 0.5) * cell * 0.6;
        final center = Offset(c * cell + jx, r * cell + jy);
        final angle = ((h >> 16) & 0xFF) / 255 * math.pi;

        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        switch ((h >> 24) % 6) {
          case 0: // ring
            canvas.drawCircle(Offset.zero, 5.5, ink);
          case 1: // cross
            canvas.drawLine(const Offset(-4, 0), const Offset(4, 0), ink);
            canvas.drawLine(const Offset(0, -4), const Offset(0, 4), ink);
          case 2: // sparkle
            for (var i = 0; i < 4; i++) {
              final a = i * math.pi / 2 + math.pi / 4;
              canvas.drawLine(
                Offset(math.cos(a) * 2, math.sin(a) * 2),
                Offset(math.cos(a) * 5.5, math.sin(a) * 5.5),
                ink,
              );
            }
          case 3: // dot
            canvas.drawCircle(Offset.zero, 1.6, fill);
          case 4: // open arc (little smile)
            canvas.drawArc(
              Rect.fromCircle(center: Offset.zero, radius: 6),
              0.4,
              1.8,
              false,
              ink,
            );
          case 5: // tiny diamond
            final path = Path()
              ..moveTo(0, -4.5)
              ..lineTo(3.5, 0)
              ..lineTo(0, 4.5)
              ..lineTo(-3.5, 0)
              ..close();
            canvas.drawPath(path, ink);
        }
        canvas.restore();
      }
    }
  }

  /// Cheap deterministic integer hash (xorshift-flavoured).
  int _hash(int x) {
    var h = x;
    h = (h ^ (h >> 16)) * 0x45d9f3b;
    h = (h ^ (h >> 16)) * 0x45d9f3b;
    h = h ^ (h >> 16);
    return h & 0x7fffffff;
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) => old.dark != dark;
}
