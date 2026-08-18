import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/share_config.dart';
import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/motion/brand_spinner.dart';

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

class _EventDetailsScreenState extends State<EventDetailsScreen>
    with SingleTickerProviderStateMixin {
  Event? _event;
  bool _loading = true;
  bool _isRsvped = false;
  bool _rsvpBusy = false;
  String? _error;
  Timer? _ticker;
  Duration _timeRemaining = Duration.zero;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    _loading = widget.initialEvent == null;
    _updateTimeRemaining();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(
      begin: 12,
      end: 0,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOut));

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_updateTimeRemaining);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  bool _isOrganizer(Event event) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return uid != null && event.organizerId == uid;
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
      // Pull the authoritative rsvp_count back from the server so the
      // optimistic +/- 1 above doesn't drift when the user enters
      // the screen with a stale cached count. Trigger updates the
      // count in the same transaction as the rsvp insert/delete, so
      // by the time this refetch resolves the row is correct.
      try {
        final fresh = await EventService.fetchEventById(event.id);
        if (!mounted || fresh == null) return;
        setState(() => _event = fresh);
      } catch (_) {
        // Best-effort — the optimistic count still stands if the
        // refetch hiccups.
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
      backgroundColor: Colors.transparent,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _event == null) {
      return const Center(child: BrandSpinner(size: 30));
    }
    if (_error != null && _event == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.red),
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
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                ),
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
        SliverToBoxAdapter(
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _slide.value),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMetaRow(event),
                  const SizedBox(height: 20),
                  _buildCountdown(event),
                  const SizedBox(height: 16),
                  _buildRsvpButton(event),
                  const SizedBox(height: 24),
                  _buildOrganizer(event),
                  _buildContactActions(event),
                  const SizedBox(height: 16),
                  _buildAbout(event),
                  if (event.location != null && event.location!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildLocation(event),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero(Event event) {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 260,
          // Receiving end of the Hero on Home's event cards — the cover
          // expands into this screen rather than the page swapping under it.
          child: Hero(
            tag: 'event_cover_${event.id}',
            child: _CoverImage(url: event.coverPhotoUrl),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back,
                  onTap: () => context.canPop()
                      ? context.pop()
                      // Events is no longer a tab; fall back to Home (which
                      // carries the bottom nav) when there's nothing to pop.
                      : context.goNamed('home'),
                ),
                const Spacer(),
                if (_isOrganizer(event)) ...[
                  _CircleIconButton(
                    icon: Icons.edit_outlined,
                    onTap: () async {
                      final updated = await context.pushNamed<bool>(
                        'edit_event',
                        extra: event,
                      );
                      if (updated == true) _bootstrap();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                _CircleIconButton(
                  icon: Icons.share_outlined,
                  onTap: () => _shareEvent(event),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatChip(event.eventDate, event.eventTime),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                event.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.displayMedium.copyWith(
                  color: AppColors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetaRow(Event event) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _MetaTile(
            icon: Icons.calendar_today_outlined,
            label: event.endDate != null && event.endDate != event.eventDate
                ? 'Dates'
                : 'Date',
            value: event.endDate != null && event.endDate != event.eventDate
                ? '${_formatShortDate(event.eventDate)} → ${_formatShortDate(event.endDate!)}'
                : _formatShortDate(event.eventDate),
          ),
          _verticalDivider(),
          _MetaTile(
            icon: Icons.access_time,
            label: event.endTime != null ? 'Time' : 'Starts',
            value: event.endTime != null
                ? '${_formatTime(event.eventTime)} – ${_formatTime(event.endTime!)}'
                : _formatTime(event.eventTime),
          ),
          _verticalDivider(),
          _MetaTile(
            icon: Icons.people_outline,
            label: 'Going',
            value: event.capacity != null
                ? '${event.rsvpCount}/${event.capacity}'
                : '${event.rsvpCount}',
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(width: 1, height: 36, color: context.palette.divider);
  }

  Widget _buildCountdown(Event event) {
    final isPast = event.isPast;
    final remaining = _timeRemaining;
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final seconds = remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            isPast ? 'EVENT HAS ENDED' : 'STARTS IN',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.7),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 14),
          if (isPast)
            Text(
              _formatPastAgo(event.startsAt),
              style: AppTextStyles.headlineMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
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
      label = 'RSVP for this event';
      onTap = _rsvpBusy ? null : _toggleRsvp;
      isPrimary = true;
    }

    return SizedBox(
      width: double.infinity,
      child: isPrimary
          ? _PrimaryButton(label: label, busy: _rsvpBusy, onTap: onTap)
          : _SecondaryButton(label: label, busy: _rsvpBusy, onTap: onTap),
    );
  }

  Widget _buildOrganizer(Event event) {
    // Tappable to contact the organizer — unless the event is the
    // viewer's own, or there's no organizer user id to message (some
    // events only carry a contact name/phone, not a profile).
    final canContact =
        (event.organizerId ?? '').isNotEmpty && !_isOrganizer(event);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canContact ? () => _messageOrganizer(event) : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.campaign_outlined,
                  color: AppColors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ORGANIZED BY',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _organizerLabel(event),
                      style: AppTextStyles.titleMedium.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (canContact) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Tap to message',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.primaryBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                canContact ? Icons.chat_bubble_outline : Icons.chevron_right,
                color: canContact
                    ? AppColors.primaryBlue
                    : context.palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// WhatsApp + Call actions, shown beneath the organizer card when
  /// the event row carries a contact_phone. Mirrors the jobs detail
  /// screen pattern so users can always reach the poster outside
  /// the in-app chat.
  Widget _buildContactActions(Event event) {
    final phone = (event.contactPhone ?? '').trim();
    if (phone.isEmpty || _isOrganizer(event)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: _ContactActionButton(
              icon: Icons.chat,
              label: 'WhatsApp',
              tint: const Color(0xFF25D366),
              onTap: () => _openWhatsApp(phone, event),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ContactActionButton(
              icon: Icons.call,
              label: 'Call',
              tint: AppColors.primaryBlue,
              onTap: () => _placeCall(phone),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWhatsApp(String phone, Event event) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final text = Uri.encodeComponent(
      'Hi, I saw your event on Adventist Super App: ${event.title}',
    );
    final url = Uri.parse('https://wa.me/$cleaned?text=$text');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open WhatsApp.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _placeCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final url = Uri.parse('tel:$cleaned');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not start the call.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _shareEvent(Event event) async {
    // Share the event-share Edge Function URL (not the generic landing
    // page) so WhatsApp/Facebook render a rich preview with the event
    // flyer as og:image. The function deep-links back into the app and
    // falls back to a download CTA.
    final shareUrl = eventShareUrl(event.id);
    final text =
        '${event.title}\n\n'
        'Join me at this event on Adventist Super App:\n$shareUrl';
    await Share.share(text, subject: event.title);
  }

  Future<void> _messageOrganizer(Event event) async {
    final organizerId = event.organizerId;
    if (organizerId == null || organizerId.isEmpty) return;
    try {
      // createConversation resolves the organizer's real profile name,
      // so even events that only stored a contact_name open a chat
      // with the actual person.
      final convo = await MessagingService.createConversation(
        otherUserId: organizerId,
        otherUserName: _organizerLabel(event),
        source: 'direct',
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      context.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not open chat. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Widget _buildAbout(Event event) {
    if (event.description == null || event.description!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About this event',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            event.description!,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.text,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  String _organizerLabel(Event event) {
    // Church-hosted events (posted from the admin dashboard) are credited to
    // the local church, never the individual admin. Personal events keep the
    // organizer's own name.
    if (event.isChurchEvent) {
      final church = event.churchName?.trim();
      if (church != null && church.isNotEmpty) return church;
      return 'Affiliated SDA church';
    }
    final name = event.organizerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Adventist Super App';
  }

  Future<void> _openMap(Event event) async {
    final location = (event.location ?? '').trim();
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No location set for this event.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    // Google Maps universal search URL — works on iOS/Android web view
    // and the native Maps app via deep-link handling.
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(location)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch returned false');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open maps.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Widget _buildLocation(Event event) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openMap(event),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: context.palette.cardMuted,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(painter: _MapGridPainter()),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.place,
                            color: AppColors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(0, 0, 0, 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Tap to open in Maps',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location',
                    style: AppTextStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                          event.location ?? '',
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

  String _formatChip(DateTime date, String time) {
    const months = [
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
    return '${months[date.month - 1]} ${date.day}  •  ${_formatTime(time)}';
  }

  String _formatShortDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]}';
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

  String _formatPastAgo(DateTime then) {
    final diff = DateTime.now().difference(then);
    if (diff.inDays >= 1)
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    if (diff.inHours >= 1)
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    return '${diff.inMinutes} minute${diff.inMinutes != 1 ? 's' : ''} ago';
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryBlue),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.18)),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label.toUpperCase(),
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.white.withValues(alpha: 0.65),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
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
      opacity: onTap == null && !busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          letterSpacing: 0.4,
                        ),
                      ),
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
              ? context.palette.divider
              : context.palette.textMuted,
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: context.palette.text,
              ),
            )
          : Text(
              label,
              style: AppTextStyles.titleMedium.copyWith(
                color: onTap == null
                    ? context.palette.textMuted
                    : context.palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 0, 0, 0.35),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      ),
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
            color: AppColors.white.withValues(alpha: 0.55),
            size: 80,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => FullImageViewer.show(context, url),
      child: CachedImage(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppColors.white.withValues(alpha: 0.55),
              size: 56,
            ),
          ),
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

class _ContactActionButton extends StatelessWidget {
  const _ContactActionButton({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tint.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: tint, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
