import 'package:flutter/material.dart';

import '../models/post_model.dart';
import '../services/feed_service.dart';
import 'moderation_appeal_sheet.dart';

/// Super admin: hide [post] (asking why) or restore it if already hidden.
///
/// Returns the post as it now stands, or null if nothing changed
/// (cancelled, or the call failed — the snackbar says which). Callers drop
/// a newly hidden post from their list and replace a restored one.
Future<Post?> moderatePost(BuildContext context, Post post) async {
  final messenger = ScaffoldMessenger.of(context);
  final hiding = !post.isModerated;
  String? reason;
  if (hiding) {
    reason = await showModerationReasonDialog(
      context,
      what: 'post',
      defaultReason: 'It breaks the community guidelines.',
    );
    if (reason == null) return null;
  }
  try {
    await FeedService.adminSetPostHidden(
      post.id,
      hidden: hiding,
      reason: reason,
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e.toString().contains('admin_set_post_hidden')
              ? 'Hiding posts needs database patch_272 to be run first.'
              : 'Could not update this post. Try again.',
        ),
      ),
    );
    return null;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        hiding
            ? 'Post hidden. The author has been told why and can appeal.'
            : 'Post restored. The author has been told.',
      ),
    ),
  );
  return post.copyWith(
    moderationHiddenAt: hiding ? DateTime.now() : null,
    moderationReason: hiding ? reason : null,
  );
}
