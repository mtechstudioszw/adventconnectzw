import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../models/story_model.dart';
import '../../services/feed_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';

/// Opens the "write a post" bottom sheet. Resolves to the freshly
/// created Post or null if the user cancelled.
Future<Post?> showPostComposer(BuildContext context) {
  return showModalBottomSheet<Post>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _PostComposer(),
  );
}

/// Opens the "share a story" bottom sheet. Resolves to the freshly
/// created Story or null if the user cancelled.
Future<Story?> showStoryComposer(BuildContext context) {
  return showModalBottomSheet<Story>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _StoryComposer(),
  );
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
  PostVisibility _visibility = PostVisibility.public;

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
        visibility: _visibility,
      );
      if (!mounted) return;
      Navigator.of(context).pop(post);
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

  void _toggleVisibility() {
    setState(() {
      _visibility = _visibility == PostVisibility.public
          ? PostVisibility.friendsOnly
          : PostVisibility.public;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final hasContent = _controller.text.trim().isNotEmpty ||
        (_imageUrl != null && _imageUrl!.isNotEmpty);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
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
                  const SizedBox(width: 10),
                  _VisibilityPill(
                    visibility: _visibility,
                    onTap: _toggleVisibility,
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
                  color: context.palette.inputFill,
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
                        CachedImage(_imageUrl!, fit: BoxFit.cover),
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
      ),
    );
  }
}

class _VisibilityPill extends StatelessWidget {
  const _VisibilityPill({required this.visibility, required this.onTap});

  final PostVisibility visibility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility == PostVisibility.public;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPublic ? Icons.public : Icons.people_alt_outlined,
                size: 12,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 5),
              Text(
                isPublic ? 'Public' : 'Friends',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.swap_horiz,
                size: 12,
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
  bool _pickerLaunched = false;

  @override
  void initState() {
    super.initState();
    // Stories require an image, so launch the picker immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_pickerLaunched) {
        _pickerLaunched = true;
        _pickImage();
      }
    });
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
      Navigator.of(context).pop(story);
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
    // Use the safe screen height minus the keyboard so the sheet
    // doesn't overlap the caption field while typing.
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height - media.padding.top - 24;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          decoration: BoxDecoration(
            color: context.palette.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(26, 26, 46, 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
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
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_uploading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          )
                        else if (_mediaUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AspectRatio(
                              // 4:5 keeps the preview tall enough to feel
                              // like a story but short enough that the
                              // caption + keyboard still fit on most
                              // phones without scrolling.
                              aspectRatio: 4 / 5,
                              child: CachedImage(
                                _mediaUrl!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: context.palette.inputFill,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  const Color.fromRGBO(26, 26, 46, 0.06),
                            ),
                          ),
                          child: TextField(
                            controller: _caption,
                            minLines: 1,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                            style: AppTextStyles.bodyMedium
                                .copyWith(fontSize: 14.5),
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
                            _mediaUrl == null
                                ? 'Choose a photo'
                                : 'Replace photo',
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
