import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Super-admin queue for church-admin claims (patch_112). Each card surfaces
/// the applicant's contact so the founder can verify them on WhatsApp, then
/// Approve / Reject. Approving flips status='approved' (the applicant gets a
/// notification + dashboard access).
class ChurchAdminApprovalsScreen extends StatefulWidget {
  const ChurchAdminApprovalsScreen({super.key});

  @override
  State<ChurchAdminApprovalsScreen> createState() =>
      _ChurchAdminApprovalsScreenState();
}

class _ChurchAdminApprovalsScreenState
    extends State<ChurchAdminApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<PendingChurchAdmin> _items = const [];
  final _busy = <int>{};

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
      final items = await ChurchService.listPendingChurchAdmins();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load requests.';
        _loading = false;
      });
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse(
        'https://wa.me/$cleaned?text=${Uri.encodeComponent('Hi, about your Advent Connect church-admin request…')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _email(String email) async {
    await launchUrl(Uri.parse('mailto:$email'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _approve(PendingChurchAdmin a) async {
    setState(() => _busy.add(a.id));
    try {
      await ChurchService.approveChurchAdmin(a.id);
      if (!mounted) return;
      setState(() => _items = _items.where((x) => x.id != a.id).toList());
      _toast('${a.applicantName} approved for ${a.churchName}.',
          AppColors.successGreen);
    } catch (_) {
      _toast('Could not approve. Try again.', AppColors.red);
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  Future<void> _reject(PendingChurchAdmin a) async {
    final reason = await _askReason();
    if (reason == null) return;
    setState(() => _busy.add(a.id));
    try {
      await ChurchService.rejectChurchAdmin(a.id, reason: reason);
      if (!mounted) return;
      setState(() => _items = _items.where((x) => x.id != a.id).toList());
      _toast('Request rejected.', AppColors.darkNavy);
    } catch (_) {
      _toast('Could not reject. Try again.', AppColors.red);
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  Future<String?> _askReason() async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Reject request', style: AppTextStyles.headlineSmall),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'Reason (optional, shown to applicant)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text('Reject', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    c.dispose();
    return result;
  }

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: bg,
      content:
          Text(msg, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const ScreenHero(
                title: 'Church admin requests',
                tagline: 'Verify on WhatsApp, then approve',
                subtitle: 'Approve people to manage their church.',
                fallbackRoute: 'home',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primaryBlue)),
                      )
                    : _error != null
                        ? ErrorBanner(message: _error!)
                        : _items.isEmpty
                            ? const EmptyStateCard(
                                icon: Icons.verified_user_outlined,
                                title: 'No pending requests',
                                message:
                                    'Church-admin applications will appear here.',
                              )
                            : Column(
                                children: [
                                  for (final a in _items)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _ClaimCard(
                                        item: a,
                                        busy: _busy.contains(a.id),
                                        onWhatsApp: () =>
                                            _openWhatsApp(a.applicantPhone),
                                        onEmail: a.applicantEmail == null
                                            ? null
                                            : () => _email(a.applicantEmail!),
                                        onApprove: () => _approve(a),
                                        onReject: () => _reject(a),
                                      ),
                                    ),
                                ],
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClaimCard extends StatelessWidget {
  const _ClaimCard({
    required this.item,
    required this.busy,
    required this.onWhatsApp,
    required this.onApprove,
    required this.onReject,
    this.onEmail,
  });

  final PendingChurchAdmin item;
  final bool busy;
  final VoidCallback onWhatsApp;
  final VoidCallback? onEmail;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.applicantName,
              style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w800, color: context.palette.text)),
          const SizedBox(height: 2),
          Text('${item.role} · ${item.churchName}'
              '${item.churchCity != null && item.churchCity!.isNotEmpty ? ' · ${item.churchCity}' : ''}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.palette.textMuted)),
          if (item.note != null && item.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item.note!,
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.palette.text, height: 1.4)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onWhatsApp,
                icon: const Icon(Icons.chat, size: 18),
                label: Text(item.applicantPhone,
                    style: AppTextStyles.labelMedium),
              ),
              if (onEmail != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEmail,
                  icon: const Icon(Icons.email_outlined,
                      color: AppColors.primaryBlue),
                  tooltip: item.applicantEmail,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onApprove,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.successGreen),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.white))
                      : Text('Approve', style: AppTextStyles.labelLarge),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red)),
                  child: Text('Reject',
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.red)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
