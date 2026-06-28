import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/quiz_question_model.dart';
import '../../services/ads/interstitial_ad_manager.dart';
import '../../services/quiz_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Plays a list of quiz questions: one MCQ at a time, reveal the answer +
/// explanation, then a results screen. [isDaily] advances the streak.
class QuizPlayScreen extends StatefulWidget {
  const QuizPlayScreen({
    super.key,
    required this.questions,
    required this.title,
    this.isDaily = false,
  });

  final List<QuizQuestion> questions;
  final String title;
  final bool isDaily;

  @override
  State<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends State<QuizPlayScreen> {
  int _index = 0;
  int _score = 0;
  int? _chosen; // null until the user answers the current question
  bool _finished = false;

  QuizQuestion get _q => widget.questions[_index];

  void _answer(int i) {
    if (_chosen != null) return; // already answered
    setState(() {
      _chosen = i;
      if (_q.isCorrect(i)) _score++;
    });
  }

  Future<void> _next() async {
    if (_index < widget.questions.length - 1) {
      setState(() {
        _index++;
        _chosen = null;
      });
    } else {
      if (widget.isDaily) await QuizService.recordDailyComplete();
      if (!mounted) return;
      setState(() => _finished = true);
      // One capped interstitial at the natural end of a session (never
      // mid-question). The manager enforces its own frequency cap.
      InterstitialAdManager.maybeShow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      appBar: AppBar(
        title: Text(widget.title,
            style: AppTextStyles.appBarTitle.copyWith(fontSize: 18)),
        foregroundColor: AppColors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.appBarGradient),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _finished ? _buildResults(context) : _buildQuestion(context),
      ),
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final palette = context.palette;
    final answered = _chosen != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progress.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Question ${_index + 1} of ${widget.questions.length}',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: palette.textMuted)),
                  Text(_q.category,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.primaryBlue)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (_index + 1) / widget.questions.length,
                  minHeight: 6,
                  backgroundColor: palette.cardMuted,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primaryBlue),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Text(_q.question,
                  style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w700, height: 1.35)),
              const SizedBox(height: 18),
              for (var i = 0; i < _q.options.length; i++)
                _OptionTile(
                  label: _q.options[i],
                  state: !answered
                      ? _OptState.idle
                      : i == _q.correctIndex
                          ? _OptState.correct
                          : (i == _chosen ? _OptState.wrong : _OptState.dim),
                  onTap: () => _answer(i),
                ),
              if (answered && (_q.explanation ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _q.isCorrect(_chosen!)
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: _q.isCorrect(_chosen!)
                                ? AppColors.successGreen
                                : AppColors.primaryBlue,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _q.isCorrect(_chosen!) ? 'Correct!' : 'Good to know',
                            style: AppTextStyles.labelMedium.copyWith(
                                fontWeight: FontWeight.w800,
                                color: _q.isCorrect(_chosen!)
                                    ? AppColors.successGreen
                                    : AppColors.primaryBlue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_q.explanation!,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: palette.text, height: 1.5)),
                      if ((_q.reference ?? '').isNotEmpty &&
                          _q.reference != '-') ...[
                        const SizedBox(height: 6),
                        Text(_q.reference!,
                            style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (answered)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _next,
                child: Text(
                    _index < widget.questions.length - 1
                        ? 'Next question'
                        : 'See results',
                    style: AppTextStyles.buttonText
                        .copyWith(color: AppColors.white)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    final palette = context.palette;
    final total = widget.questions.length;
    final pct = total == 0 ? 0 : (_score / total * 100).round();
    final passed = pct >= 60;
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (passed ? AppColors.successGreen : AppColors.primaryBlue)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text('$pct%',
                  style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: passed
                          ? AppColors.successGreen
                          : AppColors.primaryBlue)),
            ),
          ),
          const SizedBox(height: 18),
          Text(passed ? 'Well done!' : 'Keep studying!',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSmall
                  .copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('You scored $_score out of $total.',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.bodyMedium.copyWith(color: palette.textMuted)),
          if (widget.isDaily) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_fire_department,
                      color: AppColors.goldAccent),
                  const SizedBox(width: 8),
                  Text('${QuizService.currentStreak()}-day streak',
                      style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.white, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Done',
                  style:
                      AppTextStyles.buttonText.copyWith(color: AppColors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _OptState { idle, correct, wrong, dim }

class _OptionTile extends StatelessWidget {
  const _OptionTile(
      {required this.label, required this.state, required this.onTap});
  final String label;
  final _OptState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Color border = palette.divider;
    Color bg = palette.card;
    Color fg = palette.text;
    IconData? icon;
    Color? iconColor;
    switch (state) {
      case _OptState.correct:
        border = AppColors.successGreen;
        bg = AppColors.successGreen.withValues(alpha: 0.10);
        icon = Icons.check_circle;
        iconColor = AppColors.successGreen;
        break;
      case _OptState.wrong:
        border = AppColors.red;
        bg = AppColors.red.withValues(alpha: 0.08);
        icon = Icons.cancel;
        iconColor = AppColors.red;
        break;
      case _OptState.dim:
        fg = palette.textMuted;
        break;
      case _OptState.idle:
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: state == _OptState.idle ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: fg, fontWeight: FontWeight.w600)),
                ),
                if (icon != null) Icon(icon, color: iconColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
