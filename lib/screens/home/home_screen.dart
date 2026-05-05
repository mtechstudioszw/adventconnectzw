import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        title: Text('Advent Connect ZW', style: AppTextStyles.appBarTitle),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: AppColors.successGreen),
              const SizedBox(height: 16),
              Text('Stage 1 Complete', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 8),
              Text('Theme • Router • SecureStorage • Supabase', style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
