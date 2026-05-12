import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Slim top banner that appears when the device drops offline and
/// disappears as soon as connectivity comes back. Wraps `child` so it
/// can sit at the very top of the app shell without participating in
/// per-screen scaffolding.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late bool _online;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _online = ConnectivityService.isOnline;
    _sub = ConnectivityService.onChanged.listen((value) {
      if (mounted) setState(() => _online = value);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _online
              ? const SizedBox(height: 0, width: double.infinity)
              : Container(
                  width: double.infinity,
                  color: AppColors.darkNavy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Text(
                      "📡 You're offline — showing saved content",
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
