import 'dart:async';

import 'package:flutter/material.dart';

import '../config/router_config.dart';
import '../screens/calls/call_screen.dart';
import '../services/calls/call_service.dart';
import '../services/calls/call_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// "Tap to return to call" — shown at the top of every screen while a
/// call is live and the call screen is not on top (owner, 3 Nov 2026).
///
/// Back on the call screen now leaves it without ending the call; this bar
/// is the way back, the same as WhatsApp's. Brand blue, not green: green
/// backgrounds are off-palette (CLAUDE.md).
class OngoingCallBar extends StatefulWidget {
  const OngoingCallBar({super.key});

  @override
  State<OngoingCallBar> createState() => _OngoingCallBarState();
}

class _OngoingCallBarState extends State<OngoingCallBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The elapsed time on the bar moves once a second while connected.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && CallService.value.phase == CallPhase.connected) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([CallService.state, CallScreen.onScreen]),
      builder: (context, _) {
        final state = CallService.value;
        final show = state.phase.isLive && !CallScreen.onScreen.value;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: !show
              ? const SizedBox.shrink()
              : _Bar(
                  title: state.peerName ?? 'Call',
                  status: state.phase == CallPhase.connected
                      ? _fmt(state.elapsed)
                      : state.phase.label,
                  onTap: () => appRouter.pushNamed('call'),
                ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.title, required this.status, required this.onTap});

  final String title;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryBlue,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                const Icon(
                  Icons.call_rounded,
                  color: AppColors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap to return to call · $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  status,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
