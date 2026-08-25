import 'package:flutter/material.dart';

import '../../services/signup_survey_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../motion/brand_spinner.dart';
import '../motion/pressable.dart';

/// One-time welcome survey shown on the first home visit after signup.
/// Asks how the user found the app (+ a light optional question) so the
/// founder can understand their audience. Not skippable (user decision
/// 2026-07-02): the sheet can't be dismissed until a source is picked
/// and submitted. Never shown twice.
class SignupSurveySheet extends StatefulWidget {
  const SignupSurveySheet({super.key});

  /// Show it once, to genuinely new accounts that haven't answered yet.
  static Future<void> maybeShow(BuildContext context) async {
    if (!await SignupSurveyService.shouldPrompt()) return;
    // Deliberately NOT marked as shown here. Marking up front meant a
    // failed submit (which was every non-admin submit — see patch_180)
    // silently lost the answer and never asked again. The sheet can't be
    // dismissed without answering, so the only way to see it twice is to
    // kill the app mid-question, which is the right trade.
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Must answer — no tap-outside/drag dismissal, no Skip button.
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const SignupSurveySheet(),
    );
  }

  @override
  State<SignupSurveySheet> createState() => _SignupSurveySheetState();
}

class _SignupSurveySheetState extends State<SignupSurveySheet> {
  static const _sources = <(String, IconData)>[
    ('Friend or family', Icons.diversity_3_rounded),
    ('My church', Icons.church_rounded),
    ('Social media', Icons.public_rounded),
    ('App store / search', Icons.storefront_rounded),
    ('Other', Icons.more_horiz_rounded),
  ];

  String? _source;
  final _hopeController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _hopeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_source == null || _saving) return;
    setState(() => _saving = true);
    try {
      await SignupSurveyService.submit(
        source: _source!,
        answers: {
          if (_hopeController.text.trim().isNotEmpty)
            'hoping_for': _hopeController.text.trim(),
        },
      );
    } catch (_) {
      // The write failed (offline, or a server-side rejection). Mark it
      // shown anyway so a member can never be trapped behind a sheet they
      // are not allowed to dismiss — but let them see that it didn't send,
      // rather than reporting success for a response nobody received.
      await SignupSurveyService.markShown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.red,
            content: Text(
              'Couldn\'t send your answer — thanks anyway!',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    // Back button shouldn't dismiss it either — answering takes one tap.
    return PopScope(
      canPop: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: BoxDecoration(
            color: palette.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.goldAccent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.waving_hand_rounded,
                        color: AppColors.goldAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome to the family!',
                            style: AppTextStyles.headlineSmall
                                .copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'One quick question before you dive in.',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: palette.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'HOW DID YOU HEAR ABOUT ADVENTIST SUPER APP?',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                for (final (label, icon) in _sources) ...[
                  _OptionRow(
                    label: label,
                    icon: icon,
                    selected: _source == label,
                    onTap: () => setState(() => _source = label),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 10),
                Text(
                  'What are you hoping to find here? (optional)',
                  style: AppTextStyles.labelMedium
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _hopeController,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
                  decoration: InputDecoration(
                    hintText: 'Fellowship, events, marketplace…',
                    hintStyle: TextStyle(color: palette.textMuted),
                    filled: true,
                    fillColor: palette.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primaryBlue),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PressEffect(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        disabledBackgroundColor:
                            AppColors.primaryBlue.withValues(alpha: 0.35),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: (_source == null || _saving) ? null : _submit,
                      child: _saving
                          ? const BrandSpinner(size: 22, color: AppColors.white)
                          : Text(
                              _source == null
                                  ? 'Pick one to continue'
                                  : 'Continue',
                              style: AppTextStyles.buttonText
                                  .copyWith(color: AppColors.white),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PressEffect(
      pressedScale: 0.97,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : palette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : palette.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.primaryBlue : palette.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: selected ? AppColors.primaryBlue : palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: AppMotion.maybe(context, AppMotion.quick),
                switchInCurve: AppMotion.spring,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('on'),
                        color: AppColors.primaryBlue,
                        size: 20,
                      )
                    : Icon(
                        Icons.circle_outlined,
                        key: const ValueKey('off'),
                        color: palette.divider,
                        size: 20,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
