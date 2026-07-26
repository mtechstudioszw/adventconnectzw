import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../widgets/cached_image.dart';

/// Shared visual pieces for the Music experience. Kept in one file so the
/// player, the mini bar and the track list all move with the same voice.

// ---------------------------------------------------------------------------
//  Album art — cover image with a branded gradient fallback.
// ---------------------------------------------------------------------------

/// Square cover art. Falls back to the brand gradient + a note glyph when the
/// track has no `cover_url`, so a list of un-arted uploads still looks
/// deliberate rather than broken.
class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    required this.coverUrl,
    required this.size,
    this.radius = 12,
    this.icon = Icons.music_note_rounded,
  });

  final String? coverUrl;
  final double size;
  final double radius;
  final IconData icon;

  bool get _hasArt => coverUrl != null && coverUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: _hasArt
            ? CachedImage(coverUrl!, fit: BoxFit.cover)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
                child: Icon(
                  icon,
                  color: AppColors.white.withValues(alpha: 0.92),
                  size: size * 0.42,
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Blurred backdrop — the "now playing" atmosphere.
// ---------------------------------------------------------------------------

/// Full-bleed blurred cover art behind the full player, scrimmed down to navy
/// so white text always clears contrast regardless of the artwork.
///
/// When the track has no art this is a pure navy gradient — no blur pass at
/// all, which keeps mid-range Androids from paying for an effect that would
/// render as a flat colour anyway.
class BlurredArtBackdrop extends StatelessWidget {
  const BlurredArtBackdrop({super.key, required this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final hasArt = coverUrl != null && coverUrl!.isNotEmpty;
    if (!hasArt) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A2F5A), AppColors.darkNavy],
          ),
        ),
        child: SizedBox.expand(),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedImage(coverUrl!, fit: BoxFit.cover),
        // Heavy blur + saturation-killing scrim. Two stacked layers because a
        // single dark overlay either washes the art out or leaves hot spots
        // that fight the controls.
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
          child: const SizedBox.expand(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.darkNavy.withValues(alpha: 0.62),
                AppColors.darkNavy.withValues(alpha: 0.88),
                AppColors.darkNavy,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Equalizer bars — the "this row is playing" affordance.
// ---------------------------------------------------------------------------

/// Three bars that bounce while audio is playing and settle flat when paused.
///
/// Purely decorative — it is NOT driven by real audio amplitude (just_audio
/// exposes no visualizer on Android without a native plugin). It reads as
/// "this is the live track", which is the job.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color = AppColors.primaryBlue,
    this.size = 18,
    this.barCount = 3,
  });

  final bool playing;
  final Color color;
  final double size;
  final int barCount;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
      _c.animateTo(0, duration: AppMotion.quick);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour "remove animations": show a static glyph instead of a loop.
    if (!AppMotion.enabled(context)) {
      return Icon(Icons.graphic_eq_rounded,
          color: widget.color, size: widget.size);
    }
    final barWidth = widget.size / (widget.barCount * 2 - 1);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < widget.barCount; i++)
                _bar(i, barWidth),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(int i, double width) {
    // Offset each bar's phase so they never move as one block.
    final phase = _c.value * 2 * math.pi + (i * math.pi / 1.7);
    final wave = (math.sin(phase) + 1) / 2; // 0..1
    final height = widget.size * (0.28 + wave * 0.72);
    return Container(
      width: width,
      height: widget.playing ? height : widget.size * 0.22,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(width),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Spinning record — the full player's "it's alive" cue.
// ---------------------------------------------------------------------------

/// Slowly rotates its child while [playing], easing to a stop when paused.
/// Used behind the full player's cover art so the screen has a heartbeat
/// without a distracting animation.
class SlowSpin extends StatefulWidget {
  const SlowSpin({super.key, required this.playing, required this.child});

  final bool playing;
  final Widget child;

  @override
  State<SlowSpin> createState() => _SlowSpinState();
}

class _SlowSpinState extends State<SlowSpin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant SlowSpin old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return widget.child;
    return RotationTransition(turns: _c, child: widget.child);
  }
}

// ---------------------------------------------------------------------------
//  Formatting
// ---------------------------------------------------------------------------

/// mm:ss (or h:mm:ss past an hour) for seek labels and track durations.
String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '${d.inMinutes}:${two(seconds)}';
}
