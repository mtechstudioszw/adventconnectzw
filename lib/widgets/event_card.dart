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

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DateBadge(date: event.eventDate),
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
                            style: AppTextStyles.titleLarge,
                          ),
                        ),
                        if (isGoing) ...[
                          const SizedBox(width: 8),
                          _GoingBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 14,
                          color: Color.fromRGBO(26, 26, 46, 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(event.eventTime),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color.fromRGBO(26, 26, 46, 0.6),
                          ),
                        ),
                        if (event.location != null &&
                            event.location!.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.place_outlined,
                            size: 14,
                            color: Color.fromRGBO(26, 26, 46, 0.6),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              event.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: const Color.fromRGBO(26, 26, 46, 0.6),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 14,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${event.rsvpCount}',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          event.capacity != null
                              ? ' / ${event.capacity} going'
                              : ' going',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color.fromRGBO(26, 26, 46, 0.6),
                          ),
                        ),
                        if (event.isFull) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'FULL',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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

  String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return time;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour =
        hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final DateTime date;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 72,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _months[date.month - 1],
            style: AppTextStyles.overline.copyWith(
              color: AppColors.white,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            date.day.toString(),
            style: AppTextStyles.displayMedium.copyWith(
              color: AppColors.white,
              fontSize: 26,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.successGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.successGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle,
            size: 12,
            color: AppColors.successGreen,
          ),
          const SizedBox(width: 4),
          Text(
            'Going',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.successGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
