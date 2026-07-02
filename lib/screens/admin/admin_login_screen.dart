import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';

/// Gate into the church-admin dashboard. Checks for an approved row in
/// `church_admins` against the current user and routes them on. This
/// is NOT app-admin / super-admin — that lives only on the web.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  bool _checking = false;
  String? _error;
  List<ChurchAdminRole> _roles = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      if (!AuthService.isSignedIn) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _loaded = true;
          _error = 'You must be signed in to access the church admin panel.';
        });
        return;
      }
      final roles = await ChurchService.fetchMyAdminRoles();
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _checking = false;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _loaded = true;
        _error = 'Could not check your admin status. Pull to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _roles.where((r) => r.isApproved).toList();
    final pending = _roles.where((r) => !r.isApproved).toList();
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _check,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const ScreenHero(
                title: 'Church admin',
                tagline: 'Restricted area',
                subtitle:
                    'Only approved church admins can post announcements and manage church content.',
                fallbackRoute: 'profile',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: _buildBody(approved, pending),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    List<ChurchAdminRole> approved,
    List<ChurchAdminRole> pending,
  ) {
    if (_checking || !_loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    if (_error != null) {
      return ErrorBanner(message: _error!);
    }
    if (approved.isEmpty && pending.isEmpty) {
      return EmptyStateCard(
        icon: Icons.shield_outlined,
        title: 'Not an admin yet',
        message:
            'Find your church in the directory and tap "Claim this church" to apply.',
        action: PrimaryGradientButton(
          label: 'Find my church',
          icon: Icons.search,
          onTap: () => context.goNamed('churches'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (approved.isNotEmpty) ...[
          _SectionLabel(label: 'APPROVED CHURCHES', count: approved.length),
          const SizedBox(height: 10),
          for (final r in approved)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RoleCard(
                role: r,
                onTap: () => context.pushNamed(
                  'admin_dashboard',
                  extra: r,
                ),
              ),
            ),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 4),
          _SectionLabel(label: 'PENDING REVIEW', count: pending.length),
          const SizedBox(height: 10),
          for (final r in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RoleCard(role: r, onTap: null),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primaryBlue,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.onTap});

  final ChurchAdminRole role;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final approved = role.isApproved;
    return ScreenCard(
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: approved ? AppColors.primaryGradient : null,
                  color: approved
                      ? null
                      : AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  approved ? Icons.lock_open : Icons.hourglass_top,
                  color: approved ? AppColors.white : AppColors.primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.churchName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${role.role[0].toUpperCase()}${role.role.substring(1)} admin · ${role.status}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: approved
                            ? AppColors.successGreen
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (approved)
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
