import 'package:flutter/material.dart';

import '../config/router_config.dart';
import '../services/voice_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// WhatsApp-style global voice-note bar. Pinned just under the status bar,
/// it appears whenever a voice note is playing (or finished, paused) while
/// the user is NOT in that note's chat. Play/pause, a DRAGGABLE scrub bar,
/// tap to jump to the chat it came from, and a close button (the only
/// thing that dismisses it).
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
        final convId = svc.activeConversationId.value;
        final inItsChat =
            convId != null && convId == VoicePlayerService.openChatId.value;
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
                  onSeek: (f) => svc.seekFraction(f),
                  onClose: () => svc.stop(),
                  onOpen: convId == null
                      ? null
                      : () => appRouter
                          .pushNamed('chat', pathParameters: {'id': convId}),
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
    required this.onSeek,
    required this.onClose,
    required this.onOpen,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final String Function(Duration) fmt;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;
  final VoidCallback onClose;
  final VoidCallback? onOpen;

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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                // Tapping the label/icon jumps to the chat the note is from.
                GestureDetector(
                  onTap: onOpen,
                  child: Row(
                    children: [
                      const Icon(Icons.mic_rounded,
                          color: AppColors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Voice note',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Draggable scrubber. A custom bar (NOT a Slider) because
                // the global mini-bar lives outside the Navigator's
                // Overlay, and Slider's value-indicator OverlayPortal
                // throws "No Overlay widget found" there.
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, c) {
                      final w = c.maxWidth <= 0 ? 1.0 : c.maxWidth;
                      void seekAt(double dx) =>
                          onSeek((dx / w).clamp(0.0, 1.0));
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => seekAt(d.localPosition.dx),
                        onHorizontalDragUpdate: (d) =>
                            seekAt(d.localPosition.dx),
                        child: SizedBox(
                          height: 24,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppColors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: fraction,
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: AppColors.goldAccent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment(fraction * 2 - 1, 0),
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: AppColors.goldAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
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
