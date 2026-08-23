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
}) async {
  final user = AuthService.currentUser;
  final meta = user?.userMetadata ?? const {};
  final trimmed = body.trim();

  // The viewer's own gold tick. It is NOT in auth metadata — it is a
  // `profiles` column — so a draft built from metadata alone always came
  // out unverified, and a verified member's preview showed no tick even
  // though the published post would have one. The whole promise of this
  // sheet is "this is how it will look", so getting the badge wrong is
  // exactly the kind of lie it exists to prevent.
  //
  // Cached after the first call, and fails soft to false.
  final authorIsVerified = await AuthService.isCurrentUserVerified();
  if (!context.mounted) return false;

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
    authorIsVerified: authorIsVerified,
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
