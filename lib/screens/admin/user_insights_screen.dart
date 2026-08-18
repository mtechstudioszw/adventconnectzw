import 'package:flutter/material.dart';

import '../../services/signup_survey_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Super-admin "User insights" — where signup-survey responses land
/// (patch_136). Shows how members heard about the app, plus recent
/// individual responses. Gated server-side (RLS / RPC require super admin).
class UserInsightsScreen extends StatefulWidget {
  const UserInsightsScreen({super.key});

  @override
  State<UserInsightsScreen> createState() => _UserInsightsScreenState();
}

class _UserInsightsScreenState extends State<UserInsightsScreen> {
  late Future<_InsightsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_InsightsData> _load() async {
    final summary = await SignupSurveyService.fetchSummary();
    final recent = await SignupSurveyService.fetchRecent();
    return _InsightsData(summary: summary, recent: recent);
  }

  // Braces: an arrow body returns the assigned Future, and `setState`
  // asserts against that — so this threw instead of reloading.
  void _reload() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'User insights',
          style: AppTextStyles.appBarTitleFlat.copyWith(fontSize: 19),
        ),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<_InsightsData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: BrandSpinner(size: 30));
            }
            if (snap.hasError) {
              return _Error(message: '${snap.error}', onRetry: _reload);
            }
            final data = snap.data!;
            final total = data.summary.fold<int>(0, (sum, e) => sum + e.total);
            if (total == 0) {
              return _Empty(palette: palette, onRetry: _reload);
            }
            return BrandedRefreshIndicator(
              color: AppColors.primaryBlue,
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'HOW USERS HEARD ABOUT US',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$total response(s)',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final s in data.summary)
                    _SourceBar(
                      label: s.source,
                      count: s.total,
                      fraction: total == 0 ? 0 : s.total / total,
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'RECENT RESPONSES',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final r in data.recent) _ResponseTile(response: r),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InsightsData {
  const _InsightsData({required this.summary, required this.recent});
  final List<({String source, int total})> summary;
  final List<SurveyResponse> recent;
}

class _SourceBar extends StatelessWidget {
  const _SourceBar({
    required this.label,
    required this.count,
    required this.fraction,
  });
  final String label;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.02, 1.0),
              minHeight: 8,
              backgroundColor: palette.cardMuted,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseTile extends StatelessWidget {
  const _ResponseTile({required this.response});
  final SurveyResponse response;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hope = response.answers['hoping_for']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  response.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  response.source,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (hope != null && hope.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '“$hope”',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.palette, required this.onRetry});
  final AppPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 60, color: palette.textMuted),
            const SizedBox(height: 16),
            Text(
              'No survey responses yet.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              onPressed: onRetry,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
