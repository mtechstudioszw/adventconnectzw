import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Lists events the current user has RSVP'd to, split into upcoming
/// and past. Tap a row → event_details. Cancel RSVP swipes the row off
/// the upcoming list.
class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen> {
  bool _loading = true;
  String? _error;
  List<Event> _upcoming = const [];
  List<Event> _past = const [];

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
      final ids = await EventService.fetchUserRsvpedEventIds();
      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _upcoming = const [];
          _past = const [];
          _loading = false;
        });
        return;
      }
      // Fetch a wide window of events, then filter to ones we RSVP'd to
      // and split by date. Cheaper than N round-trips for one row each.
      final all = await EventService.fetchEvents(upcomingOnly: true);
      final past = await EventService.fetchEvents(upcomingOnly: false);
      final mine = [...all, ...past].where((e) => ids.contains(e.id)).toList();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final upcoming = mine
          .where((e) => !e.eventDate.isBefore(today))
          .toList()
        ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
      final pastEvents = mine
          .where((e) => e.eventDate.isBefore(today))
          .toList()
        ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
      if (!mounted) return;
      setState(() {
        _upcoming = upcoming;
        _past = pastEvents;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your events. Pull to retry.';
      });
    }
  }

  Future<void> _cancel(Event e) async {
    try {
      await EventService.cancelRsvp(e.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'RSVP cancelled.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not cancel. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
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
              const ScreenHero(
                title: 'My events',
                tagline: 'Your RSVPs',
                subtitle: 'Events you said you\'re going to.',
                fallbackRoute: 'profile',
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
    if (_error != null) {
      return ErrorBanner(message: _error!);
    }
    if (_upcoming.isEmpty && _past.isEmpty) {
      return EmptyStateCard(
        icon: Icons.event_outlined,
        title: 'No events yet',
        message:
            'Browse the Events tab and tap "I\'m going" to start collecting RSVPs.',
        action: PrimaryGradientButton(
          label: 'Browse events',
          icon: Icons.search,
          onTap: () => context.goNamed('events'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_upcoming.isNotEmpty) ...[
          _SectionLabel(label: 'UPCOMING', count: _upcoming.length),
          const SizedBox(height: 10),
          for (final e in _upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EventRow(
                event: e,
                isPast: false,
                onOpen: () => context.pushNamed(
                  'event_details',
                  pathParameters: {'id': e.id},
                  extra: e,
                ),
                onCancel: () => _cancel(e),
              ),
            ),
        ],
        if (_past.isNotEmpty) ...[
          if (_upcoming.isNotEmpty) const SizedBox(height: 12),
          _SectionLabel(label: 'PAST', count: _past.length),
          const SizedBox(height: 10),
          for (final e in _past)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EventRow(
                event: e,
                isPast: true,
                onOpen: () => context.pushNamed(
                  'event_details',
                  pathParameters: {'id': e.id},
                  extra: e,
                ),
                onCancel: null,
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
            fontSize: 10.5,
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

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.isPast,
    required this.onOpen,
    required this.onCancel,
  });

  final Event event;
  final bool isPast;
  final VoidCallback onOpen;
  final VoidCallback? onCancel;

  String _monthShort(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 70,
                decoration: BoxDecoration(
                  gradient: isPast ? null : AppColors.primaryGradient,
                  color: isPast
                      ? AppColors.lightGrey
                      : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _monthShort(event.eventDate.month).toUpperCase(),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isPast
                            ? const Color.fromRGBO(26, 26, 46, 0.55)
                            : AppColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      '${event.eventDate.day}',
                      style: AppTextStyles.displayMedium.copyWith(
                        color: isPast ? AppColors.textDark : AppColors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 13,
                          color: Color.fromRGBO(26, 26, 46, 0.55),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.eventTime,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color.fromRGBO(26, 26, 46, 0.65),
                          ),
                        ),
                        if (event.location != null && event.location!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: Color.fromRGBO(26, 26, 46, 0.55),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              event.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: const Color.fromRGBO(26, 26, 46, 0.65),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onCancel != null)
                IconButton(
                  tooltip: 'Cancel RSVP',
                  icon: const Icon(
                    Icons.event_busy_outlined,
                    color: AppColors.red,
                    size: 20,
                  ),
                  onPressed: onCancel,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
