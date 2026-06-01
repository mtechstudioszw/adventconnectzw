import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/feedback_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackCategory {
  const _FeedbackCategory(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const List<_FeedbackCategory> _categories = [
  _FeedbackCategory('general', 'General', Icons.chat_bubble_outline),
  _FeedbackCategory('bug', 'Bug report', Icons.bug_report_outlined),
  _FeedbackCategory('feature_request', 'Feature request', Icons.lightbulb_outline),
  _FeedbackCategory('content', 'Content issue', Icons.flag_outlined),
  _FeedbackCategory('other', 'Other', Icons.more_horiz),
];

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  String _categoryId = 'general';
  bool _submitting = false;
  String? _serverError;

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await FeedbackService.submit(
        category: _categoryId,
        subject: _subjectController.text,
        body: _bodyController.text,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Thanks — we got it.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _serverError = 'Could not send feedback. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Send feedback',
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tell us what\'s working, what\'s broken, or what you wish was there. The team reads every message.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    label: 'Category',
                    child: _CategoryChips(
                      selected: _categoryId,
                      onSelected: (id) => setState(() => _categoryId = id),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    label: 'Subject',
                    child: TextFormField(
                      controller: _subjectController,
                      maxLength: 120,
                      decoration: _inputDecoration('A short summary'),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.length < 3) return 'At least 3 characters';
                        return null;
                      },
                    ),
                  ),
                  _Section(
                    label: 'Details',
                    child: TextFormField(
                      controller: _bodyController,
                      maxLines: 8,
                      minLines: 5,
                      maxLength: 2000,
                      decoration: _inputDecoration(
                        'What happened? What did you expect?',
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.length < 5) return 'A bit more detail, please';
                        return null;
                      },
                    ),
                  ),
                  if (_serverError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.red.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _serverError!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _SubmitButton(
                    loading: _submitting,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: context.palette.inputFill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in _categories)
          GestureDetector(
            onTap: () => onSelected(c.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.id == selected
                    ? AppColors.primaryBlue
                    : context.palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: c.id == selected
                      ? AppColors.primaryBlue
                      : context.palette.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    c.icon,
                    size: 16,
                    color: c.id == selected
                        ? AppColors.white
                        : AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    c.label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: c.id == selected
                          ? AppColors.white
                          : AppColors.textDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null && !loading ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppColors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        'Send feedback',
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          letterSpacing: 0.4,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
