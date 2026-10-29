import 'package:flutter/material.dart';

import '../../services/follow_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// "Follow back" for someone who follows you — on their follow
/// notification and in your Followers list (owner, 28 Oct 2026).
///
/// Reads [FollowService.followingIds], so once you follow back it reads
/// "Following" everywhere at once. Renders nothing until that set is
/// loaded rather than guess — a "Follow back" on someone you already
/// follow would be a lie.
class FollowBackButton extends StatefulWidget {
  const FollowBackButton({super.key, required this.userId, this.name});

  final String userId;

  /// For the refusal message; first name is enough.
  final String? name;

  @override
  State<FollowBackButton> createState() => _FollowBackButtonState();
}

class _FollowBackButtonState extends State<FollowBackButton> {
  bool _busy = false;
  FollowState? _result;

  Future<void> _follow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final state = await FollowService.follow(widget.userId);
      if (mounted) setState(() => _result = state);
    } on FollowNotAllowed {
      _toast("${widget.name ?? 'They'} isn't taking followers.");
    } catch (_) {
      _toast("Couldn't follow back. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>?>(
      valueListenable: FollowService.followingIds,
      builder: (context, ids, _) {
        if (ids == null && _result == null) return const SizedBox.shrink();
        final following = ids?.contains(widget.userId) ?? false;
        final palette = context.palette;
        if (following || _result != null) {
          final requested = _result == FollowState.requested;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                requested ? Icons.schedule_rounded : Icons.check_rounded,
                size: 16,
                color: palette.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                requested ? 'Requested' : 'Following',
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }
        return Material(
          color: AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: _busy ? null : _follow,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : Text(
                      'Follow back',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
