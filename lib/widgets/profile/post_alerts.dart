import 'package:flutter/material.dart';

import '../../services/follow_service.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Post alerts from people and Pages you follow (patch_283): when they
/// post, you get a notification; this is the per-source off switch.
/// Muting keeps the follow — you still see their posts on Home.

/// Whether alerts from [type]/[id] are muted, or null while unknown.
bool? alertsMuted(String type, String id) =>
    FollowService.mutedAlerts.value?.contains(FollowService.alertKey(type, id));

/// Flips the mute and says what happened. [name] is who it's about.
Future<void> toggleAlertMute(
  BuildContext context, {
  required String type,
  required String id,
  required String name,
}) async {
  final muted = alertsMuted(type, id) ?? false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await FollowService.setAlertsMuted(type: type, id: id, muted: !muted);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          muted
              ? "You'll be notified when $name posts."
              : "Muted. You won't be notified when $name posts — "
                    "you still follow them.",
        ),
      ),
    );
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't change post alerts. Try again.")),
    );
  }
}

/// "Mute alerts" / "Alerts on" under a new-post notification, so the
/// switch is right where the noise is.
class PostAlertMuteButton extends StatelessWidget {
  const PostAlertMuteButton({
    super.key,
    required this.type,
    required this.id,
    required this.name,
  });

  final String type;
  final String id;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>?>(
      valueListenable: FollowService.mutedAlerts,
      builder: (context, set, _) {
        if (set == null) return const SizedBox.shrink();
        final muted = set.contains(FollowService.alertKey(type, id));
        final palette = context.palette;
        return InkWell(
          onTap: () => toggleAlertMute(context, type: type, id: id, name: name),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 16,
                  color: palette.brandBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  muted ? 'Turn alerts back on' : 'Mute post alerts',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: palette.brandBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
