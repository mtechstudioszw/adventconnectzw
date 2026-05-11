import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Approval queue for a church admin. Shows community events that
/// reference this church and edit suggestions waiting on review.
class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key, required this.role});

  final ChurchAdminRole role;

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _edits = const [];

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
      final eventsResp = await _client
          .from('events')
          .select()
          .eq('church_id', widget.role.churchId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      final editsResp = await _client
          .from('church_edit_suggestions')
          .select()
          .eq('church_id', widget.role.churchId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _events = (eventsResp as List).cast<Map<String, dynamic>>();
        _edits = (editsResp as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the queue. Pull to retry.';
      });
    }
  }

  Future<void> _decideEvent(String id, bool approve) async {
    try {
      await _client
          .from('events')
          .update({'status': approve ? 'approved' : 'rejected'})
          .eq('id', id);
      _showSnack(approve ? 'Event approved.' : 'Event rejected.');
      _load();
    } catch (_) {
      _showSnack('Could not update. Try again.', isError: true);
    }
  }

  Future<void> _decideEdit(String id, bool approve) async {
    try {
      await _client
          .from('church_edit_suggestions')
          .update({'status': approve ? 'approved' : 'rejected'})
          .eq('id', id);
      _showSnack(approve ? 'Edit approved.' : 'Edit rejected.');
      _load();
    } catch (_) {
      _showSnack('Could not update. Try again.', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.red : AppColors.successGreen,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _events.length + _edits.length;
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              ScreenHero(
                title: 'Pending approvals',
                tagline: widget.role.churchName,
                subtitle:
                    '$total item${total == 1 ? '' : 's'} waiting on your review.',
                fallbackRoute: 'admin_dashboard',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_error != null) return ErrorBanner(message: _error!);
    if (_events.isEmpty && _edits.isEmpty) {
      return EmptyStateCard(
        icon: Icons.task_alt_outlined,
        title: 'All caught up',
        message: 'Nothing waiting on you right now. Good work.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_events.isNotEmpty) ...[
          _SectionLabel(label: 'COMMUNITY EVENTS', count: _events.length),
          const SizedBox(height: 10),
          for (final e in _events)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ApprovalCard(
                icon: Icons.event_outlined,
                title: (e['title'] ?? 'Event') as String,
                subtitle:
                    '${(e['venue'] ?? '') as String}  ·  ${(e['start_date'] ?? '') as String}',
                body: (e['description'] ?? '') as String,
                onApprove: () => _decideEvent(e['id'].toString(), true),
                onReject: () => _decideEvent(e['id'].toString(), false),
              ),
            ),
        ],
        if (_edits.isNotEmpty) ...[
          if (_events.isNotEmpty) const SizedBox(height: 6),
          _SectionLabel(label: 'EDIT SUGGESTIONS', count: _edits.length),
          const SizedBox(height: 10),
          for (final e in _edits)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ApprovalCard(
                icon: Icons.edit_outlined,
                title:
                    'Change ${((e['field_name'] ?? 'field') as String).replaceAll('_', ' ')}',
                subtitle:
                    '"${(e['current_value'] ?? '—') as String}" → "${(e['suggested_value'] ?? '—') as String}"',
                body: '',
                onApprove: () => _decideEdit(e['id'].toString(), true),
                onReject: () => _decideEdit(e['id'].toString(), false),
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryBlue,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onApprove,
    required this.onReject,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String body;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.75),
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Reject',
                  icon: Icons.close,
                  color: AppColors.red,
                  filled: false,
                  onTap: onReject,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: 'Approve',
                  icon: Icons.check,
                  color: AppColors.successGreen,
                  filled: true,
                  onTap: onApprove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: filled ? AppColors.white : color,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: filled ? AppColors.white : color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
