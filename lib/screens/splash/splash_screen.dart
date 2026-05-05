import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    if (AuthService.isSignedIn) {
      context.goNamed('home');
      return;
    }

    final ageVerified = await AuthService.isAgeVerified();
    if (!mounted) return;

    if (ageVerified) {
      context.goNamed('login');
    } else {
      context.goNamed('age_verification');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.church, size: 80, color: AppColors.goldAccent),
                const SizedBox(height: 24),
                Text('Advent Connect ZW', style: AppTextStyles.displayMedium.copyWith(color: AppColors.white)),
                const SizedBox(height: 8),
                Text('Community • Faith • Zimbabwe', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
                const SizedBox(height: 48),
                const CircularProgressIndicator(color: AppColors.goldAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
