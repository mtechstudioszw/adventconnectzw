import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';

/// Lists events the current user has RSVP'd to OR posted, split by
/// tab. Tap a row → event_details. Cancel RSVP swipes the row off
/// the upcoming list (Going tab only).
enum _MyEventsTab { going, posted }

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
  List<Event> _postedUpcoming = const [];
  List<Event> _postedPast = const [];
  _MyEventsTab _tab = _MyEventsTab.going;

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
      // Fetch RSVP ids + posted events in parallel so the screen
      // paints once instead of twice.
      final ids = await EventService.fetchUserRsvpedEventIds();
      final posted = await EventService.fetchMyPostedEvents();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      List<Event> rsvpUpcoming = const [];
      List<Event> rsvpPast = const [];
      if (ids.isNotEmpty) {
        final all = await EventService.fetchEvents(upcomingOnly: true);
        final pastAll = await EventService.fetchEvents(upcomingOnly: false);
        final mine =
            [...all, ...pastAll].where((e) => ids.contains(e.id)).toList();
        rsvpUpcoming = mine
            .where((e) => !e.eventDate.isBefore(today))
            .toList()
          ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
        rsvpPast = mine
            .where((e) => e.eventDate.isBefore(today))
            .toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
      }

      final postedUpcoming = posted
          .where((e) => !e.eventDate.isBefore(today))
          .toList()
        ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
      final postedPast = posted
          .where((e) => e.eventDate.isBefore(today))
          .toList()
        ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

      if (!mounted) return;
      setState(() {
        _upcoming = rsvpUpcoming;
        _past = rsvpPast;
        _postedUpcoming = postedUpcoming;
        _postedPast = postedPast;
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
      backgroundColor: context.palette.scaffoldBg,
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
    final isGoing = _tab == _MyEventsTab.going;
    final upcoming = isGoing ? _upcoming : _postedUpcoming;
    final past = isGoing ? _past : _postedPast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabSwitcher(
          active: _tab,
          goingCount: _upcoming.length + _past.length,
          postedCount: _postedUpcoming.length + _postedPast.length,
          onChanged: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 16),
        if (upcoming.isEmpty && past.isEmpty)
          EmptyStateCard(
            icon: Icons.event_outlined,
            title: isGoing ? 'No RSVPs yet' : 'No events posted yet',
            message: isGoing
                ? 'Browse the Events tab and tap "I\'m going" to start collecting RSVPs.'
                : 'Tap the + button on the Events tab to post your first event.',
            action: PrimaryGradientButton(
              label: isGoing ? 'Browse events' : 'Post an event',
              icon: isGoing ? Icons.search : Icons.add_circle_outline,
              onTap: () => context.goNamed(isGoing ? 'events' : 'post_event'),
            ),
          )
        else ...[
          if (upcoming.isNotEmpty) ...[
            _SectionLabel(label: 'UPCOMING', count: upcoming.length),
            const SizedBox(height: 10),
            for (final e in upcoming)
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
                  // Cancel button only on the Going tab — Posted
                  // tab uses the event detail screen's edit flow.
                  onCancel: isGoing ? () => _cancel(e) : null,
                ),
              ),
          ],
          if (past.isNotEmpty) ...[
            if (upcoming.isNotEmpty) const SizedBox(height: 12),
            _SectionLabel(label: 'PAST', count: past.length),
            const SizedBox(height: 10),
            for (final e in past)
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
      ],
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({
    required this.active,
    required this.goingCount,
    required this.postedCount,
    required this.onChanged,
  });

  final _MyEventsTab active;
  final int goingCount;
  final int postedCount;
  final ValueChanged<_MyEventsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _TabPill(
            label: 'Going',
            count: goingCount,
            selected: active == _MyEventsTab.going,
            onTap: () => onChanged(_MyEventsTab.going),
          ),
          _TabPill(
            label: 'Posted',
            count: postedCount,
            selected: active == _MyEventsTab.posted,
            onTap: () => onChanged(_MyEventsTab.posted),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: selected ? AppColors.primaryGradient : null,
              color: selected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color:
                            AppColors.primaryBlue.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: selected ? AppColors.white : AppColors.textDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.white.withValues(alpha: 0.22)
                          : const Color.fromRGBO(26, 26, 46, 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: selected
                            ? AppColors.white
                            : const Color.fromRGBO(26, 26, 46, 0.65),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
                      ? context.palette.cardMuted
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
