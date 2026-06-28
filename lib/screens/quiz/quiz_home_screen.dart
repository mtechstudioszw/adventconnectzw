import 'package:flutter/material.dart';

import '../../models/quiz_question_model.dart';
import '../../services/quiz_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'quiz_play_screen.dart';

/// Bible Quiz home — Daily Challenge (with streak) + Practice by category.
class QuizHomeScreen extends StatefulWidget {
  const QuizHomeScreen({super.key});

  @override
  State<QuizHomeScreen> createState() => _QuizHomeScreenState();
}

class _QuizHomeScreenState extends State<QuizHomeScreen> {
  late Future<List<String>> _categories;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _categories = QuizService.categories();
  }

  Future<void> _play({
    required String title,
    required bool isDaily,
    String? category,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final qs = isDaily
        ? await QuizService.dailySet()
        : await QuizService.practiceSet(category: category);
    if (!mounted) return;
    setState(() => _busy = false);
    if (qs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No questions available yet.')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          QuizPlayScreen(questions: qs, title: title, isDaily: isDaily),
    ));
    if (mounted) setState(() {}); // refresh streak after a daily round
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text('Bible Quiz',
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 19)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _DailyCard(
              streak: QuizService.currentStreak(),
              playedToday: QuizService.playedToday(),
              onPlay: () => _play(title: 'Daily Challenge', isDaily: true),
            ),
            const SizedBox(height: 20),
            Text('PRACTICE',
                style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4)),
            const SizedBox(height: 10),
            _PracticeTile(
              icon: Icons.shuffle_rounded,
              title: 'Random mix',
              subtitle: '10 questions across all topics',
              onTap: () => _play(title: 'Practice', isDaily: false),
            ),
            const SizedBox(height: 16),
            Text('BY TOPIC',
                style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4)),
            const SizedBox(height: 10),
            FutureBuilder<List<String>>(
              future: _categories,
              builder: (context, snap) {
                final cats = snap.data ?? const [];
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primaryBlue)),
                  );
                }
                if (cats.isEmpty) {
                  return Text('No topics yet.',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: palette.textMuted));
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in cats)
                      ActionChip(
                        label: Text(c),
                        backgroundColor: palette.card,
                        side: BorderSide(color: palette.divider),
                        labelStyle: AppTextStyles.labelMedium
                            .copyWith(color: palette.text),
                        onPressed: () =>
                            _play(title: c, isDaily: false, category: c),
                      ),
                  ],
                );
              },
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primaryBlue)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard(
      {required this.streak,
      required this.playedToday,
      required this.onPlay});
  final int streak;
  final bool playedToday;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.quiz_rounded, color: AppColors.white),
              const SizedBox(width: 8),
              Text('Daily Challenge',
                  style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.white, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (streak > 0)
                Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: AppColors.goldAccent, size: 18),
                    const SizedBox(width: 4),
                    Text('$streak',
                        style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            playedToday
                ? 'You\'ve done today\'s quiz — come back tomorrow to keep your streak.'
                : '5 questions on the Bible & Adventist beliefs. Keep your streak alive!',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onPlay,
              child: Text(playedToday ? 'Play again' : 'Start',
                  style: AppTextStyles.buttonText.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeTile extends StatelessWidget {
  const _PracticeTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTextStyles.titleSmall
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
