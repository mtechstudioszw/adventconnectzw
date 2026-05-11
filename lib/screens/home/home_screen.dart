import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/church_model.dart';
import '../../models/event_model.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../services/event_service.dart';
import '../../services/notification_service.dart';
import '../../services/urgent_banner_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../widgets/main_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Event> _events = [];
  List<Church> _churches = [];
  Set<String> _followedChurchIds = <String>{};
  Set<String> _rsvpedEventIds = <String>{};
  int _unreadNotifications = 0;
  UrgentBanner? _banner;
  // Banners dismissed in this session — kept in memory only so the
  // user sees fresh banners on relaunch but isn't pestered after they
  // already swiped one away.
  final Set<String> _dismissedBannerIds = <String>{};
  bool _loading = true;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    // Rebuild whenever the user's profile metadata changes (e.g. after a
    // save in Edit Profile) so the greeting / welcome card refresh without
    // requiring the user to relaunch the app.
    _authSub = AuthService.authStateChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        EventService.fetchEvents(upcomingOnly: true),
        ChurchService.fetchChurches(),
        ChurchService.fetchUserFollowedChurchIds(),
        EventService.fetchUserRsvpedEventIds(),
        NotificationService.unreadCount(),
        UrgentBannerService.fetchActive(),
      ]);
      if (!mounted) return;
      setState(() {
        _events = (results[0] as List<Event>).take(8).toList();
        _churches = (results[1] as List<Church>).take(6).toList();
        _followedChurchIds = results[2] as Set<String>;
        _rsvpedEventIds = results[3] as Set<String>;
        _unreadNotifications = results[4] as int;
        _banner = results[5] as UrgentBanner?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }

  String _firstName() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['full_name'] as String?)?.trim() ?? '';
    if (raw.isEmpty) {
      final email = user?.email ?? '';
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : 'Friend';
    }
    return raw.split(' ').first;
  }

  String _initials() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['full_name'] as String?)?.trim() ?? '';
    if (raw.isEmpty) return (user?.email ?? '?').substring(0, 1).toUpperCase();
    final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _bootstrap,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _slide.value),
                child: child,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                if (_banner != null &&
                    !_dismissedBannerIds.contains(_banner!.id)) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _UrgentBannerCard(
                      banner: _banner!,
                      onDismiss: () => setState(
                        () => _dismissedBannerIds.add(_banner!.id),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _buildSectionHeader('Quick stats', null),
                const SizedBox(height: 12),
                _buildQuickStats(),
                const SizedBox(height: 28),
                _buildSectionHeader(
                  'Upcoming events',
                  _events.isEmpty ? null : 'See all',
                  onAction: () => context.goNamed('events'),
                ),
                const SizedBox(height: 12),
                _buildEventsRow(),
                const SizedBox(height: 28),
                _buildSectionHeader('Active prayers', null),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _PrayersEmpty(
                    onTap: () => context.pushNamed('prayer'),
                  ),
                ),
                const SizedBox(height: 28),
                _buildSectionHeader(
                  'Discover churches',
                  _churches.isEmpty ? null : 'See all',
                  onAction: () => context.goNamed('churches'),
                ),
                const SizedBox(height: 12),
                _buildChurchGrid(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const MainBottomNav(currentIndex: 0),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 240,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipPath(
            clipper: _HeaderClipper(),
            child: Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: AppColors.appBarGradient,
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.6, -0.8),
                            radius: 1.0,
                            colors: [
                              AppColors.white.withValues(alpha: 0.07),
                              AppColors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _greeting().toUpperCase(),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.white
                                        .withValues(alpha: 0.65),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hello, ${_firstName()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.headlineLarge.copyWith(
                                    color: AppColors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _NotificationBell(
                            unread: _unreadNotifications,
                            onTap: () async {
                              await context.pushNamed('notification_centre');
                              if (mounted) _bootstrap();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: _WelcomeCard(
              initials: _initials(),
              fullName: _displayFullName(),
              followedCount: _followedChurchIds.length,
            ),
          ),
        ],
      ),
    );
  }

  String _displayFullName() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['full_name'] as String?)?.trim() ?? '';
    if (raw.isNotEmpty) return raw;
    return user?.email ?? 'Welcome';
  }

  Widget _buildSectionHeader(
    String title,
    String? action, {
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.headlineMedium.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final upcomingForUser = _events
        .where((e) => _rsvpedEventIds.contains(e.id))
        .length;
    return SizedBox(
      height: 124,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _StatCard(
            icon: Icons.church_outlined,
            label: 'Churches you follow',
            value: '${_followedChurchIds.length}',
            tint: const Color(0xFF1565C0),
          ),
          const SizedBox(width: 12),
          _StatCard(
            icon: Icons.event_available_outlined,
            label: 'Events going to',
            value: '$upcomingForUser',
            tint: const Color(0xFF0D47A1),
          ),
          const SizedBox(width: 12),
          _StatCard(
            icon: Icons.volunteer_activism_outlined,
            label: 'Prayer requests',
            value: '0',
            tint: const Color(0xFF1976D2),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsRow() {
    if (_loading && _events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _EmptyTile(
          icon: Icons.event_outlined,
          title: 'No upcoming events',
          subtitle: 'Check back soon — events post all week.',
        ),
      );
    }
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _events.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final e = _events[i];
          return _HomeEventCard(
            event: e,
            isGoing: _rsvpedEventIds.contains(e.id),
            onTap: () async {
              await context.pushNamed(
                'event_details',
                pathParameters: {'id': e.id},
                extra: e,
              );
              if (mounted) _bootstrap();
            },
          );
        },
      ),
    );
  }

  Widget _buildChurchGrid() {
    if (_loading && _churches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_churches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _EmptyTile(
          icon: Icons.church_outlined,
          title: 'No churches yet',
          subtitle: 'Once churches are added they\'ll show here.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _churches.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (context, i) {
          final c = _churches[i];
          return _HomeChurchTile(
            church: c,
            isFollowed: _followedChurchIds.contains(c.id),
            onTap: () async {
              await context.pushNamed(
                'church_details',
                pathParameters: {'id': c.id},
                extra: c,
              );
              if (mounted) _bootstrap();
            },
          );
        },
      ),
    );
  }
}

class _HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 24);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 24,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _UrgentBannerCard extends StatelessWidget {
  const _UrgentBannerCard({required this.banner, required this.onDismiss});

  final UrgentBanner banner;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        banner.title,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: AppColors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (banner.conference?.isNotEmpty == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          banner.conference!.toUpperCase(),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  banner.body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.85),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.red.withValues(alpha: 0.7),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.10),
                ),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.white,
                size: 22,
              ),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.darkNavy, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.initials,
    required this.fullName,
    required this.followedCount,
  });

  final String initials;
  final String fullName;
  final int followedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              initials,
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.church_outlined,
                      size: 14,
                      color: Color.fromRGBO(26, 26, 46, 0.6),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        followedCount == 0
                            ? 'No church set yet'
                            : '$followedCount church${followedCount == 1 ? '' : 'es'} followed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.65),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Color.fromRGBO(26, 26, 46, 0.4),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tint, Color.lerp(tint, Colors.black, 0.18)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.white, size: 18),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTextStyles.displayLarge.copyWith(
              color: AppColors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeEventCard extends StatelessWidget {
  const _HomeEventCard({
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Material(
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
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 11,
                        child: _CoverImage(
                          url: event.coverPhotoUrl,
                          fallbackIcon: Icons.event,
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
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                                stops: const [0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _months[event.eventDate.month - 1],
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                event.eventDate.day.toString(),
                                style: AppTextStyles.headlineMedium.copyWith(
                                  color: AppColors.darkNavy,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isGoing)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'GOING',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 12,
                              color: Color.fromRGBO(26, 26, 46, 0.6),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                (event.location ?? '').isEmpty
                                    ? 'Location TBA'
                                    : event.location!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: const Color.fromRGBO(26, 26, 46, 0.6),
                                  fontSize: 11.5,
                                ),
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
          ),
        ),
      ),
    );
  }
}

class _HomeChurchTile extends StatelessWidget {
  const _HomeChurchTile({
    required this.church,
    required this.isFollowed,
    required this.onTap,
  });

  final Church church;
  final bool isFollowed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CoverImage(
                  url: church.coverPhotoUrl,
                  fallbackIcon: Icons.church,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                if (church.isVerified)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.darkNavy.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified,
                        size: 14,
                        color: AppColors.goldAccent,
                      ),
                    ),
                  ),
                if (isFollowed)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'FOLLOWING',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        church.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 11,
                            color: Color.fromRGBO(255, 255, 255, 0.85),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              church.city.isEmpty
                                  ? 'Zimbabwe'
                                  : church.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: const Color.fromRGBO(
                                    255, 255, 255, 0.85),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
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
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({this.url, required this.fallbackIcon});

  final String? url;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: Center(
          child: Icon(
            fallbackIcon,
            color: AppColors.white.withValues(alpha: 0.55),
            size: 42,
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
            fallbackIcon,
            color: AppColors.white.withValues(alpha: 0.55),
            size: 42,
          ),
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: AppColors.lightGrey,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}

class _PrayersEmpty extends StatelessWidget {
  const _PrayersEmpty({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
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
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.volunteer_activism_outlined,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Be the first to share a prayer',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pray together with the community.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Open',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color.fromRGBO(26, 26, 46, 0.45),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
