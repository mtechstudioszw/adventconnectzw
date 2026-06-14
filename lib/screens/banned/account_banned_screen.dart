import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Full-screen, non-dismissible lockout shown when the signed-in account
/// has been banned (profiles.is_banned). The backend already rejects all
/// actions via user_is_active(); this gives an honest explanation + a way
/// to reach support instead of cryptic errors.
class AccountBannedScreen extends StatelessWidget {
  const AccountBannedScreen({super.key});

  static const _whatsApp = '263778092494';
  static const _email = 'tanatswamichaelmikuwa@gmail.com';

  Future<void> _contactWhatsApp() async {
    final uri = Uri.parse(
        'https://wa.me/$_whatsApp?text=${Uri.encodeComponent('Hi, about my Advent Connect account…')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _contactEmail() async {
    final uri = Uri.parse(
        'mailto:$_email?subject=${Uri.encodeComponent('Advent Connect account')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
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
                      child: const Icon(Icons.block,
                          color: AppColors.white, size: 48),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Account unavailable',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Advent Connect is no longer available on this account. '
                      'If you think this is a mistake, contact support.',
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
                        onPressed: _contactWhatsApp,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.white,
                          foregroundColor: AppColors.darkNavy,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.chat),
                        label: Text(
                          'Contact support on WhatsApp',
                          style: AppTextStyles.buttonText
                              .copyWith(color: AppColors.darkNavy),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _contactEmail,
                      icon: const Icon(Icons.email_outlined,
                          color: AppColors.white),
                      label: Text(
                        'Email support',
                        style: AppTextStyles.labelMedium
                            .copyWith(color: AppColors.white),
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
