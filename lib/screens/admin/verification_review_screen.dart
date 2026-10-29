import 'package:flutter/material.dart';

import '../../services/verification_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/motion/brand_spinner.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/screen_shell.dart';

/// Super admin: decide gold-tick requests (patch 289).
///
/// Compare the selfie with the ID photo and the legal name with the
/// account. Approve, or reject with a reason the member is sent. Either
/// way the photos are deleted straight after — we keep the decision, not
/// the documents. Approved ticks can be revoked from the second tab
/// (impersonation, scams, a reported fake).
class VerificationReviewScreen extends StatefulWidget {
  const VerificationReviewScreen({super.key});

  @override
  State<VerificationReviewScreen> createState() =>
      _VerificationReviewScreenState();
}

class _VerificationReviewScreenState extends State<VerificationReviewScreen> {
  List<VerificationRequest> _pending = const [];
  List<VerificationRequest> _approved = const [];
  bool _loading = true;
  String? _error;
  bool _showApproved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        VerificationService.pending(),
        VerificationService.approved(),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0];
        _approved = results[1];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load requests. Has patch 289 been run?";
      });
    }
  }

  Future<void> _decide(VerificationRequest r, String action) async {
    String? reason;
    if (action != 'approve') {
      reason = await _askReason(action);
      if (reason == null) return;
    }
    try {
      await VerificationService.review(r, action, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            'approve' => 'Approved. ${r.memberName ?? 'They'} will be told.',
            'reject' => 'Rejected. The reason was sent.',
            _ => 'Tick removed.',
          }),
        ),
      );
      _load();
    } on VerificationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<String?> _askReason(String action) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'reject' ? 'Reason for rejecting' : 'Reason for removing'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'e.g. The name on the ID does not match the account.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(context, t);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _showApproved ? _approved : _pending;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const ScreenHero(
            title: 'Gold tick requests',
            tagline: 'Admin',
            subtitle: 'Check the ID, then decide. Photos are deleted after.',
            fallbackRoute: 'settings',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text('Waiting (${_pending.length})'),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Approved (${_approved.length})'),
                ),
              ],
              selected: {_showApproved},
              onSelectionChanged: (s) =>
                  setState(() => _showApproved = s.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: BrandSpinner(size: 30))
                : _error != null
                ? Center(child: ErrorBanner(message: _error!, onRetry: _load))
                : BrandedRefreshIndicator(
                    onRefresh: _load,
                    child: list.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              EmptyStateCard(
                                icon: Icons.verified_outlined,
                                title: _showApproved
                                    ? 'No ticks yet'
                                    : 'Nothing waiting',
                                message: _showApproved
                                    ? 'Approved members appear here.'
                                    : 'New requests appear here.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) => _RequestCard(
                              request: list[i],
                              onApprove: () => _decide(list[i], 'approve'),
                              onReject: () => _decide(list[i], 'reject'),
                              onRevoke: () => _decide(list[i], 'revoke'),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    required this.onRevoke,
  });

  final VerificationRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final r = request;
    final pending = r.status == VerifyStatus.pending;
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: palette.chipBg,
                backgroundImage: r.memberPhotoUrl != null
                    ? NetworkImage(r.memberPhotoUrl!)
                    : null,
                child: r.memberPhotoUrl == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.memberName ?? 'Member',
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                      ),
                    ),
                    Text(
                      r.isPage
                          ? 'Page: ${r.pageName ?? 'unnamed'} · ${r.category.label}'
                          : r.category.label,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Name on ID: ${r.legalName}',
            style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
          ),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Doc(path: r.idDocPath, label: 'ID')),
                const SizedBox(width: 10),
                Expanded(child: _Doc(path: r.selfiePath, label: 'Selfie')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryGradientButton(
                    label: 'Approve',
                    onTap: onApprove,
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRevoke,
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                child: const Text('Remove tick'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One private document, through a 10-minute signed link.
class _Doc extends StatelessWidget {
  const _Doc({required this.path, required this.label});
  final String? path;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FutureBuilder<String?>(
      future: VerificationService.viewUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        return GestureDetector(
          onTap: url == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: InteractiveViewer(child: Image.network(url)),
                  ),
                ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: palette.chipBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: url == null
                  ? Center(
                      child: snap.connectionState == ConnectionState.waiting
                          ? const BrandSpinner(size: 20)
                          : Text(
                              '$label unavailable',
                              style: AppTextStyles.caption.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                    )
                  : Image.network(url, fit: BoxFit.cover),
            ),
          ),
        );
      },
    );
  }
}
