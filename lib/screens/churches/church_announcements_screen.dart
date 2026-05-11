import 'package:flutter/material.dart';

import '../../models/church_model.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Read-only feed of a single church's announcements.
class ChurchAnnouncementsScreen extends StatefulWidget {
  const ChurchAnnouncementsScreen({super.key, required this.church});

  final Church church;

  @override
  State<ChurchAnnouncementsScreen> createState() =>
      _ChurchAnnouncementsScreenState();
}

class _ChurchAnnouncementsScreenState
    extends State<ChurchAnnouncementsScreen> {
  bool _loading = true;
  String? _error;
  List<ChurchAnnouncement> _items = const [];

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
      final items =
          await ChurchService.fetchAnnouncements(churchId: widget.church.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load announcements. Pull to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                title: 'Announcements',
                tagline: widget.church.name,
                subtitle: 'Updates posted by the church admin.',
                fallbackRoute: 'churches',
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
    if (_items.isEmpty) {
      return EmptyStateCard(
        icon: Icons.campaign_outlined,
        title: 'Nothing yet',
        message:
            'When ${widget.church.name} posts an update, it\'ll show here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AnnouncementCard(item: a),
          ),
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item});

  final ChurchAnnouncement item;

  Color _accentFor(String category) {
    switch (category) {
      case 'urgent':
        return AppColors.red;
      case 'obituary':
        return AppColors.darkNavy;
      case 'event':
        return AppColors.primaryBlue;
      case 'program':
        return AppColors.goldAccent;
      default:
        return AppColors.primaryBlue;
    }
  }

  String _labelFor(String category) {
    switch (category) {
      case 'urgent':
        return 'URGENT';
      case 'obituary':
        return 'OBITUARY';
      case 'event':
        return 'EVENT';
      case 'program':
        return 'PROGRAM';
      default:
        return 'GENERAL';
    }
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 7) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[d.month - 1]} ${d.day}';
    }
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(item.category);
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _labelFor(item.category),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (item.isPinned) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.goldAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.push_pin,
                        color: AppColors.goldAccent,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'PINNED',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.goldAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Text(
                _relative(item.createdAt),
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.body,
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.85),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
