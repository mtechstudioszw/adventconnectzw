import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/business_application_model.dart';
import '../../services/account_service.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../services/event_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/invite_friends_card.dart';
import '../widgets/main_bottom_nav.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  int _churchesFollowed = 0;
  int _eventsGoing = 0;
  int _prayersPraying = 0;
  bool _loading = true;
  AccountState? _accountState;

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
    _bootstrap();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        ChurchService.fetchUserFollowedChurchIds(),
        EventService.fetchUserRsvpedEventIds(),
        AccountService.fetchMyAccount(),
      ]);
      if (!mounted) return;
      setState(() {
        _churchesFollowed = (results[0] as Set).length;
        _eventsGoing = (results[1] as Set).length;
        _prayersPraying = 0;
        _accountState = results[2] as AccountState?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openApplyBusiness() async {
    final result = await context.pushNamed<BusinessApplication>(
      'apply_business',
    );
    if (!mounted || result == null) return;
    // After a fresh application the latest row is `pending` — refresh
    // local state so the badge updates without a manual reload.
    setState(() {
      _accountState = AccountState(
        userId: _accountState?.userId ?? '',
        isBusiness: _accountState?.isBusiness ?? false,
        latestApplication: result,
      );
    });
  }

  String _displayName() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final name = (meta['full_name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return user?.email ?? 'Welcome';
  }

  String _initials() {
    final name = _displayName();
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _bio() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final bio = (meta['bio'] as String?)?.trim() ?? '';
    if (bio.isNotEmpty) return bio;
    return 'Add a bio to tell the community about yourself.';
  }

  String _email() {
    return AuthService.currentUser?.email ?? '';
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: AppTextStyles.headlineSmall),
        content: Text(
          'You\'ll need to sign in again to access the community.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textDark,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
            ),
            child: Text('Sign out', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.signOut();
    if (!mounted) return;
    context.goNamed('age_verification');
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
              children: [
                _buildHeader(),
                _buildIdentity(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildStats(),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildBioCard(),
                ),
                const SizedBox(height: 16),
                _buildAccountCard(),
                const SizedBox(height: 16),
                const InviteFriendsCard(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildActionButtons(),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildSettingsList(),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const MainBottomNav(currentIndex: 4),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 180,
            child: ClipPath(
              clipper: _CoverClipper(),
              child: Container(
                decoration:
                    const BoxDecoration(gradient: AppColors.appBarGradient),
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
                          children: [
                            Text(
                              'Profile',
                              style: AppTextStyles.appBarTitle.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            _CircleIconButton(
                              icon: Icons.settings_outlined,
                              onTap: () => context.pushNamed('settings'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 120,
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Text(
                  _initials(),
                  style: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 38,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentity() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Text(
            _displayName(),
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.email_outlined,
                size: 14,
                color: Color.fromRGBO(26, 26, 46, 0.55),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  _email(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
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
          _StatTile(
            value: _loading ? '…' : '$_churchesFollowed',
            label: 'Churches',
          ),
          _verticalDivider(),
          _StatTile(
            value: _loading ? '…' : '$_eventsGoing',
            label: 'Events',
          ),
          _verticalDivider(),
          _StatTile(
            value: _loading ? '…' : '$_prayersPraying',
            label: 'Prayers',
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 40,
      color: const Color.fromRGBO(26, 26, 46, 0.08),
    );
  }

  Widget _buildBioCard() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABOUT',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.5),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _bio(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    final state = _accountState;
    final isBusiness = state?.isBusiness ?? false;
    final latest = state?.latestApplication;
    final pending = latest != null && latest.isPending;
    final rejected = !isBusiness && latest != null && latest.isRejected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color.fromRGBO(26, 26, 46, 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isBusiness
                        ? AppColors.primaryGradient
                        : null,
                    color: isBusiness
                        ? null
                        : AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isBusiness ? Icons.business_center : Icons.person,
                    color: isBusiness
                        ? AppColors.white
                        : AppColors.primaryBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isBusiness
                                ? 'Business account'
                                : 'Personal account',
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          if (isBusiness) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: AppColors.goldAccent,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _accountSubtitle(isBusiness, pending, rejected),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.6),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isBusiness && !pending) ...[
              const SizedBox(height: 14),
              _ApplyBusinessButton(
                rejected: rejected,
                rejectionNote: rejected ? latest.reviewerNote : null,
                onTap: _openApplyBusiness,
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.goldAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.goldAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_empty_rounded,
                      color: AppColors.goldAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your business application is under review.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.goldAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _accountSubtitle(bool isBusiness, bool pending, bool rejected) {
    if (isBusiness) {
      return 'You can sell in the marketplace and claim a church listing.';
    }
    if (pending) {
      return 'We\'ll let you know in the app once your account is upgraded.';
    }
    if (rejected) {
      return 'Your last application was declined. You can re-apply below.';
    }
    return 'Upgrade to a business account to sell or claim a church.';
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _GradientButton(
            label: 'Edit profile',
            icon: Icons.edit_outlined,
            onTap: () async {
              await context.pushNamed('edit_profile');
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(width: 12),
        _IconButton(
          icon: Icons.share_outlined,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildSettingsList() {
    return Container(
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
      child: Column(
        children: [
          _SettingsRow(
            icon: Icons.church_outlined,
            label: 'My churches',
            onTap: () => context.pushNamed('churches'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.event_outlined,
            label: 'My events',
            onTap: () => context.pushNamed('my_events'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.volunteer_activism_outlined,
            label: 'My prayers',
            onTap: () => context.pushNamed('prayer'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.chat_bubble_outline,
            label: 'Advent Chat',
            onTap: () => context.pushNamed('messages'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.work_outline,
            label: 'Jobs',
            onTap: () => context.pushNamed('jobs'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.storefront_outlined,
            label: 'Marketplace',
            onTap: () => context.pushNamed('marketplace'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.store_mall_directory_outlined,
            label: 'My seller dashboard',
            onTap: () => context.pushNamed('seller_dashboard'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.favorite_outline,
            label: 'Saved listings',
            onTap: () => context.pushNamed('saved_listings'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.people_outline,
            label: 'Member directory',
            onTap: () => context.pushNamed('member_directory'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.brightness_3_outlined,
            label: 'Sabbath timer',
            onTap: () => context.pushNamed('sabbath_timer'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            onTap: () => context.pushNamed('notification_preferences'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.block_outlined,
            label: 'Blocked users',
            onTap: () => context.pushNamed('blocked_users'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Church admin',
            onTap: () => context.pushNamed('admin_login'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.shield_outlined,
            label: 'Privacy & security',
            onTap: () => context.pushNamed('settings'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.help_outline,
            label: 'Help & support',
            onTap: () => context.pushNamed('feedback'),
          ),
          const _Divider(),
          _SettingsRow(
            icon: Icons.logout,
            label: 'Sign out',
            destructive: true,
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}

class _CoverClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 28);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 28,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 22),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onTap,
    this.icon,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: AppColors.white, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 14,
                    letterSpacing: 0.4,
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

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 50,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.1),
            ),
          ),
          child: Icon(icon, color: AppColors.textDark, size: 20),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.textDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 18),
      child: Divider(
        height: 1,
        color: Color.fromRGBO(26, 26, 46, 0.06),
      ),
    );
  }
}

class _ApplyBusinessButton extends StatelessWidget {
  const _ApplyBusinessButton({
    required this.rejected,
    required this.rejectionNote,
    required this.onTap,
  });

  final bool rejected;
  final String? rejectionNote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rejected && (rejectionNote ?? "").isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
            ),
            child: Text(
              rejectionNote!,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                rejected ? "Re-apply for Business" : "Apply for Business",
                style: AppTextStyles.buttonText.copyWith(
                  color: AppColors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
