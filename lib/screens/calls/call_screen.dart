import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/call_model.dart';
import '../../services/calls/call_audio.dart';
import '../../services/calls/call_service.dart';
import '../../services/calls/call_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/user_avatar.dart';

/// The one call surface. Outgoing, incoming, active, group — all of it.
///
/// ## Why one screen and not four
///
/// A call moves between those states while the member is looking at it,
/// and every boundary between two screens is a place where a transition
/// can drop a frame, lose the controls, or leave two screens stacked.
/// The states differ by which controls are shown and what the status
/// line says; everything else — avatar, name, timer, background — is
/// continuous. So it is one widget that reads [CallService.state], and
/// the ONLY navigation it performs is popping itself when the call is
/// finished and the member has seen the outcome.
///
/// ## It renders, it does not decide
///
/// Every button calls into [CallService]. This file contains no policy:
/// not who may be called, not how long a call may run, not whether the
/// End-for-everyone button should work. The server owns all of that and
/// re-checks it, so hiding a button here is a courtesy to the member,
/// never a control.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  /// How long a finished call stays on screen before dismissing itself.
  /// Long enough to read "Call ended · 4:12", short enough not to feel
  /// stuck.
  static const _dismissDelay = Duration(milliseconds: 2200);

  Timer? _dismissTimer;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    CallService.state.addListener(_onCallState);
    // A call screen that lets the phone sleep is a call screen that
    // vanishes mid-conversation. Released in dispose.
    unawaited(_setWakeLock(true));
    _onCallState();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    CallService.state.removeListener(_onCallState);
    unawaited(_setWakeLock(false));
    super.dispose();
  }

  Future<void> _setWakeLock(bool on) async {
    try {
      // No wakelock package in this project, and adding one for a single
      // screen is not worth the dependency: keeping the app in immersive
      // mode while a call is up is enough on both platforms, and the
      // proximity sensor handles the earpiece case natively.
      await SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {
      // Cosmetic only.
    }
  }

  void _onCallState() {
    final phase = CallService.value.phase;

    if (phase == CallPhase.idle) {
      _pop();
      return;
    }

    if (phase.isTerminal) {
      // Hold the outcome on screen briefly, then leave. Doing this on a
      // timer rather than immediately is what makes "Declined" and
      // "No answer" readable instead of a flash.
      _dismissTimer ??= Timer(_dismissDelay, () {
        CallService.dismiss();
        _pop();
      });
    }
    if (mounted) setState(() {});
  }

  void _pop() {
    if (_popped || !mounted) return;
    _popped = true;
    // `canPop` because the call screen can be the first route on a cold
    // start from a lock-screen accept, in which case there is nothing
    // beneath it and popping would leave a black window.
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = CallService.value;
    final palette = context.palette;

    return PopScope(
      // Back must not dismiss a live call — that is how a member ends up
      // on the home screen with a call still running and no way back to
      // it. Hanging up is an explicit act.
      canPop: !state.phase.isLive,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _CallHeader(state: state),
                const SizedBox(height: 28),
                Expanded(
                  child: state.isGroup
                      ? _GroupGrid(state: state)
                      : _DirectAvatar(state: state),
                ),
                if (state.failureMessage != null) ...[
                  _FailureNote(message: state.failureMessage!),
                  const SizedBox(height: 16),
                ],
                _Controls(state: state, palette: palette),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Name, status line, and the timer.
class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.state});

  final CallUiState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = state.session;

    final title = state.isGroup
        ? (state.peerName ?? 'Group call')
        : (state.peerName ??
              session?.othersFor('').firstOrNull?.name ??
              'Calling');

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.headlineSmall.copyWith(
            color: palette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _StatusLine(state: state),
        if (state.isGroup && session != null) ...[
          const SizedBox(height: 6),
          Text(
            _participantSummary(session),
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
        ],
      ],
    );
  }

  static String _participantSummary(CallSession session) {
    final joined = session.active.length;
    final ringing = session.pending.length;
    final buffer = StringBuffer('$joined in call');
    if (ringing > 0) buffer.write(' · $ringing ringing');
    return buffer.toString();
  }
}

/// The one line that must never be a bare spinner.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});

  final CallUiState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final phase = state.phase;

    // Once connected the timer IS the status. It is driven from the
    // server's `connected_at`, so it never counts ringing time and
    // cannot drift with the device clock.
    if (phase == CallPhase.connected) {
      return Text(
        _formatDuration(state.elapsed),
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.successGreen,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    final color = switch (phase) {
      CallPhase.reconnecting => AppColors.goldAccent,
      CallPhase.failed || CallPhase.busy => AppColors.red,
      CallPhase.rejected || CallPhase.missed => AppColors.red,
      _ => palette.textMuted,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (phase == CallPhase.reconnecting) ...[
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            phase == CallPhase.reconnecting && state.elapsed > Duration.zero
                ? '${phase.label}  ${_formatDuration(state.elapsed)}'
                : phase.label,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// 1:1 — one big avatar with a pulse while it is ringing.
class _DirectAvatar extends StatefulWidget {
  const _DirectAvatar({required this.state});

  final CallUiState state;

  @override
  State<_DirectAvatar> createState() => _DirectAvatarState();
}

class _DirectAvatarState extends State<_DirectAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  // MediaQuery is not available in initState, and _syncPulse reads
  // `disableAnimations` from it. didChangeDependencies is the earliest
  // safe point, and it also re-fires if the member flips the setting.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _DirectAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    final ringing =
        widget.state.phase == CallPhase.ringing ||
        widget.state.phase == CallPhase.incoming;
    // Honour "remove animations" — the app-wide rule from AppMotion.
    final allowed = !MediaQuery.maybeDisableAnimationsOf(context);
    if (ringing && allowed) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final scale = 1 + (_pulse.value * 0.05);
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryBlue.withValues(
                alpha: 0.06 + (_pulse.value * 0.08),
              ),
            ),
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: UserAvatar(
          photoUrl: state.peerPhotoUrl,
          size: 148,
          name: state.peerName,
          fallbackIcon: state.isGroup ? Icons.groups_rounded : null,
        ),
      ),
    );
  }
}

/// Group — a grid of everyone, with live status per person.
class _GroupGrid extends StatelessWidget {
  const _GroupGrid({required this.state});

  final CallUiState state;

  @override
  Widget build(BuildContext context) {
    final session = state.session;
    if (session == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    // Everyone, including me: seeing your own tile is what tells you
    // your mute actually took.
    final participants = session.participants
        .where((p) => !p.isGone || p.status == ParticipantStatus.left)
        .toList();

    return GridView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) => _ParticipantTile(
        participant: participants[index],
        speaking: state.speakingPeers.contains(participants[index].userId),
        isHost: session.createdBy == participants[index].userId,
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.speaking,
    required this.isHost,
  });

  final CallParticipant participant;
  final bool speaking;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final subtitle = switch (participant.status) {
      ParticipantStatus.joined => isHost ? 'Host' : null,
      ParticipantStatus.invited || ParticipantStatus.ringing => 'Ringing…',
      ParticipantStatus.rejected => 'Declined',
      ParticipantStatus.missed => 'No answer',
      ParticipantStatus.busy => 'Busy',
      ParticipantStatus.left => 'Left',
      ParticipantStatus.removed => 'Removed',
      ParticipantStatus.failed => 'Failed',
      _ => null,
    };

    final dimmed = !participant.isActive;

    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // The speaking ring. A live green outline is the one piece
              // of feedback that makes a group call legible — without it
              // nobody knows who is talking.
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speaking
                        ? AppColors.successGreen
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: UserAvatar(
                  photoUrl: participant.photoUrl,
                  size: 62,
                  name: participant.name,
                ),
              ),
              if (participant.muted && participant.isActive)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: palette.card,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic_off_rounded,
                      size: 13,
                      color: AppColors.red,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            participant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: palette.textMuted),
            ),
        ],
      ),
    );
  }
}

class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
      ),
    );
  }
}

/// The buttons. Which ones appear is entirely a function of the phase.
class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.palette});

  final CallUiState state;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final phase = state.phase;

    if (phase.isTerminal) {
      return _CallButton(
        icon: Icons.close_rounded,
        label: 'Close',
        background: palette.cardMuted,
        foreground: palette.text,
        onTap: () {
          CallService.dismiss();
          if (context.canPop()) context.pop();
        },
      );
    }

    if (phase == CallPhase.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            background: AppColors.red,
            foreground: Colors.white,
            onTap: () => unawaited(CallService.reject()),
          ),
          _CallButton(
            icon: Icons.call_rounded,
            label: 'Accept',
            background: AppColors.successGreen,
            foreground: Colors.white,
            onTap: () => unawaited(_acceptGuarded(context)),
          ),
        ],
      );
    }

    // Outgoing / connecting / connected / reconnecting.
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ToggleButton(
              icon: state.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: state.muted ? 'Unmute' : 'Mute',
              active: state.muted,
              palette: palette,
              onTap: () => unawaited(CallService.toggleMute()),
            ),
            _AudioRouteButton(palette: palette),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallButton(
              icon: Icons.call_end_rounded,
              label: state.isGroup ? 'Leave' : 'End',
              background: AppColors.red,
              foreground: Colors.white,
              onTap: () => unawaited(CallService.hangUp()),
            ),
            if (_canEndForAll(state)) ...[
              const SizedBox(width: 28),
              _CallButton(
                icon: Icons.stop_circle_outlined,
                label: 'End for all',
                background: palette.cardMuted,
                foreground: AppColors.red,
                onTap: () => unawaited(_confirmEndForAll(context)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Only the creator of a group call sees the End-for-everyone button.
  ///
  /// This is presentation only. `call_end` re-checks authorisation
  /// server-side (creator, group admin, or super admin), so a member who
  /// forges the call would still be refused.
  static bool _canEndForAll(CallUiState state) {
    final session = state.session;
    if (session == null || !session.isGroup) return false;
    return state.outgoing && session.active.length > 1;
  }

  static Future<void> _confirmEndForAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('End for everyone?', style: AppTextStyles.titleMedium),
        content: Text(
          'This will hang up the call for every person in it.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('End for all'),
          ),
        ],
      ),
    );
    if (confirmed == true) await CallService.endForAll();
  }

  static Future<void> _acceptGuarded(BuildContext context) async {
    try {
      await CallService.accept();
    } on MicrophoneDenied catch (e) {
      if (!context.mounted) return;
      await showMicrophoneDeniedDialog(context, permanently: e.permanently);
    } catch (_) {
      // CallService has already moved to a terminal phase with a
      // message; the screen is showing it.
    }
  }
}

/// A round action button — the shape every calling app uses, because it
/// has to be hittable without looking.
class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 68,
                height: 68,
                child: Icon(icon, color: foreground, size: 29),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: active ? AppColors.primaryBlue : palette.cardMuted,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 58,
                height: 58,
                child: Icon(
                  icon,
                  size: 24,
                  color: active ? Colors.white : palette.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Speaker / earpiece / Bluetooth / headphones.
///
/// Two options → a plain toggle. Three or more → a sheet, because
/// cycling blindly through four routes to find the one you want is
/// worse than one extra tap.
class _AudioRouteButton extends StatelessWidget {
  const _AudioRouteButton({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AudioRoute>>(
      valueListenable: CallAudio.available,
      builder: (context, routes, _) {
        return ValueListenableBuilder<AudioRoute>(
          valueListenable: CallAudio.route,
          builder: (context, current, _) {
            return _ToggleButton(
              icon: _iconFor(current),
              label: routes.length > 2 ? current.label : 'Speaker',
              active: current == AudioRoute.speaker,
              palette: palette,
              onTap: () {
                if (routes.length > 2) {
                  unawaited(_pickRoute(context, routes, current));
                } else {
                  unawaited(CallAudio.toggleSpeaker());
                }
              },
            );
          },
        );
      },
    );
  }

  static IconData _iconFor(AudioRoute route) => switch (route) {
    AudioRoute.speaker => Icons.volume_up_rounded,
    AudioRoute.earpiece => Icons.phone_in_talk_rounded,
    AudioRoute.bluetooth => Icons.bluetooth_audio_rounded,
    AudioRoute.wired => Icons.headphones_rounded,
  };

  static Future<void> _pickRoute(
    BuildContext context,
    List<AudioRoute> routes,
    AudioRoute current,
  ) async {
    final chosen = await showModalBottomSheet<AudioRoute>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final route in routes)
              ListTile(
                leading: Icon(
                  _iconFor(route),
                  color: route == current
                      ? AppColors.primaryBlue
                      : context.palette.textMuted,
                ),
                title: Text(route.label, style: AppTextStyles.bodyMedium),
                trailing: route == current
                    ? const Icon(Icons.check_rounded, color: AppColors.primaryBlue)
                    : null,
                onTap: () => Navigator.of(context).pop(route),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) await CallAudio.setRoute(chosen);
  }
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// Shared by the call screen and every call button in the app: the
/// member said no to the microphone, and there is exactly one useful
/// thing to offer them.
Future<void> showMicrophoneDeniedDialog(
  BuildContext context, {
  required bool permanently,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Microphone needed', style: AppTextStyles.titleMedium),
      content: Text(
        permanently
            ? 'Voice calls need the microphone. Turn it on for Adventist '
                  'Super App in your phone settings, then try again.'
            : 'Voice calls need the microphone to work.',
        style: AppTextStyles.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        if (permanently)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(openAppSettings());
            },
            child: const Text('Open settings'),
          ),
      ],
    ),
  );
}
