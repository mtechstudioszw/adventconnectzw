import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'cached_image.dart';
import 'motion/pressable.dart';

/// Large hero-style event card used in the Events tab.
///
/// Layout: full-width cover image (16:9) with a date pill in the top
/// corner, followed by a tall info block with title, schedule, location
/// and an attendance footer. Designed to feel closer to Facebook /
/// Eventbrite cards than the previous compact row.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.isGoing,
    required this.onTap,
  });

  final Event event;
  final bool isGoing;
  final VoidCallback onTap;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CoverHero(
                  url: event.coverPhotoUrl,
                  date: event.eventDate,
                  isGoing: isGoing,
                  isFull: event.isFull,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(
                        icon: event.isPast ? Icons.event_busy : Icons.schedule,
                        // Past events get an "ENDED" prefix instead of the
                        // future start time so the card doesn't look like a
                        // live upcoming event when it isn't.
                        text: event.isPast
                            ? 'Ended  ·  ${_weekdays[event.eventDate.weekday - 1]} ${event.eventDate.day} ${_titleCase(_months[event.eventDate.month - 1])}'
                            : '${_weekdays[event.eventDate.weekday - 1]} ${event.eventDate.day} ${_titleCase(_months[event.eventDate.month - 1])}  ·  ${_formatTime(event.eventTime)}',
                      ),
                      if (event.location != null &&
                          event.location!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _InfoRow(
                          icon: Icons.place_outlined,
                          text: event.location!,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(height: 1, color: AppColors.divider),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.people_outline,
                            size: 16,
                            color: AppColors.primaryBlue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${event.rsvpCount}',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            event.capacity != null
                                ? ' / ${event.capacity} going'
                                : ' going',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'View',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primaryBlue,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _titleCase(String upper) =>
      upper.substring(0, 1) + upper.substring(1).toLowerCase();

  String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return time;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}

class _CoverHero extends StatelessWidget {
  const _CoverHero({
    required this.url,
    required this.date,
    required this.isGoing,
    required this.isFull,
  });

  final String? url;
  final DateTime date;
  final bool isGoing;
  final bool isFull;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null || url!.isEmpty)
            Container(
              decoration: const BoxDecoration(
                gradient: AppColors.appBarGradient,
              ),
              child: Center(
                child: Icon(
                  Icons.event,
                  color: AppColors.white.withValues(alpha: 0.55),
                  size: 42,
                ),
              ),
            )
          else
            CachedImage(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: context.palette.cardMuted,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textMuted,
                    size: 36,
                  ),
                ),
              ),
            ),
          // Soft gradient at the bottom so the date pill / chips read
          // cleanly over busy photos.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.30),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(top: 12, left: 12, child: _DateBadge(date: date)),
          if (isGoing || isFull)
            Positioned(
              top: 12,
              right: 12,
              child: isGoing ? const _GoingChip() : const _FullChip(),
            ),
        ],
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            EventCard._months[date.month - 1],
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1.1,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${date.day}',
            style: AppTextStyles.titleLarge.copyWith(
              color: context.palette.text,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoingChip extends StatelessWidget {
  const _GoingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.successGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            'GOING',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullChip extends StatelessWidget {
  const _FullChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'FULL',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
