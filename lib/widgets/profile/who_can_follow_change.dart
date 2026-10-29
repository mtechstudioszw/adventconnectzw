import 'package:flutter/material.dart';

import '../../services/follow_service.dart';
import '../../theme/app_colors.dart';

/// Switches "who can follow me" to [picked], warning first when that
/// removes followers. Returns the setting now in force — [picked] on
/// success, [current] if the member cancelled or the save failed.
///
/// Shared so the Privacy screen and anything else that offers the setting
/// can't drift apart on the one step that matters: nobody loses followers
/// without being told how many first.
Future<WhoCanFollow> changeWhoCanFollow(
  BuildContext context, {
  required WhoCanFollow current,
  required WhoCanFollow picked,
}) async {
  if (picked == current) return current;
  try {
    final losing = await FollowService.followersRemovedBy(picked);
    if (!context.mounted) return current;
    if (losing > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Remove $losing follower${losing == 1 ? '' : 's'}?'),
          content: Text(
            picked == WhoCanFollow.nobody
                ? 'Turning following off removes everyone who follows you. '
                      "Your friends stay your friends. They won't be told."
                : "Followers who aren't your friends will be removed. "
                      "They won't be told.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true) return current;
    }
    await FollowService.setWhoCanFollow(picked);
    return picked;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't change who can follow you. Try again."),
        ),
      );
    }
    return current;
  }
}
