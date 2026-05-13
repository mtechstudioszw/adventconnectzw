import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CompactThumbnail(
                url: event.coverPhotoUrl,
                date: event.eventDate,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (isGoing) ...[
                          const SizedBox(width: 6),
                          const _GoingChip(),
                        ] else if (event.isFull) ...[
                          const SizedBox(width: 6),
                          const _FullChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.schedule,
                      text:
                          '${_weekdays[event.eventDate.weekday - 1]} ${event.eventDate.day} ${_titleCase(_months[event.eventDate.month - 1])} • ${_formatTime(event.eventTime)}',
                    ),
                    if (event.location != null && event.location!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _InfoRow(
                        icon: Icons.place_outlined,
                        text: event.location!,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 13,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${event.rsvpCount}',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          event.capacity != null
                              ? ' / ${event.capacity} going'
                              : ' going',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color.fromRGBO(26, 26, 46, 0.6),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color.fromRGBO(26, 26, 46, 0.3),
              ),
            ],
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

/// Square thumbnail with a small date badge in the corner. Replaces the
/// full-width 16:9 cover hero — cuts each card from ~320 to ~120 tall.
class _CompactThumbnail extends StatelessWidget {
  const _CompactThumbnail({required this.url, required this.date});

  final String? url;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
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
                    size: 28,
                  ),
                ),
              )
            else
              Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.lightGrey,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Color.fromRGBO(26, 26, 46, 0.3),
                    size: 28,
                  ),
                ),
              ),
            // Bottom-left date pill so the day is glanceable without
            // having to read the body row.
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${date.day}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.darkNavy,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      EventCard._months[date.month - 1],
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 9,
                        letterSpacing: 0.6,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoingChip extends StatelessWidget {
  const _GoingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.successGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'GOING',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _FullChip extends StatelessWidget {
  const _FullChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'FULL',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
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
        Icon(
          icon,
          size: 12,
          color: const Color.fromRGBO(26, 26, 46, 0.55),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.7),
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}
