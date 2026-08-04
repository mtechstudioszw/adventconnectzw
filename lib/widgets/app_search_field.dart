import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';

/// The one search control in the app.
///
/// There were two. New chat / find friends used a flat pill —
/// `palette.cardMuted`, a hairline divider border, a muted glyph, no
/// shadow. The main search screen used something else entirely: a rounded
/// rectangle that lit up with a primary-blue ring and lifted on a shadow
/// when focused, with the glyph tweening to the accent colour alongside it.
///
/// Both were defensible on their own. Together they meant the same act —
/// typing to find something — looked like two different features depending
/// on which screen you happened to be standing in, which is the opposite of
/// what a premium app feels like. The founder's call (4 Aug 2026) is that
/// the chat one is the house style.
///
/// So this is that pill, and the main search screen renders it.
///
/// New chat / find friends deliberately still has its own private
/// `_SearchField` — the founder asked for chat to be left alone, and it
/// already looks right. This widget is a faithful copy of that design, so
/// adopting it there later is a no-op change whenever someone touches that
/// screen for another reason. Until then, keep the two in step by hand: if
/// you restyle one, restyle the other.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
    this.onClear,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String> onChanged;

  /// Shown as a trailing ✕ once there is text. When null the field simply
  /// clears the controller and reports the empty string.
  final VoidCallback? onClear;

  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.cardMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search, size: 19, color: palette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.text,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: palette.textMuted,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // ValueListenableBuilder so the ✕ appears on the first keystroke
          // without the host screen needing a setState for it. The old main
          // search screen called setState on every change purely to keep
          // this button in sync, which rebuilt the whole results list.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox(width: 12);
              return IconButton(
                tooltip: 'Clear search',
                icon: Icon(Icons.close, size: 18, color: palette.textMuted),
                splashRadius: 18,
                onPressed: () {
                  if (onClear != null) {
                    onClear!();
                    return;
                  }
                  controller.clear();
                  onChanged('');
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
