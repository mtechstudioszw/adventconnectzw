import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Calm connectivity overlay (29 Oct 2026). Going offline slides in a
/// small navy "Offline · showing what's saved" pill for a few seconds and
/// then gets out of the way; coming back online shows nothing. Screens keep
/// showing their saved content, and per-screen notices speak up only where
/// something actually failed to load.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _showOffline = false;
  StreamSubscription<bool>? _sub;
  Timer? _hideTimer;

  /// How long the "Offline" pill stays before it gets out of the way.
  static const _visibleFor = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _sub = ConnectivityService.onChanged.listen((online) {
      if (!mounted) return;
      _hideTimer?.cancel();
      // Calm by design (owner, 29 Oct 2026): going offline shows a small
      // pill for a few seconds, then nothing — the screens keep showing
      // what is saved. Coming back online shows nothing at all; the green
      // "Back online" bar this replaced broke the no-green-backgrounds
      // rule and interrupted every reconnect on a patchy network.
      setState(() => _showOffline = !online);
      if (!online) {
        _hideTimer = Timer(_visibleFor, () {
          if (mounted) setState(() => _showOffline = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
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
              child: Align(
                alignment: Alignment.topCenter,
                child: AnimatedSlide(
                  offset: _showOffline ? Offset.zero : const Offset(0, -1.5),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _showOffline ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.darkNavy.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.darkNavy.withValues(alpha: 0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 14,
                            color: AppColors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Offline · showing what's saved",
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
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
