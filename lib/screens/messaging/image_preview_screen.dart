import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/motion/pressable.dart';

/// Full-screen "check this before it goes" step for an outgoing photo.
///
/// Picking a photo used to send it the instant the picker closed — no
/// preview, no caption, and no way to back out of the wrong photo. That is
/// the one place a messaging app cannot afford to be fast, because the
/// mistake is public and permanent.
///
/// Returns the caption on send (empty string for no caption), or null if the
/// user backed out — so the caller can tell "send with no caption" apart from
/// "cancelled", which a plain empty string could not.
class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({
    super.key,
    required this.bytes,
    required this.recipientLabel,
  });

  final Uint8List bytes;

  /// Who this is going to, shown on the send button's row — the same
  /// reassurance WhatsApp gives you before you commit.
  final String recipientLabel;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  final _caption = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _caption.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() => Navigator.of(context).pop(_caption.text.trim());

  @override
  Widget build(BuildContext context) {
    // Committed single-theme surface: a photo is judged against black in
    // every app that handles photos, and a light chrome here would tint how
    // the image reads.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
                child: Row(
                  children: [
                    _RoundButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text(
                      'Send photo',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  // contain, never cover: this is the last look before it
                  // sends, so it must show the whole frame including any
                  // edge the sender might want to reconsider.
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.memory(widget.bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const SizedBox(width: 14),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Icon(
                                Icons.photo_size_select_actual_outlined,
                                size: 18,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _caption,
                                focusNode: _focus,
                                maxLines: null,
                                minLines: 1,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.white,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Add a caption…',
                                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 14,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Pressable(
                      onTap: _send,
                      pressedScale: 0.9,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue.withValues(
                                alpha: 0.45,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: AppColors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'To ${widget.recipientLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.white, size: 21),
      ),
    );
  }
}
