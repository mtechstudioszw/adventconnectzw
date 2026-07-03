import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';

import '../../services/advent_news_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Super-admin queue of member-submitted Advent News awaiting review.
/// Mirrors SellerApprovalsScreen — same RPC-backed approve/reject
/// pattern (patch_047). Reachable from Settings → Super admin →
/// News approvals, and gated server-side by is_super_admin.
class NewsApprovalsScreen extends StatefulWidget {
  const NewsApprovalsScreen({super.key});

  @override
  State<NewsApprovalsScreen> createState() => _NewsApprovalsScreenState();
}

class _NewsApprovalsScreenState extends State<NewsApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = const [];
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdventNewsService.fetchPendingNews();
      if (!mounted) return;
      setState(() {
        _pending = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('Not authorized')
            ? 'Only super admins can review news.'
            : 'Could not load pending news. Pull to retry.';
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> n) async {
    final id = n['id'].toString();
    if (_busyIds.contains(id)) return;
    setState(() => _busyIds.add(id));
    try {
      await AdventNewsService.approveNews(id);
      if (!mounted) return;
      setState(() => _pending.removeWhere((x) => x['id'].toString() == id));
      _snack('Approved — now live on Advent News.', AppColors.successGreen);
    } catch (_) {
      if (!mounted) return;
      _snack('Could not approve. Try again.', AppColors.red);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> n) async {
    final id = n['id'].toString();
    final reason = await _askReason();
    if (reason == null) return;
    if (_busyIds.contains(id)) return;
    setState(() => _busyIds.add(id));
    try {
      await AdventNewsService.rejectNews(id, reason: reason);
      if (!mounted) return;
      setState(() => _pending.removeWhere((x) => x['id'].toString() == id));
      _snack('Rejected.', AppColors.red);
    } catch (_) {
      if (!mounted) return;
      _snack('Could not reject. Try again.', AppColors.red);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<String?> _askReason() {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject this story?'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 240,
          decoration: InputDecoration(
            hintText: 'Reason (optional, shown to the author)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(
          msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ),
      );
    }
    if (_pending.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              const Icon(
                Icons.inbox_outlined,
                size: 48,
                color: AppColors.successGreen,
              ),
              const SizedBox(height: 12),
              Text(
                'No news awaiting review',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in _pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PendingNewsCard(
              news: n,
              busy: _busyIds.contains(n['id'].toString()),
              onApprove: () => _approve(n),
              onReject: () => _reject(n),
            ),
          ),
      ],
    );
  }

  Widget _buildHero() {
    return const ScreenHero(
      title: 'News approvals',
      tagline: 'Super admin',
      subtitle:
          'Review member-submitted stories before they go live on Advent News.',
      fallbackRoute: 'settings',
    );
  }
}

class _PendingNewsCard extends StatelessWidget {
  const _PendingNewsCard({
    required this.news,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> news;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final cover = (news['cover_photo_url'] as String?) ?? '';
    final title = (news['title'] as String?) ?? '(untitled)';
    final summary = (news['summary'] as String?) ?? '';
    final body = (news['body'] as String?) ?? '';
    final author = (news['author_name'] as String?) ?? 'Member';
    final category = (news['category'] as String?) ?? '';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cover.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 7,
              child: CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                errorWidget: (ctx, url, error) => const ColoredBox(
                  color: Color(0xFFE4E7EC),
                  child: Icon(
                    Icons.image_outlined,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${category.isNotEmpty ? '$category · ' : ''}by $author',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    summary,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.text,
                      height: 1.5,
                    ),
                  ),
                ],
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    body.length > 500 ? '${body.substring(0, 500)}…' : body,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onReject,
                        icon: const Icon(Icons.close, size: 18),
                        label: Text('Reject', style: AppTextStyles.labelLarge),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onApprove,
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: AppColors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                          busy ? 'Working' : 'Approve',
                          style: AppTextStyles.labelLarge,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.successGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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

