import 'package:flutter/material.dart';

import '../services/voice_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// WhatsApp-style global voice-note bar. Pinned just under the status bar,
/// it appears whenever a voice note is playing while the user is NOT in
/// that note's chat — play/pause, scrub progress, and a close button.
class VoiceMiniBar extends StatelessWidget {
  const VoiceMiniBar({super.key});

  String _fmt(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final svc = VoicePlayerService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([
        svc.activeId,
        svc.activeConversationId,
        VoicePlayerService.openChatId,
        svc.playing,
        svc.position,
        svc.duration,
      ]),
      builder: (context, _) {
        final activeId = svc.activeId.value;
        final inItsChat = svc.activeConversationId.value != null &&
            svc.activeConversationId.value ==
                VoicePlayerService.openChatId.value;
        // Show only when a note is active and we're outside its chat.
        final show = activeId != null && !inItsChat;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: !show
              ? const SizedBox.shrink()
              : _Bar(
                  playing: svc.playing.value,
                  position: svc.position.value,
                  duration: svc.duration.value,
                  fmt: _fmt,
                  onToggle: () =>
                      svc.playing.value ? svc.pause() : svc.resume(),
                  onClose: () => svc.stop(),
                ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.playing,
    required this.position,
    required this.duration,
    required this.fmt,
    required this.onToggle,
    required this.onClose,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final String Function(Duration) fmt;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
    final fraction = (position.inMilliseconds / total).clamp(0.0, 1.0);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          color: AppColors.darkNavy,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: AppColors.white,
                  ),
                  onPressed: onToggle,
                ),
                const Icon(Icons.mic_rounded,
                    color: AppColors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice note',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 3,
                          backgroundColor:
                              AppColors.white.withValues(alpha: 0.25),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.goldAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  fmt(position),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, color: AppColors.white),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
