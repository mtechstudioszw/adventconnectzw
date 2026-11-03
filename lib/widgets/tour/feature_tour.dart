import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cache_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';

/// Guided feature tour (owner, 3 Nov 2026): "it greys out everything and
/// highlights a button — you click this, it does this".
///
/// * [TourAnchor] marks something the tour can point at, by id. Anchors
///   register themselves while mounted; no GlobalKeys, because the island
///   can be built twice at once (shell + a pushed screen) and a duplicate
///   GlobalKey would crash the app.
/// * [FeatureTour.run] dims the screen, cuts a soft spotlight around each
///   anchor in turn and shows a card explaining it. Steps whose anchor
///   isn't on screen are skipped.
/// * Each tour has an id; once finished or skipped it never shows again
///   on this phone (`pref:` — a device preference).
class TourAnchor extends StatefulWidget {
  const TourAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  static final Map<String, _TourAnchorState> _live = {};

  /// Where [id] is on screen right now, or null.
  static Rect? rectOf(String id) {
    final state = _live[id];
    if (state == null || !state.mounted) return null;
    final box = state.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchor._live[widget.id] = this;
  }

  @override
  void didUpdateWidget(TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (TourAnchor._live[old.id] == this) TourAnchor._live.remove(old.id);
      TourAnchor._live[widget.id] = this;
    }
  }

  @override
  void dispose() {
    if (TourAnchor._live[widget.id] == this) {
      TourAnchor._live.remove(widget.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One stop on a tour.
class TourStep {
  const TourStep({
    required this.anchor,
    required this.title,
    required this.body,
    this.icon,
  });

  final String anchor;
  final String title;
  final String body;
  final IconData? icon;
}

class FeatureTour {
  FeatureTour._();

  static String _key(String tourId) => 'pref:tour_done_$tourId';

  static bool isDone(String tourId) =>
      CacheService.readPref(_key(tourId)) == '1';

  static Future<void> markDone(String tourId) =>
      CacheService.writePref(_key(tourId), '1');

  static bool _running = false;

  /// Runs [steps] once per phone. Returns true if it was shown.
  static Future<bool> run(
    BuildContext context, {
    required String tourId,
    required List<TourStep> steps,
  }) async {
    if (_running || isDone(tourId)) return false;
    final visible = [
      for (final s in steps)
        if (TourAnchor.rectOf(s.anchor) != null) s,
    ];
    if (visible.isEmpty) return false;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;
    _running = true;
    final done = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        steps: visible,
        onFinish: () {
          entry.remove();
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    overlay.insert(entry);
    await done.future;
    _running = false;
    await markDone(tourId);
    return true;
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.onFinish});

  final List<TourStep> steps;
  final VoidCallback onFinish;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay>
    with SingleTickerProviderStateMixin {
  int _i = 0;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    HapticFeedback.selectionClick();
    if (_i + 1 >= widget.steps.length) return _finish();
    setState(() => _i++);
  }

  Future<void> _finish() async {
    await _fade.reverse();
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final size = MediaQuery.sizeOf(context);
    final target =
        (TourAnchor.rectOf(step.anchor) ??
                Rect.fromCenter(
                  center: size.center(Offset.zero),
                  width: 0,
                  height: 0,
                ))
            .inflate(8);
    final below = target.center.dy < size.height / 2;
    final dur = AppMotion.maybe(context, const Duration(milliseconds: 320));

    return FadeTransition(
      opacity: _fade,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Dim everything; tapping anywhere moves on.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _next,
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: target),
                  duration: dur,
                  curve: Curves.easeOutCubic,
                  builder: (context, rect, _) =>
                      CustomPaint(painter: _SpotlightPainter(rect ?? target)),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: dur,
              curve: Curves.easeOutCubic,
              left: 16,
              right: 16,
              top: below
                  ? math.min(target.bottom + 14, size.height - 260)
                  : null,
              bottom: below
                  ? null
                  : math.max(size.height - target.top + 14, 24),
              child: _Card(
                step: step,
                index: _i,
                total: widget.steps.length,
                onNext: _next,
                onSkip: _finish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole);

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(hole.shortestSide / 2, 28.0);
    final outer = Path()..addRect(Offset.zero & size);
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, cut),
      Paint()..color = const Color(0xD90D1B3E),
    );
    // A gold ring around the spotlight — the app's ring motif.
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole.inflate(2), Radius.circular(radius + 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.goldAccent,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}

class _Card extends StatelessWidget {
  const _Card({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final last = index + 1 == total;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (step.icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(step.icon, color: AppColors.white, size: 19),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  step.title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.darkNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color(0xFF1A1A2E),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${index + 1} of $total',
                style: AppTextStyles.caption.copyWith(
                  color: const Color(0x991A1A2E),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!last)
                TextButton(onPressed: onSkip, child: const Text('Skip tour')),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(last ? 'Got it' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
