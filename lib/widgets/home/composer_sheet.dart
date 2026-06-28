import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../models/story_model.dart';
import '../../services/feed_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../cached_image.dart';
import 'story_text_style.dart';

/// Opens the "write a post" bottom sheet. Resolves to the freshly
/// created Post or null if the user cancelled.
Future<Post?> showPostComposer(BuildContext context, {String? churchId}) {
  return showModalBottomSheet<Post>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PostComposer(churchId: churchId),
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
  const _PostComposer({this.churchId});

  /// When set, the post is published as a church update (shows the church's
  /// name + gold tick in the feed).
  final String? churchId;

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
        churchId: widget.churchId,
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
                    color: context.palette.divider,
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
                                  : context.palette.textMuted,
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
                  border: Border.all(color: context.palette.divider),
                ),
                child: TextField(
                  controller: _controller,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: true,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 15,
                    color: context.palette.text,
                  ),
                  decoration: InputDecoration(
                    hintText: 'What\'s on your mind today?',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
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
  final _statusText = TextEditingController();
  String? _mediaUrl;
  bool _uploading = false;
  bool _publishing = false;
  // Text status (WhatsApp-style). Defaults ON so the user can just type;
  // tapping the photo button switches to an image story.
  bool _textMode = true;
  int _bgIndex = 0;
  int _fontIndex = 0;
  static const List<int> _bgColors = [
    0xFF1565C0, // brand blue
    0xFF0D1B3E, // navy
    0xFF2E7D32, // green
    0xFFC8A951, // gold
    0xFF6A1B9A, // purple
    0xFFD32F2F, // red
    0xFF00695C, // teal
  ];

  @override
  void dispose() {
    _caption.dispose();
    _statusText.dispose();
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
        // A chosen photo switches the composer to image mode.
        if (url != null) _textMode = false;
      });
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

  bool get _canShare => _textMode
      ? _statusText.text.trim().isNotEmpty
      : (_mediaUrl != null && _mediaUrl!.isNotEmpty);

  Future<void> _publish() async {
    if (!_canShare) return;
    setState(() => _publishing = true);
    try {
      final story = _textMode
          ? await FeedService.createStory(
              kind: 'text',
              textContent: _statusText.text.trim(),
              backgroundColor:
                  '#${_bgColors[_bgIndex].toRadixString(16).substring(2)}',
              textFont: kStoryFontKeys[_fontIndex],
            )
          : await FeedService.createStory(
              mediaUrl: _mediaUrl!,
              caption:
                  _caption.text.trim().isEmpty ? null : _caption.text.trim(),
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

Color _storyTextColor(int bgArgb) {
    final r = (bgArgb >> 16) & 0xFF;
    final g = (bgArgb >> 8) & 0xFF;
    final b = bgArgb & 0xFF;
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.5 ? Colors.black87 : AppColors.white;
  }

  @override
  Widget build(BuildContext context) {
    // Use the safe screen height minus the keyboard so the sheet
    // doesn't overlap the caption field while typing.
    final media = MediaQuery.of(context);
    // Text status fills the WHOLE screen (WhatsApp-style) so the chosen
    // colour covers everything — no home screen showing through above the
    // sheet (the "white space" the tester saw). Photo mode stays a sheet.
    final maxSheetHeight = _textMode
        ? media.size.height - media.viewInsets.bottom
        : media.size.height - media.padding.top - 24;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxSheetHeight,
          minHeight: _textMode ? maxSheetHeight : 0,
        ),
        child: Container(
          decoration: BoxDecoration(
            // In text-status mode the WHOLE sheet is the chosen colour
            // (WhatsApp-style) so the white text always shows — there's no
            // white card behind it.
            color: _textMode
                ? Color(_bgColors[_bgIndex])
                : context.palette.sheet,
            borderRadius: _textMode
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: _textMode,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.divider,
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
                          color: _textMode ? AppColors.white : null,
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
                              onPressed: _canShare ? _publish : null,
                              child: Text(
                                'Share',
                                style: AppTextStyles.buttonText.copyWith(
                                  color: _textMode
                                      ? AppColors.white.withValues(
                                          alpha: _canShare ? 1 : 0.5)
                                      : (_canShare
                                          ? AppColors.primaryBlue
                                          : context.palette.textMuted),
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
                        if (_textMode) ...[
                          // ---- TEXT STATUS editor (full-screen, WhatsApp-style)
                          // The sheet itself is already the chosen colour, so
                          // the field is seamless (no inner card / white box).
                          // White text, picked font, centred.
                        ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 220),
                            child: Center(
                              child: Builder(builder: (context) {
                                final textCol = _storyTextColor(_bgColors[_bgIndex]);
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    inputDecorationTheme:
                                        const InputDecorationTheme(
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _statusText,
                                    autofocus: true,
                                    textAlign: TextAlign.center,
                                    minLines: 1,
                                    maxLines: null,
                                    maxLength: 700,
                                    keyboardType: TextInputType.multiline,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: storyFontStyle(
                                      kStoryFontKeys[_fontIndex],
                                      color: textCol,
                                      fontSize: 30,
                                    ),
                                    cursorColor: textCol,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      filled: false,
                                      counterText: '',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      hintText: 'Type a status…',
                                      hintStyle: TextStyle(
                                          color: textCol.withValues(alpha: 0.55),
                                          fontSize: 24),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Font picker.
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: kStoryFontKeys.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () => setState(() => _fontIndex = i),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 16),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.white.withValues(
                                        alpha: _fontIndex == i ? 0.25 : 0.10),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: _fontIndex == i
                                          ? AppColors.white
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(
                                    kStoryFontLabels[i],
                                    style: storyFontStyle(
                                      kStoryFontKeys[i],
                                      color: AppColors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Background colour picker.
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _bgColors.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () => setState(() => _bgIndex = i),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: Color(_bgColors[i]),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _bgIndex == i
                                          ? AppColors.primaryBlue
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // White-on-translucent chip so the "use a photo"
                          // option is visible on EVERY background colour (it
                          // used brand blue, which vanished on the blue/navy
                          // backgrounds — users thought the option was gone).
                          Center(
                            child: TextButton.icon(
                              onPressed: _uploading ? null : _pickImage,
                              style: TextButton.styleFrom(
                                backgroundColor:
                                    AppColors.white.withValues(alpha: 0.18),
                                foregroundColor: AppColors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                      color: AppColors.white
                                          .withValues(alpha: 0.4)),
                                ),
                              ),
                              icon: const Icon(Icons.image_outlined,
                                  color: AppColors.white, size: 20),
                              label: Text('Use a photo instead',
                                  style: AppTextStyles.buttonText.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  )),
                            ),
                          ),
                        ] else ...[
                          // ---- PHOTO STATUS ----
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
                                aspectRatio: 4 / 5,
                                child: CachedImage(_mediaUrl!,
                                    fit: BoxFit.cover),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: context.palette.inputFill,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: context.palette.divider),
                            ),
                            child: TextField(
                              controller: _caption,
                              minLines: 1,
                              maxLines: 3,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 14.5,
                                color: context.palette.text,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Add a caption (optional)',
                                hintStyle: AppTextStyles.bodyMedium.copyWith(
                                  color: context.palette.textMuted,
                                  fontSize: 14.5,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(14),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _uploading ? null : _pickImage,
                                icon: const Icon(Icons.image_outlined,
                                    color: AppColors.primaryBlue, size: 20),
                                label: Text('Replace photo',
                                    style: AppTextStyles.buttonText.copyWith(
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    )),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _textMode = true),
                                icon: const Icon(Icons.text_fields,
                                    color: AppColors.primaryBlue, size: 20),
                                label: Text('Text',
                                    style: AppTextStyles.buttonText.copyWith(
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    )),
                              ),
                            ],
                          ),
                        ],
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
