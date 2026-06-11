import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_version.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Full-screen, non-dismissible gate shown when the installed build is
/// below the remote minimum (ForceUpdateService). Forces the user to the
/// Play Store before they can continue.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  Future<void> _openStore() async {
    // Prefer the Play Store app; fall back to the web listing.
    final market = Uri.parse('market://details?id=$kAndroidPackageId');
    final web = Uri.parse(
        'https://play.google.com/store/apps/details?id=$kAndroidPackageId');
    if (!await launchUrl(market, mode: LaunchMode.externalApplication)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // canPop: false → the system back button can't dismiss the gate.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update,
                          color: AppColors.white, size: 48),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Update required',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A newer version of Advent Connect is available. Please '
                      'update to continue — your account and chats are safe.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.white.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openStore,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.white,
                          foregroundColor: AppColors.darkNavy,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.shop),
                        label: Text(
                          'Update now',
                          style: AppTextStyles.buttonText
                              .copyWith(color: AppColors.darkNavy),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
