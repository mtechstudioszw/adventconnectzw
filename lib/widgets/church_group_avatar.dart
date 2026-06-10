import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'cached_image.dart';

/// Avatar for the auto-created church groups/channels. They share ONE
/// default logo — the Seventh-day Adventist church logo at
/// `assets/icon/sda_logo.png` — unless a (claimed) church admin sets a
/// custom photo, in which case [photoUrl] wins. Falls back to a church
/// glyph if the logo asset isn't bundled yet.
class ChurchGroupAvatar extends StatelessWidget {
  const ChurchGroupAvatar({super.key, this.photoUrl, this.size = 44});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white,
      ),
      child: hasPhoto
          ? CachedImage(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _logo(),
            )
          : _logo(),
    );
  }

  Widget _logo() {
    return Padding(
      padding: EdgeInsets.all(size * 0.12),
      child: Image.asset(
        'assets/icon/sda_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.church,
          size: size * 0.55,
          color: AppColors.primaryBlue,
        ),
      ),
    );
  }
}
