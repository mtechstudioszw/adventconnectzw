import 'package:flutter/material.dart';

import '../../models/post_model.dart';
import '../../services/auth_service.dart';
import '../preview_sheet.dart';
import 'post_card.dart';

/// "See it before you send it" for a feed post.
///
/// The sheet chrome lives in [showEntityPreview] now, shared with the
/// story, event and product composers — this file only builds the draft
/// post and hands over the **real [PostCard]**.
///
/// Returns `true` if the member pressed **Post it** from here, so the
/// composer can publish without making them go back first.
Future<bool> showPostPreview(
  BuildContext context, {
  required String body,
  required List<String> photos,
  required PostVisibility visibility,
  String? churchName,
  String? churchPhotoUrl,
}) {
  final user = AuthService.currentUser;
  final meta = user?.userMetadata ?? const {};
  final trimmed = body.trim();

  // `createdAt` is now, so the card's relative timestamp reads "just now"
  // — which is exactly what it will say a second after publishing.
  final draft = Post(
    // Never persisted — the real id is assigned by the insert.
    id: 'preview',
    authorId: user?.id ?? 'preview',
    authorName: (meta['full_name'] as String?)?.trim().isNotEmpty == true
        ? (meta['full_name'] as String).trim()
        : 'You',
    authorPhotoUrl: (meta['profile_photo_url'] as String?)?.trim(),
    createdAt: DateTime.now(),
    body: trimmed.isEmpty ? null : trimmed,
    imageUrl: photos.isEmpty ? null : photos.first,
    imageUrls: photos,
    visibility: visibility,
    churchName: churchName,
    churchPhotoUrl: churchPhotoUrl,
  );

  return showEntityPreview(
    context,
    title: 'How your post will look',
    confirmLabel: 'Post it',
    // Interactions are inert because there is nothing to act on yet: the
    // post has no id until it is published.
    child: PostCard(
      post: draft,
      viewerId: user?.id,
      onLikeToggled: () {},
      onCommentsTapped: () {},
      onImageTapped: (_) {},
    ),
  );
}
