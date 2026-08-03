import 'package:flutter/material.dart';

import '../../services/quiz_music.dart';
import '../../services/quiz_sfx.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Sound and haptics, in the main settings where they can be found.
///
/// These controls used to live ONLY on the Quiz Arena's boot screen — and
/// that screen is a gate, not a route: it crossfades into the lobby after
/// roughly 900ms and is never seen again. So the volume slider existed for
/// under a second per launch and was effectively unreachable, which is how
/// it was reported ("the settings button appears only while quiz is
/// loading"). Worse, the slider used to reach 0%, so a single stray drag
/// could silence the arena permanently with no way back and no
/// explanation. See [QuizSfx.kMinVolume].
///
/// Effects and haptics are deliberately separate: muting is about sound in
/// a quiet room, and silent feedback is exactly what you still want there.
class SoundSettingsScreen extends StatefulWidget {
  const SoundSettingsScreen({super.key});

  @override
  State<SoundSettingsScreen> createState() => _SoundSettingsScreenState();
}

class _SoundSettingsScreenState extends State<SoundSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Without these two lines every control on this screen renders from a
    // compiled-in default rather than from what the member actually saved.
    // `QuizSfx` used to read its preferences only inside `init()`, which
    // builds the audio pool and runs when the ARENA opens — so arriving
    // here from Settings, without having played that session, showed every
    // switch ON no matter what was stored. Someone who had muted the quiz
    // saw "Sound effects: ON", changed nothing, and still got silence.
    QuizSfx.loadPrefs();
    QuizMusic.loadPrefs();
  }

  Future<void> _setEffects(bool on) async {
    await QuizSfx.setMuted(!on);
    if (!mounted) return;
    setState(() {});
    // Play the confirmation AFTER the state lands, so turning sound on
    // demonstrates itself.
    if (on) QuizSfx.play(QuizSound.tap);
  }

  Future<void> _setVolume(double v) async {
    await QuizSfx.setVolume(v);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setMusic(bool on) async {
    await QuizMusic.setEnabled(on);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setMusicVolume(double v) async {
    await QuizMusic.setVolume(v);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setHaptics(bool on) async {
    await QuizSfx.setHapticsEnabled(on);
    if (!mounted) return;
    setState(() {});
    if (on) QuizSfx.hapticTap();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final effectsOn = !QuizSfx.muted;

    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ScreenHero brings its own FlatStatusBar, SafeArea and back
            // button — the flat header pattern, never a navy slab.
            const ScreenHero(
              title: 'Sound & haptics',
              subtitle: 'How the app sounds and feels when you tap.',
              fallbackRoute: 'settings',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  _Card(
                    children: [
                      _ToggleTile(
                        icon: Icons.graphic_eq_rounded,
                        label: 'Sound effects',
                        subtitle:
                            'Taps, countdown ticks and answer sounds in the '
                            'Quiz Arena.',
                        value: effectsOn,
                        onChanged: _setEffects,
                      ),
                      const _Divider(),
                      _VolumeTile(
                        enabled: effectsOn,
                        value: QuizSfx.volume,
                        onChanged: _setVolume,
                        // Playing on release rather than on every drag
                        // frame — otherwise dragging machine-guns the clip.
                        onChangeEnd: () => QuizSfx.play(QuizSound.tap),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Card(
                    children: [
                      _ToggleTile(
                        icon: Icons.music_note_rounded,
                        label: 'Quiz music',
                        subtitle:
                            'A soundtrack while you play. It steps aside on '
                            'its own if you are already playing your own '
                            'music.',
                        value: QuizMusic.enabled,
                        onChanged: _setMusic,
                      ),
                      const _Divider(),
                      _VolumeTile(
                        enabled: QuizMusic.enabled,
                        value: QuizMusic.volume,
                        min: QuizMusic.kMinVolume,
                        onChanged: _setMusicVolume,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Card(
                    children: [
                      _ToggleTile(
                        icon: Icons.vibration_rounded,
                        label: 'Vibration',
                        subtitle:
                            'Kept separate from sound on purpose — in a quiet '
                            'room, silent feedback is often exactly what you '
                            'want.',
                        value: QuizSfx.hapticsEnabled,
                        onChanged: _setHaptics,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'The Quiz Arena never interrupts your music — its sounds '
                    'mix with whatever is already playing.',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, thickness: 1, color: context.palette.divider),
  );
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _VolumeTile extends StatelessWidget {
  const _VolumeTile({
    required this.enabled,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = QuizSfx.kMinVolume,
  });

  final bool enabled;
  final double value;
  final ValueChanged<double> onChanged;

  /// Optional preview on release. The effects slider plays a tap so the
  /// new level demonstrates itself; the music slider needs no preview
  /// because the loop is already audible while you drag it.
  final VoidCallback? onChangeEnd;

  /// Each control has its own floor — see [QuizSfx.kMinVolume] and
  /// [QuizMusic.kMinVolume]. Neither may reach silence: that is what the
  /// toggle above it is for.
  final double min;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Row(
          children: [
            Icon(Icons.volume_down_rounded, size: 19, color: palette.textMuted),
            Expanded(
              child: Slider(
                // Floored above silence on purpose: turning sound OFF is
                // the toggle above, which says so and can be turned back
                // on. A slider that reaches zero just looks broken.
                min: min,
                max: 1.0,
                divisions: 9,
                value: value.clamp(min, 1.0),
                label: '${(value * 100).round()}%',
                onChanged: enabled ? onChanged : null,
                onChangeEnd: (enabled && onChangeEnd != null)
                    ? (_) => onChangeEnd!()
                    : null,
              ),
            ),
            Icon(Icons.volume_up_rounded, size: 19, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
