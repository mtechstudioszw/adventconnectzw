import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Silent-offline / brief-back-online overlay. The previous version
/// kept a persistent grey strip pinned to the status bar while the
/// device was offline; this version stays out of the way while
/// offline (per-screen offline notices already speak up where data
/// failed to load) and only surfaces a small "Back online" toast for
/// three seconds when connectivity is restored.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late bool _online;
  bool _showRestored = false;
  StreamSubscription<bool>? _sub;
  Timer? _restoreTimer;

  @override
  void initState() {
    super.initState();
    _online = ConnectivityService.isOnline;
    _sub = ConnectivityService.onChanged.listen((value) {
      if (!mounted) return;
      final wasOffline = !_online;
      setState(() => _online = value);
      if (wasOffline && value) {
        _flashRestored();
      }
    });
  }

  void _flashRestored() {
    _restoreTimer?.cancel();
    setState(() => _showRestored = true);
    _restoreTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showRestored = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _restoreTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: SafeArea(
              bottom: false,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _showRestored
                    ? Container(
                        height: 24,
                        color: AppColors.successGreen,
                        alignment: Alignment.center,
                        child: Text(
                          'Back online',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      )
                    : const SizedBox(height: 0, width: double.infinity),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
