import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/ads/interstitial_ad_manager.dart';
import '../../../services/quiz_generator_service.dart';
import '../../../services/quiz_music.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/advent_ai_bubble.dart';
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
    // No Advent AI bubble anywhere in the arena (founder, 25 Aug 2026).
    //
    // `/quiz` is on AdventAiBubble.blockedPrefixes too, and that alone
    // should be enough — but the blocklist tests the router's *reported*
    // location, and every screen past the lobby (round, results,
    // matchmaking, a live match) is a plain `MaterialPageRoute` push. A
    // screen that knows it is open is a fact where a router location is
    // an inference, and this one is mounted underneath the entire arena:
    // the boot screen crossfades into the lobby *in place* and stays
    // below everything pushed over it, so one suppress here covers the
    // whole session and lifts on the way out.
    AdventAiBubble.suppress();
    // Start fetching the open-the-quiz interstitial NOW, in parallel with
    // the warm-up below, so it has the whole boot to arrive. Requesting it
    // at the moment we want to show it would almost always miss.
    //
    // No premium check needed here: loadAd() goes through
    // AdsService.canRequestAds, and a subscriber never even issues the
    // request — hiding a loaded ad would still have cost them the fetch and
    // the battery, which is most of what they are paying to be rid of.
    InterstitialAdManager.loadAd();
    unawaited(_boot());
  }

  @override
  void dispose() {
    AdventAiBubble.unsuppress();
    super.dispose();
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

    // The open-the-quiz ad (founder, 4 Aug 2026), shown at the END of boot
    // and BEFORE the lobby is revealed.
    //
    // Order matters. Showing it after the lobby appears would drop a
    // full-screen ad on top of a screen the member had already started
    // reading, which is the most irritating placement available. Showing it
    // here makes the ad the loading wait they were already having, and the
    // lobby is what they get when it ends.
    //
    // Awaited, so the transition below happens once the ad is gone.
    // maybeShow() is cheap and honest when it cannot deliver: no ad loaded,
    // premium, or inside the two-minute cap all return false immediately,
    // so re-entering the arena repeatedly does not mean an ad every time.
    if (!mounted) return;
    await InterstitialAdManager.maybeShow();

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
    // The sheet now carries five controls rather than three. Without this
    // the default half-screen cap clips the last one, and at a large system
    // font size it overflows instead of scrolling.
    isScrollControlled: true,
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
        child: SingleChildScrollView(
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
              // A real level, not just on/off. Plays a tap on release so the
              // chosen loudness is something you hear, not guess at.
              AnimatedOpacity(
                opacity: QuizSfx.muted ? 0.4 : 1,
                duration: const Duration(milliseconds: 180),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl,
                    0,
                    AppSpace.xl,
                    AppSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.volume_down_rounded,
                        size: 18,
                        color: ArenaTheme.textMutedOnNavy,
                      ),
                      Expanded(
                        child: Slider(
                          value: QuizSfx.volume,
                          activeColor: ArenaTheme.gold,
                          label: '${(QuizSfx.volume * 100).round()}%',
                          // Silence belongs to the mute button, which can be
                          // seen and undone. A slider that reaches 0 just
                          // looks like the quiz has no sound.
                          min: QuizSfx.kMinVolume,
                          divisions: 9,
                          onChanged: QuizSfx.muted
                              ? null
                              : (v) {
                                  QuizSfx.setVolume(v);
                                  setState(() {});
                                },
                          onChangeEnd: (_) => QuizSfx.play(QuizSound.tap),
                        ),
                      ),
                      Icon(
                        Icons.volume_up_rounded,
                        size: 18,
                        color: ArenaTheme.textMutedOnNavy,
                      ),
                    ],
                  ),
                ),
              ),
              // The soundtrack, with its own level.
              //
              // Its absence here is what "the volume is not working — it just
              // keeps playing" was. This sheet is the only sound control
              // reachable from inside the arena, and every knob on it drove
              // QuizSfx: the effects toggle, and an effects-only slider. The
              // one thing you can actually hear for the whole round had no
              // control at all, so dragging the slider changed nothing
              // audible and the bed played on.
              SwitchListTile.adaptive(
                value: QuizMusic.enabled,
                onChanged: (on) async {
                  await QuizMusic.setEnabled(on);
                  if (!mounted) return;
                  setState(() {});
                  if (on) await QuizMusic.start();
                },
                title: Text(
                  'Music',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: ArenaTheme.textOnNavy,
                  ),
                ),
                subtitle: Text(
                  QuizMusic.unavailable
                      ? 'The soundtrack could not be loaded on this device'
                      : 'The arena soundtrack. It steps aside for your own '
                            'music on its own.',
                  style: AppTextStyles.caption.copyWith(
                    color: ArenaTheme.textMutedOnNavy,
                  ),
                ),
                secondary: Icon(
                  QuizMusic.enabled
                      ? Icons.music_note_rounded
                      : Icons.music_off_rounded,
                  color: ArenaTheme.gold,
                ),
                activeThumbColor: ArenaTheme.gold,
              ),
              AnimatedOpacity(
                opacity: QuizMusic.enabled ? 1 : 0.4,
                duration: const Duration(milliseconds: 180),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl,
                    0,
                    AppSpace.xl,
                    AppSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.volume_down_rounded,
                        size: 18,
                        color: ArenaTheme.textMutedOnNavy,
                      ),
                      Expanded(
                        child: Slider(
                          value: QuizMusic.volume,
                          activeColor: ArenaTheme.gold,
                          label: '${(QuizMusic.volume * 100).round()}%',
                          min: QuizMusic.kMinVolume,
                          divisions: 9,
                          // No preview clip on release: the loop is already
                          // playing underneath, so the new level is audible
                          // while you are still dragging.
                          onChanged: QuizMusic.enabled
                              ? (v) {
                                  QuizMusic.setVolume(v);
                                  setState(() {});
                                }
                              : null,
                        ),
                      ),
                      Icon(
                        Icons.volume_up_rounded,
                        size: 18,
                        color: ArenaTheme.textMutedOnNavy,
                      ),
                    ],
                  ),
                ),
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
      ),
    );
  }
}
