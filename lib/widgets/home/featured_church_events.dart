import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/event_model.dart';
import '../../services/cache_service.dart';
import '../../services/event_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';

/// Big, prominent strip of CHURCH-posted events at the top of Home. Official
/// church events stand out from regular community events with the church's
/// name + a gold verified tick. Renders nothing when there are none.
class FeaturedChurchEvents extends StatefulWidget {
  const FeaturedChurchEvents({super.key, this.refreshTick = 0});

  /// Bump to refetch. Home is a kept-alive tab now (Batch 2), so `initState`
  /// runs once a session: without this a church event posted after launch
  /// never appeared, and pull-to-refresh skipped this strip entirely.
  final int refreshTick;

  @override
  State<FeaturedChurchEvents> createState() => _FeaturedChurchEventsState();
}

class _FeaturedChurchEventsState extends State<FeaturedChurchEvents> {
  /// User-scoped (no `pref:`), so sign-out clears it with the rest of Home.
  static const _cacheKey = 'home_featured_church_events';

  List<Event> _events = const [];

  @override
  void initState() {
    super.initState();
    // Paint the last good list first, so the strip is there on the first
    // frame — offline included — instead of dropping in under the
    // member's thumb a second later.
    _events = _upcoming(_readCache());
    _load();
  }

  @override
  void didUpdateWidget(FeaturedChurchEvents old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  Future<void> _load() async {
    try {
      final fresh = await EventService.fetchFeaturedChurchEvents();
      if (!mounted) return;
      setState(() => _events = fresh);
      await CacheService.writeString(
        _cacheKey,
        jsonEncode([for (final e in fresh) e.toJson()]),
      );
    } catch (_) {
      // Offline or the query failed: keep whatever is already showing.
    }
  }

  static List<Event> _readCache() {
    try {
      final raw = CacheService.readString(_cacheKey);
      if (raw == null) return const [];
      return [
        for (final e in jsonDecode(raw) as List)
          Event.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// A cache can be up to a day old, so drop anything that has already
  /// passed rather than feature yesterday's service as upcoming.
  static List<Event> _upcoming(List<Event> events) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (final e in events)
        if (!e.eventDate.isBefore(today)) e,
    ];
  }

  static const _months = [
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

  String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final events = _events;
    if (events.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              const Icon(Icons.verified, color: AppColors.goldAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                'CHURCH EVENTS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 188,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                _Card(event: events[i], dateLabel: _date(events[i].eventDate)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Small round church logo for the featured card. Falls back to a church
/// glyph until an admin uploads the church's photo.
class _ChurchLogo extends StatelessWidget {
  const _ChurchLogo({this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: 20,
      height: 20,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: hasPhoto
          ? CachedImage(photoUrl!, fit: BoxFit.cover, width: 20, height: 20)
          : const Icon(Icons.church, color: AppColors.white, size: 12),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.event, required this.dateLabel});
  final Event event;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasCover = (event.coverPhotoUrl ?? '').isNotEmpty;
    return SizedBox(
      width: 300,
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(
            'event_details',
            pathParameters: {'id': event.id},
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover (or gradient fallback) with date chip.
              SizedBox(
                height: 110,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasCover)
                      CachedImage(event.coverPhotoUrl!, fit: BoxFit.cover)
                    else
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.appBarGradient,
                        ),
                      ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.darkNavy.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          dateLabel,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Church logo (once uploaded) + name + gold tick (official).
                    Row(
                      children: [
                        _ChurchLogo(photoUrl: event.churchPhotoUrl),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            (event.churchName ?? 'Church').trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          color: AppColors.goldAccent,
                          size: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if ((event.location ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: palette.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              event.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
