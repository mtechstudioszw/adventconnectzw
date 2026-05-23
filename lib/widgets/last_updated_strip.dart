import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Compact "Updated 5 minutes ago" strip with a refresh icon, shown at
/// the top of cache-backed list tabs (Events, Jobs, Marketplace,
/// Churches). Lets users see how fresh the content they're looking at
/// is, especially useful when they're offline and seeing yesterday's
/// snapshot.
class LastUpdatedStrip extends StatelessWidget {
  const LastUpdatedStrip({
    super.key,
    required this.timestamp,
    required this.onRefresh,
    this.isOnline = true,
  });

  /// When the underlying cache was last written (network success). Null
  /// means we've never cached the list — the strip won't render in that
  /// case so brand-new installs don't show a misleading message.
  final DateTime? timestamp;
  final VoidCallback onRefresh;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final ts = timestamp;
    if (ts == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.update : Icons.cloud_off_rounded,
            size: 14,
            color: const Color.fromRGBO(26, 26, 46, 0.5),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isOnline
                  ? 'Updated ${_relative(ts)}'
                  : 'Offline · cached ${_relative(ts)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.55),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            onTap: onRefresh,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.refresh,
                size: 14,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _relative(DateTime when) {
    final diff = DateTime.now().toUtc().difference(when.toUtc());
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
