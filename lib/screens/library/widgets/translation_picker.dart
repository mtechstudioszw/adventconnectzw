import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/bible_translation.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';

/// Cinematic translation switcher.
///
/// Opens as a blurred full-screen overlay rather than a list sheet: each
/// translation is a card carrying its own script glyph (א, Ω, S, K) and its
/// name in its own language, so choosing a translation feels like picking up a
/// different book instead of ticking a radio button.
///
/// Motion: the backdrop blurs in, cards rise and fade with a stagger, and the
/// chosen card pulses before the overlay dissolves. All of it is skipped when
/// the OS "remove animations" setting is on.
class TranslationPicker extends StatefulWidget {
  const TranslationPicker({super.key, required this.current});

  final BibleTranslation current;

  /// Pushes the picker. Resolves to the chosen translation, or null on
  /// dismiss.
  static Future<BibleTranslation?> show(
    BuildContext context, {
    required BibleTranslation current,
  }) {
    return Navigator.of(context).push<BibleTranslation>(
      PageRouteBuilder<BibleTranslation>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => TranslationPicker(current: current),
        transitionsBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.easeOut,
            reverseCurve: AppMotion.easeIn,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  @override
  State<TranslationPicker> createState() => _TranslationPickerState();
}

class _TranslationPickerState extends State<TranslationPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  String? _chosenId;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _choose(BibleTranslation t) async {
    if (_chosenId != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _chosenId = t.id);
    // Let the selected card's pulse read before the overlay leaves.
    if (AppMotion.enabled(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }
    if (!mounted) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.enabled(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Blurred, dimmed backdrop — the reader stays faintly visible
          // underneath so the switch feels like a layer, not a new screen.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = animate ? _c.value : 1.0;
                  return BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: 18 * t,
                      sigmaY: 18 * t,
                    ),
                    child: ColoredBox(
                      color: AppColors.darkNavy.withValues(alpha: 0.82 * t),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
                    itemCount: BibleTranslations.all.length,
                    itemBuilder: (context, i) {
                      final t = BibleTranslations.all[i];
                      return _card(t, i, animate);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'READ IT IN',
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.goldAccent,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Choose a translation',
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: AppColors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _card(BibleTranslation t, int index, bool animate) {
    final isCurrent = t.id == widget.current.id;
    final isChosen = t.id == _chosenId;

    // Staggered rise: each card starts a beat after the one above it.
    final start = (index * 0.07).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: AppMotion.easeOut),
    );

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final v = animate ? anim.value : 1.0;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - v)),
            child: child,
          ),
        );
      },
      child: AnimatedScale(
        // The chosen card swells for a moment — the "cut" of the transition.
        scale: isChosen ? 1.04 : 1.0,
        duration: AppMotion.quick,
        curve: AppMotion.spring,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _choose(t),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isChosen || isCurrent
                        ? t.accent
                        : AppColors.white.withValues(alpha: 0.16),
                    width: isChosen || isCurrent ? 2 : 1,
                  ),
                  boxShadow: isChosen
                      ? [
                          BoxShadow(
                            color: t.accent.withValues(alpha: 0.5),
                            blurRadius: 22,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    // Script glyph tile — the card's identity.
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            t.accent,
                            Color.lerp(t.accent, Colors.black, 0.35)!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        t.glyph,
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.languageLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.white.withValues(alpha: 0.68),
                            ),
                          ),
                          if (t.note != null) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                if (t.hasAudio) ...[
                                  const Icon(Icons.headphones_rounded,
                                      size: 12,
                                      color: AppColors.goldAccent),
                                  const SizedBox(width: 4),
                                ],
                                if (t.isBundled) ...[
                                  const Icon(Icons.offline_pin_rounded,
                                      size: 12,
                                      color: AppColors.successGreen),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    t.note!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.white
                                          .withValues(alpha: 0.5),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isCurrent && !isChosen)
                      Icon(Icons.check_circle_rounded, color: t.accent),
                    if (isChosen)
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppColors.goldAccent),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps chapter text so a translation change dissolves instead of snapping.
///
/// Keyed on the translation id, so switching Shona → Hebrew cross-fades the
/// whole passage and slides it a few pixels — the "cinematic" beat the switch
/// itself sets up.
class TranslationCrossfade extends StatelessWidget {
  const TranslationCrossfade({
    super.key,
    required this.translationId,
    required this.child,
  });

  final String translationId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(translationId), child: child),
    );
  }
}
