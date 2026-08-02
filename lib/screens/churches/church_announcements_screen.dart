import 'package:flutter/material.dart';

import '../../models/church_model.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/announcement_reaction_bar.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Read-only feed of a single church's announcements.
class ChurchAnnouncementsScreen extends StatefulWidget {
  const ChurchAnnouncementsScreen({
    super.key,
    required this.church,
    this.autoLoad = true,
  });

  final Church church;

  /// Test seam. `initState` fetches announcements, marks them read and
  /// batch-fetches reactions — three Supabase calls that a widget test has
  /// no client for. Same convention as `ChurchDetailsScreen.autoLoad` and
  /// `SearchScreen.autoLoad`.
  final bool autoLoad;

  @override
  State<ChurchAnnouncementsScreen> createState() =>
      _ChurchAnnouncementsScreenState();
}

class _ChurchAnnouncementsScreenState extends State<ChurchAnnouncementsScreen> {
  bool _loading = true;
  String? _error;
  List<ChurchAnnouncement> _items = const [];

  /// Reactions per announcement id. Held here rather than in the card so
  /// one batched fetch fills every card, and so an optimistic tap has a
  /// single place to roll back to.
  Map<String, AnnouncementReactionState> _reactions = const {};

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ChurchService.fetchAnnouncements(
        churchId: widget.church.id,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      // Every card on this screen shows its FULL body — there is no
      // "tap to expand", so reaching this list is reading it. Recording
      // it here is what makes the admin reach sparkline mean opens
      // rather than sends (patch_173). Fire-and-forget.
      for (final a in items) {
        ChurchService.markAnnouncementRead(a.id).ignore();
      }
      // One call for the whole list, after the cards are already on screen
      // — the announcement is the content, the faces are decoration, and
      // waiting on them would delay the thing the member came to read.
      final reactions = await ChurchService.fetchAnnouncementReactions(
        items.map((a) => a.id).toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _reactions = reactions);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load announcements. Pull to retry.';
      });
    }
  }

  /// Applies the tap locally before the server hears about it.
  ///
  /// The founder's rule is that premium reads as FAST, so the face fills
  /// on touch and the number moves with it. `set_announcement_reaction`
  /// returns the authoritative tally in the same round trip, so the
  /// reconcile below is a correction, not a second render — and on failure
  /// it puts back exactly what was there before.
  Future<void> _react(String id, AnnouncementReaction tapped) async {
    final before = _reactions[id] ?? AnnouncementReactionState.empty;
    setState(() => _reactions = {..._reactions, id: before.afterTapping(tapped)});

    final server = await ChurchService.setAnnouncementReaction(id, tapped);
    if (!mounted) return;
    setState(() => _reactions = {..._reactions, id: server ?? before});
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
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }
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
            child: _AnnouncementCard(
              item: a,
              reactions: _reactions[a.id] ?? AnnouncementReactionState.empty,
              onReact: (kind) => _react(a.id, kind),
            ),
          ),
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.item,
    required this.reactions,
    required this.onReact,
  });

  final ChurchAnnouncement item;
  final AnnouncementReactionState reactions;
  final ValueChanged<AnnouncementReaction> onReact;

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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                  color: AppColors.textMuted,
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
              color: AppColors.textMuted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: context.palette.divider),
          const SizedBox(height: 10),
          AnnouncementReactionBar(state: reactions, onReact: onReact),
        ],
      ),
    );
  }
}
