import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/maintenance_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// The blocking screen shown while maintenance is on (#22).
///
/// Its job is to explain, not to enforce — enforcement is the database
/// trigger from `patch_187`, which refuses every content write regardless of
/// what any client thinks. So this screen is free to be calm and useful
/// rather than defensive.
///
/// It polls, so the app comes back on its own when maintenance ends. Nobody
/// should have to guess when to try again, and "force quit and reopen" is
/// not an instruction a premium app gives.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.autoPoll = true});

  /// False in tests — the timer otherwise reaches Supabase forever.
  final bool autoPoll;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPoll) {
      // 20s: often enough to feel responsive when it ends, rare enough that
      // a few hundred phones sitting on this screen are not a load problem
      // for the very server that is being worked on.
      _poll = Timer.periodic(const Duration(seconds: 20), (_) => _recheck());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _recheck() async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    final state = await MaintenanceService.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!state.active) {
      _poll?.cancel();
      context.goNamed('splash');
    }
  }

  String? _backWhen() {
    final ends = MaintenanceService.last.endsAt?.toLocal();
    if (ends == null) return null;
    if (ends.isBefore(DateTime.now())) return null;
    final hh = ends.hour.toString().padLeft(2, '0');
    final mm = ends.minute.toString().padLeft(2, '0');
    final sameDay = DateUtils.isSameDay(ends, DateTime.now());
    return sameDay
        ? 'Expected back around $hh:$mm.'
        : 'Expected back ${ends.day}/${ends.month} around $hh:$mm.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final backWhen = _backWhen();

    return PopScope(
      // There is nowhere to go back to. Leaving this screen would land on a
      // shell whose every action is being refused by the server.
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.scaffoldBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.build_rounded,
                      size: 42,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Back shortly',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: palette.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    MaintenanceService.last.message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.textMuted,
                      height: 1.5,
                    ),
                  ),
                  if (backWhen != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      backWhen,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _checking ? null : _recheck,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _checking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Check again',
                              style: AppTextStyles.labelLarge
                                  .copyWith(color: AppColors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    // Says what the screen is actually doing, so nobody sits
                    // there tapping.
                    'This screen checks by itself every few seconds.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption
                        .copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
