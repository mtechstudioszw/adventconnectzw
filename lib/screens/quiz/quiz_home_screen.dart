import 'package:flutter/material.dart';

import '../../services/quiz_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import 'quiz_play_screen.dart';
import '../../widgets/motion/brand_spinner.dart';

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
    int count = 10,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final qs = isDaily
        ? await QuizService.dailySet()
        : await QuizService.practiceSet(category: category, count: count);
    if (!mounted) return;
    setState(() => _busy = false);
    if (qs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No questions available yet.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            QuizPlayScreen(questions: qs, title: title, isDaily: isDaily),
      ),
    );
    if (mounted) setState(() {}); // refresh streak/rating/resume after a round
  }

  /// Continue an interrupted round saved by the play screen.
  Future<void> _resume(Map<String, dynamic> s) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ids = (s['ids'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final qs = await QuizService.questionsByIds(ids);
    if (!mounted) return;
    setState(() => _busy = false);
    // Questions changed underneath us (e.g. admin edits) — drop the stale save.
    if (qs.length != ids.length || qs.isEmpty) {
      await QuizService.clearSession();
      if (mounted) setState(() {});
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizPlayScreen(
          questions: qs,
          title: s['title']?.toString() ?? 'Quiz',
          startIndex: (s['index'] as num?)?.toInt() ?? 0,
          startScore: (s['score'] as num?)?.toInt() ?? 0,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final session = QuizService.loadSession();
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(
          'Bible Quiz',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (session != null) ...[
              _ResumeCard(
                index: (session['index'] as num?)?.toInt() ?? 0,
                total: (session['ids'] as List?)?.length ?? 0,
                title: session['title']?.toString() ?? 'Quiz',
                onResume: () => _resume(session),
                onDiscard: () async {
                  await QuizService.clearSession();
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 16),
            ],
            _DailyCard(
              streak: QuizService.currentStreak(),
              playedToday: QuizService.playedToday(),
              onPlay: () => QuizService.playedToday()
                  ? _play(title: 'Daily Challenge', isDaily: false, count: 5)
                  : _play(title: 'Daily Challenge', isDaily: true),
            ),
            const SizedBox(height: 16),
            _RatingCard(
              label: QuizService.ratingLabel(),
              accuracy: QuizService.accuracyPct(),
              answered: QuizService.totalAnswered(),
              stars: QuizService.ratingStars(),
            ),
            const SizedBox(height: 20),
            Text(
              'PRACTICE',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            _PracticeTile(
              icon: Icons.shuffle_rounded,
              title: 'Random mix',
              subtitle: '10 questions across all topics',
              onTap: () => _play(title: 'Practice', isDaily: false),
            ),
            const SizedBox(height: 16),
            Text(
              'BY TOPIC',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
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
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  );
                }
                if (cats.isEmpty) {
                  return Text(
                    'No topics yet.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.textMuted,
                    ),
                  );
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
                        labelStyle: AppTextStyles.labelMedium.copyWith(
                          color: palette.text,
                        ),
                        onPressed: () =>
                            _play(title: c, isDaily: false, category: c),
                      ),
                  ],
                );
              },
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: BrandSpinner(size: 30)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.streak,
    required this.playedToday,
    required this.onPlay,
  });
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
              Text(
                'Daily Challenge',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (streak > 0)
                Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: AppColors.goldAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$streak',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            playedToday
                ? 'You\'ve done today\'s quiz — come back tomorrow to keep your streak.'
                : '5 questions on the Bible & Adventist beliefs. Keep your streak alive!',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.white.withValues(alpha: 0.9),
            ),
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
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPlay,
              child: Text(
                playedToday ? 'Play again' : 'Start',
                style: AppTextStyles.buttonText.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Continue-where-you-left-off banner, shown when a round was interrupted.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.index,
    required this.total,
    required this.title,
    required this.onResume,
    required this.onDiscard,
  });
  final int index;
  final int total;
  final String title;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, color: AppColors.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resume “$title”',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You stopped at question ${index + 1} of $total',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDiscard,
            child: Text(
              'Discard',
              style: AppTextStyles.labelMedium.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onResume,
            child: Text(
              'Resume',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The player's lifetime "rating" — rank, stars and accuracy.
class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.label,
    required this.accuracy,
    required this.answered,
    required this.stars,
  });
  final String label;
  final int accuracy;
  final int answered;
  final int stars;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Your rating: ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    Text(
                      label,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (answered == 0)
                  Text(
                    'Play a round to start your rating.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  )
                else
                  Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(
                          i < stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 18,
                          color: AppColors.goldAccent,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '$accuracy% · $answered answered',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeTile extends StatelessWidget {
  const _PracticeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
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
                    Text(
                      title,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
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
