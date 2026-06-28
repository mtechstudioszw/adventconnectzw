import 'package:flutter/material.dart';

import '../../services/signup_survey_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// One-time welcome survey shown on the first home visit after signup.
/// Asks how the user found the app (+ a light optional question) so the
/// founder can understand their audience. Skippable; never shown twice.
class SignupSurveySheet extends StatefulWidget {
  const SignupSurveySheet({super.key});

  /// Show it once if the user hasn't answered/dismissed before.
  static Future<void> maybeShow(BuildContext context) async {
    if (!SignupSurveyService.shouldPrompt()) return;
    // Mark shown immediately so a back-press or crash doesn't re-trigger it.
    await SignupSurveyService.markShown();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => const SignupSurveySheet(),
    );
  }

  @override
  State<SignupSurveySheet> createState() => _SignupSurveySheetState();
}

class _SignupSurveySheetState extends State<SignupSurveySheet> {
  static const _sources = [
    'Friend or family',
    'My church',
    'Social media',
    'App store / search',
    'Other',
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
      // Swallowed — markShown already ran so we never nag again; the founder
      // just misses this one response.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Welcome! 👋',
                  style: AppTextStyles.headlineSmall
                      .copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Quick question so we can grow the community — how did you hear '
                'about Advent Connect?',
                style:
                    AppTextStyles.bodyMedium.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _sources)
                    _Chip(
                      label: s,
                      selected: _source == s,
                      onTap: () => setState(() => _source = s),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('What are you hoping to find here? (optional)',
                  style: AppTextStyles.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
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
                  counterText: '',
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
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: (_source == null || _saving) ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.white))
                      : Text('Submit',
                          style: AppTextStyles.buttonText
                              .copyWith(color: AppColors.white)),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text('Skip',
                      style: TextStyle(color: palette.textMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : palette.inputFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : palette.divider,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? AppColors.white : palette.text,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}
