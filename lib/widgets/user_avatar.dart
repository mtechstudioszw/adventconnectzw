import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'cached_image.dart';

/// A round profile photo that actually fills its circle.
///
/// This exists because the same avatar was hand-rolled in seven files and
/// six of them carried the same bug: a
/// `Container(width: 44, height: 44, alignment: Alignment.center)` around
/// an **unsized** [CachedImage]. Setting `alignment` makes Container wrap
/// its child in an `Align`, and `Align` hands the child **LOOSE**
/// constraints — so the image laid itself out at the downloaded photo's
/// own size and sat centred inside the circle, leaving a ring of whatever
/// was painted behind it. On a white card that ring is the "white edges"
/// the founder reported (2 Aug 2026); it is the one the church avatar in
/// `church_details_screen.dart` was already fixed for.
///
/// Two rules, both of which this widget applies once so no call site has
/// to remember them:
///
///  * **Size the image.** The [SizedBox] gives TIGHT constraints and the
///    explicit `width`/`height` on [CachedImage] keeps it honest even if
///    someone later drops the box, so `BoxFit.cover` fills the circle.
///  * **Centre the fallback.** [CachedImage] hands its `errorBuilder`
///    TIGHT constraints, so a bare `Text` paints at the top-left corner —
///    which is why an initial sat at the top of the circle whenever the
///    photo failed to load (i.e. offline).
///
/// A ring around the avatar stays at the call site, as an outer container
/// one size up: the rings differ (gold on Sabbath, red when live, the
/// sheet colour behind a story) and folding them in here would mean a
/// flag per caller.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.photoUrl,
    required this.size,
    this.name,
    this.fallbackIcon,
    this.onTap,
  });

  final String? photoUrl;
  final double size;

  /// Used for the initial when there is no photo. Ignored when
  /// [fallbackIcon] is set.
  final String? name;

  /// Shown instead of an initial — groups use `Icons.groups`.
  final IconData? fallbackIcon;

  final VoidCallback? onTap;

  bool get _hasPhoto => (photoUrl ?? '').trim().isNotEmpty;

  Widget _fallback() {
    final trimmed = (name ?? '').trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: Center(
        child: fallbackIcon != null
            ? Icon(fallbackIcon, color: AppColors.white, size: size * 0.46)
            : Text(
                initial,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.4,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: _hasPhoto
            ? CachedImage(
                photoUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );

    if (onTap == null) return avatar;
    return GestureDetector(onTap: onTap, child: avatar);
  }
}
