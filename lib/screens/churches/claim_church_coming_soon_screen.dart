import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/church_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Replaces the live church-admin claim flow with a "Coming Soon"
/// landing + sponsorship pitch while the full Church Admin Dashboard
/// (members, tithes, events, announcements) is still in development.
///
/// Drives an EcoCash donate-to-fund-development CTA so churches that
/// want the feature shipped sooner have a concrete way to support
/// the build instead of waiting silently.
class ClaimChurchComingSoonScreen extends StatelessWidget {
  const ClaimChurchComingSoonScreen({super.key, required this.church});

  final Church church;

  static const _ecoCashNumber = '0778 092 494';
  static const _ecoCashName = 'Advent Connect ZW';
  static const _supportWhatsApp = '+263778092494';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHero(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPitchCard(context),
                  const SizedBox(height: 18),
                  _buildFeaturePreview(context),
                  const SizedBox(height: 18),
                  _buildSponsorCta(context),
                  const SizedBox(height: 14),
                  _buildContactCta(context),
                  const SizedBox(height: 22),
                  Center(
                    child: Text(
                      'You\'re viewing: ${church.name}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.45),
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.canPop()
                        ? context.pop()
                        : context.goNamed('churches'),
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
                        Icons.arrow_back,
                        color: AppColors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.goldAccent.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: AppColors.goldAccent, width: 1),
                        ),
                        child: Text(
                          'COMING SOON',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.goldAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Church Admin\nDashboard',
                    style: AppTextStyles.displayMedium.copyWith(
                      color: AppColors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'A full toolkit to run your local church from inside Advent Connect ZW.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.white.withValues(alpha: 0.78),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPitchCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: AppColors.goldAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Built for elders, youth leaders, and pastors',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'When ${church.name} is ready, your appointed admin will be '
            'able to manage members, post announcements, schedule '
            'events, track Sabbath attendance, coordinate Sabbath '
            'school classes, and accept tithes & offerings — all from '
            'one place inside the app. No more scattered WhatsApp '
            'groups, no more lost contact lists.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.78),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePreview(BuildContext context) {
    final features = const [
      _Feature(
        icon: Icons.people_alt_outlined,
        title: 'Member directory',
        body: 'Verified roster of your local church, with roles + contacts.',
      ),
      _Feature(
        icon: Icons.campaign_outlined,
        title: 'Announcements',
        body: 'Push Sabbath announcements straight to every member\'s phone.',
      ),
      _Feature(
        icon: Icons.event_outlined,
        title: 'Events scheduling',
        body: 'Plan camp meetings, week-of-prayer, youth nights — with RSVPs.',
      ),
      _Feature(
        icon: Icons.payments_outlined,
        title: 'Tithes & offerings',
        body: 'Record contributions, send statements, no manual receipts.',
      ),
      _Feature(
        icon: Icons.fact_check_outlined,
        title: 'Sabbath attendance',
        body: 'Quick check-in for Sabbath school + Divine service.',
      ),
      _Feature(
        icon: Icons.insights_outlined,
        title: 'Insights',
        body: 'See growth, engagement, and giving trends at a glance.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            'WHAT\'S COMING',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        for (final f in features) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(f.icon,
                      color: AppColors.primaryBlue, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.title,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        f.body,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.65),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSponsorCta(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite,
                  color: AppColors.goldAccent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Sponsor the build',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Want this dashboard ready for your church sooner? Early '
            'sponsors directly fund development. Even small amounts '
            'help us ship faster — and sponsoring churches get first '
            'access when it launches.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.white.withValues(alpha: 0.88),
              height: 1.5,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ECOCASH',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.goldAccent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _ecoCashNumber,
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Material(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _copyNumber(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.content_copy,
                                color: AppColors.primaryBlue,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Copy',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Account name: $_ecoCashName',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _dialUssd,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.dialpad,
                        color: AppColors.primaryBlue, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Open dialer  •  *151#',
                      style: AppTextStyles.buttonText.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCta(BuildContext context) {
    return Material(
      color: context.palette.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openWhatsApp,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.chat,
                  color: Color(0xFF25D366),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Talk to the team',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      'WhatsApp us about admin access or sponsorship.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primaryBlue),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyNumber(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _ecoCashNumber));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.successGreen,
        content: Text(
          'EcoCash number copied.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _dialUssd() async {
    final uri = Uri.parse('tel:*151%23');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsApp() async {
    final cleaned = _supportWhatsApp.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse(
      'https://wa.me/$cleaned?text=${Uri.encodeComponent("Hi — I'd like to claim or sponsor the Church Admin Dashboard for ${church.name}.")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _HeroClipper extends CustomClipper<Path> {
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
