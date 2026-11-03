import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cache_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../tour/feature_tour.dart';
import '../../theme/app_tokens.dart';

/// Home's floating "+" (owner, 3 Nov 2026).
///
/// * It rides **just above the island**. When the island slides away on
///   scroll, the "+" glides down into the island's place; when the island
///   comes back, the "+" rises above it again — same 230 ms ease as
///   `HideOnScroll`, so the two move as one.
/// * It can be **dragged anywhere**. On release it snaps to the nearest
///   side (left or right) and keeps the height you left it at, measured
///   from its resting spot above the island, so it never lands under the
///   bar. The spot is remembered on this phone (`pref:` key — a device
///   preference, not per account).
/// * Frosted glass ring with the brand-blue disc, matching the island.
///
/// Mount it in a [Stack] that covers the screen (TabShell does, on Home).
class IslandCreateFab extends StatefulWidget {
  const IslandCreateFab({
    super.key,
    required this.islandVisible,
    required this.onTap,
  });

  final bool islandVisible;
  final VoidCallback onTap;

  /// The island: 62dp tall, 12dp off the bottom inset (MainBottomNav).
  static const double islandHeight = 62;
  static const double islandBottomGap = AppSpace.md;
  static const double size = 58;
  static const double sideMargin = AppSpace.lg;

  /// Where the "+" rests, measured from the bottom safe inset to its bottom
  /// edge, before any height the member dragged it up by.
  @visibleForTesting
  static double restingBottom({required bool islandVisible}) => islandVisible
      // Just above the island, with a 12dp breath.
      ? islandBottomGap + islandHeight + AppSpace.md
      // Centred on where the island was.
      : islandBottomGap + (islandHeight - size) / 2;

  static const _kPos = 'pref:island_fab_pos_v1';

  @override
  State<IslandCreateFab> createState() => _IslandCreateFabState();
}

class _IslandCreateFabState extends State<IslandCreateFab> {
  /// true = right side.
  bool _right = true;

  /// Extra height above the resting spot the member dragged it to.
  double _lift = 0;

  /// Live finger position while dragging (left, bottom in the stack).
  Offset? _drag;

  @override
  void initState() {
    super.initState();
    final saved = CacheService.readPref(IslandCreateFab._kPos);
    if (saved != null) {
      final parts = saved.split(',');
      _right = parts.first != 'l';
      _lift = parts.length > 1 ? double.tryParse(parts[1]) ?? 0 : 0;
    }
  }

  void _save() => CacheService.writePref(
    IslandCreateFab._kPos,
    '${_right ? 'r' : 'l'},${_lift.toStringAsFixed(0)}',
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final inset = MediaQuery.paddingOf(context).bottom;
        final base =
            inset +
            IslandCreateFab.restingBottom(islandVisible: widget.islandVisible);
        // Never higher than ~60% of the screen, never under the island.
        final maxLift = (box.maxHeight * 0.6 - base).clamp(
          0.0,
          double.infinity,
        );
        final lift = _lift.clamp(0.0, maxLift);
        final restLeft = _right
            ? box.maxWidth - IslandCreateFab.size - IslandCreateFab.sideMargin
            : IslandCreateFab.sideMargin;

        final drag = _drag;
        final left = drag?.dx ?? restLeft;
        final bottom = drag?.dy ?? base + lift;

        return Stack(
          children: [
            AnimatedPositioned(
              // Follow the finger exactly; glide everywhere else (snap,
              // island up/down).
              duration: drag != null
                  ? Duration.zero
                  : AppMotion.maybe(context, const Duration(milliseconds: 230)),
              curve: AppMotion.easeOut,
              left: left,
              bottom: bottom,
              width: IslandCreateFab.size,
              height: IslandCreateFab.size,
              child: GestureDetector(
                // Measure the drag from finger-down, so the "+" stays under
                // the finger instead of lagging by the touch slop.
                dragStartBehavior: DragStartBehavior.down,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap();
                },
                onPanStart: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _drag = Offset(restLeft, base + lift));
                },
                onPanUpdate: (d) {
                  final cur = _drag ?? Offset(restLeft, base + lift);
                  setState(() {
                    _drag = Offset(
                      (cur.dx + d.delta.dx).clamp(
                        0.0,
                        box.maxWidth - IslandCreateFab.size,
                      ),
                      (cur.dy - d.delta.dy).clamp(base, base + maxLift),
                    );
                  });
                },
                onPanEnd: (_) {
                  final cur = _drag;
                  if (cur == null) return;
                  setState(() {
                    _right =
                        cur.dx + IslandCreateFab.size / 2 > box.maxWidth / 2;
                    _lift = (cur.dy - base).clamp(0.0, maxLift);
                    _drag = null;
                  });
                  HapticFeedback.lightImpact();
                  _save();
                },
                child: AnimatedScale(
                  scale: drag != null ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 140),
                  child: const TourAnchor(
                    id: 'home_create',
                    child: _GlassPlus(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Frosted ring + brand-blue disc, the island's glass at button size.
class _GlassPlus extends StatelessWidget {
  const _GlassPlus();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blurring = AppMotion.enabled(context);
    final surface = palette.card.withValues(alpha: blurring ? 0.82 : 1.0);

    Widget glass = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: dark
              ? AppColors.white.withValues(alpha: 0.08)
              : palette.divider,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              AppColors.white.withValues(alpha: dark ? 0.06 : 0.5),
              surface,
            ),
            surface,
          ],
        ),
      ),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.34),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: AppColors.white, size: 28),
      ),
    );
    if (blurring) {
      glass = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: glass,
      );
    }
    return Semantics(
      button: true,
      label: 'Create a post. Drag to move.',
      child: Tooltip(
        message: 'Create a post',
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: AppShadows.floating(context),
          ),
          child: ClipOval(child: glass),
        ),
      ),
    );
  }
}
