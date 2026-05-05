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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCover(),
                _buildBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CoverImage(url: event.coverPhotoUrl),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: _DateBadge(date: event.eventDate),
          ),
          if (isGoing)
            Positioned(
              top: 12,
              right: 12,
              child: _GoingPill(),
            ),
          if (event.isFull && !isGoing)
            Positioned(
              top: 12,
              right: 12,
              child: _FullPill(),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            text:
                '${_weekdays[event.eventDate.weekday - 1]}, ${event.eventDate.day} ${_months[event.eventDate.month - 1].toLowerCase()[0].toUpperCase()}${_months[event.eventDate.month - 1].toLowerCase().substring(1)}  •  ${_formatTime(event.eventTime)}',
          ),
          if (event.location != null && event.location!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.place_outlined,
              text: event.location!,
            ),
          ],
          const SizedBox(height: 12),
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
                  fontWeight: FontWeight.w700,
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
              const Spacer(),
              const Icon(
                Icons.arrow_forward,
                size: 16,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }

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

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            EventCard._months[date.month - 1],
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryBlue,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            date.day.toString(),
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.darkNavy,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoingPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.successGreen,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.successGreen.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
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

class _FullPill extends StatelessWidget {
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
        Icon(
          icon,
          size: 14,
          color: const Color.fromRGBO(26, 26, 46, 0.55),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.7),
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: Center(
          child: Icon(
            Icons.event,
            color: AppColors.white.withValues(alpha: 0.45),
            size: 48,
          ),
        ),
      );
    }
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: AppColors.white.withValues(alpha: 0.45),
            size: 40,
          ),
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: AppColors.lightGrey,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}
