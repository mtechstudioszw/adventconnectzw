import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The gold verified tick shown beside a verified account's name
/// EVERYWHERE they appear — posts, profile, chat (inbox tiles + header),
/// find friends (member directory), and suggestions. A user is "verified"
/// when profiles.is_verified OR is_verified_admin is true.
class VerifiedTick extends StatelessWidget {
  const VerifiedTick({super.key, this.size = 14, this.leftGap = 4});

  final double size;

  /// Horizontal gap placed before the tick (so callers can drop it
  /// straight after a name without wrapping in extra padding).
  final double leftGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: leftGap),
      child: Icon(Icons.verified, size: size, color: AppColors.goldAccent),
    );
  }
}
