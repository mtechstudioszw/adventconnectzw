import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/quiz_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/screen_shell.dart';

/// Super-admin view of questions players have reported.
///
/// The KJV generator writes questions procedurally. Its gates are strict —
/// well-known passages only, no leaked answers, no ambiguous "which book"
/// verses — but no gate is perfect, and a generated question has no row to
/// edit. This is the backstop: players flag anything that reads wrong, and
/// an admin can see exactly what they saw.
///
/// Curated reports link to a real `quiz_questions` row and can be fixed in
/// the editor. Generated ones can't be edited — the fix is to tighten a
/// gate in `QuizGenerator`, so the report text is the signal.
class AdminQuizReportsScreen extends StatefulWidget {
  const AdminQuizReportsScreen({super.key});

  @override
  State<AdminQuizReportsScreen> createState() => _AdminQuizReportsScreenState();
}

class _AdminQuizReportsScreenState extends State<AdminQuizReportsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _showResolved = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final query = Supabase.instance.client.from('quiz_reports').select();
    final rows = await (_showResolved
        ? query.order('created_at', ascending: false).limit(200)
        : query
            .eq('resolved', false)
            .order('created_at', ascending: false)
            .limit(200));
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // Braces: an arrow body returns the assigned Future, and `setState`
  // asserts against that — so this threw instead of reloading.
  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _resolve(Map<String, dynamic> report) async {
    try {
      await Supabase.instance.client
          .from('quiz_reports')
          .update({'resolved': true}).eq('id', report['id']);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _deleteQuestion(Map<String, dynamic> report) async {
    final id = report['question_id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      await QuizService.deleteQuestion(id);
      await _resolve(report);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            ScreenHero(
              title: 'Reported questions',
              tagline: 'Quiz',
              subtitle: _showResolved
                  ? 'Showing all reports'
                  : 'Showing open reports',
              trailing: ScreenHeroTrailing(
                icon: _showResolved
                    ? Icons.filter_alt_off_outlined
                    : Icons.filter_alt_outlined,
                onTap: () {
                  setState(() => _showResolved = !_showResolved);
                  _reload();
                },
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: BrandSpinner(size: 30));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: palette.textMuted),
                        ),
                      ),
                    );
                  }
                  final reports = snapshot.data ?? const [];
                  if (reports.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _showResolved
                              ? 'No reports yet.'
                              : 'No open reports — nothing to review.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: palette.textMuted),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _ReportCard(
                      report: reports[i],
                      onResolve: () => _resolve(reports[i]),
                      onDelete: () => _deleteQuestion(reports[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.onResolve,
    required this.onDelete,
  });

  final Map<String, dynamic> report;
  final VoidCallback onResolve;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isGenerated = report['is_generated'] == true;
    final resolved = report['resolved'] == true;

    return ScreenCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isGenerated
                          ? AppColors.goldAccent
                          : AppColors.primaryBlue)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isGenerated ? 'Generated' : 'Curated',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isGenerated
                        ? AppColors.goldAccent
                        : AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (resolved)
                Text(
                  'Resolved',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.successGreen),
                ),
              const Spacer(),
              Text(
                report['question_id']?.toString() ?? '',
                style: AppTextStyles.labelSmall
                    .copyWith(color: palette.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report['question_text']?.toString() ?? '(no text captured)',
            style: AppTextStyles.bodyMedium
                .copyWith(color: palette.text, height: 1.45),
          ),
          if ((report['reason']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${report['reason']}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: palette.textMuted),
            ),
          ],
          if (!resolved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Only curated questions have a row to delete. Generated
                // ones are fixed by tightening a gate in QuizGenerator.
                if (!isGenerated)
                  TextButton(
                    onPressed: onDelete,
                    child: Text(
                      'Delete question',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: AppColors.red),
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onResolve,
                  child: Text(
                    'Mark reviewed',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
