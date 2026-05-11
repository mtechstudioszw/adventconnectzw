import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/notice_model.dart';
import '../../services/notice_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Post a community notice. The Home tab's quick-action strip lands here.
class PostNoticeScreen extends StatefulWidget {
  const PostNoticeScreen({super.key});

  @override
  State<PostNoticeScreen> createState() => _PostNoticeScreenState();
}

class _PostNoticeScreenState extends State<PostNoticeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String? _category;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String? _validateTitle(String? v) {
    if (v == null || v.trim().isEmpty) return 'Give it a clear title';
    if (v.trim().length < 4) return 'A bit more please';
    if (v.length > 80) return 'Keep it under 80 characters';
    return null;
  }

  String? _validateBody(String? v) {
    if (v == null || v.trim().isEmpty) return 'Add the details';
    if (v.trim().length < 20) return 'At least 20 characters';
    if (v.length > 600) return 'Keep it under 600 characters';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      setState(() => _error = 'Pick a category.');
      return;
    }
    setState(() => _saving = true);
    try {
      await NoticeService.post(
        title: _titleController.text,
        body: _bodyController.text,
        category: _category!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Notice posted.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed('home');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const ScreenHero(
              title: 'Post a notice',
              tagline: 'Community board',
              subtitle:
                  'A short message visible to everyone — lost items, accommodation, transport.',
              fallbackRoute: 'home',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CATEGORY',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: const Color.fromRGBO(26, 26, 46, 0.65),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: [
                              for (final c in NoticeCategory.all)
                                _CategoryChip(
                                  category: c,
                                  active: _category == c.id,
                                  onTap: () =>
                                      setState(() => _category = c.id),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ScreenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TITLE',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: const Color.fromRGBO(26, 26, 46, 0.65),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _titleController,
                            validator: _validateTitle,
                            textCapitalization: TextCapitalization.sentences,
                            style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                            decoration: _decoration(
                              icon: Icons.title,
                              hint: 'e.g. Lost phone at AHU',
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Text(
                                'DETAILS',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: const Color.fromRGBO(26, 26, 46, 0.65),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_bodyController.text.length}/600',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color:
                                      const Color.fromRGBO(26, 26, 46, 0.45),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _bodyController,
                            validator: _validateBody,
                            maxLength: 600,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                            style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                            decoration: _decoration(
                              icon: Icons.notes_outlined,
                              hint:
                                  'What happened, where, how to reach you.',
                            ).copyWith(counterText: ''),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 24),
                    PrimaryGradientButton(
                      label: _saving ? 'Posting...' : 'Post notice',
                      busy: _saving,
                      onTap: _saving ? null : _submit,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Keep it respectful. Posts violating community guidelines will be removed.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.55),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required IconData icon,
    required String hint,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: AppColors.lightGrey,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color.fromRGBO(26, 26, 46, 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.primaryBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.active,
    required this.onTap,
  });

  final NoticeCategory category;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: active ? AppColors.primaryGradient : null,
          color: active ? null : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppColors.primaryBlue
                : const Color.fromRGBO(26, 26, 46, 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(category.icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: AppTextStyles.labelMedium.copyWith(
                color: active ? AppColors.white : AppColors.textDark,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
