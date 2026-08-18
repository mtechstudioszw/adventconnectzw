import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_version.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/notification_preferences_service.dart';
import '../../services/premium_service.dart';
import '../../services/push_service.dart';
import '../../services/sabbath_service.dart';
import '../../services/seller_service.dart';
import '../../services/theme_service.dart';
import '../../services/youtube_prefs.dart';
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

  NotificationCategoryPrefs _categoryPrefs = NotificationCategoryPrefs.defaults;
  bool _sabbathEnabled = SabbathService.isEnabled();
  bool _sabbathMode = SabbathService.sabbathModeEnabled();
  String _sabbathProvince = SabbathService.province() ?? 'Harare';
  ThemeMode _themeMode = ThemeService.current;
  // Watch (YouTube) preferences — synchronous reads from local prefs.
  bool _ytAutoplayNext = YoutubePrefs.autoplayNext;
  bool _isSuperAdmin = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = BiometricService.enabledCached ?? false;
  bool _biometricBusy = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(
      begin: 12,
      end: 0,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOut));
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
    _settingsSearchController.dispose();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ctx.palette.sheet,
        title: Text(title, style: AppTextStyles.headlineSmall),
        content: Text(body, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.text),
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
      // Same bug as the profile screen's sign out, same fix: signOut()
      // disposes this screen, so a `mounted` check placed AFTER it
      // returns early and the navigation never happens. The member is
      // left on a settings screen belonging to an account with no
      // session, and only discovers it worked by relaunching.
      //
      // Hold the router from before the await; it outlives the widget.
      final router = GoRouter.of(context);
      try {
        await AuthService.signOut();
      } finally {
        router.goNamed('login');
      }
    },
  );

  /// Opens the exit survey. Deleting anything is that screen's own final
  /// confirmation, so this one only has to be honest about being a step on
  /// the way — it used to say "Continue" over a body claiming the deletion
  /// was permanent and immediate, which is a promise the next screen then
  /// kept before anybody had agreed to it.
  Future<void> _deleteAccount() async {
    if (!mounted) return;
    context.pushNamed('delete_account');
  }

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

  // The EcoCash donation details moved to DonateScreen, which Home and
  // Settings now share. Same number doubles as the support WhatsApp + a
  // contact email.
  // Update these as the ministry's reach grows.
  static const _supportWhatsApp = '+263778092494';
  static const _supportEmail = 'adventconnectzw@gmail.com';

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
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Contact us',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Reach the Adventist Super App team for support, '
                'feedback, or partnership.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
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
                    '?text=${Uri.encodeComponent("Hi Adventist Super App team — ")}',
                  );
                  Navigator.of(ctx).pop();
                  await launchUrl(url, mode: LaunchMode.externalApplication);
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
                    queryParameters: {'subject': 'Adventist Super App — Support'},
                  );
                  Navigator.of(ctx).pop();
                  await launchUrl(url, mode: LaunchMode.externalApplication);
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

  /// Opens the shared Donate screen rather than a sheet local to Settings.
  ///
  /// Home gained a Donate button, and two copies of the EcoCash number in two
  /// files is one copy too many — see [DonateScreen] for the number and for
  /// why the flow deliberately collects nothing in-app.
  Future<void> _openDonation() async {
    await context.pushNamed('donate');
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

  // ── Settings search ────────────────────────────────────────────────
  // iOS and Android both landed on a search field at the top of Settings
  // for the same reason: past about thirty rows, browsing stops working.
  // This screen is well past thirty.

  final _settingsSearchController = TextEditingController();
  String _settingsQuery = '';

  /// The searchable index.
  ///
  /// This is a hand-maintained list rather than something derived from the
  /// widget tree, because the sections below are a static tree of widgets,
  /// not data. **Adding a row above means adding it here too** — an entry
  /// that goes missing is invisible rather than broken, so it is worth
  /// checking this list whenever a destination is added.
  ///
  /// Only rows with a real destination are indexed. Toggles live inside a
  /// section and are found by opening it, which is why each entry carries
  /// its section name.
  List<_SettingsEntry> _searchIndex() {
    return [
      // Subscription — keywords cover how people actually describe it
      // ("remove ads", "stop ads") rather than only the product name.
      _SettingsEntry(
        'Go Premium',
        'Subscription',
        Icons.star_rounded,
        AppColors.goldAccent,
        'premium subscription no ads remove ads stop ads adfree upgrade '
            'support billing cancel restore',
        () => context.pushNamed('premium'),
      ),
      // Account
      _SettingsEntry(
        'Edit profile',
        'Account',
        Icons.person_outline,
        AppColors.primaryBlue,
        'name photo bio church avatar',
        () => context.pushNamed('edit_profile'),
      ),
      _SettingsEntry(
        'Change password',
        'Account',
        Icons.lock_outline,
        AppColors.primaryBlue,
        'security passcode reset',
        () => _changePassword(),
      ),
      _SettingsEntry(
        'Blocked contacts',
        'Account',
        Icons.block,
        AppColors.red,
        'block unblock privacy people',
        () => context.pushNamed('blocked_contacts'),
      ),
      // Preferences
      _SettingsEntry(
        'Notification permissions',
        'Preferences',
        Icons.notifications_active_outlined,
        AppColors.goldAccent,
        'alerts push permission',
        () => context.pushNamed('notification_permissions'),
      ),
      _SettingsEntry(
        'Sound & haptics',
        'Preferences',
        Icons.volume_up_outlined,
        AppColors.primaryBlue,
        'sound volume mute audio effects vibration haptics quiz silent',
        () => context.pushNamed('sound_settings'),
      ),
      _SettingsEntry(
        'Appearance',
        'Preferences',
        Icons.brightness_6_outlined,
        AppColors.primaryBlue,
        'theme dark light mode display',
        () => _pickTheme(),
      ),
      _SettingsEntry(
        'Sabbath province',
        'Preferences',
        Icons.location_on_outlined,
        AppColors.goldAccent,
        'sundown sunset harare bulawayo countdown timer',
        () => _pickSabbathProvince(),
      ),
      _SettingsEntry(
        'Sabbath mode',
        'Preferences',
        Icons.do_not_disturb_on_outlined,
        AppColors.goldAccent,
        'quiet mute silence notifications sabbath friday sundown',
        () => _toggleSabbathModeFromSearch(),
      ),
      // Legal
      _SettingsEntry(
        'Terms of service',
        'Legal',
        Icons.description_outlined,
        AppColors.textMuted,
        'legal terms conditions',
        () => context.pushNamed('terms'),
      ),
      _SettingsEntry(
        'Privacy policy',
        'Legal',
        Icons.privacy_tip_outlined,
        AppColors.textMuted,
        'legal privacy data',
        () => context.pushNamed('privacy'),
      ),
      _SettingsEntry(
        'Community guidelines',
        'Legal',
        Icons.groups_outlined,
        AppColors.textMuted,
        'rules conduct moderation',
        () => context.pushNamed('community_guidelines'),
      ),
      // Support
      _SettingsEntry(
        'Send feedback',
        'Support',
        Icons.feedback_outlined,
        AppColors.successGreen,
        'suggest idea complain',
        () => context.pushNamed('feedback'),
      ),
      _SettingsEntry(
        'Help center',
        'Support',
        Icons.help_outline,
        AppColors.successGreen,
        'faq support question',
        () => context.pushNamed('help_center'),
      ),
      _SettingsEntry(
        'Report a problem',
        'Support',
        Icons.bug_report_outlined,
        AppColors.red,
        'bug broken crash issue',
        () => context.pushNamed('report_problem'),
      ),
      // App
      _SettingsEntry(
        'About',
        'App',
        Icons.info_outline,
        AppColors.primaryBlue,
        'version credits developer',
        () => context.pushNamed('about'),
      ),
    ];
  }

  /// Reached from the search results, where there is no Switch to flip.
  /// Clears the query so the user lands back on the section with the
  /// toggle visible in its new state, rather than on a result row that
  /// silently changed something.
  Future<void> _toggleSabbathModeFromSearch() async {
    final next = !_sabbathMode;
    setState(() {
      _sabbathMode = next;
      _settingsQuery = '';
      _settingsSearchController.clear();
    });
    await SabbathService.setSabbathMode(next);
  }

  /// "Quiet from Fri 17:52 to Sat 18:04" — the toggle should show the
  /// actual window it will act on, computed from the chosen province.
  /// Falls back to a plain description if the province isn't recognised.
  String _sabbathModeSubtitle() {
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    final start = SabbathService.nextSabbathStart(
      overrideProvince: _sabbathProvince,
    );
    final end = SabbathService.currentSabbathEnd(
      overrideProvince: _sabbathProvince,
    );
    if (SabbathService.isSabbathNow(overrideProvince: _sabbathProvince) &&
        end != null) {
      return 'Quiet until sundown, ${hhmm(end.toLocal())}';
    }
    if (start == null) return 'Mutes non-essential alerts over the Sabbath';
    return 'Quiet from Fri ${hhmm(start.toLocal())} to Saturday sundown';
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.inputFill,
          borderRadius: BorderRadius.circular(100),
        ),
        child: TextField(
          controller: _settingsSearchController,
          onChanged: (v) => setState(() => _settingsQuery = v.trim()),
          textInputAction: TextInputAction.search,
          style: AppTextStyles.bodyMedium.copyWith(fontSize: 14.5),
          decoration: InputDecoration(
            hintText: 'Search settings',
            hintStyle: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 19,
              color: context.palette.textMuted,
            ),
            suffixIcon: _settingsQuery.isEmpty
                ? null
                : IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: context.palette.textMuted,
                    ),
                    onPressed: () {
                      _settingsSearchController.clear();
                      setState(() => _settingsQuery = '');
                      FocusScope.of(context).unfocus();
                    },
                  ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final q = _settingsQuery.toLowerCase();
    // Match the label first, then the keyword bag, so typing "dark" finds
    // Appearance and "sundown" finds Sabbath province.
    final hits = _searchIndex()
        .where(
          (e) =>
              e.label.toLowerCase().contains(q) ||
              e.keywords.contains(q) ||
              e.section.toLowerCase().contains(q),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: hits.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off,
                    size: 34,
                    color: context.palette.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nothing in Settings matches "$_settingsQuery"',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ),
            )
          : Container(
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
                children: [
                  for (var i = 0; i < hits.length; i++) ...[
                    if (i > 0) const _Divider(),
                    _NavRow(
                      icon: hits[i].icon,
                      label: hits[i].label,
                      tint: hits[i].tint,
                      // The section name is the useful second line here —
                      // it tells you where the row lives so next time you
                      // can browse straight to it.
                      trailing: hits[i].section,
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        hits[i].onTap();
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildHero(),
            _buildSearchField(),
            // Searching replaces the whole section stack rather than
            // filtering in place: past ~30 rows, browsing stops working,
            // and a partially-filtered stack of section cards is harder
            // to read than a flat list of hits.
            if (_settingsQuery.isNotEmpty)
              _buildSearchResults()
            else
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
                      // Top of the list on purpose. Gold is the app's
                      // one-accent-per-screen colour, so this reads as the
                      // single different thing here without shouting.
                      ValueListenableBuilder<bool>(
                        valueListenable: PremiumService.isPremium,
                        builder: (context, isPremium, _) => Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _Section(
                            title: 'Subscription',
                            accent: AppColors.goldAccent,
                            children: [
                              _NavRow(
                                icon: Icons.star_rounded,
                                tint: AppColors.goldAccent,
                                label: isPremium
                                    ? 'Premium'
                                    : 'Go Premium — no ads',
                                trailing: isPremium ? 'Active' : null,
                                onTap: () => context.pushNamed('premium'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _Section(
                        title: 'Account',
                        accent: AppColors.primaryBlue,
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
                        accent: AppColors.goldAccent,
                        children: [
                          _ToggleRow(
                            icon: Icons.event_outlined,
                            label: 'Event reminders',
                            value: _categoryPrefs.events,
                            onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(events: v),
                            ),
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.volunteer_activism_outlined,
                            label: 'Prayer updates',
                            value: _categoryPrefs.prayers,
                            onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(prayers: v),
                            ),
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.chat_bubble_outline,
                            label: 'New messages',
                            value: _categoryPrefs.messages,
                            onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(messages: v),
                            ),
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.favorite_border,
                            label: 'Likes & comments',
                            value: _categoryPrefs.social,
                            onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(social: v),
                            ),
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.storefront_outlined,
                            label: 'Marketplace alerts',
                            value: _categoryPrefs.marketplace,
                            onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(marketplace: v),
                            ),
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.campaign_outlined,
                            label: 'Church announcements',
                            value: _categoryPrefs.announcements,
                            onChanged: (v) => _setCategory(
                              _categoryPrefs.copyWith(announcements: v),
                            ),
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.newspaper_outlined,
                            label: 'Advent News updates',
                            value: _categoryPrefs.news,
                            onChanged: (v) =>
                                _setCategory(_categoryPrefs.copyWith(news: v)),
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.play_circle_outline,
                            label: 'Watch — new videos & live',
                            value: _categoryPrefs.watch,
                            onChanged: (v) {
                              _setCategory(_categoryPrefs.copyWith(watch: v));
                              PushService.setWatchPushesEnabled(v);
                            },
                          ),
                          const _Divider(),
                          _ToggleRow(
                            icon: Icons.emoji_events_outlined,
                            // "Reminders", precisely. A live challenge from
                            // a named person is not covered by this and
                            // always arrives — see NotificationCategoryPrefs.quiz.
                            label: 'Quiz reminders',
                            value: _categoryPrefs.quiz,
                            onChanged: (v) =>
                                _setCategory(_categoryPrefs.copyWith(quiz: v)),
                          ),
                          const _Divider(),
                          _NavRow(
                            icon: Icons.shield_moon_outlined,
                            label: 'Permissions',
                            onTap: () => context.pushNamed('permissions'),
                          ),
                          const _Divider(),
                          _NavRow(
                            icon: Icons.volume_up_outlined,
                            label: 'Sound & haptics',
                            onTap: () => context.pushNamed('sound_settings'),
                          ),
                          const _Divider(),
                          _NavRow(
                            icon: Icons.brightness_6_outlined,
                            label: 'Appearance',
                            trailing: _themeLabel(_themeMode),
                            onTap: _pickTheme,
                          ),
                          const _Divider(),
                          // The app-language switcher is gone (18 Aug 2026).
                          // It offered English / Shona / Ndebele and changed
                          // nothing — the app has no translations, so it was
                          // a setting that persisted a preference no screen
                          // ever read. It also read as a promise the app
                          // could not keep now that members outside Zimbabwe
                          // are signing up. The Bible translation, Sabbath
                          // School language (~90) and Hymnal language
                          // pickers are separate and stay.
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
                          const _Divider(),
                          // Sabbath mode (patch_169) — the countdown above
                          // SHOWS the Sabbath; this one acts on it.
                          _ToggleRow(
                            icon: Icons.do_not_disturb_on_outlined,
                            label: 'Sabbath mode',
                            subtitle: _sabbathModeSubtitle(),
                            value: _sabbathMode,
                            onChanged: (v) async {
                              setState(() => _sabbathMode = v);
                              await SabbathService.setSabbathMode(v);
                            },
                          ),
                          if (_sabbathEnabled || _sabbathMode) ...[
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
                        title: 'Watch',
                        accent: AppColors.red,
                        children: [
                          _ToggleRow(
                            icon: Icons.smart_display_outlined,
                            label: 'Autoplay next video',
                            value: _ytAutoplayNext,
                            onChanged: (v) async {
                              await YoutubePrefs.setAutoplayNext(v);
                              if (mounted) setState(() => _ytAutoplayNext = v);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _Section(
                        title: 'Legal',
                        accent: AppColors.textMuted,
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
                            onTap: () => _openLegal(
                              'https://mtechstudioszw.github.io/adventconnect-legal/guidelines.html',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _DonationCard(onTap: _openDonation),
                      const SizedBox(height: 18),
                      _Section(
                        title: 'Support',
                        accent: AppColors.successGreen,
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
                          accent: AppColors.darkNavy,
                          children: [
                            _NavRow(
                              icon: Icons.verified_user_outlined,
                              label: 'Seller approvals',
                              onTap: () =>
                                  context.pushNamed('admin_seller_approvals'),
                            ),
                            const _Divider(),
                            _NavRow(
                              icon: Icons.church_outlined,
                              label: 'Church admin requests',
                              onTap: () =>
                                  context.pushNamed('admin_church_approvals'),
                            ),
                            const _Divider(),
                            _NavRow(
                              icon: Icons.newspaper_outlined,
                              label: 'News approvals',
                              onTap: () =>
                                  context.pushNamed('admin_news_approvals'),
                            ),
                            const _Divider(),
                            _NavRow(
                              icon: Icons.event_outlined,
                              label: 'Event approvals',
                              onTap: () =>
                                  context.pushNamed('admin_event_approvals'),
                            ),
                            const _Divider(),
                            _NavRow(
                              icon: Icons.library_books_outlined,
                              label: 'Manage Library',
                              onTap: () => context.pushNamed('admin_library'),
                            ),
                            const _Divider(),
                            _NavRow(
                              icon: Icons.insights_outlined,
                              label: 'User insights',
                              onTap: () =>
                                  context.pushNamed('admin_user_insights'),
                            ),
                            const _Divider(),
                            _NavRow(
                              icon: Icons.quiz_outlined,
                              label: 'Manage Quiz',
                              onTap: () => context.pushNamed('admin_quiz'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      _Section(
                        title: 'App',
                        accent: AppColors.primaryBlue,
                        children: [
                          _NavRow(
                            icon: Icons.info_outline,
                            label: 'About',
                            onTap: () => context.pushNamed('about'),
                          ),
                          const _Divider(),
                          _InfoRow(
                            icon: Icons.tag,
                            label: 'App version',
                            // The CI build stamps the commit SHA via
                            // --dart-define=GIT_SHA. Shows "local" for local
                            // builds. Lets you confirm at a glance that the
                            // build you're running is the latest one (no more
                            // chasing already-fixed bugs in a stale build).
                            value: 'v$kAppVersionName',
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
                          'Made with care • Tanatswa Michael Mikuwa',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textMuted,
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
    return const ScreenHero(
      title: 'Tune the app to you',
      tagline: 'Settings',
      fallbackRoute: 'profile',
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
            border: Border.all(color: AppColors.divider),
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
                        color: AppColors.textMuted,
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
                      'Every feature here is free, and the servers are not. '
                      'A voluntary EcoCash gift of any size helps keep '
                      'Adventist Super App running for the whole community.',
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
              const Icon(Icons.chevron_right, color: AppColors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded tinted square behind a settings icon. A bare glyph in a
/// 60-row list gives the eye nothing to land on; a colour does.
/// One searchable destination in Settings. [keywords] is a lowercase bag
/// of synonyms so people find things by the word they actually use —
/// "dark" for Appearance, "sundown" for Sabbath province.
class _SettingsEntry {
  const _SettingsEntry(
    this.label,
    this.section,
    this.icon,
    this.tint,
    this.keywords,
    this.onTap,
  );

  final String label;
  final String section;
  final IconData icon;
  final Color tint;
  final String keywords;
  final VoidCallback onTap;
}

class _SettingsIconChip extends StatelessWidget {
  const _SettingsIconChip({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: tint, size: 18),
    );
  }
}

/// Carries a section's accent colour down to its rows, so each group of
/// settings is a different colour without threading `tint:` through
/// forty call sites. A row can still override with its own `tint`.
class _SectionAccent extends InheritedWidget {
  const _SectionAccent({required this.color, required super.child});

  final Color color;

  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SectionAccent>()?.color;

  @override
  bool updateShouldNotify(_SectionAccent oldWidget) => oldWidget.color != color;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.accent});
  final String title;
  final List<Widget> children;

  /// Icon colour for every row in this section. Defaults to Primary Blue.
  /// Only ever one of the CLAUDE.md scheme colours.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return _SectionAccent(
      color: accent ?? AppColors.primaryBlue,
      child: _buildSection(context),
    );
  }

  Widget _buildSection(BuildContext context) {
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
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.destructive = false,
    this.tint,
  });

  final IconData icon;
  final String label;
  // Nullable so callers can render a passive (non-tappable) row when
  // there is nothing left to do — e.g. "Google linked" once linking
  // has succeeded. A null onTap also disables InkWell's ripple.
  final VoidCallback? onTap;
  final String? trailing;
  final bool destructive;

  /// Icon chip colour. Defaults to Primary Blue; sections override it so
  /// a long list is scannable by colour before it is read. Destructive
  /// rows ignore it and go red.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.red : AppColors.text;
    final chipTint = destructive
        ? AppColors.red
        : (tint ?? _SectionAccent.of(context) ?? AppColors.primaryBlue);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              _SettingsIconChip(icon: icon, tint: chipTint),
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
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.4)),
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
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final bool value;
  // Nullable so callers can disable the Switch during an in-flight
  // OS prompt (e.g. waiting for the biometric dialog to return).
  final ValueChanged<bool>? onChanged;

  /// Optional second line — used where the toggle's effect depends on
  /// data the user should see (Sabbath mode shows tonight's sundown).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          _SettingsIconChip(
            icon: icon,
            tint: _SectionAccent.of(context) ?? AppColors.primaryBlue,
          ),
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
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
              color: AppColors.textMuted,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Divider(height: 1, color: AppColors.divider),
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
                      color: AppColors.divider,
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
                          color: AppColors.textMuted,
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
                                      : AppColors.textMuted,
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
                    color: AppColors.divider,
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
                'Choose how Adventist Super App looks. Match system follows your '
                'phone\'s light or dark setting.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
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
                                : AppColors.textMuted,
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Icon(icon, color: AppColors.text, size: 20),
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
                                      26,
                                      26,
                                      46,
                                      0.6,
                                    ),
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
      final verify = await AuthService.verifyCurrentPassword(_currentCtrl.text);
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
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.red),
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
            style: AppTextStyles.labelMedium.copyWith(color: AppColors.text),
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
