import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/messaging_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Pops a bottom sheet that lets the current user send a first message
/// to [otherUserId]. On send it calls MessagingService.createConversation
/// (or reuses an existing conversation between the pair), navigates to
/// the chat screen, and pops itself. Shared by:
///   - member_directory_screen → "Message" tap on a profile
///   - home_screen → "Say hi" tap on a friend suggestion card
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
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: widget.otherUserId,
        otherUserName: widget.otherUserName,
        firstMessage: body,
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
            'Could not send request. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final firstName = widget.otherUserName.split(' ').first;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              'Send a message request',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'To ${widget.otherUserName}. They\'ll see it in their Requests inbox and can accept or decline.',
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.65),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color.fromRGBO(26, 26, 46, 0.06),
                ),
              ),
              child: TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Hi $firstName…',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.45),
                    fontSize: 14.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 16),
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
                  onPressed: _sending || _controller.text.trim().isEmpty
                      ? null
                      : _send,
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
                          'Send request',
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
      ),
    );
  }
}
