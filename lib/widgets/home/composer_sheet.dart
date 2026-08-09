import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../motion/brand_spinner.dart';
import '../../models/church_model.dart';
import '../../models/post_model.dart';
import '../../models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/cache_service.dart';
import '../../services/church_service.dart';
import '../../services/feed_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../blurred_sheet.dart';
import '../cached_image.dart';
import '../preview_sheet.dart';
import '../user_avatar.dart';
import 'post_preview_sheet.dart';
import 'story_text_style.dart';

/// Opens the "write a post" bottom sheet. Resolves to the freshly
/// created Post or null if the user cancelled.
Future<Post?> showPostComposer(BuildContext context, {String? churchId}) {
  return showBlurredSheet<Post>(
    context: context,
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

class _PostComposerState extends State<_PostComposer>
    with SingleTickerProviderStateMixin {
  /// Matches the `posts_body_check` constraint in Supabase
  /// (`char_length(body) <= 2000`). Without this the insert simply failed
  /// with a generic "Could not publish", and because nothing was saved the
  /// member lost everything they'd typed.
  static const int _maxBody = 2000;

  /// Show the counter only once it's actually relevant.
  static const int _counterFrom = 1800;

  /// Cap on photos per post. The DB check allows 10; the product decision is
  /// 4, which is what fits a 2×2 grid without the card dominating the feed.
  static const int _maxPhotos = 4;

  final _controller = TextEditingController();
  final List<String> _photos = [];
  bool _uploadingImage = false;
  bool _publishing = false;
  PostVisibility _visibility = PostVisibility.public;
  Timer? _draftDebounce;

  /// True when [_restoreDraft] actually put something back. The autosave has
  /// always worked and has always been invisible, which means the one time it
  /// matters — you come back and your words are there — the member has no way
  /// to know it was the app that saved them rather than luck. Shown once, in
  /// the sheet, then it goes away when they type.
  bool _draftRestored = false;

  /// Drives the staggered reveal of the sheet's contents.
  ///
  /// The sheet itself already slides up; without this the whole form arrives
  /// as one solid block at the end of that slide, which is the difference
  /// between a surface that opens and a dialog that appears.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.entrance,
  );

  /// The header hairline only exists once there is something above it to
  /// separate from — a permanent line under a header that nothing has
  /// scrolled beneath is a border for its own sake.
  final _scroll = ScrollController();
  bool _scrolled = false;

  /// Church updates keep their own draft so a half-written church notice
  /// can't overwrite a half-written personal post.
  String get _draftKey =>
      'composer_draft_v1${widget.churchId == null ? '' : ':${widget.churchId}'}';

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    _controller.addListener(_onBodyChanged);
    _scroll.addListener(_onScroll);
    _entrance.forward();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _controller.removeListener(_onBodyChanged);
    _controller.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _entrance.dispose();
    super.dispose();
  }

  void _onScroll() {
    final next = _scroll.hasClients && _scroll.offset > 4;
    if (next != _scrolled) setState(() => _scrolled = next);
  }

  /// One step of the entrance stagger.
  Widget _step(int index, Widget child) {
    final start = (index * 0.10).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, 1.0, curve: AppMotion.easeOut),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, inner) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * 10),
          child: inner,
        ),
      ),
      child: child,
    );
  }

  /// Autosave is the real safety net, not the discard prompt.
  ///
  /// A modal sheet can go away in ways we don't control — swipe-down, an
  /// incoming call, the OS killing the app in the background. Persisting on
  /// every keystroke (debounced) means the text survives all of them, and
  /// the confirm dialog is just a courtesy on top.
  void _onBodyChanged() {
    setState(() {
      // The restored-draft note has done its job the moment they start
      // writing again. Leaving it up would be the app talking over them.
      _draftRestored = false;
    });
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  void _restoreDraft() {
    final raw = CacheService.readStringStale(_draftKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final body = (m['body'] as String?) ?? '';
      final photos = <String>[
        // 'images' is the current shape; 'image' is a single-photo draft
        // written before multi-photo landed.
        if (m['images'] is List)
          for (final u in m['images'] as List)
            if (u != null && u.toString().isNotEmpty) u.toString(),
        if (m['image'] is String && (m['image'] as String).isNotEmpty)
          m['image'] as String,
      ];
      if (body.isEmpty && photos.isEmpty) return;
      _controller.text = body;
      _photos
        ..clear()
        ..addAll(photos.take(_maxPhotos));
      _draftRestored = true;
    } catch (_) {
      // Corrupt draft — start clean rather than block the composer.
    }
  }

  void _saveDraft() {
    final body = _controller.text;
    if (body.trim().isEmpty && _photos.isEmpty) {
      unawaited(CacheService.deletePref(_draftKey));
      return;
    }
    unawaited(
      CacheService.writeString(
        _draftKey,
        jsonEncode({'body': body, 'images': _photos}),
      ),
    );
  }

  void _clearDraft() {
    _draftDebounce?.cancel();
    unawaited(CacheService.deletePref(_draftKey));
  }

  bool get _hasContent =>
      _controller.text.trim().isNotEmpty || _photos.isNotEmpty;

  /// Shows the post as the feed will render it, and publishes straight from
  /// there if the member is happy — so "check it, then send it" is two taps,
  /// not a round trip back through the composer.
  Future<void> _openPreview() async {
    // Dismiss the keyboard first: the preview is about seeing the whole card,
    // and half of it would otherwise be behind the keyboard.
    FocusScope.of(context).unfocus();
    final publish = await showPostPreview(
      context,
      body: _controller.text,
      photos: List<String>.of(_photos),
      visibility: _visibility,
    );
    if (!mounted || !publish) return;
    await _publish();
  }

  /// Confirms before throwing away work. Returns true if it's OK to close.
  Future<bool> _confirmDiscard() async {
    if (!_hasContent) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Keep this post?',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          "We've saved it as a draft — it'll be here when you come back.",
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: Text(
              'Discard',
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.red,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('keep'),
            child: Text(
              'Keep draft',
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.primaryBlue,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
    if (choice == 'discard') {
      _clearDraft();
      return true;
    }
    if (choice == 'keep') {
      _saveDraft();
      return true;
    }
    // Dismissed the dialog itself — stay in the composer.
    return false;
  }

  Future<void> _pickImage() async {
    if (_uploadingImage || _publishing) return;
    if (_photos.length >= _maxPhotos) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await StorageService.pickAndUploadPostPhoto();
      if (!mounted) return;
      setState(() {
        if (url != null && url.isNotEmpty && !_photos.contains(url)) {
          _photos.add(url);
        }
        _uploadingImage = false;
      });
      // Persist immediately — an uploaded photo is real work already spent.
      _saveDraft();
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
    if (body.isEmpty && _photos.isEmpty) return;
    setState(() => _publishing = true);
    try {
      final post = await FeedService.createPost(
        body: body.isEmpty ? null : body,
        imageUrls: _photos,
        visibility: _visibility,
        churchId: widget.churchId,
      );
      if (!mounted) return;
      // Only drop the draft once the insert actually succeeded — a failed
      // publish must leave the text exactly where it was.
      _clearDraft();
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

  /// Who will see this.
  ///
  /// It used to be a pill that swapped its own label on tap, which meant the
  /// only way to learn there were two audiences was to change the one you had
  /// already chosen. A menu shows both, says what each means, and marks the
  /// current one — the choice is legible before you make it.
  Future<void> _chooseVisibility() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final chosen = await showMenu<PostVisibility>(
      context: context,
      color: context.palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      position: RelativeRect.fromLTRB(
        origin.dx + 20,
        origin.dy + 96,
        origin.dx + box.size.width - 20,
        origin.dy + box.size.height,
      ),
      items: [
        for (final option in PostVisibility.values.take(2))
          PopupMenuItem<PostVisibility>(
            value: option,
            child: _VisibilityOption(
              option: option,
              selected: option == _visibility,
            ),
          ),
      ],
    );
    if (chosen != null && mounted) setState(() => _visibility = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.viewInsets.bottom;
    final hasContent = _hasContent;
    final palette = context.palette;
    final isChurch = widget.churchId != null;

    // A deliberate height instead of one that grows with the text.
    //
    // The old sheet was `mainAxisSize.min` around a scroll view, so it stood
    // up at the height of an empty field and then shoved itself taller on the
    // line that wrapped. Committing to a tall surface up front says "this is
    // a page to write on", and nothing under your thumb moves while you use
    // it. It still shrinks on a short screen, and the body scrolls.
    final maxHeight = media.size.height * 0.88 - bottom;

    return PopScope(
      // Intercept the back button so a half-written post asks first. Swipe-
      // to-dismiss is still allowed — the autosaved draft covers that path.
      canPop: !hasContent,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Resolve the navigator BEFORE awaiting, so we're not reaching
        // through a BuildContext that may be gone by the time the dialog
        // closes.
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: BoxDecoration(
              color: palette.sheet,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkNavy.withValues(alpha: 0.16),
                  blurRadius: 32,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),

                // ---- Header ------------------------------------------
                // Close, title, publish. The Post button used to sit inside
                // the identity row, sharing a line with the author's name and
                // the audience control — three unrelated jobs competing for
                // the same 360 pixels. The action belongs in the chrome.
                _step(
                  0,
                  _Header(
                    title: isChurch ? 'Church update' : 'New post',
                    onClose: () async {
                      final navigator = Navigator.of(context);
                      if (await _confirmDiscard()) navigator.pop();
                    },
                    action: _PostButton(
                      enabled: hasContent,
                      busy: _publishing,
                      onTap: _publish,
                    ),
                  ),
                ),

                // Appears only once something has scrolled under it.
                AnimatedOpacity(
                  duration: AppMotion.maybe(context, AppMotion.quick),
                  opacity: _scrolled ? 1 : 0,
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: palette.divider,
                  ),
                ),

                // ---- Body --------------------------------------------
                Flexible(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Who is about to say this, and to whom.
                        //
                        // Not decoration: the same sheet publishes AS A
                        // CHURCH when it is opened from a church page — a
                        // post that carries the church's name and gold tick
                        // into everyone's feed. Showing that before you write
                        // rather than after you publish is the difference
                        // between speaking for yourself and speaking for your
                        // congregation.
                        _step(
                          1,
                          _IdentityRow(
                            churchId: widget.churchId,
                            visibility: _visibility,
                            onChooseVisibility: _chooseVisibility,
                          ),
                        ),

                        if (_draftRestored) ...[
                          const SizedBox(height: 12),
                          _DraftRestoredNote(onDiscard: () {
                            _clearDraft();
                            setState(() {
                              _controller.clear();
                              _photos.clear();
                              _draftRestored = false;
                            });
                          }),
                        ],

                        const SizedBox(height: 6),

                        // Borderless. A boxed input inside a sheet reads as a
                        // form to be filled in; the composer should read as a
                        // page to write on, so the field IS the sheet.
                        _step(
                          2,
                          TextField(
                            controller: _controller,
                            minLines: 5,
                            maxLines: null,
                            // Enforced here so the member is stopped AT the
                            // limit, instead of the database rejecting the
                            // insert afterwards with an unexplained failure.
                            maxLength: _maxBody,
                            textCapitalization: TextCapitalization.sentences,
                            keyboardType: TextInputType.multiline,
                            autofocus: true,
                            // What you are writing is the most important thing
                            // on this sheet, so it is the largest thing on it.
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 18,
                              height: 1.5,
                              color: palette.text,
                            ),
                            // The counter lives on the toolbar. Two of them
                            // would disagree the moment one was wrong.
                            buildCounter:
                                (
                                  context, {
                                  required currentLength,
                                  required isFocused,
                                  required maxLength,
                                }) => null,
                            decoration: InputDecoration(
                              hintText: isChurch
                                  ? 'Share news with your church…'
                                  : "What's on your mind today?",
                              hintStyle: AppTextStyles.bodyMedium.copyWith(
                                color: palette.textMuted,
                                fontSize: 18,
                                height: 1.5,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),

                        // Growing into place rather than snapping: adding a
                        // photo is the one thing on this sheet that changes
                        // the layout underneath your hands.
                        AnimatedSize(
                          duration: AppMotion.maybe(
                            context,
                            AppMotion.standard,
                          ),
                          curve: AppMotion.easeOut,
                          alignment: Alignment.topCenter,
                          child: _photos.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: _PhotoGrid(
                                    photos: _photos,
                                    onRemove: (i) {
                                      setState(() => _photos.removeAt(i));
                                      _saveDraft();
                                    },
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // ---- Toolbar -----------------------------------------
                _step(
                  3,
                  _Toolbar(
                    photoCount: _photos.length,
                    maxPhotos: _maxPhotos,
                    uploading: _uploadingImage,
                    onPickPhoto: _uploadingImage || _photos.length >= _maxPhotos
                        ? null
                        : _pickImage,
                    onPreview: hasContent ? _openPreview : null,
                    used: _controller.text.length,
                    max: _maxBody,
                    showCounterFrom: _counterFrom,
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

/// The sheet's chrome: leave, what this is, publish.
///
/// A `Wrap` is deliberately NOT used here — this row must stay one line, so
/// each part is bounded instead: the close control is an icon (it does not
/// scale), the title is the only flexible thing and ellipsises, and the
/// action sizes to its own label. That is what keeps it safe at 2.5x text
/// scale on a 360px screen, which is exactly what `composer_sheet_test`
/// pumps.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onClose,
    required this.action,
  });

  final String title;
  final VoidCallback onClose;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 12),
      child: Row(
        children: [
          Material(
            color: palette.cardMuted,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLarge.copyWith(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: palette.text,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          action,
        ],
      ),
    );
  }
}

/// The composer's primary action. Deliberately the only filled control
/// on the sheet: everything else here is something you *might* do, and
/// this is the thing you came to do.
///
/// It animates between three states rather than swapping widgets, so the
/// moment a post becomes publishable the button fills in place — the
/// member sees "ready" instead of having to work it out from a colour
/// change on a text label.
class _PostButton extends StatelessWidget {
  const _PostButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = enabled && !busy;
    return AnimatedScale(
      // A small settle the instant the post becomes publishable. It costs
      // nothing and it is the moment worth marking.
      scale: live ? 1 : 0.96,
      duration: AppMotion.maybe(context, AppMotion.quick),
      curve: AppMotion.spring,
      child: AnimatedContainer(
        duration: AppMotion.maybe(context, AppMotion.quick),
        curve: AppMotion.ease,
        decoration: BoxDecoration(
          gradient: live ? AppColors.primaryGradient : null,
          color: live ? null : context.palette.cardMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: live
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: live ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: busy
                  // Sized to the label it replaces so the header doesn't
                  // reflow the instant you tap Post.
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : Text(
                      'Post',
                      style: AppTextStyles.buttonText.copyWith(
                        color: live
                            ? AppColors.white
                            : context.palette.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar under the writing area: what else you can add, and how much room
/// is left.
///
/// A `Wrap`, not a `Row`. These labels scale with the system font, and a Row
/// that runs out of width throws rather than clipping quietly — the exact
/// failure `composer_sheet_test` was written to catch. At 2.5x the chips take
/// a second line instead of overflowing.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.photoCount,
    required this.maxPhotos,
    required this.uploading,
    required this.onPickPhoto,
    required this.onPreview,
    required this.used,
    required this.max,
    required this.showCounterFrom,
  });

  final int photoCount;
  final int maxPhotos;
  final bool uploading;
  final VoidCallback? onPickPhoto;
  final VoidCallback? onPreview;
  final int used;
  final int max;
  final int showCounterFrom;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: palette.cardMuted.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // A photo is what people reach for most often after the words, so
            // it gets a filled tonal chip rather than a text link that reads
            // like a footnote.
            _ToolButton(
              icon: Icons.add_photo_alternate_rounded,
              label: photoCount == 0 ? 'Photo' : '$photoCount/$maxPhotos',
              busy: uploading,
              onTap: onPickPhoto,
            ),
            // Disabled on an empty post — there is nothing to preview.
            _ToolButton(
              icon: Icons.visibility_rounded,
              label: 'Preview',
              onTap: onPreview,
            ),
            // The limit is a fact about the post, so it belongs here with the
            // other facts — not floating under the text where it pushed the
            // layout around every time it appeared.
            if (used >= showCounterFrom) _CounterRing(used: used, max: max),
          ],
        ),
      ),
    );
  }
}

/// How much room is left, as a ring that fills.
///
/// A bare "203 left" is a number you have to compare against a limit you do
/// not remember. A ring closing is the same information without the
/// arithmetic, and it turns red only once it actually matters.
class _CounterRing extends StatelessWidget {
  const _CounterRing({required this.used, required this.max});

  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final left = max - used;
    final urgent = left <= 50;
    final color = urgent ? AppColors.red : AppColors.primaryBlue;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (used / max).clamp(0.0, 1.0)),
            duration: AppMotion.maybe(context, AppMotion.quick),
            curve: AppMotion.ease,
            builder: (context, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 2.4,
              backgroundColor: context.palette.divider,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          '$left left',
          style: AppTextStyles.labelSmall.copyWith(
            color: urgent ? AppColors.red : context.palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A composer toolbar action: tonal chip, icon + short label.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final color = enabled ? AppColors.primaryBlue : context.palette.textMuted;
    return Material(
      color: enabled
          ? AppColors.primaryBlue.withValues(alpha: 0.10)
          : context.palette.cardMuted,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.buttonText.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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

/// The attached photos, laid out the way the feed will show them.
///
/// One photo gets the whole width at a portrait-friendly 4:5 — the feed
/// renders post media at its natural ratio (see `post_card.dart`), so
/// squeezing a single photo into a square here would preview a crop that
/// never happens. Two or more tile as squares, which is what the feed's grid
/// actually does.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos, required this.onRemove});

  final List<String> photos;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (photos.length == 1) {
      return _Tile(
        url: photos.first,
        onRemove: () => onRemove(0),
        isCover: false,
        aspectRatio: 4 / 5,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < photos.length; i++)
              SizedBox(
                width: size,
                height: size,
                child: _Tile(
                  url: photos[i],
                  onRemove: () => onRemove(i),
                  // Order matters — the first photo is what lands in
                  // `image_url` and is all a v1.3.0 client will ever see.
                  isCover: i == 0,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.url,
    required this.onRemove,
    required this.isCover,
    this.aspectRatio,
  });

  final String url;
  final VoidCallback onRemove;
  final bool isCover;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedImage(url, fit: BoxFit.cover),
          // A scrim behind the controls so a white photo does not swallow
          // them. Only at the top, only where a control sits.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.darkNavy.withValues(alpha: 0.34),
                    AppColors.darkNavy.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: AppColors.darkNavy.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
          if (isCover)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.darkNavy.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'Cover',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return aspectRatio == null
        ? image
        : AspectRatio(aspectRatio: aspectRatio!, child: image);
  }
}

/// Avatar, name, audience — the "who is speaking" line.
///
/// For a personal post that is the member's own photo and name, with the
/// audience control directly under it, so the privacy setting reads as a
/// property of the author rather than a stray toggle in a header.
///
/// For a church update it is the church's name with a gold tick and the
/// word "Church update", because that is what the feed will show and the
/// member needs to know it before they write, not after they publish.
class _IdentityRow extends StatefulWidget {
  const _IdentityRow({
    required this.churchId,
    required this.visibility,
    required this.onChooseVisibility,
  });

  final String? churchId;
  final PostVisibility visibility;
  final VoidCallback onChooseVisibility;

  @override
  State<_IdentityRow> createState() => _IdentityRowState();
}

class _IdentityRowState extends State<_IdentityRow> {
  Church? _church;

  @override
  void initState() {
    super.initState();
    _loadChurch();
  }

  Future<void> _loadChurch() async {
    final id = widget.churchId;
    if (id == null) return;
    try {
      final church = await ChurchService.fetchChurchById(id);
      if (mounted) setState(() => _church = church);
    } catch (_) {
      // The row degrades to "Church update" without a name — still true,
      // still enough to stop someone posting as their church by accident.
    }
  }

  /// Reading the signed-in user must never be able to take the composer
  /// down. `AuthService.currentUser` reaches through `Supabase.instance`,
  /// which throws outright when the client has not been initialised — in a
  /// widget test, and on any startup path that opens this sheet before auth
  /// has settled. An unnamed avatar is a survivable outcome; a sheet that
  /// throws while you are trying to write a post is not.
  Map<String, dynamic> _selfMeta() {
    try {
      return AuthService.currentUser?.userMetadata ?? const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChurch = widget.churchId != null;
    final meta = _selfMeta();
    final name = isChurch
        ? (_church?.name ?? 'Your church')
        : ((meta['full_name'] as String?)?.trim().isNotEmpty ?? false
              ? (meta['full_name'] as String).trim()
              : 'You');
    final photo = isChurch
        ? _church?.profilePhotoUrl
        : (meta['profile_photo_url'] as String?);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        UserAvatar(
          photoUrl: photo,
          size: 44,
          name: name,
          fallbackIcon: isChurch ? Icons.church_rounded : null,
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: context.palette.text,
                      ),
                    ),
                  ),
                  if (isChurch) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      size: 15,
                      color: AppColors.goldAccent,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              // Church updates go to everyone by design — there is no
              // audience to choose, so this states the fact instead of
              // offering a control that does nothing.
              if (isChurch)
                Text(
                  'Church update · everyone',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 11.5,
                  ),
                )
              else
                _VisibilityPill(
                  visibility: widget.visibility,
                  onTap: widget.onChooseVisibility,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Says out loud what the autosave has always done silently.
class _DraftRestoredNote extends StatelessWidget {
  const _DraftRestoredNote({required this.onDiscard});

  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.history_rounded,
            size: 16,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'Picked up where you left off',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
          TextButton(
            onPressed: onDiscard,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            ),
            child: Text(
              'Start fresh',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The current audience, and the way to change it.
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
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPublic ? Icons.public_rounded : Icons.people_alt_rounded,
                size: 13,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 5),
              // Flexible + ellipsis: this pill sits inside the identity row's
              // Expanded column, and its own Row is mainAxisSize.min — so at
              // a large system font the label would push past the available
              // width and throw instead of clipping.
              Flexible(
                child: Text(
                  isPublic ? 'Public' : 'Friends',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the audience menu: what it is, and what it means.
class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({required this.option, required this.selected});

  final PostVisibility option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isPublic = option == PostVisibility.public;
    final palette = context.palette;
    return Row(
      children: [
        Icon(
          isPublic ? Icons.public_rounded : Icons.people_alt_rounded,
          size: 20,
          color: selected ? AppColors.primaryBlue : palette.textMuted,
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isPublic ? 'Public' : 'Friends',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: selected ? AppColors.primaryBlue : palette.text,
                ),
              ),
              Text(
                isPublic ? 'Anyone on Advent Connect' : 'Only your friends',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        if (selected)
          const Icon(
            Icons.check_rounded,
            size: 18,
            color: AppColors.primaryBlue,
          ),
      ],
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

  /// The story at the shape the viewer shows it — 9:16, full-bleed.
  ///
  /// The composer types into a boxed field on a sheet; the viewer paints
  /// the whole screen. A caption that fits here can still collide with
  /// the viewer's chrome, and a photo is cropped differently, so the
  /// preview renders the destination rather than the editor.
  Widget _storyPreview() {
    final bg = Color(_bgColors[_bgIndex]);
    final fg = _storyTextColor(_bgColors[_bgIndex]);
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          width: 220,
          height: 220 * 16 / 9,
          child: _textMode
              ? ColoredBox(
                  color: bg,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Center(
                      child: Text(
                        _statusText.text.trim(),
                        textAlign: TextAlign.center,
                        maxLines: 12,
                        overflow: TextOverflow.ellipsis,
                        style: storyFontStyle(
                          kStoryFontKeys[_fontIndex],
                          color: fg,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_mediaUrl != null)
                      CachedImage(_mediaUrl!, fit: BoxFit.cover)
                    else
                      const ColoredBox(color: AppColors.darkNavy),
                    if (_caption.text.trim().isNotEmpty)
                      Positioned(
                        left: AppSpace.md,
                        right: AppSpace.md,
                        bottom: AppSpace.xl,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.sm,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.darkNavy.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            _caption.text.trim(),
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _publish() async {
    if (!_canShare) return;

    final confirmed = await showEntityPreview(
      context,
      title: 'How your story will look',
      confirmLabel: 'Share it',
      canvasColor: AppColors.darkNavy,
      child: _storyPreview(),
    );
    if (!confirmed || !mounted) return;

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
              caption: _caption.text.trim().isEmpty
                  ? null
                  : _caption.text.trim(),
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
                                          alpha: _canShare ? 1 : 0.5,
                                        )
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
                              child: Builder(
                                builder: (context) {
                                  final textCol = _storyTextColor(
                                    _bgColors[_bgIndex],
                                  );
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
                                        hintText: 'Type a story…',
                                        hintStyle: TextStyle(
                                          color: textCol.withValues(
                                            alpha: 0.55,
                                          ),
                                          fontSize: 24,
                                        ),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  );
                                },
                              ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.white.withValues(
                                      alpha: _fontIndex == i ? 0.25 : 0.10,
                                    ),
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
                                backgroundColor: AppColors.white.withValues(
                                  alpha: 0.18,
                                ),
                                foregroundColor: AppColors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: AppColors.white.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                              icon: const Icon(
                                Icons.image_outlined,
                                color: AppColors.white,
                                size: 20,
                              ),
                              label: Text(
                                'Use a photo instead',
                                style: AppTextStyles.buttonText.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // ---- PHOTO STATUS ----
                          if (_uploading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: Center(child: BrandSpinner(size: 30)),
                            )
                          else if (_mediaUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: AspectRatio(
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
                                color: context.palette.divider,
                              ),
                            ),
                            child: TextField(
                              controller: _caption,
                              minLines: 1,
                              maxLines: 3,
                              textCapitalization: TextCapitalization.sentences,
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
                                icon: const Icon(
                                  Icons.image_outlined,
                                  color: AppColors.primaryBlue,
                                  size: 20,
                                ),
                                label: Text(
                                  'Replace photo',
                                  style: AppTextStyles.buttonText.copyWith(
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _textMode = true),
                                icon: const Icon(
                                  Icons.text_fields,
                                  color: AppColors.primaryBlue,
                                  size: 20,
                                ),
                                label: Text(
                                  'Text',
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
