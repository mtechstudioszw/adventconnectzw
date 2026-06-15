import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../models/advent_news_model.dart';
import '../../services/advent_news_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

/// In-app posting flow for Advent News. Open to any signed-in
/// member (patch_030) — the gate on the Advent News screen is now
/// just "are you logged in?" and RLS enforces the same.
class PostAdventNewsScreen extends StatefulWidget {
  const PostAdventNewsScreen({super.key, this.existing});

  /// When supplied, the screen runs in edit mode — fields are
  /// pre-filled and Publish calls [AdventNewsService.updateNews].
  final AdventNews? existing;

  @override
  State<PostAdventNewsScreen> createState() => _PostAdventNewsScreenState();
}

class _PostAdventNewsScreenState extends State<PostAdventNewsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _bodyController = TextEditingController();
  final _sourceUrlController = TextEditingController();
  final _sourceLabelController = TextEditingController();

  NewsCategory _category = NewsCategory.general;
  String? _coverPhotoUrl;
  bool _uploadingCover = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _titleController.text = ex.title;
      _summaryController.text = ex.summary;
      _bodyController.text = ex.body ?? '';
      _sourceUrlController.text = ex.sourceUrl ?? '';
      _sourceLabelController.text = ex.sourceLabel ?? '';
      _category = ex.category;
      _coverPhotoUrl = ex.coverPhotoUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _bodyController.dispose();
    _sourceUrlController.dispose();
    _sourceLabelController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    if (_uploadingCover) return;
    setState(() {
      _uploadingCover = true;
      _error = null;
    });
    try {
      // Reuse the cover-photo bucket — same dimensions / handling
      // as profile covers and event covers.
      final url = await StorageService.pickAndUploadCoverPhoto();
      if (!mounted) return;
      if (url != null) setState(() => _coverPhotoUrl = url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not upload cover photo. Try again.');
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _publish() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    // Dismiss the keyboard so it doesn't linger over the screen we return
    // to after posting.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      final result = _isEdit
          ? await AdventNewsService.updateNews(
              id: widget.existing!.id,
              title: _titleController.text,
              summary: _summaryController.text,
              body: _bodyController.text,
              coverPhotoUrl: _coverPhotoUrl,
              category: _category,
              sourceUrl: _sourceUrlController.text,
              sourceLabel: _sourceLabelController.text,
            )
          : await AdventNewsService.postNews(
              title: _titleController.text,
              summary: _summaryController.text,
              body: _bodyController.text,
              coverPhotoUrl: _coverPhotoUrl,
              category: _category,
              sourceUrl: _sourceUrlController.text,
              sourceLabel: _sourceLabelController.text,
            );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            _isEdit
                ? 'Story updated.'
                : 'Submitted for review — it\'ll appear on Advent News once an admin approves it.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      // Return a bool — the caller awaits pushNamed<bool>. Popping the
      // AdventNews object here threw a type-cast error on return (the
      // "error that flashes" + the screen jank / stuck back button).
      result; // referenced so the edit/update result isn't flagged unused
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. ${e is Exception ? '' : e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHero(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCoverPicker(),
                    const SizedBox(height: 16),
                    _buildFieldCard(
                      label: 'Headline',
                      child: TextFormField(
                        controller: _titleController,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.sentences,
                        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                        decoration: _filledDecoration(
                          icon: Icons.title,
                          hint: 'e.g. Solusi University graduation 2026',
                        ).copyWith(counterText: ''),
                        validator: (v) {
                          if ((v ?? '').trim().length < 4) {
                            return 'At least 4 characters';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFieldCard(
                      label: 'Summary',
                      helper:
                          'One-paragraph hook. Shown on home + on news cards.',
                      child: TextFormField(
                        controller: _summaryController,
                        maxLines: 3,
                        maxLength: 400,
                        textCapitalization: TextCapitalization.sentences,
                        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                        decoration: _filledDecoration(
                          icon: Icons.subject_outlined,
                          hint: 'A short hook that explains why it matters.',
                        ).copyWith(counterText: ''),
                        validator: (v) {
                          if ((v ?? '').trim().length < 10) {
                            return 'At least 10 characters';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFieldCard(
                      label: 'Full article (optional)',
                      helper:
                          'Long-form body shown on the article details screen.',
                      child: TextFormField(
                        controller: _bodyController,
                        maxLines: 10,
                        maxLength: 10000,
                        textCapitalization: TextCapitalization.sentences,
                        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                        decoration: _filledDecoration(
                          icon: Icons.article_outlined,
                          hint: 'The full story. Leave empty if the summary '
                              'is enough.',
                        ).copyWith(counterText: ''),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCategoryCard(),
                    const SizedBox(height: 12),
                    _buildFieldCard(
                      label: 'Source link (optional)',
                      helper: 'Outbound URL — opened in browser when readers '
                          'tap the source card.',
                      child: TextFormField(
                        controller: _sourceUrlController,
                        keyboardType: TextInputType.url,
                        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                        decoration: _filledDecoration(
                          icon: Icons.link,
                          hint: 'https://adventist.news/...',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFieldCard(
                      label: 'Source label (optional)',
                      helper: 'Short name for the source — e.g. "ANN", '
                          '"Solusi PR", "Conference press release".',
                      child: TextFormField(
                        controller: _sourceLabelController,
                        maxLength: 60,
                        style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                        decoration: _filledDecoration(
                          icon: Icons.tag,
                          hint: 'e.g. ANN',
                        ).copyWith(counterText: ''),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 22),
                    _buildPublishButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.canPop()
                        ? context.pop()
                        : context.goNamed('news'),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: AppColors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADMIN',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.goldAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isEdit ? 'Edit story' : 'Publish news',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isEdit
                            ? 'Refine your story — readers will see the new version.'
                            : 'Editorial coverage of the SDA community in Zimbabwe.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPicker() {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _uploadingCover ? null : _pickCover,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty)
                CachedImage(_coverPhotoUrl!, fit: BoxFit.cover)
              else
                const DecoratedBox(
                  decoration:
                      BoxDecoration(gradient: AppColors.appBarGradient),
                ),
              if (_coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_uploadingCover)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.white),
                )
              else if (_coverPhotoUrl == null || _coverPhotoUrl!.isEmpty)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_outlined,
                        color: AppColors.white.withValues(alpha: 0.85),
                        size: 36,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to add a cover photo',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '16:9 recommended',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit,
                            color: AppColors.white, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'Change',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
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
    );
  }

  Widget _buildFieldCard({
    required String label,
    required Widget child,
    String? helper,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 4),
            Text(
              helper,
              style: AppTextStyles.bodySmall.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.55),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildCategoryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CATEGORY',
            style: AppTextStyles.labelSmall.copyWith(
              color: const Color.fromRGBO(26, 26, 46, 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in NewsCategory.values)
                _CategoryChip(
                  label: c.label,
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPublishButton() {
    return Opacity(
      opacity: _saving ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _saving ? null : _publish,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.white,
                        ),
                      )
                    : Text(
                        _isEdit ? 'Save changes' : 'Publish story',
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _filledDecoration({
    required IconData icon,
    required String hint,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      prefixIconConstraints:
          const BoxConstraints(minWidth: 40, minHeight: 40),
      filled: true,
      fillColor: AppColors.lightGrey,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppColors.primaryBlue,
          width: 1.2,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryBlue : AppColors.lightGrey,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : const Color.fromRGBO(26, 26, 46, 0.08),
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: selected ? AppColors.white : AppColors.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 24);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 24,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
