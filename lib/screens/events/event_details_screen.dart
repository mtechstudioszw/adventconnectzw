import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class EventDetailsScreen extends StatefulWidget {
  const EventDetailsScreen({
    super.key,
    required this.eventId,
    this.initialEvent,
  });

  final String eventId;
  final Event? initialEvent;

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  Event? _event;
  bool _loading = true;
  bool _isRsvped = false;
  bool _rsvpBusy = false;
  String? _error;
  Timer? _ticker;
  Duration _timeRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _loading = widget.initialEvent == null;
    _updateTimeRemaining();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_updateTimeRemaining);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _updateTimeRemaining() {
    final event = _event;
    if (event == null) return;
    final diff = event.startsAt.difference(DateTime.now());
    _timeRemaining = diff.isNegative ? Duration.zero : diff;
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        EventService.fetchEventById(widget.eventId),
        EventService.isRsvped(widget.eventId),
      ]);
      if (!mounted) return;
      setState(() {
        _event = (results[0] as Event?) ?? _event;
        _isRsvped = results[1] as bool;
        _loading = false;
        _updateTimeRemaining();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load event details.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleRsvp() async {
    final event = _event;
    if (event == null) return;

    setState(() => _rsvpBusy = true);
    try {
      if (_isRsvped) {
        await EventService.cancelRsvp(event.id);
        if (!mounted) return;
        setState(() {
          _isRsvped = false;
          _event = event.copyWith(
            rsvpCount: (event.rsvpCount - 1).clamp(0, 1 << 31),
          );
        });
      } else {
        await EventService.rsvpToEvent(event.id);
        if (!mounted) return;
        setState(() {
          _isRsvped = true;
          _event = event.copyWith(rsvpCount: event.rsvpCount + 1);
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update RSVP. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _rsvpBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _event == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null && _event == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.red),
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _bootstrap();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final event = _event!;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(event)),
        SliverToBoxAdapter(child: _buildHeader(event)),
        SliverToBoxAdapter(child: _buildCountdown(event)),
        SliverToBoxAdapter(child: _buildRsvpButton(event)),
        SliverToBoxAdapter(child: _buildAbout(event)),
        SliverToBoxAdapter(child: _buildLocation(event)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildHero(Event event) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: event.coverPhotoUrl == null || event.coverPhotoUrl!.isEmpty
              ? Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.appBarGradient,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.event,
                      size: 96,
                      color: AppColors.white,
                    ),
                  ),
                )
              : Image.network(
                  event.coverPhotoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.lightGrey,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      size: 64,
                      color: Color.fromRGBO(26, 26, 46, 0.3),
                    ),
                  ),
                ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            color: const Color.fromRGBO(0, 0, 0, 0.4),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.canPop()
                  ? context.pop()
                  : context.goNamed('events'),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back,
                    color: AppColors.white, size: 22),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(Event event) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: AppTextStyles.displayMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                _formatFullDate(event.eventDate),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.access_time,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                _formatTime(event.eventTime),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.people_outline,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                event.capacity != null
                    ? '${event.rsvpCount} / ${event.capacity} attendees'
                    : '${event.rsvpCount} attendees',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountdown(Event event) {
    final isPast = event.isPast;
    final remaining = _timeRemaining;

    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                isPast ? 'Event has ended' : 'Starts in',
                style: AppTextStyles.titleMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.6),
                ),
              ),
              const SizedBox(height: 12),
              if (isPast)
                Text(
                  _formatPastAgo(event.startsAt),
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: AppColors.textDark,
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CountdownUnit(value: days, label: 'days'),
                    _CountdownUnit(value: hours, label: 'hrs'),
                    _CountdownUnit(value: minutes, label: 'min'),
                    _CountdownUnit(value: seconds, label: 'sec'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRsvpButton(Event event) {
    final isPast = event.isPast;
    final isFull = event.isFull && !_isRsvped;

    String label;
    VoidCallback? onTap;
    bool isPrimary;

    if (isPast) {
      label = 'Event has ended';
      onTap = null;
      isPrimary = false;
    } else if (_isRsvped) {
      label = 'Cancel RSVP';
      onTap = _rsvpBusy ? null : _toggleRsvp;
      isPrimary = false;
    } else if (isFull) {
      label = 'Event Full';
      onTap = null;
      isPrimary = false;
    } else {
      label = 'RSVP';
      onTap = _rsvpBusy ? null : _toggleRsvp;
      isPrimary = true;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: SizedBox(
        width: double.infinity,
        child: isPrimary
            ? _PrimaryButton(label: label, busy: _rsvpBusy, onTap: onTap)
            : _SecondaryButton(label: label, busy: _rsvpBusy, onTap: onTap),
      ),
    );
  }

  Widget _buildAbout(Event event) {
    if (event.description == null || event.description!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About this event', style: AppTextStyles.titleLarge),
              const SizedBox(height: 8),
              Text(
                event.description!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.8),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocation(Event event) {
    if (event.location == null || event.location!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  border: Border(
                    bottom: BorderSide(
                      color: const Color.fromRGBO(26, 26, 46, 0.08),
                    ),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _MapGridPainter(),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.place,
                          color: AppColors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 8,
                      right: 8,
                      child: _MapPlaceholderBadge(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Location', style: AppTextStyles.titleLarge),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.location!,
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFullDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
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

  String _formatPastAgo(DateTime then) {
    final diff = DateTime.now().difference(then);
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    return '${diff.inMinutes} minute${diff.inMinutes != 1 ? 's' : ''} ago';
  }
}

class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: const Color.fromRGBO(26, 26, 46, 0.6),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(label, style: AppTextStyles.buttonText),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: onTap == null
              ? const Color.fromRGBO(26, 26, 46, 0.2)
              : const Color.fromRGBO(26, 26, 46, 0.4),
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.textDark,
              ),
            )
          : Text(
              label,
              style: AppTextStyles.titleMedium.copyWith(
                color: onTap == null
                    ? const Color.fromRGBO(26, 26, 46, 0.5)
                    : AppColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class _MapPlaceholderBadge extends StatelessWidget {
  const _MapPlaceholderBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Map preview',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromRGBO(21, 101, 192, 0.08)
      ..strokeWidth = 1;

    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
