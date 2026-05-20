import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/messaging_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// One-tap "say hello" sheet. We no longer ask the user to type a
/// message before they can start a chat — Facebook Messenger doesn't
/// either, and the modal felt like an extra wall between users.
/// Tapping the primary button creates (or reuses) the conversation
/// with a friendly default opener, then opens the chat where the
/// user can keep typing normally.
Future<void> showStartConversationSheet(
  BuildContext context, {
  required String otherUserId,
  required String otherUserName,
  String source = 'direct',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _StartConversationSheet(
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      source: source,
    ),
  );
}

class _StartConversationSheet extends StatefulWidget {
  const _StartConversationSheet({
    required this.otherUserId,
    required this.otherUserName,
    required this.source,
  });

  final String otherUserId;
  final String otherUserName;
  final String source;

  @override
  State<_StartConversationSheet> createState() =>
      _StartConversationSheetState();
}

class _StartConversationSheetState extends State<_StartConversationSheet> {
  bool _sending = false;

  Future<void> _start() async {
    if (_sending) return;
    setState(() => _sending = true);
    final firstName = widget.otherUserName.split(' ').first;
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: widget.otherUserId,
        otherUserName: widget.otherUserName,
        firstMessage: 'Hi $firstName 👋',
        source: widget.source,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await context.pushNamed(
        'chat',
        pathParameters: {'id': convo.id},
        extra: convo,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not start chat. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.otherUserName.split(' ').first;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(26, 26, 46, 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Start a chat',
            style: AppTextStyles.titleLarge.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'We\'ll open Advent Chat with $firstName. If you aren\'t '
            'friends yet, they\'ll see it in their Requests inbox.',
            style: AppTextStyles.bodySmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _sending ? null : _start,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(
                        'Open chat',
                        style: AppTextStyles.buttonText.copyWith(
                          color: AppColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
