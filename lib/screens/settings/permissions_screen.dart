import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Settings → Permissions. Shows the current grant status for each
/// runtime permission the app uses, lets the user grant any that
/// were skipped during onboarding, and routes to system Settings
/// when a permission has been permanently denied (where the in-app
/// request dialog can no longer be shown).
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  final Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = true;

  /// Permissions surfaced in the UI. We include `storage` alongside
  /// `photos` because on Android 12 and below `Permission.photos`
  /// doesn't exist as a distinct grant — gallery access goes through
  /// the legacy READ_EXTERNAL_STORAGE permission instead. We pick
  /// whichever is appropriate when displaying / requesting.
  static const _all = [
    Permission.notification,
    Permission.camera,
    Permission.location,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The user may flip permissions in system Settings and bounce back
  /// to the app — re-check on resume so the UI reflects reality.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final next = <Permission, PermissionStatus>{};
    for (final p in _all) {
      try {
        next[p] = await p.status;
      } catch (_) {
        next[p] = PermissionStatus.denied;
      }
    }
    if (!mounted) return;
    setState(() {
      _statuses
        ..clear()
        ..addAll(next);
      _loading = false;
    });
  }

  Future<void> _handleTap(Permission permission) async {
    HapticFeedback.selectionClick();
    final current = _statuses[permission];
    if (current == PermissionStatus.permanentlyDenied ||
        current == PermissionStatus.restricted) {
      // The OS won't show the prompt again — bounce to Settings so
      // the user can flip it manually. We re-read state in
      // didChangeAppLifecycleState when they return.
      await openAppSettings();
      return;
    }
    final result = await permission.request();
    if (!mounted) return;
    setState(() => _statuses[permission] = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildHero(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }
    return Container(
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
      child: Column(
        children: [
          _PermissionRow(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            description:
                'Receive new-message, prayer, and event alerts on this device.',
            status: _statuses[Permission.notification]!,
            onTap: () => _handleTap(Permission.notification),
          ),
          const _Divider(),
          _PermissionRow(
            icon: Icons.camera_alt_outlined,
            label: 'Camera',
            description:
                'Take profile, cover, and product photos directly from the app.',
            status: _statuses[Permission.camera]!,
            onTap: () => _handleTap(Permission.camera),
          ),
          const _Divider(),
          _PermissionRow(
            icon: Icons.location_on_outlined,
            label: 'Location',
            description:
                'Used only by the "Near me" filter on the Churches tab — '
                'never tracked in the background.',
            status: _statuses[Permission.location]!,
            onTap: () => _handleTap(Permission.location),
          ),
        ],
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
                Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.goNamed('settings'),
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
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PERMISSIONS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        Platform.isIOS ? 'iOS access' : 'Android access',
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

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final PermissionStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (String chipText, Color chipColor, String actionLabel) =
        _statusFor(status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: chipColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            chipText,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: chipColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.65),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      actionLabel,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps a PermissionStatus to a chip label, chip colour, and
  /// affordance string. Tapping `permanentlyDenied` opens system
  /// Settings since the in-app dialog is suppressed by the OS.
  (String, Color, String) _statusFor(PermissionStatus s) {
    if (s.isGranted || s.isLimited) {
      return ('GRANTED', AppColors.successGreen, 'Tap to manage in Settings');
    }
    if (s.isPermanentlyDenied || s.isRestricted) {
      return (
        'BLOCKED',
        AppColors.red,
        'Permission is blocked — tap to open system Settings',
      );
    }
    return ('NOT SET', AppColors.goldAccent, 'Tap to allow');
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
