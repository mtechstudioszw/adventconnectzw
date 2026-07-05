import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Full-screen "couldn't load" state with a Try again button — YouTube-style.
///
/// The copy adapts to connectivity: an explicit "you're offline" when the
/// device has no connection, otherwise a generic failure. Drop this into a
/// screen's error branch (`if (_error != null) return ConnectionErrorView(
/// onRetry: _load);`) so a failed load never dead-ends on a blank page or an
/// endless spinner.
class ConnectionErrorView extends StatelessWidget {
  const ConnectionErrorView({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;

  /// Overrides the auto-chosen message when a screen wants something specific.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final offline = !ConnectivityService.isOnline;
    final title = offline ? 'No connection' : "Couldn't load";
    final body = message ??
        (offline
            ? 'Check your internet connection and try again.'
            : 'Something went wrong. Please try again.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
              size: 48,
              color: context.palette.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: const BorderSide(color: AppColors.primaryBlue),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
