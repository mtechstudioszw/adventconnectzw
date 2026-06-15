import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/notification_preferences_service.dart';
import '../../services/sabbath_service.dart';
import '../../services/seller_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/invite_friends_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  NotificationCategoryPrefs _categoryPrefs =
      NotificationCategoryPrefs.defaults;
  String _language = 'English';
  bool _sabbathEnabled = SabbathService.isEnabled();
  String _sabbathProvince = SabbathService.province() ?? 'Harare';
  ThemeMode _themeMode = ThemeService.current;
  bool _isSuperAdmin = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricBusy = false;

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
    _loadCategoryPrefs();
    _loadSuperAdmin();
    _loadBiometric();
  }

  Future<void> _loadCategoryPrefs() async {
    final prefs = await NotificationPreferencesService.fetchCategories();
    if (!mounted) return;
    setState(() => _categoryPrefs = prefs);
  }

  Future<void> _loadSuperAdmin() async {
    final isAdmin = await SellerService.isCurrentUserSuperAdmin();
    if (!mounted) return;
    setState(() => _isSuperAdmin = isAdmin);
  }

  Future<void> _loadBiometric() async {
    final results = await Future.wait([
      BiometricService.isAvailable(),
      BiometricService.isEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _biometricAvailable = results[0];
      _biometricEnabled = results[1];
    });
  }

  Future<void> _toggleBiometric(bool next) async {
    if (_biometricBusy) return;
    setState(() => _biometricBusy = true);
    final ok = await BiometricService.setEnabled(next);
    if (!mounted) return;
    setState(() {
      _biometricBusy = false;
      // setEnabled(false) is unconditional, setEnabled(true) only
      // returns true once the OS prompt is satisfied — so this
      // single expression covers cancel-flip-back too.
      _biometricEnabled = ok && next;
    });
    if (next && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not verify biometrics. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }


  /// Optimistic write — flip the local toggle immediately so the
  /// Switch animates, then fire-and-forget the persist call. The
  /// service swallows network errors silently; if the write fails
  /// the toggle simply doesn't survive a reload, and the user can
  /// retry by flipping again. This is what makes the toggles feel
  /// snappy AND survive killing the app (previous behaviour was
  /// ephemeral local state that defaulted on every fresh open).
  void _setCategory(NotificationCategoryPrefs next) {
    setState(() => _categoryPrefs = next);
    NotificationPreferencesService.saveCategories(next);
  }

  // Biometric loader + toggle handler removed in this build (revisit
  // ~2 months post-launch). Restore from git history if re-enabling.

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: ctx.palette.sheet,
        title: Text(title, style: AppTextStyles.headlineSmall),
        content: Text(body, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.text,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmLabel, style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await action();
  }

  Future<void> _signOut() => _confirmAndRun(
        title: 'Sign out?',
        body: 'You\'ll need to sign in again to access the community.',
        confirmLabel: 'Sign out',
        confirmColor: AppColors.red,
        action: () async {
          await AuthService.signOut();
          if (!mounted) return;
          context.goNamed('login');
        },
      );

  Future<void> _deleteAccount() => _confirmAndRun(
        title: 'Delete account?',
        body:
            'This permanently removes your profile, prayers, posts and messages. This cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: AppColors.red,
        action: () async {
          final result = await AuthService.deleteAccount();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: result.isSuccess
                  ? AppColors.successGreen
                  : AppColors.darkNavy,
              content: Text(
                result.isSuccess
                    ? 'Account deleted.'
                    : (result.errorMessage ?? 'Deletion failed.'),
                style:
                    AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
              ),
            ),
          );
          context.goNamed('login');
        },
      );

  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ChangePasswordDialog(),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            'Password updated.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  /// Personal EcoCash details for ministry donations. Zim's
  /// dominant mobile-money network — every smartphone user already
  /// has the dialer flow muscle-memorised. Two CTAs in the sheet
  /// below: tap-to-copy the number so it pastes straight into the
  /// EcoCash app, and tap-to-dial *151# to launch the USSD send-
  /// money flow without leaving the phone keyboard.
  ///
  /// REPLACE both constants with your real values:
  ///   - Number: full Zim mobile (e.g. +263 77 123 4567)
  ///   - Display name: how the recipient appears on the EcoCash
  ///     confirmation prompt (helps donors trust the destination)
  static const _ecoCashNumber = '0778 092 494';
  static const _ecoCashName = 'Advent Connect ZW';
  // Same number doubles as the support WhatsApp + a contact email.
  // Update these as the ministry's reach grows.
  static const _supportWhatsApp = '+263778092494';
  static const _supportEmail = 'tanatswamichaelmikuwa@gmail.com';

  Future<void> _openSupportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(26, 26, 46, 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Contact us',
                style: AppTextStyles.titleLarge
                    .copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Reach the Advent Connect ZW team for support, '
                'feedback, or partnership.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.65),
                ),
              ),
              const SizedBox(height: 16),
              _SupportChannel(
                icon: Icons.chat,
                tint: const Color(0xFF25D366),
                label: 'WhatsApp',
                subtitle: _supportWhatsApp,
                onTap: () async {
                  final url = Uri.parse(
                    'https://wa.me/${_supportWhatsApp.replaceAll(RegExp(r"[^0-9+]"), "")}'
                    '?text=${Uri.encodeComponent("Hi Advent Connect ZW team — ")}',
                  );
                  Navigator.of(ctx).pop();
                  await launchUrl(url,
                      mode: LaunchMode.externalApplication);
                },
              ),
              const SizedBox(height: 10),
              _SupportChannel(
                icon: Icons.email_outlined,
                tint: AppColors.primaryBlue,
                label: 'Email',
                subtitle: _supportEmail,
                onTap: () async {
                  final url = Uri(
                    scheme: 'mailto',
                    path: _supportEmail,
                    queryParameters: {
                      'subject': 'Advent Connect ZW — Support',
                    },
                  );
                  Navigator.of(ctx).pop();
                  await launchUrl(url,
                      mode: LaunchMode.externalApplication);
                },
              ),
              const SizedBox(height: 10),
              _SupportChannel(
                icon: Icons.feedback_outlined,
                tint: AppColors.darkNavy,
                label: 'In-app feedback form',
                subtitle: 'Send us a structured report from inside the app.',
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.pushNamed('feedback');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDonation() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _EcoCashDonationSheet(
        number: _ecoCashNumber,
        recipientName: _ecoCashName,
        onSnack: (msg) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.successGreen,
              content: Text(
                msg,
                style:
                    AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LanguageSheet(selected: _language),
    );
    if (picked != null && mounted) {
      setState(() => _language = picked);
    }
  }

  // Theme picker — kept available for the v1.1 dark-mode update.
  // The Settings row that triggers it is hidden in build() until
  // the remaining ~45 screens are migrated to context.palette.
  // ignore: unused_element
  Future<void> _pickTheme() async {
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ThemeSheet(selected: _themeMode),
    );
    if (picked != null && mounted) {
      await ThemeService.setMode(picked);
      setState(() => _themeMode = picked);
    }
  }

  // ignore: unused_element
  String _themeLabel(ThemeMode m) {
    switch (m) {
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.system:
        return 'System';
    }
  }

  Future<void> _pickSabbathProvince() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      // Without this the sheet caps at ~50% of screen and the bottom
      // provinces in the list get clipped behind the system nav bar.
      isScrollControlled: true,
      builder: (ctx) => _ProvinceSheet(selected: _sabbathProvince),
    );
    if (picked != null && mounted) {
      await SabbathService.setProvince(picked);
      setState(() => _sabbathProvince = picked);
    }
  }

  Future<void> _openLegal(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
      throw Exception('launch failed');
    } catch (_) {
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildHero(),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) => Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: child,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'Account',
                      children: [
                        _NavRow(
                          icon: Icons.person_outline,
                          label: 'Edit profile',
                          onTap: () => context.pushNamed('edit_profile'),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.lock_outline,
                          label: 'Change password',
                          onTap: _changePassword,
                        ),
                        if (_biometricAvailable) ...[
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.fingerprint,
                            label: 'Biometric unlock',
                            value: _biometricEnabled,
                            onChanged: _biometricBusy
                                ? null
                                : (v) => _toggleBiometric(v),
                          ),
                        ],
                        const _Divider(),
                        _NavRow(
                          icon: Icons.block,
                          label: 'Blocked contacts',
                          onTap: () => context.pushNamed('blocked_users'),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.delete_outline,
                          label: 'Delete account',
                          destructive: true,
                          onTap: _deleteAccount,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _Section(
                      title: 'Preferences',
                      children: [
                        _ToggleRow(
                          icon: Icons.event_outlined,
                          label: 'Event reminders',
                          value: _categoryPrefs.events,
                          onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(events: v)),
                        ),
                        const _Divider(),
                        _ToggleRow(
                          icon: Icons.volunteer_activism_outlined,
                          label: 'Prayer updates',
                          value: _categoryPrefs.prayers,
                          onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(prayers: v)),
                        ),
                        const _Divider(),
                        _ToggleRow(
                          icon: Icons.chat_bubble_outline,
                          label: 'New messages',
                          value: _categoryPrefs.messages,
                          onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(messages: v)),
                        ),
                        const _Divider(),
                        _ToggleRow(
                          icon: Icons.storefront_outlined,
                          label: 'Marketplace alerts',
                          value: _categoryPrefs.marketplace,
                          onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(marketplace: v)),
                        ),
                        const _Divider(),
                        _ToggleRow(
                          icon: Icons.campaign_outlined,
                          label: 'Church announcements',
                          value: _categoryPrefs.announcements,
                          onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(announcements: v)),
                        ),
                        const _Divider(),
                        _ToggleRow(
                          icon: Icons.newspaper_outlined,
                          label: 'Advent News updates',
                          value: _categoryPrefs.news,
                          onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(news: v)),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.shield_moon_outlined,
                          label: 'Permissions',
                          onTap: () => context.pushNamed('permissions'),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.brightness_6_outlined,
                          label: 'Appearance',
                          trailing: _themeLabel(_themeMode),
                          onTap: _pickTheme,
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.language,
                          label: 'Language',
                          trailing: _language,
                          onTap: _pickLanguage,
                        ),
                        const _Divider(),
                        _ToggleRow(
                          icon: Icons.brightness_3,
                          label: 'Sabbath countdown',
                          value: _sabbathEnabled,
                          onChanged: (v) async {
                            await SabbathService.setEnabled(v);
                            if (mounted) {
                              setState(() => _sabbathEnabled = v);
                            }
                          },
                        ),
                        if (_sabbathEnabled) ...[
                          const _Divider(),
                          _NavRow(
                            icon: Icons.place_outlined,
                            label: 'Sabbath province',
                            trailing: _sabbathProvince,
                            onTap: _pickSabbathProvince,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    _Section(
                      title: 'Legal',
                      children: [
                        _NavRow(
                          icon: Icons.description_outlined,
                          label: 'Terms of service',
                          onTap: () => _openLegal(
                            'https://mtechstudioszw.github.io/adventconnect-legal/terms.html',
                          ),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.privacy_tip_outlined,
                          label: 'Privacy policy',
                          onTap: () => _openLegal(
                            'https://mtechstudioszw.github.io/adventconnect-legal/privacy.html',
                          ),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.shield_outlined,
                          label: 'Community guidelines',
                          onTap: () => _openLegal('https://mtechstudioszw.github.io/adventconnect-legal/guidelines.html'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DonationCard(onTap: _openDonation),
                    const SizedBox(height: 18),
                    _Section(
                      title: 'Support',
                      children: [
                        _NavRow(
                          icon: Icons.feedback_outlined,
                          label: 'Send feedback',
                          onTap: () => context.pushNamed('feedback'),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.help_outline,
                          label: 'Help center',
                          onTap: () => context.pushNamed('feedback'),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.flag_outlined,
                          label: 'Report a problem',
                          onTap: () => context.pushNamed('feedback'),
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.mail_outline,
                          label: 'Contact us',
                          onTap: _openSupportSheet,
                        ),
                      ],
                    ),
                    if (_isSuperAdmin) ...[
                      const SizedBox(height: 18),
                      _Section(
                        title: 'Super admin',
                        children: [
                          _NavRow(
                            icon: Icons.verified_user_outlined,
                            label: 'Seller approvals',
                            onTap: () => context.pushNamed(
                              'admin_seller_approvals',
                            ),
                          ),
                          const _Divider(),
                          _NavRow(
                            icon: Icons.newspaper_outlined,
                            label: 'News approvals',
                            onTap: () => context.pushNamed(
                              'admin_news_approvals',
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    _Section(
                      title: 'App',
                      children: [
                        _NavRow(
                          icon: Icons.info_outline,
                          label: 'About',
                          onTap: () => context.pushNamed('about'),
                        ),
                        const _Divider(),
                        const _InfoRow(
                          icon: Icons.tag,
                          label: 'App version',
                          value: 'v1.0.0',
                        ),
                        const _Divider(),
                        _NavRow(
                          icon: Icons.logout,
                          label: 'Sign out',
                          destructive: true,
                          onTap: _signOut,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const InviteFriendsCard(horizontalMargin: 0),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Made with care • MyTech Studios Zw',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.45),
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
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

  Widget _buildHero() {
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
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('profile'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SETTINGS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tune the app to you',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
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

class _SupportChannel extends StatelessWidget {
  const _SupportChannel({
    required this.icon,
    required this.tint,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EcoCashDonationSheet extends StatelessWidget {
  const _EcoCashDonationSheet({
    required this.number,
    required this.recipientName,
    required this.onSnack,
  });

  final String number;
  final String recipientName;
  final void Function(String) onSnack;

  Future<void> _copyNumber(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: number));
    onSnack('EcoCash number copied — paste it in your EcoCash app.');
  }

  Future<void> _dialUssd(BuildContext context) async {
    // *151# is the EcoCash menu shortcut on Econet lines. We URL-
    // encode the # as %23 because some Android dialers refuse a
    // raw # in a tel: URI. Launches the dialer pre-filled, user
    // hits the call button.
    final uri = Uri.parse('tel:*151%23');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch failed');
    } catch (_) {
      onSnack('Could not open the dialer. Try dialling *151# manually.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(26, 26, 46, 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: AppColors.goldAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Donate via EcoCash',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Send any amount to the number below.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: context.palette.cardMuted,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color.fromRGBO(26, 26, 46, 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ECOCASH NUMBER',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.55),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
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
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      Material(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _copyNumber(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // TODO(dark-mode): const Icon — sits on primaryBlue copy button.
                                const Icon(
                                  Icons.content_copy,
                                  color: AppColors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Copy',
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Account name: Tanatswa Michael Mikuwa',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.70),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _dialUssd(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // TODO(dark-mode): const Icon — sits on primaryBlue dialer button.
                      const Icon(Icons.dialpad,
                          color: AppColors.white, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Open dialer  •  *151#',
                        style: AppTextStyles.buttonText.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'How to send:\n'
              '1. Dial *151# (or open the EcoCash app)\n'
              '2. Choose "Send Money" → "To Mobile"\n'
              '3. Enter the number above\n'
              '4. Enter the amount you want to donate\n'
              '5. Confirm with your PIN',
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.70),
                height: 1.55,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationCard extends StatelessWidget {
  const _DonationCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.goldAccent, width: 1.5),
                ),
                child: const Icon(
                  Icons.favorite,
                  color: AppColors.goldAccent,
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
                      'Support this ministry',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Donate via PayNow — EcoCash, OneMoney, ZIPIT '
                      'or card. Every contribution keeps the app '
                      'free for the Adventist community.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.open_in_new,
                color: AppColors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
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
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  // Nullable so callers can render a passive (non-tappable) row when
  // there is nothing left to do — e.g. "Google linked" once linking
  // has succeeded. A null onTap also disables InkWell's ripple.
  final VoidCallback? onTap;
  final String? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.text;
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
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    trailing!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.55),
                      fontWeight: FontWeight.w600,
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  // Nullable so callers can disable the Switch during an in-flight
  // OS prompt (e.g. waiting for the biometric dialog to return).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.white,
            activeTrackColor: AppColors.primaryBlue,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}

class _ProvinceSheet extends StatelessWidget {
  const _ProvinceSheet({required this.selected});
  final String selected;

  @override
  Widget build(BuildContext context) {
    final options = SabbathService.provinces;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(26, 26, 46, 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Choose your province',
                        style: AppTextStyles.headlineSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Used to compute Friday sundown.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color.fromRGBO(26, 26, 46, 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final opt = options[i];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, opt),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  opt == selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: opt == selected
                                      ? AppColors.primaryBlue
                                      : const Color.fromRGBO(26, 26, 46, 0.4),
                                  size: 22,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    opt,
                                    style: AppTextStyles.titleMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.selected});
  final ThemeMode selected;

  static const _options = <(ThemeMode, String, IconData, String)>[
    (
      ThemeMode.system,
      'Match system',
      Icons.brightness_auto_outlined,
      'Use whichever theme your phone is on.',
    ),
    (
      ThemeMode.light,
      'Light',
      Icons.light_mode_outlined,
      'Bright surfaces — best in daylight.',
    ),
    (
      ThemeMode.dark,
      'Dark',
      Icons.dark_mode_outlined,
      'Dim surfaces — easier on the eyes at night.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(26, 26, 46, 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Appearance',
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dark mode is still rolling out screen-by-screen — a few '
                'pages may still appear light for now.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              for (final (mode, label, icon, description) in _options) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, mode),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            mode == selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: mode == selected
                                ? AppColors.primaryBlue
                                : const Color.fromRGBO(26, 26, 46, 0.4),
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Icon(
                            icon,
                            color: AppColors.text,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: AppTextStyles.titleMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: const Color.fromRGBO(
                                        26, 26, 46, 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.selected});
  final String selected;

  static const _options = ['English', 'Shona', 'Ndebele'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(26, 26, 46, 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose language',
                style: AppTextStyles.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              for (final opt in _options) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, opt),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            opt == selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: opt == selected
                                ? AppColors.primaryBlue
                                : const Color.fromRGBO(26, 26, 46, 0.4),
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Text(
                            opt,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  // Independent obscure flags for each field — tapping the eye on the
  // current-password field doesn't reveal the new one, and vice versa.
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Verify the current password BEFORE we let Supabase accept the
      // new one. The session-token is already proof of identity but
      // for "change password" the user expects this extra check (and
      // it stops a stolen-but-locked phone from rotating the password).
      final verify = await AuthService.verifyCurrentPassword(
        _currentCtrl.text,
      );
      if (!verify.isSuccess) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = verify.errorMessage ?? 'Current password is incorrect.';
        });
        return;
      }
      final r = await AuthService.changePassword(_newCtrl.text);
      if (!mounted) return;
      if (!r.isSuccess) {
        setState(() {
          _busy = false;
          _error = r.errorMessage;
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? hint,
    bool autofocus = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: AppColors.text.withValues(alpha: 0.55),
          ),
          onPressed: onToggle,
          tooltip: obscure ? 'Show password' : 'Hide password',
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Change password', style: AppTextStyles.headlineSmall),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _passwordField(
              controller: _currentCtrl,
              label: 'Current password',
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
              autofocus: true,
              validator: (v) {
                if ((v ?? '').isEmpty) return 'Enter your current password';
                return null;
              },
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: _newCtrl,
              label: 'New password',
              hint: 'Min 8 characters',
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              validator: (v) {
                if ((v ?? '').length < 8) return 'At least 8 characters';
                if (v == _currentCtrl.text) {
                  return 'Choose a different password from your current one';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _passwordField(
              controller: _confirmCtrl,
              label: 'Confirm new password',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) {
                if (v != _newCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: AppTextStyles.labelMedium
                .copyWith(color: AppColors.text),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          onPressed: _busy ? null : _save,
          child: Text(
            _busy ? 'Saving…' : 'Save',
            style: AppTextStyles.labelLarge,
          ),
        ),
      ],
    );
  }
}
