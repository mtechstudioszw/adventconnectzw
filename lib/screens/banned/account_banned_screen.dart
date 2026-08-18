import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Full-screen, non-dismissible lockout shown when the signed-in account
/// has been banned (profiles.is_banned). The backend already rejects all
/// actions via user_is_active(); this gives an honest explanation + a way
/// to reach support instead of cryptic errors.
///
/// The ONLY way out is an admin unban: the screen re-checks the server on a
/// short interval and, the moment the account is no longer banned, clears the
/// local flag (done inside [AuthService.isCurrentUserBanned]) and returns the
/// user to the app. There is no back button, no dismiss, no offline escape.
class AccountBannedScreen extends StatefulWidget {
  const AccountBannedScreen({super.key});

  @override
  State<AccountBannedScreen> createState() => _AccountBannedScreenState();
}

class _AccountBannedScreenState extends State<AccountBannedScreen> {
  static const _whatsApp = '263778092494';
  static const _email = 'adventconnectzw@gmail.com';

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Re-check immediately (admin may have unbanned while the app was
    // closed and the local flag is stale), then keep checking.
    _checkUnbanned();
    _poll = Timer.periodic(
        const Duration(seconds: 15), (_) => _checkUnbanned());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkUnbanned() async {
    final stillBanned = await AuthService.isCurrentUserBanned();
    if (!stillBanned && mounted) {
      _poll?.cancel();
      // Re-enter through splash so the normal gates (biometric / profile /
      // home) run cleanly now that the ban is lifted.
      context.goNamed('splash');
    }
  }

  Future<void> _contactWhatsApp() async {
    final uri = Uri.parse(
        'https://wa.me/$_whatsApp?text=${Uri.encodeComponent('Hi, about my Adventist Super App account…')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _contactEmail() async {
    final uri = Uri.parse(
        'mailto:$_email?subject=${Uri.encodeComponent('Adventist Super App account')}');
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
                      'Adventist Super App is no longer available on this account. '
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
