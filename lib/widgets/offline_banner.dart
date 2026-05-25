import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Facebook-style "no connection" strip. Slim grey bar that slides
/// down from under the status bar when the device drops offline,
/// slides back up when it reconnects. Doesn't overlap navigation,
/// doesn't grab focus, doesn't animate aggressively. The previous
/// dark-navy floating pill felt loud — this is invisible until it
/// matters and then quietly self-removes.
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
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _online
                    ? const SizedBox(height: 0, width: double.infinity)
                    : Container(
                        height: 22,
                        color: const Color(0xFF6B7280),
                        alignment: Alignment.center,
                        child: Text(
                          'No Internet Connection',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
