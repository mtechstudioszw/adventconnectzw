import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/call_model.dart';
import '../../screens/calls/call_screen.dart' show showMicrophoneDeniedDialog;
import '../../services/calls/call_config.dart';
import '../../services/calls/call_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Placing a call, from anywhere in the app.
///
/// ## Why this is one function and not a line at each call site
///
/// There are four places a call can start — a profile, a chat header, a
/// group's info screen, the call log — and each one has to do the same
/// six things: check the feature is on, ask for the microphone at the
/// right moment, handle a refusal the server wrote, handle a permanent
/// permission denial, avoid double-tapping into two calls, and NOT
/// navigate (a listener in main.dart owns that). Four copies of that is
/// four chances to get one of them wrong, and the one most likely to be
/// dropped is the microphone dialog — which fails silently and makes
/// every call from that entry point mute.
///
/// So: entry points render a button, and call this.
class CallActions {
  CallActions._();

  /// Ring one person. Returns true if a call was actually placed.
  ///
  /// Never throws. Everything the member needs to be told is shown from
  /// here, because the refusal text is written server-side and is
  /// deliberately identical for "they blocked you", "their privacy
  /// setting says no" and "that account is gone" — reconstructing a more
  /// specific message at the call site would leak exactly what the
  /// server took care not to say.
  static Future<bool> callUser(
    BuildContext context, {
    required String userId,
    required String displayName,
    String? photoUrl,
    String? conversationId,
  }) async {
    if (!await _preflight(context)) return false;
    try {
      await CallService.startDirect(
        userId: userId,
        displayName: displayName,
        photoUrl: photoUrl,
        conversationId: conversationId,
      );
      return true;
    } on MicrophoneDenied catch (e) {
      if (context.mounted) {
        await showMicrophoneDeniedDialog(context, permanently: e.permanently);
      }
      return false;
    } on CallFailure catch (e) {
      if (context.mounted) _showFailure(context, e);
      return false;
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Could not start the call. Please try again.');
      }
      return false;
    }
  }

  /// Start — or join — the call for a group conversation.
  static Future<bool> callGroup(
    BuildContext context, {
    required String conversationId,
    required String groupName,
    String? photoUrl,
  }) async {
    if (!await _preflight(context)) return false;
    try {
      await CallService.startGroup(
        conversationId: conversationId,
        groupName: groupName,
        photoUrl: photoUrl,
      );
      return true;
    } on MicrophoneDenied catch (e) {
      if (context.mounted) {
        await showMicrophoneDeniedDialog(context, permanently: e.permanently);
      }
      return false;
    } on CallFailure catch (e) {
      if (context.mounted) _showFailure(context, e);
      return false;
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Could not start the call. Please try again.');
      }
      return false;
    }
  }

  static Future<bool> _preflight(BuildContext context) async {
    // The server's master switch, so calling can be taken down without
    // shipping a build if TURN costs spike or a bug lands. Refreshed
    // rather than trusted from launch — a member who has had the app
    // open for six hours would otherwise still be working from the
    // config as it was at breakfast.
    if (!CallConfig.isLoaded) await CallConfig.refresh();
    if (!CallConfig.enabled) {
      if (context.mounted) {
        _snack(context, 'Calling is temporarily unavailable.');
      }
      return false;
    }
    if (CallService.isBusy) {
      if (context.mounted) _snack(context, 'You are already on a call.');
      return false;
    }
    return true;
  }

  static void _showFailure(BuildContext context, CallFailure failure) {
    // A quota is worth a dialog: it has a cause and a remedy, and a
    // SnackBar that vanishes in three seconds is not where someone
    // learns they are out of minutes for the day.
    if (failure.isQuota) {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Call limit reached', style: AppTextStyles.titleMedium),
            content: Text(failure.message, style: AppTextStyles.bodyMedium),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    _snack(context, failure.message);
  }

  static void _snack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.darkNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }
}

/// A round call button that disables itself while a call is live.
///
/// The disabled state matters more than it looks: without it, tapping
/// call from a chat header during an existing call fires a second
/// `call_start`, which the server refuses with ALREADY_IN_CALL — a
/// refusal the member reads as the button being broken.
class CallIconButton extends StatelessWidget {
  const CallIconButton({
    super.key,
    required this.onTap,
    this.size = 40,
    this.tooltip = 'Voice call',
  });

  final Future<void> Function() onTap;
  final double size;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: CallService.state,
      builder: (context, state, _) {
        final busy = state.phase.isLive;
        return Tooltip(
          message: busy ? 'Already on a call' : tooltip,
          child: Semantics(
            button: true,
            enabled: !busy,
            label: tooltip,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : () => unawaited(onTap()),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    Icons.call_rounded,
                    size: size * 0.5,
                    color: busy
                        ? AppColors.textMuted
                        : AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
