import 'package:flutter/material.dart';

import '../../../models/quiz_question_model.dart';
import '../../../models/quiz_round.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import 'arena_theme.dart';
import 'widgets/arena_scaffold.dart';

/// "What did I get wrong?"
///
/// Every commercial quiz game has this, and in a Bible app it's arguably
/// the most valuable screen in the feature — the explanation and reference
/// flash past mid-round, and this is where they can actually be read. Wrong
/// answers are listed first, because that's what people came here for.
class QuizReviewScreen extends StatefulWidget {
  const QuizReviewScreen({super.key, required this.result});

  final QuizRoundResult result;

  @override
  State<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<QuizReviewScreen> {
  bool _wrongOnly = false;

  @override
  Widget build(BuildContext context) {
    final pairs = widget.result.reviewPairs;
    final wrong = [
      for (final pair in pairs)
        if (!pair.$2.correct) pair,
    ];
    final visible = _wrongOnly
        ? wrong
        // Missed questions first — the reason anyone opens this screen.
        : [
            ...wrong,
            for (final pair in pairs)
              if (pair.$2.correct) pair,
          ];

    return ArenaScaffold(
      title: 'Review answers',
      showMute: false,
      child: Column(
        children: [
          _buildSummary(pairs.length, wrong.length),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(
                        wrong.isEmpty
                            ? 'You got every question right — nothing to review.'
                            : 'Nothing to show.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: ArenaTheme.textMutedOnNavy),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visible.length,
                    itemBuilder: (context, i) => _ReviewCard(
                      index: i,
                      question: visible[i].$1,
                      answer: visible[i].$2,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(int total, int wrongCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              wrongCount == 0
                  ? 'All $total correct'
                  : '$wrongCount of $total missed',
              style: AppTextStyles.titleSmall.copyWith(
                color: ArenaTheme.textOnNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (wrongCount > 0)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
                onTap: () => setState(() => _wrongOnly = !_wrongOnly),
                child: AnimatedContainer(
                  duration: AppMotion.maybe(context, AppMotion.quick),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: _wrongOnly
                        ? ArenaTheme.gold.withValues(alpha: 0.18)
                        : ArenaTheme.glass,
                    borderRadius:
                        BorderRadius.circular(ArenaTheme.radiusPill),
                    border: Border.all(
                      color: _wrongOnly
                          ? ArenaTheme.gold.withValues(alpha: 0.55)
                          : ArenaTheme.glassBorder,
                    ),
                  ),
                  child: Text(
                    'Missed only',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: _wrongOnly
                          ? ArenaTheme.goldBright
                          : ArenaTheme.textMutedOnNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.index,
    required this.question,
    required this.answer,
  });

  final int index;
  final QuizQuestion question;
  final QuizAnswer answer;

  @override
  Widget build(BuildContext context) {
    final correct = answer.correct;
    final accent =
        correct ? ArenaTheme.correctOnNavy : ArenaTheme.wrongOnNavy;
    final chosenValid =
        answer.chosenIndex >= 0 && answer.chosenIndex < question.options.length;
    final correctValid = question.correctIndex >= 0 &&
        question.correctIndex < question.options.length;
    final reference = question.reference ?? '';
    final hasReference = reference.isNotEmpty && reference != '-';

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: ArenaPanel(
        padding: const EdgeInsets.all(15),
        borderColor: accent.withValues(alpha: 0.38),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  correct
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 17,
                  color: accent,
                ),
                const SizedBox(width: 7),
                Text(
                  correct ? 'Correct' : 'Missed',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  question.category,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: ArenaTheme.textFaintOnNavy,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              question.question,
              style: AppTextStyles.bodyLarge.copyWith(
                color: ArenaTheme.textOnNavy,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            // Only show "your answer" separately when it was wrong —
            // repeating it under a correct one is just noise.
            if (!correct && chosenValid)
              _AnswerRow(
                label: 'You said',
                value: question.options[answer.chosenIndex],
                color: ArenaTheme.wrongOnNavy,
                icon: Icons.close_rounded,
              ),
            if (correctValid)
              _AnswerRow(
                label: correct ? 'Your answer' : 'Correct answer',
                value: question.options[question.correctIndex],
                color: ArenaTheme.correctOnNavy,
                icon: Icons.check_rounded,
              ),
            if ((question.explanation ?? '').isNotEmpty) ...[
              const SizedBox(height: 11),
              Text(
                question.explanation!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: ArenaTheme.textMutedOnNavy,
                  height: 1.55,
                ),
              ),
            ],
            if (hasReference) ...[
              const SizedBox(height: 7),
              Text(
                reference,
                style: AppTextStyles.labelSmall.copyWith(
                  color: ArenaTheme.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 12, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: ArenaTheme.textFaintOnNavy,
                    fontSize: 10.5,
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
