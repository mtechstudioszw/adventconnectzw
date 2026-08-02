import 'package:flutter/material.dart';

import '../../services/notification_preferences_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Per-church notification level. Three levels: All, Urgent only, None.
/// Pulls existing preferences from `notification_preferences` and lets
/// the user adjust each independently.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _loading = true;
  String? _error;
  List<NotificationPreference> _prefs = const [];
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await NotificationPreferencesService.fetchMyPreferences();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load preferences. Pull to retry.';
      });
    }
  }

  Future<void> _setLevel(NotificationPreference pref, String level) async {
    setState(() => _saving.add(pref.churchId));
    try {
      await NotificationPreferencesService.setChurchLevel(
        churchId: pref.churchId,
        level: level,
      );
      if (!mounted) return;
      setState(() {
        _prefs = _prefs
            .map(
              (p) => p.churchId == pref.churchId
                  ? NotificationPreference(
                      id: p.id,
                      churchId: p.churchId,
                      churchName: p.churchName,
                      level: level,
                    )
                  : p,
            )
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not update. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(pref.churchId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const ScreenHero(
                title: 'Church notifications',
                tagline: 'Notifications',
                subtitle:
                    'Pick which alerts you get from each church you follow — '
                    'All, only Urgent, or None.',
                fallbackRoute: 'settings',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null) {
      return ErrorBanner(message: _error!, onRetry: _load);
    }
    if (_prefs.isEmpty) {
      return EmptyStateCard(
        icon: Icons.notifications_off_outlined,
        title: 'No churches followed yet',
        message:
            'Once you follow a church, choose here whether it sends you all '
            'notices, only urgent ones, or none at all.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in _prefs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PrefCard(
              pref: p,
              busy: _saving.contains(p.churchId),
              onChange: (level) => _setLevel(p, level),
            ),
          ),
      ],
    );
  }
}

class _PrefCard extends StatelessWidget {
  const _PrefCard({
    required this.pref,
    required this.busy,
    required this.onChange,
  });

  final NotificationPreference pref;
  final bool busy;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return ScreenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.church,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pref.churchName,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryBlue,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Segmented(level: pref.level, onChange: onChange),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.level, required this.onChange});

  final String level;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.palette.cardMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _Pill(
            label: 'All',
            active: level == 'all',
            onTap: () => onChange('all'),
          ),
          _Pill(
            label: 'Urgent',
            active: level == 'urgent',
            onTap: () => onChange('urgent'),
          ),
          _Pill(
            label: 'None',
            active: level == 'none',
            onTap: () => onChange('none'),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: active ? AppColors.primaryGradient : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: active ? AppColors.white : context.palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
