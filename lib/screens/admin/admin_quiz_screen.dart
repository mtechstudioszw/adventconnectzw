import 'package:flutter/material.dart';

import '../../models/quiz_question_model.dart';
import '../../services/quiz_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import 'admin_quiz_reports_screen.dart';

/// Super-admin "Manage Quiz" — add / edit / delete Bible-quiz questions
/// (patch_147). Gated server-side by RLS (super admin only).
class AdminQuizScreen extends StatefulWidget {
  const AdminQuizScreen({super.key});

  @override
  State<AdminQuizScreen> createState() => _AdminQuizScreenState();
}

class _AdminQuizScreenState extends State<AdminQuizScreen> {
  late Future<List<QuizQuestion>> _future;

  @override
  void initState() {
    super.initState();
    _future = QuizService.fetchAllAdmin();
  }

  // Braces: an arrow body returns the assigned Future, and `setState`
  // asserts against that — so this threw instead of reloading.
  void _reload() => setState(() {
        _future = QuizService.fetchAllAdmin();
      });

  Future<void> _edit([QuizQuestion? q]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _QuizEditorScreen(question: q)),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(QuizQuestion q) async {
    final palette = context.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        title: Text(
          'Delete question?',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          q.question,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: palette.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await QuizService.deleteQuestion(q.id);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Manage Quiz',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
        ),
        actions: [
          IconButton(
            tooltip: 'Reported questions',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminQuizReportsScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add question'),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<QuizQuestion>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: BrandSpinner(size: 30));
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              );
            }
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return Center(
                child: Text(
                  'No questions yet. Tap “Add question”.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final q = list[i];
                return Material(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _edit(q),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.divider),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  q.question,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.titleSmall.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${q.category} · ${q.difficulty}',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.red,
                            ),
                            onPressed: () => _delete(q),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _QuizEditorScreen extends StatefulWidget {
  const _QuizEditorScreen({this.question});
  final QuizQuestion? question;

  @override
  State<_QuizEditorScreen> createState() => _QuizEditorScreenState();
}

class _QuizEditorScreenState extends State<_QuizEditorScreen> {
  late final _question = TextEditingController(
    text: widget.question?.question ?? '',
  );
  late final List<TextEditingController> _opts = List.generate(
    4,
    (i) => TextEditingController(
      text: (widget.question != null && i < widget.question!.options.length)
          ? widget.question!.options[i]
          : '',
    ),
  );
  late int _correct = widget.question?.correctIndex ?? 0;
  late final _explanation = TextEditingController(
    text: widget.question?.explanation ?? '',
  );
  late final _reference = TextEditingController(
    text: widget.question?.reference ?? '',
  );
  late final _category = TextEditingController(
    text: widget.question?.category ?? 'General',
  );
  late String _difficulty = widget.question?.difficulty ?? 'medium';
  bool _saving = false;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _opts) {
      c.dispose();
    }
    _explanation.dispose();
    _reference.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final opts = _opts.map((c) => c.text.trim()).toList();
    if (_question.text.trim().isEmpty || opts.any((o) => o.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Question and all 4 options are required.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await QuizService.saveQuestion(
        id: widget.question?.id,
        question: _question.text,
        options: opts,
        correctIndex: _correct,
        explanation: _explanation.text,
        reference: _reference.text,
        category: _category.text,
        difficulty: _difficulty,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          widget.question == null ? 'New question' : 'Edit question',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 18),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_question, 'Question', minLines: 2, maxLines: 4),
            const SizedBox(height: 14),
            Text(
              'OPTIONS (tap the circle to mark the correct one)',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _correct = i),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _correct == i
                              ? AppColors.successGreen
                              : Colors.transparent,
                          border: Border.all(
                            color: _correct == i
                                ? AppColors.successGreen
                                : palette.divider,
                            width: 2,
                          ),
                        ),
                        child: _correct == i
                            ? const Icon(
                                Icons.check,
                                color: AppColors.white,
                                size: 16,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_opts[i], 'Option ${i + 1}')),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(_category, 'Category')),
                const SizedBox(width: 12),
                _DifficultyPicker(
                  value: _difficulty,
                  onChanged: (v) => setState(() => _difficulty = v),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _field(
              _explanation,
              'Explanation (optional)',
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 14),
            _field(_reference, 'Bible / reference (optional)'),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(
                        'Save question',
                        style: AppTextStyles.buttonText.copyWith(
                          color: AppColors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    int minLines = 1,
    int maxLines = 1,
  }) {
    final palette = context.palette;
    return TextField(
      controller: c,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
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
    );
  }
}

class _DifficultyPicker extends StatelessWidget {
  const _DifficultyPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: const [
            DropdownMenuItem(value: 'easy', child: Text('Easy')),
            DropdownMenuItem(value: 'medium', child: Text('Medium')),
            DropdownMenuItem(value: 'hard', child: Text('Hard')),
          ],
          onChanged: (v) => onChanged(v ?? 'medium'),
        ),
      ),
    );
  }
}
