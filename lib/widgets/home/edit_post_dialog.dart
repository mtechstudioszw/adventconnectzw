import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Show the "Edit post" dialog. Returns the new body text, or null if
/// the user cancelled.
///
/// The controller lives inside the dialog's own StatefulWidget so it
/// is created in the dialog's element tree and disposed after the
/// dialog is removed from the tree — this avoids the
/// `_dependents.isEmpty` framework assertion that fires when a parent
/// disposes a TextEditingController while the TextField still has
/// inherited dependents.
Future<String?> showEditPostDialog(
  BuildContext context, {
  required String initialBody,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _EditPostDialog(initialBody: initialBody),
  );
}

class _EditPostDialog extends StatefulWidget {
  const _EditPostDialog({required this.initialBody});

  final String initialBody;

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Edit post',
        style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        // posts.body is CHECK (<= 2000) — patch_011. The composer that
        // creates a post has always enforced it; the dialog that edits one
        // never did, so an edit could only fail at save time.
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: AppTextStyles.buttonText.copyWith(
              color: context.palette.text,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
