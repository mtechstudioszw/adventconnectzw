import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../models/org_page_model.dart';
import '../../screens/onboarding/widgets/film_scenes.dart'
    show AmbientPainter, byBrightness;
import '../../services/sabbath_service.dart';
import '../../services/auth_service.dart';
import '../../services/devotion_service.dart';
import '../../services/page_service.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../motion/pressable.dart';
import '../studio/artboard.dart';
import '../user_avatar.dart';
import 'composer_sheet.dart' show readPostDraft;

/// Everything a member can put into the app from Home.
enum CreateKind { post, story, event, prayer, news, notice, job, product }

/// What the studio asks Home to open: a kind, plus how to start it.
@immutable
class CreateRequest {
  const CreateRequest(
    this.kind, {
    this.page,
    this.initialText,
    this.pickPhoto = false,
  });

  final CreateKind kind;

  /// Post as this organization Page instead of as yourself.
  final OrgPage? page;

  /// Seed text for a post — a starter or today's verse.
  final String? initialText;

  /// Open the composer straight on the photo picker.
  final bool pickPhoto;
}

/// The create studio (28 Oct 2026 redesign, founder: "make it look like a
/// workspace, like a studio").
///
/// The previous two versions were menus — first a list, then a grid of
/// cards — and both read as generated, because a menu only tells you what
/// exists. A studio is where you START, so this one opens on a canvas:
///
/// - **Canvas** — an artboard with a sheet of paper on it, signed with who
///   you're posting as. If you have an unpublished post it shows your
///   words, and "Write" becomes "Continue". The draft is the one the
///   composer already autosaves; the studio just stops hiding it.
/// - **Posting as** — members who run Pages switch identity here, before
///   writing, instead of hunting for the Page's own screen.
/// - **Today's verse** — when the day's devotion is cached, one tap starts
///   a post with that verse already quoted.
/// - **Photo / Photo story** — open straight on the picker, no extra tap.
/// - **Start from** — openers for the posts people actually write here,
///   with a Sabbath greeting on Friday and Saturday.
/// - **Publish elsewhere** — the five occasional tools, as a dock.
///
/// Every animation is driven by the route's own animation, so dismissing
/// plays the entrance backwards instead of cutting.
///
/// Returns what to open, or null if dismissed. Deliberately presentational
/// — the caller owns navigation, because posts and stories come back with a
/// value the feed needs and the rest are plain route pushes.
Future<CreateRequest?> showCreateSheet(BuildContext context) {
  return showGeneralDialog<CreateRequest>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close create menu',
    // We paint our own scrim so it can fade in step with the blur.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, animation, _) => _CreateScreen(animation: animation),
  );
}

@immutable
class _Option {
  const _Option(this.kind, this.icon, this.title, this.subtitle);
  final CreateKind kind;
  final IconData icon;

  /// Short — it sits under a dock icon.
  final String title;

  /// Read out by screen readers with the title.
  final String subtitle;
}

@immutable
class _Starter {
  const _Starter(this.icon, this.title, this.text);
  final IconData icon;
  final String title;

  /// What the post opens with; the member finishes the sentence.
  final String text;
}

class _CreateScreen extends StatefulWidget {
  const _CreateScreen({required this.animation});

  final Animation<double> animation;

  @override
  State<_CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<_CreateScreen>
    with SingleTickerProviderStateMixin {
  /// The same slow ambient drift the splash, onboarding film, auth shell
  /// and maintenance screen run on. It also blinks the canvas caret and
  /// runs nothing else — one controller for the whole studio.
  late final AnimationController _ambient;

  /// Pages this member can post as (visible ones only).
  List<OrgPage> _pages = const [];

  /// Who the post goes out as; null is yourself.
  OrgPage? _as;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _loadPages();
  }

  Future<void> _loadPages() async {
    try {
      final pages = await PageService.mine();
      if (!mounted) return;
      setState(
        () => _pages = [
          for (final p in pages)
            if (!p.isHidden) p,
        ],
      );
    } catch (_) {
      // No switcher is a fine outcome; posting as yourself still works.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour "remove animations": hold the field still rather than
    // spinning a controller nobody can see.
    if (AppMotion.enabled(context)) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      _ambient
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  Animation<double> get animation => widget.animation;

  static const _tools = <_Option>[
    _Option(
      CreateKind.event,
      Icons.event_outlined,
      'Event',
      'Invite people along',
    ),
    _Option(
      CreateKind.prayer,
      Icons.volunteer_activism_outlined,
      'Prayer',
      'Ask for prayer',
    ),
    // REMOVED 23 Aug 2026 — "Church notice / Tell your local church".
    //
    // It promised something the schema cannot deliver: `notices` has no
    // church_id column, so a "church notice" was never attached to a church
    // at all, and `notices_select_all` shows every notice to every
    // authenticated member. There was also no admin gate on either side —
    // any active member could publish what reads as official church
    // communication, to everybody.
    //
    // Nobody ever did: the table holds 0 rows from 0 posters since launch.
    // So this removes a live permissions hole and a misleading label at
    // zero cost to anyone.
    //
    // The route, screen, model and service are deliberately LEFT IN PLACE
    // (post_notice / PostNoticeScreen / NoticeService). Nothing links to
    // them now, so they are unreachable, and that is the cheap half to undo
    // if the feature is built properly later — the expensive half is the
    // migration that gives notices a church_id and an
    // is_approved_church_admin() policy.
    _Option(
      CreateKind.news,
      Icons.newspaper_outlined,
      'News',
      'Advent News — reviewed before it goes live',
    ),
    _Option(
      CreateKind.product,
      Icons.storefront_outlined,
      'Sell',
      'List something on the marketplace',
    ),
    _Option(
      CreateKind.job,
      Icons.work_outline_rounded,
      'Hire',
      'Post a job opening',
    ),
  ];

  /// Openers for the posts people write from here. Day-aware: the Sabbath
  /// greeting leads on Friday and Saturday and is gone the rest of the week.
  List<_Starter> _starters() {
    // From Friday (the day the Sabbath begins, where the member keeps it)
    // until sundown on Saturday — not by calendar day.
    final sabbathNear = SabbathService.isSabbathNow() ||
        SabbathService.placeCalendarNow().weekday == DateTime.friday;
    return [
      if (sabbathNear)
        const _Starter(
          Icons.wb_twilight_rounded,
          'Sabbath greeting',
          'Happy Sabbath, family! ',
        ),
      const _Starter(
        Icons.record_voice_over_outlined,
        'Testimony',
        'I want to share what God did this week: ',
      ),
      const _Starter(
        Icons.favorite_border_rounded,
        'Grateful for',
        "Today I'm thankful for ",
      ),
      const _Starter(Icons.church_outlined, 'Church recap', 'At church today '),
      const _Starter(
        Icons.help_outline_rounded,
        'Ask the family',
        'A question for my church family: ',
      ),
    ];
  }

  /// Today's devotion verse, quoted, or null when none is cached.
  String? _verseText() {
    try {
      final d = DevotionService.cachedToday();
      final text = d?.bibleText.trim() ?? '';
      final ref = d?.bibleRef.trim() ?? '';
      if (text.isEmpty || ref.isEmpty) return null;
      return '“$text”\n— $ref\n\n';
    } catch (_) {
      return null;
    }
  }

  /// Reading the signed-in user must never take the studio down (see the
  /// composer's identity row — the client can be uninitialised in tests and
  /// early startup).
  ({String name, String? photo}) _who() {
    final page = _as;
    if (page != null) return (name: page.name, photo: page.logoUrl);
    try {
      final meta = AuthService.currentUser?.userMetadata ?? const {};
      final full = AuthService.myFullName;
      return (
        name: full.isEmpty ? 'You' : full,
        photo: meta['profile_photo_url'] as String?,
      );
    } catch (_) {
      return (name: 'You', photo: null);
    }
  }

  void _go(CreateRequest request) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(request);
  }

  void _post({String? text, bool photo = false}) => _go(
    CreateRequest(
      CreateKind.post,
      page: _as,
      initialText: text,
      pickPhoto: photo,
    ),
  );

  Future<void> _chooseIdentity() async {
    if (_pages.isEmpty) return;
    final self = _who();
    final picked = await showModalBottomSheet<_Identity>(
      useRootNavigator: true,
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) => _IdentitySheet(
        selfName: _as == null ? self.name : 'You',
        selfPhoto: _as == null ? self.photo : null,
        pages: _pages,
        current: _as,
      ),
    );
    if (picked != null && mounted) setState(() => _as = picked.page);
  }

  /// Per-tile progress: tile [i] starts [i * 0.06] into the route animation
  /// and takes 55% of it to land. Capped so the last tile isn't still
  /// arriving after the route has settled.
  double _tileT(int i) {
    final start = (i * 0.06).clamp(0.0, 0.40);
    return ((animation.value - start) / 0.55).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.enabled(context);

    // Scaffold, not a bare Stack. A `showGeneralDialog` page has no Material
    // ancestor, so every Text here inherited Flutter's missing-Material error
    // style — black glyphs with a double YELLOW underline. This is the
    // transparent-Material fix.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animate
              ? Curves.easeOutCubic.transform(animation.value.clamp(0.0, 1.0))
              : 1.0;
          double tile(int i) => animate ? _tileT(i) : 1.0;

          return Stack(
            children: [
              // Scrim + blur. Tapping anywhere off the studio closes.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  // This used to be one flat ColoredBox of navy at 82%. Over
                  // a blurred feed that is a dead, evenly-lit slab with no
                  // light source and no depth — and below the last row it
                  // became a large rectangle of nothing, which is where the
                  // screen stopped looking designed.
                  //
                  // Three layers now: the blur, a vertical gradient so light
                  // falls from the top the way it does everywhere else in the
                  // app, and the app's own AmbientPainter drifting over it.
                  // The ambient field is what fills the space under the last
                  // row, so the foot of the screen is lit rather than empty.
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            // White in LIGHT mode, on the founder's call
                            // (17 Aug 2026) — and still a gradient rather
                            // than one flat fill, because pure #FFFFFF edge
                            // to edge is what made the navy version read as
                            // a dead slab. The fault was the flatness, not
                            // the hue.
                            //
                            // Dark mode keeps that intent instead of the
                            // literal colour: a white sheet under
                            // palette-aware dark cards was the whole of the
                            // "create sheet is white in dark mode" report
                            // (founder, 17 Aug). Same shape — lifted at the
                            // top, falling to the app's own floor — so the
                            // sheet still has a light source.
                            byBrightness(
                              context,
                              light: AppColors.white.withValues(
                                alpha: 0.97 * t,
                              ),
                              dark: context.palette.cardMuted.withValues(
                                alpha: 0.97 * t,
                              ),
                            ),
                            byBrightness(
                              context,
                              light: AppColors.lightGrey.withValues(
                                alpha: 0.99 * t,
                              ),
                              dark: context.palette.scaffoldBg.withValues(
                                alpha: 0.99 * t,
                              ),
                            ),
                          ],
                        ),
                      ),
                      child: Opacity(
                        opacity: t,
                        child: AnimatedBuilder(
                          animation: _ambient,
                          builder: (context, _) => CustomPaint(
                            painter: AmbientPainter(
                              loop: _ambient.value,
                              film: 0,
                              dark:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                              quiet: true,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // Wide layouts only while they can't overflow: a narrow
                    // phone or a large system font gets the compact one.
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final roomy = box.maxWidth >= 340 && scale <= 1.3;
                    final who = _who();
                    final draft = readPostDraft(page: _as);
                    final verse = _verseText();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, -16 * (1 - t)),
                            child: _TopBar(
                              onClose: () => Navigator.of(context).pop(),
                              identity: _IdentityPill(
                                name: who.name,
                                photo: who.photo,
                                switchable: _pages.isNotEmpty,
                                onTap: _chooseIdentity,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpace.lg,
                              AppSpace.sm,
                              AppSpace.lg,
                              AppSpace.xl,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Enter(
                                  t: tile(0),
                                  child: StudioArtboard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _Canvas(
                                          name: who.name,
                                          photo: who.photo,
                                          draft: draft,
                                          caret: _ambient,
                                          animate: animate,
                                          onWrite: () => _post(),
                                          onPhoto: () => _post(photo: true),
                                          onVerse: verse == null
                                              ? null
                                              : () => _post(text: verse),
                                        ),
                                        const SizedBox(height: AppSpace.md),
                                        _StoryRow(
                                          stacked: !roomy,
                                          onText: () => _go(
                                            const CreateRequest(
                                              CreateKind.story,
                                            ),
                                          ),
                                          onPhoto: () => _go(
                                            const CreateRequest(
                                              CreateKind.story,
                                              pickPhoto: true,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpace.xl),
                                _SectionLabel('START FROM', t: tile(2)),
                                const SizedBox(height: AppSpace.md),
                                _Enter(
                                  t: tile(2),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    clipBehavior: Clip.none,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final s in _starters())
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: AppSpace.sm,
                                            ),
                                            child: _StarterCard(
                                              starter: s,
                                              onTap: () => _post(text: s.text),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpace.xl),
                                _SectionLabel('PUBLISH ELSEWHERE', t: tile(3)),
                                const SizedBox(height: AppSpace.md),
                                _Enter(
                                  t: tile(3),
                                  child: _ToolDock(
                                    tools: _tools,
                                    columns: roomy ? 5 : 3,
                                    onPick: (o) => _go(CreateRequest(o.kind)),
                                  ),
                                ),
                                const SizedBox(height: AppSpace.sm),
                                Opacity(
                                  opacity: tile(3),
                                  child: Text(
                                    'News is reviewed by editors before it '
                                    'goes live.',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.caption.copyWith(
                                      color: context.palette.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, required this.identity});

  final VoidCallback onClose;
  final Widget identity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Row(
        children: [
          _CloseButton(onTap: onClose),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CREATE',
                  style: AppTextStyles.labelSmall.copyWith(
                    // The screen's one gold moment.
                    color: AppColors.goldAccent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
                Text(
                  'Studio',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          identity,
        ],
      ),
    );
  }
}

/// "Posting as" — tappable only when there's someone else to be.
class _IdentityPill extends StatelessWidget {
  const _IdentityPill({
    required this.name,
    required this.photo,
    required this.switchable,
    required this.onTap,
  });

  final String name;
  final String? photo;
  final bool switchable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final first = name.split(RegExp(r'\s+')).first;
    final pill = Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(photoUrl: photo, name: name, size: 28),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (switchable) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: context.palette.textMuted,
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: switchable,
      label: switchable ? 'Posting as $name. Change' : 'Posting as $name',
      excludeSemantics: true,
      child: switchable
          ? Pressable(onTap: onTap, pressedScale: 0.94, child: pill)
          : pill,
    );
  }
}

/// The picker's answer — wraps the page so "yourself" (null) is a real
/// choice, distinct from dismissing the sheet.
class _Identity {
  const _Identity(this.page);
  final OrgPage? page;
}

class _IdentitySheet extends StatelessWidget {
  const _IdentitySheet({
    required this.selfName,
    required this.selfPhoto,
    required this.pages,
    required this.current,
  });

  final String selfName;
  final String? selfPhoto;
  final List<OrgPage> pages;
  final OrgPage? current;

  @override
  Widget build(BuildContext context) {
    Widget row({
      required String title,
      required String subtitle,
      required String? photo,
      required bool selected,
      required _Identity value,
    }) {
      return ListTile(
        onTap: () => Navigator.of(context).pop(value),
        leading: UserAvatar(photoUrl: photo, name: title, size: 40),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.palette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTextStyles.caption.copyWith(
            color: context.palette.textMuted,
          ),
        ),
        trailing: selected
            ? Icon(Icons.check_rounded, color: context.palette.brandBlue)
            : null,
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Text(
                'Post as',
                style: AppTextStyles.titleMedium.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            row(
              title: selfName,
              subtitle: 'Your profile',
              photo: selfPhoto,
              selected: current == null,
              value: const _Identity(null),
            ),
            for (final p in pages)
              row(
                title: p.name,
                subtitle: 'Page you manage',
                photo: p.logoUrl,
                selected: current?.id == p.id,
                value: _Identity(p),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.t});

  final String label;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Container(height: 1, color: context.palette.divider)),
        ],
      ),
    );
  }
}

/// Shared entrance: springs up and settles rather than simply fading.
class _Enter extends StatelessWidget {
  const _Enter({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clamped = t.clamp(0.0, 1.0);
    final eased = Curves.easeOutBack.transform(clamped);
    return Opacity(
      opacity: clamped,
      child: Transform.translate(
        offset: Offset(0, 22 * (1 - clamped)),
        child: Transform.scale(scale: 0.94 + 0.06 * eased, child: child),
      ),
    );
  }
}

/// The sheet of paper: who's writing, the words so far, and a toolbar.
class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.name,
    required this.photo,
    required this.draft,
    required this.caret,
    required this.animate,
    required this.onWrite,
    required this.onPhoto,
    required this.onVerse,
  });

  final String name;
  final String? photo;
  final ({String body, List<String> photos})? draft;
  final Animation<double> caret;
  final bool animate;
  final VoidCallback onWrite;
  final VoidCallback onPhoto;
  final VoidCallback? onVerse;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final hasDraft = d != null;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.palette.divider),
        boxShadow: AppShadows.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: hasDraft ? 'Continue your draft' : 'Write a post',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onWrite,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.md,
                  AppSpace.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        UserAvatar(photoUrl: photo, name: name, size: 32),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: context.palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (hasDraft) const _DraftTag(),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: hasDraft
                          ? _DraftBody(draft: d)
                          : _Prompt(caret: caret, animate: animate),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 1, color: context.palette.divider),
          Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      _ToolbarButton(
                        icon: Icons.photo_outlined,
                        label: 'Photo',
                        onTap: onPhoto,
                      ),
                      if (onVerse != null)
                        _ToolbarButton(
                          icon: Icons.menu_book_outlined,
                          label: "Today's verse",
                          onTap: onVerse!,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                _WriteButton(
                  label: hasDraft ? 'Continue' : 'Write',
                  onTap: onWrite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "What's on your heart?" with a blinking caret — the canvas waiting.
class _Prompt extends StatelessWidget {
  const _Prompt({required this.caret, required this.animate});

  final Animation<double> caret;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.titleMedium.copyWith(
      color: context.palette.textMuted,
      fontWeight: FontWeight.w500,
    );
    return Align(
      alignment: Alignment.topLeft,
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: AnimatedBuilder(
                animation: caret,
                builder: (context, _) {
                  // ~1.1s blink off the 14s ambient loop.
                  final on = !animate || (caret.value * 14) % 1.1 < 0.55;
                  return Container(
                    width: 2,
                    height: 22,
                    margin: const EdgeInsets.only(right: 3),
                    color: on ? AppColors.primaryBlue : Colors.transparent,
                  );
                },
              ),
            ),
            TextSpan(text: "What's on your heart?", style: style),
          ],
        ),
      ),
    );
  }
}

class _DraftTag extends StatelessWidget {
  const _DraftTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.palette.chipBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'DRAFT',
        style: AppTextStyles.labelSmall.copyWith(
          color: context.palette.brandBlue,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _DraftBody extends StatelessWidget {
  const _DraftBody({required this.draft});

  final ({String body, List<String> photos}) draft;

  @override
  Widget build(BuildContext context) {
    final n = draft.photos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (draft.body.trim().isNotEmpty)
          Text(
            draft.body.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.text,
              height: 1.4,
            ),
          ),
        if (n > 0) ...[
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 16,
                color: context.palette.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                n == 1 ? '1 photo' : '$n photos',
                style: AppTextStyles.caption.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(
          'Saved on this phone',
          style: AppTextStyles.caption.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.94,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: context.palette.brandBlue),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The paper's one primary action — gradient, radius 14, per the rules.
class _WriteButton extends StatelessWidget {
  const _WriteButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptics: true,
      pressedScale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.button),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: AppColors.white,
            ),
          ],
        ),
      ),
    );
  }
}

/// Text story / Photo story, under the paper on the same board.
class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.stacked,
    required this.onText,
    required this.onPhoto,
  });

  final bool stacked;
  final VoidCallback onText;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final text = _StoryButton(
      glyph: Text(
        'Aa',
        textScaler: TextScaler.noScaling,
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      title: 'Text story',
      onTap: onText,
    );
    final photo = _StoryButton(
      glyph: const Icon(
        Icons.photo_camera_outlined,
        size: 17,
        color: AppColors.white,
      ),
      title: 'Photo story',
      onTap: onPhoto,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text,
          const SizedBox(height: AppSpace.sm),
          photo,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: text),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: photo),
      ],
    );
  }
}

class _StoryButton extends StatelessWidget {
  const _StoryButton({
    required this.glyph,
    required this.title,
    required this.onTap,
  });

  final Widget glyph;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. Gone in 24 hours',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        haptics: true,
        pressedScale: 0.95,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: context.palette.divider),
          ),
          child: Row(
            children: [
              // A story ring around the glyph — the shape members already
              // read as "story" from the rail on Home.
              Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: context.palette.card, width: 2),
                    color: AppColors.primaryBlue,
                  ),
                  alignment: Alignment.center,
                  child: glyph,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Gone in 24h',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarterCard extends StatelessWidget {
  const _StarterCard({required this.starter, required this.onTap});

  final _Starter starter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start a post: ${starter.title}',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        haptics: true,
        pressedScale: 0.95,
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: context.palette.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(starter.icon, size: 20, color: context.palette.brandBlue),
              const SizedBox(height: AppSpace.sm),
              Text(
                starter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '“${starter.text.trim().replaceAll(RegExp(r'[:!,]$'), '')}…”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: context.palette.textMuted,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The occasional five, as a tool dock.
class _ToolDock extends StatelessWidget {
  const _ToolDock({
    required this.tools,
    required this.columns,
    required this.onPick,
  });

  final List<_Option> tools;
  final int columns;
  final ValueChanged<_Option> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xs,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.palette.divider),
        boxShadow: AppShadows.card(context),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / columns;
          return Wrap(
            alignment: WrapAlignment.center,
            runSpacing: AppSpace.md,
            children: [
              for (final o in tools)
                SizedBox(
                  width: w,
                  child: _DockItem(option: o, onTap: () => onPick(o)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({required this.option, required this.onTap});

  final _Option option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${option.title}. ${option.subtitle}',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        haptics: true,
        pressedScale: 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              alignment: Alignment.center,
              child: Icon(
                option.icon,
                size: 22,
                color: context.palette.brandBlue,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.88,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.palette.card,
            shape: BoxShape.circle,
            border: Border.all(color: context.palette.divider),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            color: context.palette.text,
            size: 21,
          ),
        ),
      ),
    );
  }
}
