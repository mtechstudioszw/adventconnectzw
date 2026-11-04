import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'feature_tour.dart';

/// The app's tours (owner, 3 Nov 2026).
///
/// * CORE: the main features, shown once to EVERYONE — new installs and
///   members updating — since the app never had a tour before.
/// * WHAT'S NEW: after an update, a short list of this release's new
///   features for members who already used the app. Each release adds an
///   entry below with a new id; the core tour is not repeated.
class AppTours {
  AppTours._();

  static const coreId = 'core_v1';
  static const whatsNewId = 'whats_new_2026_11';

  static const core = <TourStep>[
    TourStep(
      anchor: 'home_create',
      icon: Icons.add_rounded,
      title: 'Share something',
      body:
          'Tap + to post, share a prayer request, start a story or create an '
          'event. Drag it anywhere — it moves with the bar.',
    ),
    TourStep(
      anchor: 'home_stories',
      icon: Icons.amp_stories_rounded,
      title: 'Stories',
      body:
          "Friends' updates that last 24 hours. Tap one to watch; tap your "
          'own card to add yours.',
    ),
    TourStep(
      anchor: 'nav_library',
      icon: Icons.menu_book_rounded,
      title: 'Library',
      body:
          'The Bible in hundreds of languages (with audio in English), '
          'Sabbath School, Ellen G. White books, hymns and videos. Most of '
          'it works offline.',
    ),
    TourStep(
      anchor: 'nav_chat',
      icon: Icons.chat_bubble_rounded,
      title: 'Chat and calls',
      body:
          'Private, end-to-end encrypted chats and voice calls with friends '
          'and groups, plus your church channels.',
    ),
    TourStep(
      anchor: 'nav_marketplace',
      icon: Icons.storefront_rounded,
      title: 'Marketplace and jobs',
      body:
          'Buy and sell within the community, open your own shop, and find '
          'or post jobs.',
    ),
    TourStep(
      anchor: 'nav_profile',
      icon: Icons.person_rounded,
      title: 'Your profile',
      body:
          'Your posts, friends and QR code, your church, and Settings — '
          'privacy, Face ID or fingerprint lock, notifications and more.',
    ),
  ];

  /// This release's new features, for members who already had the app.
  static const whatsNew = <(IconData, String, String)>[
    (
      Icons.translate_rounded,
      '480+ Bibles in 300+ languages',
      'Bible → tap the translation button and search your language.',
    ),
    (
      Icons.headphones_rounded,
      'Listen to the Bible',
      'Press Listen on any English chapter. Download chapters to play '
          'offline.',
    ),
    (
      Icons.download_for_offline_rounded,
      'Sabbath School offline',
      'Download all 13 weeks in one tap — they stay even after you sign '
          'out.',
    ),
    (
      Icons.record_voice_over_rounded,
      'Read aloud',
      'In Ellen G. White books, tap the headphones to have pages read to '
          'you.',
    ),
    (
      Icons.qr_code_scanner_rounded,
      'Add friends from a photo',
      'Scan a friend code from a picture, not just the camera.',
    ),
  ];

  static bool _busy = false;

  /// Runs whatever this member hasn't seen: the core tour, then (for
  /// existing members) what's new. Safe to call on every Home visit.
  static Future<void> maybeRun(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!FeatureTour.isDone(coreId)) {
        final shown = await FeatureTour.run(
          context,
          tourId: coreId,
          steps: core,
        );
        if (!shown) return; // anchors not on screen yet — try next visit
      }
      if (!FeatureTour.isDone(whatsNewId) && context.mounted) {
        if (_isExistingMember()) {
          await _showWhatsNew(context);
        }
        await FeatureTour.markDone(whatsNewId);
      }
    } finally {
      _busy = false;
    }
  }

  /// A member whose account is more than a day old has used the app
  /// before this release; a brand-new install only needs the core tour.
  static bool _isExistingMember() {
    final created = DateTime.tryParse(AuthService.currentUser?.createdAt ?? '');
    if (created == null) return false;
    return DateTime.now().toUtc().difference(created.toUtc()) >
        const Duration(days: 1);
  }

  static Future<void> _showWhatsNew(BuildContext context) {
    return showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      backgroundColor: context.palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final palette = context.palette;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "WHAT'S NEW",
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.goldAccent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'New in this update',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                for (final (icon, title, body) in whatsNew)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(icon, color: AppColors.primaryBlue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: palette.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                body,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: palette.textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Great'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
