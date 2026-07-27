import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/quiz_generator_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/motion/pressable.dart';
import 'arena_theme.dart';
import 'quiz_lobby_screen.dart';
import 'widgets/arena_backdrop.dart';

/// Boot sequence for the Quiz Arena.
///
/// The Arena is a game inside the app, and games boot — they don't just
/// appear. This gates the lobby behind real preparation work rather than a
/// fake delay: the procedural question index is built from the bundled KJV
/// and the nine sound effects are decoded, both of which genuinely take a
/// moment on a cold start and used to happen invisibly on first tap.
///
/// It's a GATE, not a route: once warm it crossfades straight into
/// [QuizLobbyScreen], so there's no extra entry in the back stack and
/// pressing back from the lobby still leaves the Arena.
class QuizBootScreen extends StatefulWidget {
  const QuizBootScreen({super.key});

  @override
  State<QuizBootScreen> createState() => _QuizBootScreenState();
}

/// One unit of startup work plus the line shown while it runs.
typedef _BootStep = (String label, Future<void> Function() run);

class _QuizBootScreenState extends State<QuizBootScreen> {
  /// Floor on how long the boot screen stays up. Warm starts finish almost
  /// instantly and a screen that flashes for 80ms reads as a glitch, not a
  /// loading state.
  static const _minVisible = Duration(milliseconds: 900);

  late final List<_BootStep> _steps = [
    ('Opening the arena', () async {}),
    ('Loading questions', QuizGenerator.warm),
    ('Tuning sound', QuizSfx.init),
  ];

  int _index = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      setState(() => _index = i);
      try {
        await _steps[i].$2();
      } catch (_) {
        // A failed warm-up must never block play — the generator falls back
        // to on-demand generation and the arena is simply silent.
      }
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minVisible) {
      await Future.delayed(_minVisible - elapsed);
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.maybe(context, AppMotion.entrance),
      child: _ready
          ? const QuizLobbyScreen(key: ValueKey('lobby'))
          : _bootUi(context),
    );
  }

  Widget _bootUi(BuildContext context) {
    // +1 so the bar isn't already full on the last step.
    final progress = (_index + 1) / (_steps.length + 1);
    return Scaffold(
      key: const ValueKey('boot'),
      backgroundColor: ArenaTheme.canvasTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ArenaBackdrop(intensity: 0.85),
          SafeArea(
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: _SettingsButton(
                      onTap: () => showQuizSettings(context),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.xxl,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Emblem breathes while it loads so the screen never
                        // looks frozen on a slow cold start.
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.85, end: 1),
                          duration: AppMotion.celebrate,
                          curve: AppMotion.spring,
                          builder: (context, v, child) =>
                              Transform.scale(scale: v, child: child),
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ArenaTheme.glassStrong,
                              border: Border.all(
                                color: ArenaTheme.glassBorderActive,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ArenaTheme.gold.withValues(
                                    alpha: 0.28,
                                  ),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.emoji_events_rounded,
                              color: ArenaTheme.gold,
                              size: 46,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.xl),
                        Text(
                          'QUIZ ARENA',
                          style: AppTextStyles.displayMedium.copyWith(
                            color: ArenaTheme.textOnNavy,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        Text(
                          'Test your Bible knowledge',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: ArenaTheme.textMutedOnNavy,
                          ),
                        ),
                        const SizedBox(height: AppSpace.xxl),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: progress),
                            duration: AppMotion.standard,
                            curve: AppMotion.ease,
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              backgroundColor: ArenaTheme.glass,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                ArenaTheme.gold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        AnimatedSwitcher(
                          duration: AppMotion.maybe(context, AppMotion.quick),
                          child: Text(
                            '${_steps[_index].$1}…',
                            key: ValueKey(_index),
                            style: AppTextStyles.caption.copyWith(
                              color: ArenaTheme.textFaintOnNavy,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Arena settings',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.88,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ArenaTheme.glass,
            border: Border.all(color: ArenaTheme.glassBorder),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.settings_outlined,
            color: ArenaTheme.textOnNavy,
            size: 21,
          ),
        ),
      ),
    );
  }
}

/// Arena settings: sound and haptics.
///
/// Lives here rather than in app Settings because these are game options —
/// somebody muting the arena mid-match shouldn't have to leave it, and
/// somebody in the app's Settings screen shouldn't be reading about quiz
/// sound effects.
Future<void> showQuizSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _QuizSettingsSheet(),
  );
}

class _QuizSettingsSheet extends StatefulWidget {
  const _QuizSettingsSheet();

  @override
  State<_QuizSettingsSheet> createState() => _QuizSettingsSheetState();
}

class _QuizSettingsSheetState extends State<_QuizSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpace.md),
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        decoration: BoxDecoration(
          color: ArenaTheme.canvasLift,
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          border: Border.all(color: ArenaTheme.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.md,
                AppSpace.xl,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  Text(
                    'Arena settings',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile.adaptive(
              value: !QuizSfx.muted,
              onChanged: (on) async {
                await QuizSfx.setMuted(!on);
                if (!mounted) return;
                setState(() {});
                // Confirm the change audibly — the fastest way to know sound
                // is back is to hear it.
                if (on) QuizSfx.play(QuizSound.tap);
              },
              title: Text(
                'Sound effects',
                style: AppTextStyles.titleSmall.copyWith(
                  color: ArenaTheme.textOnNavy,
                ),
              ),
              subtitle: Text(
                'Taps, ticks, and the finish fanfare',
                style: AppTextStyles.caption.copyWith(
                  color: ArenaTheme.textMutedOnNavy,
                ),
              ),
              secondary: Icon(
                QuizSfx.muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: ArenaTheme.gold,
              ),
              activeThumbColor: ArenaTheme.gold,
            ),
            SwitchListTile.adaptive(
              value: QuizSfx.hapticsEnabled,
              onChanged: (on) async {
                await QuizSfx.setHapticsEnabled(on);
                if (!mounted) return;
                setState(() {});
                if (on) QuizSfx.hapticTap();
              },
              title: Text(
                'Vibration',
                style: AppTextStyles.titleSmall.copyWith(
                  color: ArenaTheme.textOnNavy,
                ),
              ),
              subtitle: Text(
                'Feedback on taps and answers',
                style: AppTextStyles.caption.copyWith(
                  color: ArenaTheme.textMutedOnNavy,
                ),
              ),
              secondary: const Icon(
                Icons.vibration_rounded,
                color: ArenaTheme.gold,
              ),
              activeThumbColor: ArenaTheme.gold,
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }
}
