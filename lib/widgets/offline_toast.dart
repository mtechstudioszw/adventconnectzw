import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// "You're offline — try again later", for three seconds.
///
/// ## Why this exists alongside [OfflineBanner]
///
/// The banner is app-wide and reacts to the connection CHANGING. It is the
/// right thing for ambient state and the wrong thing for feedback: a member
/// who pulls to refresh and gets nothing has performed an action and been
/// answered with silence. The list simply springs back, which reads as "the
/// app is broken" rather than "you have no signal" — and if the device was
/// already offline before they opened the screen, the banner never changed
/// state and so never said anything at all.
///
/// This is tied to the action instead. Call it when a refresh or a fetch
/// fails and the device is offline.
///
/// Deliberately NOT shown for every failure. A request can fail while the
/// connection is fine — a server error told as "you're offline" sends the
/// member to go and check their wifi over something that was never their
/// fault. [maybeShowOffline] makes that check for you.
void showOfflineToast(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  // Replace rather than queue. Two pulls in quick succession would otherwise
  // stack three seconds each and leave the bar sitting there long after the
  // member stopped asking.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.darkNavy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: AppColors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're offline. Try again when you have a connection.",
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.white,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shows the toast only when the device is genuinely offline.
///
/// Returns true if it said something, so a caller can fall back to its own
/// error message for the online case rather than leaving the member with
/// nothing.
bool maybeShowOffline(BuildContext context) {
  if (ConnectivityService.isOnline) return false;
  showOfflineToast(context);
  return true;
}
