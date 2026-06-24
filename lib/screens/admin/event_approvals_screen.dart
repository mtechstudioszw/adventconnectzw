import 'package:flutter/material.dart';

import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Super-admin queue of community events awaiting review.
/// Uses the admin_list_pending_events / admin_approve_event /
/// admin_reject_event RPCs (patch_109). Gated server-side by
/// assert_super_admin; reachable from Settings → Super admin →
/// Event approvals.
class EventApprovalsScreen extends StatefulWidget {
  const EventApprovalsScreen({super.key});

  @override
  State<EventApprovalsScreen> createState() => _EventApprovalsScreenState();
}

class _EventApprovalsScreenState extends State<EventApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<Event> _pending = const [];
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
      final rows = await EventService.adminFetchPendingEvents();
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
            ? 'Only super admins can review events.'
            : 'Could not load pending events. Pull to retry.';
      });
    }
  }

  Future<void> _approve(Event event) async {
    final id = event.id;
    if (_busyIds.contains(id)) return;
    setState(() => _busyIds.add(id));
    try {
      await EventService.adminApproveEvent(id);
      if (!mounted) return;
      _showSnack('Event approved and organizer notified.');
      _load();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not approve. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _reject(Event event) async {
    final id = event.id;
    if (_busyIds.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject event?'),
        content: Text(
          'Reject "${event.title}"? The organizer will not be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyIds.add(id));
    try {
      await EventService.adminRejectEvent(id);
      if (!mounted) return;
      _showSnack('Event rejected.');
      _load();
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not reject. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: isError ? AppColors.red : AppColors.primaryBlue,
      content: Text(msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Event approvals',
          style: AppTextStyles.appBarTitle,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: context.palette.textMuted)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available_outlined,
                  size: 56, color: context.palette.textMuted),
              const SizedBox(height: 16),
              Text(
                'No pending events',
                style: AppTextStyles.titleMedium.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'All community events have been reviewed.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: context.palette.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pending.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _EventCard(
          event: _pending[i],
          busy: _busyIds.contains(_pending[i].id),
          onApprove: () => _approve(_pending[i]),
          onReject: () => _reject(_pending[i]),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Event event;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover photo
          if (event.coverPhotoUrl != null && event.coverPhotoUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                event.coverPhotoUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (event.coverPhotoUrl != null && event.coverPhotoUrl!.isNotEmpty)
            const SizedBox(height: 12),
          Text(
            event.title,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 13, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                _fmtDate(event.eventDate),
                style:
                    AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
              ),
              if (event.location != null && event.location!.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.place_outlined,
                    size: 13, color: palette.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    event.location!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: palette.textMuted),
                  ),
                ),
              ],
            ],
          ),
          if (event.organizerName != null &&
              event.organizerName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person_outline, size: 13, color: palette.textMuted),
                const SizedBox(width: 4),
                Text(
                  'By ${event.organizerName}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ],
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              event.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(color: palette.text),
            ),
          ],
          const SizedBox(height: 14),
          busy
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.red),
                          foregroundColor: AppColors.red,
                        ),
                        onPressed: onReject,
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                        ),
                        onPressed: onApprove,
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
