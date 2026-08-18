import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_version.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Settings → About. Surfaces app metadata, developer credit, and
/// links back out to support / legal pages. Single source of truth
/// for who built the app and where to reach them — referenced from
/// Play Store listing copy as well.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appName = 'Adventist Super App';
  static const _appTagline = 'Connecting SDA people around the globe';
  /// Reads the single source in `app_version.dart`, so this can never
  /// again sit at v1.0.0 through three shipped releases.
  static const _appVersion = 'v$kAppVersionName';
  static const _developerName = 'Tanatswa Michael Mikuwa';
  static const _studioName = 'Tanatswa Michael Mikuwa';
  static const _contactEmail = 'adventconnectzw@gmail.com';
  static const _contactWhatsApp = '+263778092494';
  static const _sponsorEcoCash = '0778 092 494';
  static const _sponsorEcoCashName = 'Tanatswa Michael Mikuwa';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHero(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBrandCard(),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Built by',
                    children: [
                      _InfoTile(
                        icon: Icons.person_outline,
                        label: 'Developer',
                        value: _developerName,
                      ),
                      const _Divider(),
                      _TapTile(
                        icon: Icons.email_outlined,
                        label: 'Contact email',
                        value: _contactEmail,
                        onTap: () => _openEmail(context),
                      ),
                      const _Divider(),
                      _TapTile(
                        icon: Icons.chat_outlined,
                        label: 'WhatsApp',
                        value: _contactWhatsApp,
                        onTap: () => _openWhatsApp(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'About this app',
                    children: const [
                      _ParagraphTile(
                        text:
                            'Adventist Super App is a community-first platform '
                            'connecting Seventh-day Adventists around the '
                            'globe. Find churches near you, RSVP to '
                            'gatherings, lift up prayer requests, support '
                            'each other in marketplace and jobs, and stay '
                            'connected to your home congregation — wherever '
                            'in the world that is.',
                      ),
                      _Divider(),
                      _ParagraphTile(
                        text:
                            'This is an independent app, built to serve the '
                            'Adventist community. It is not an official '
                            'Seventh-day Adventist Church product, and it is '
                            'not affiliated with, endorsed by or operated by '
                            'the General Conference, any division, union or '
                            'local conference.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SponsorCard(
                    number: _sponsorEcoCash,
                    accountName: _sponsorEcoCashName,
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    title: 'Legal',
                    children: [
                      _NavTile(
                        icon: Icons.description_outlined,
                        label: 'Terms of service',
                        onTap: () => _openLegal(
                          context,
                          'https://mtechstudioszw.github.io/adventconnect-legal/terms.html',
                        ),
                      ),
                      const _Divider(),
                      _NavTile(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy policy',
                        onTap: () => _openLegal(
                          context,
                          'https://mtechstudioszw.github.io/adventconnect-legal/privacy.html',
                        ),
                      ),
                      const _Divider(),
                      _NavTile(
                        icon: Icons.shield_outlined,
                        label: 'Community guidelines',
                        onTap: () => _openLegal(
                          context,
                          'https://mtechstudioszw.github.io/adventconnect-legal/guidelines.html',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Text(
                      '$_studioName  •  Made with ❤️ in Zimbabwe',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 1.0,
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
    return ScreenHero(
      title: _appName,
      tagline: 'About',
      fallbackRoute: 'settings',
    );
  }

  Widget _buildBrandCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.goldAccent, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Image.asset(
                'assets/icon/logo.png',
                fit: BoxFit.contain,
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
                  _appName,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _appTagline,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _appVersion,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _contactEmail,
      queryParameters: {'subject': 'Adventist Super App'},
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final cleaned = _contactWhatsApp.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse(
      'https://wa.me/$cleaned?text=${Uri.encodeComponent("Hi $_developerName — ")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openLegal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
      throw Exception('launch failed');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the link. Visit adventconnectzw.netlify.app',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }
}

/// Honest "we're still building this" card. Acknowledges that some
/// features aren't yet working and frames the user's support as the
/// thing that gets them shipped. EcoCash details are surfaced
/// inline so a tap-to-copy + open-dialer flow stays one screen
/// deep — fewer hoops, more conversions.
class _SponsorCard extends StatelessWidget {
  const _SponsorCard({
    required this.number,
    required this.accountName,
  });

  final String number;
  final String accountName;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: number));
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

  Future<void> _dial() async {
    final uri = Uri.parse('tel:*151%23');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
              const Icon(Icons.favorite_outline,
                  color: AppColors.goldAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Support the ministry',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Adventist Super App is built and run by a small team to serve '
            'the Adventist community across Zimbabwe. If the app has '
            'blessed you and you\'d like to help keep it running, you can '
            'send a voluntary gift via EcoCash. Completely optional — '
            'every feature stays free for everyone.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.white.withValues(alpha: 0.88),
              height: 1.55,
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
                        number,
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
                        onTap: () => _copy(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
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
                  'Account name: $accountName',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _dial,
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
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.text, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  const _TapTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$label copied to clipboard.',
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
               Icon(
                Icons.chevron_right,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.text, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
              ),
               Icon(
                Icons.chevron_right,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParagraphTile extends StatelessWidget {
  const _ParagraphTile({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textMuted,
          height: 1.55,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Divider(
        height: 1,
        color: AppColors.divider,
      ),
    );
  }
}

