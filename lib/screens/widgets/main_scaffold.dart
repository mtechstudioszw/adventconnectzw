import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'main_bottom_nav.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({
    super.key,
    required this.title,
    required this.currentIndex,
    required this.body,
    this.floatingActionButton,
  });

  final String title;
  final int currentIndex;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        title: Text(title, style: AppTextStyles.appBarTitle),
        elevation: 0,
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: MainBottomNav(currentIndex: currentIndex),
      floatingActionButton: floatingActionButton,
    );
  }
}
