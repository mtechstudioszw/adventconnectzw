import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../models/story_model.dart';
import '../../services/feed_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The bottom-sheet the floating "+" plus-button opens. Lets the user
/// choose between writing a post or sharing a 24h story, and then
/// drops them into the matching composer. On success the parent gets
/// the freshly-created Post or Story so it can prepend it to its
/// in-memory feed without a network round-trip.
class ComposerResult {
  const ComposerResult({this.post, this.story});

  final Post? post;
  final Story? story;

  bool get isPost => post != null;
  bool get isStory => story != null;
}

Future<ComposerResult?> showComposerSheet(BuildContext context) {
  return showModalBottomSheet<ComposerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _ComposerSheet(),
  );
}

class _ComposerSheet extends StatelessWidget {
  const _ComposerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              'Share with the community',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick how you want to share what\'s on your mind today.',
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.65),
              ),
            ),
            const SizedBox(height: 18),
            _ChoiceTile(
              icon: Icons.edit_outlined,
              title: 'Write a post',
              subtitle: 'Stays on the feed for everyone to read and react.',
              onTap: () async {
                Navigator.of(context).pop();
                final result = await _openPostComposer(context);
                if (result != null && context.mounted) {
                  Navigator.of(context).pop(result);
                }
              },
            ),
            const SizedBox(height: 12),
            _ChoiceTile(
              icon: Icons.auto_awesome_outlined,
              title: 'Share a story',
              subtitle: 'A photo + caption that disappears in 24 hours.',
              onTap: () async {
                Navigator.of(context).pop();
                final result = await _openStoryComposer(context);
                if (result != null && context.mounted) {
                  Navigator.of(context).pop(result);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<ComposerResult?> _openPostComposer(BuildContext context) {
    return showModalBottomSheet<ComposerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PostComposer(),
    );
  }

  Future<ComposerResult?> _openStoryComposer(BuildContext context) {
    return showModalBottomSheet<ComposerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _StoryComposer(),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.lightGrey,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color.fromRGBO(26, 26, 46, 0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.6),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================================================================
//  Post composer
// ===================================================================
class _PostComposer extends StatefulWidget {
  const _PostComposer();

  @override
  State<_PostComposer> createState() => _PostComposerState();
}

class _PostComposerState extends State<_PostComposer> {
  final _controller = TextEditingController();
  String? _imageUrl;
  bool _uploadingImage = false;
  bool _publishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_uploadingImage || _publishing) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await StorageService.pickAndUploadPostPhoto();
      if (!mounted) return;
      setState(() {
        _imageUrl = url ?? _imageUrl;
        _uploadingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo upload failed. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _publish() async {
    final body = _controller.text.trim();
    if (body.isEmpty && (_imageUrl == null || _imageUrl!.isEmpty)) return;
    setState(() => _publishing = true);
    try {
      final post = await FeedService.createPost(
        body: body.isEmpty ? null : body,
        imageUrl: _imageUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ComposerResult(post: post));
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not publish. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final hasContent = _controller.text.trim().isNotEmpty ||
        (_imageUrl != null && _imageUrl!.isNotEmpty);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'New post',
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                _publishing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.primaryBlue,
                        ),
                      )
                    : TextButton(
                        onPressed: hasContent ? _publish : null,
                        child: Text(
                          'Post',
                          style: AppTextStyles.buttonText.copyWith(
                            color: hasContent
                                ? AppColors.primaryBlue
                                : const Color.fromRGBO(26, 26, 46, 0.35),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 12),
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
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'What\'s on your mind today?',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: const Color.fromRGBO(26, 26, 46, 0.45),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(_imageUrl!, fit: BoxFit.cover),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => _imageUrl = null),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _uploadingImage ? null : _pickImage,
                  icon: _uploadingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryBlue,
                          ),
                        )
                      : const Icon(
                          Icons.image_outlined,
                          color: AppColors.primaryBlue,
                          size: 20,
                        ),
                  label: Text(
                    _imageUrl == null ? 'Add a photo' : 'Replace photo',
                    style: AppTextStyles.buttonText.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
//  Story composer
// ===================================================================
class _StoryComposer extends StatefulWidget {
  const _StoryComposer();

  @override
  State<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<_StoryComposer> {
  final _caption = TextEditingController();
  String? _mediaUrl;
  bool _uploading = false;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    // Stories require an image, so launch the picker immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final url = await StorageService.pickAndUploadStoryPhoto();
      if (!mounted) return;
      setState(() {
        _mediaUrl = url ?? _mediaUrl;
        _uploading = false;
      });
      // If the user cancelled the picker before adding anything, drop
      // the sheet — there's nothing to do.
      if (_mediaUrl == null && mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo upload failed. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _publish() async {
    if (_mediaUrl == null || _mediaUrl!.isEmpty) return;
    setState(() => _publishing = true);
    try {
      final story = await FeedService.createStory(
        mediaUrl: _mediaUrl!,
        caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(ComposerResult(story: story));
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not publish. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'New story',
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                _publishing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.primaryBlue,
                        ),
                      )
                    : TextButton(
                        onPressed: _mediaUrl == null ? null : _publish,
                        child: Text(
                          'Share',
                          style: AppTextStyles.buttonText.copyWith(
                            color: _mediaUrl == null
                                ? const Color.fromRGBO(26, 26, 46, 0.35)
                                : AppColors.primaryBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 12),
            if (_uploading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primaryBlue),
                ),
              )
            else if (_mediaUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Image.network(_mediaUrl!, fit: BoxFit.cover),
                ),
              )
            else
              const SizedBox(height: 0),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color.fromRGBO(26, 26, 46, 0.06),
                ),
              ),
              child: TextField(
                controller: _caption,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Add a caption (optional)',
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
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _uploading ? null : _pickImage,
              icon: const Icon(
                Icons.image_outlined,
                color: AppColors.primaryBlue,
                size: 20,
              ),
              label: Text(
                _mediaUrl == null ? 'Choose a photo' : 'Replace photo',
                style: AppTextStyles.buttonText.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
