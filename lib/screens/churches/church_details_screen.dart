import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/church_model.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/church_map.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/motion/brand_spinner.dart';

class ChurchDetailsScreen extends StatefulWidget {
  const ChurchDetailsScreen({
    super.key,
    required this.churchId,
    this.initialChurch,
    this.autoLoad = true,
  });

  final String churchId;
  final Church? initialChurch;

  /// Whether to read the signed-in user and fetch follow/admin state on
  /// mount. True in the app. False lets a widget test exercise the hero
  /// against an [initialChurch] without a Supabase client. Same seam as
  /// [SearchScreen.autoLoad] and [SplashScreen.autoNavigate].
  final bool autoLoad;

  @override
  State<ChurchDetailsScreen> createState() => _ChurchDetailsScreenState();
}

class _ChurchDetailsScreenState extends State<ChurchDetailsScreen> {
  Church? _church;
  bool _loading = true;
  bool _isFollowing = false;
  bool _followBusy = false;
  bool _hasAdmin = true; // optimistic — gate only flips when we confirm
  String? _error;
  // The signed-in user's mandatory home church (profiles.church_id). You
  // can't unfollow it, and you can't follow OTHER churches — you change your
  // home church (3-month cooldown) from your profile instead.
  String? _homeChurchId;
  // The signed-in user's APPROVED admin role for this church (if any) →
  // shows the "Manage this church" button instead of the claim link.
  ChurchAdminRole? _myRole;
  // True when the user has a PENDING claim for this church → show an
  // "under review" note instead of the claim link.
  bool _myPendingForThis = false;

  /// Adventist Super App members whose home church this is. Null until loaded,
  /// or when the count could not be had — the card falls back to the
  /// follower count rather than showing nothing.
  int? _memberCount;

  bool get _isHomeChurch =>
      _homeChurchId != null &&
      _homeChurchId!.isNotEmpty &&
      _homeChurchId == widget.churchId;

  @override
  void initState() {
    super.initState();
    _church = widget.initialChurch;
    _loading = widget.initialChurch == null;
    if (!widget.autoLoad) return;
    _homeChurchId = AuthService.currentUser?.userMetadata?['church_id']
        ?.toString();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        ChurchService.fetchChurchById(widget.churchId),
        ChurchService.isFollowing(widget.churchId),
        ChurchService.hasApprovedAdmin(widget.churchId),
        ChurchService.fetchMyAdminRoles(),
        // Real membership (profiles.church_id), not followers. Fetched
        // alongside rather than after, so it costs no extra round trip.
        ChurchService.memberCount(widget.churchId),
      ]);
      if (!mounted) return;
      final roles = results[3] as List<ChurchAdminRole>;
      ChurchAdminRole? mine;
      bool pending = false;
      for (final r in roles) {
        if (r.churchId != widget.churchId) continue;
        if (r.isApproved) {
          mine = r;
        } else if (r.status == 'pending') {
          pending = true;
        }
      }
      setState(() {
        _church = (results[0] as Church?) ?? _church;
        _isFollowing = results[1] as bool;
        _hasAdmin = results[2] as bool;
        _myRole = mine;
        _myPendingForThis = pending;
        _memberCount = results[4] as int?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load church details.';
        _loading = false;
      });
    }
  }

  void _churchToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final church = _church;
    if (church == null) return;

    // You can't unfollow your HOME church — you change it (every 3 months)
    // from your profile, not by unfollowing here.
    if (_isFollowing && _isHomeChurch) {
      _churchToast(
        'This is your home church. Change it from your profile — '
        'you can switch once every 3 months.',
      );
      return;
    }
    // You can only be part of your home church — no following other churches.
    if (!_isFollowing && !_isHomeChurch) {
      _churchToast(
        'You can only follow your home church. Set this as your home '
        'church from your profile (Edit profile → Home church).',
      );
      return;
    }

    setState(() => _followBusy = true);
    try {
      if (_isFollowing) {
        await ChurchService.unfollow(church.id);
        if (!mounted) return;
        setState(() {
          _isFollowing = false;
          _church = church.copyWith(
            membersCount: (church.membersCount - 1).clamp(0, 1 << 31),
          );
        });
      } else {
        await ChurchService.follow(church.id);
        if (!mounted) return;
        setState(() {
          _isFollowing = true;
          _church = church.copyWith(membersCount: church.membersCount + 1);
        });
      }
      // Pull the authoritative follower_count back from the server
      // so a stale cached count plus the optimistic +/- 1 doesn't
      // leave the visible number wrong. The trigger updates the row
      // in the same transaction as the follower insert/delete, so by
      // the time this resolves the count is correct.
      try {
        final fresh = await ChurchService.fetchChurchById(church.id);
        if (!mounted || fresh == null) return;
        setState(() => _church = fresh);
      } catch (_) {
        // Best-effort.
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update follow. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _church == null) {
      return const Center(child: BrandSpinner(size: 30));
    }
    if (_error != null && _church == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.red),
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _bootstrap();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final church = _church!;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(church)),
        SliverToBoxAdapter(child: _buildHeader(church)),
        SliverToBoxAdapter(child: _buildFollowSection()),
        SliverToBoxAdapter(child: _buildAbout(church)),
        SliverToBoxAdapter(child: _buildLocation(church)),
        SliverToBoxAdapter(child: _buildContact(church)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Diameter of the church logo where it overlaps the cover.
  static const double _avatarSize = 92;

  /// How much of the avatar hangs below the cover's bottom edge. Exactly
  /// half, so the logo sits ON the seam rather than near it.
  static const double _avatarDrop = _avatarSize / 2;

  /// Hero: a real cover photo, or — when there isn't one — nothing.
  ///
  /// A missing cover photo is NOT a reason to paint a navy rectangle
  /// (founder rule, 28 Jul 2026, already applied to profile_screen.dart
  /// and confirmed again for churches on 17 Aug). It matters more here
  /// than anywhere else in the app: **no church in production has a cover
  /// photo**, so the placeholder was not an edge case — it was the hero
  /// every member saw on every church, a navy slab filling the top ~26%
  /// of the screen and stopping at a hard seam.
  Widget _buildHero(Church church) {
    final cover = church.coverPhotoUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    if (!hasCover) return _buildFlatHero(church);

    return Stack(
      // The avatar deliberately hangs past the cover's bottom edge.
      clipBehavior: Clip.none,
      children: [
        Padding(
          // Reserves the space the avatar drops into, so the header below
          // starts clear of it instead of being overlapped.
          padding: const EdgeInsets.only(bottom: _avatarDrop),
          child: AspectRatio(
            // 16:9 — the SAME ratio the admin frames their upload against
            // in edit_church_screen. The public profile used to be a fixed
            // 180dp at full width, which is ~2:1 on a 360dp phone and
            // wider still on a 412dp one, so the composition an admin
            // carefully arranged was cropped top and bottom the moment a
            // member looked at it. Matching the ratio is what makes an
            // upload "just fit".
            aspectRatio: 16 / 9,
            child: GestureDetector(
                    onTap: () =>
                        FullImageViewer.show(context, church.coverPhotoUrl),
                    child: CachedImage(
                      church.coverPhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: context.palette.cardMuted,
                        // Centred: CachedImage hands its errorBuilder TIGHT
                        // constraints, so a bare child paints top-left.
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 56,
                            color: context.palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            color: const Color.fromRGBO(0, 0, 0, 0.4),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.canPop()
                  ? context.pop()
                  : context.goNamed('churches'),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back, color: AppColors.white, size: 22),
              ),
            ),
          ),
        ),
        Positioned(left: 20, bottom: 0, child: _buildAvatar(church)),
      ],
    );
  }

  /// The no-cover hero: a flat back row and the logo, on `scaffoldBg`.
  ///
  /// Two things could NOT be carried over from the cover version, and both
  /// would have been silent faults — the standing lesson that flattening a
  /// navy surface breaks every foreground that assumed a dark backdrop:
  ///   * the back arrow was white on a 40%-black scrim, which is invisible
  ///     on light grey. It becomes a normal `palette.text` icon here.
  ///   * the avatar's ring is `palette.scaffoldBg`, drawn so the logo looks
  ///     punched THROUGH the cover. With no cover it is ring-on-ring, so
  ///     the shadow is all that separates it — which is exactly right, and
  ///     is why the avatar keeps its shadow rather than gaining a border.
  Widget _buildFlatHero(Church church) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.canPop()
                  ? context.pop()
                  : context.goNamed('churches'),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back,
                  color: context.palette.text,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Aligned to the same x as the cover version's avatar (12 + 8),
          // so the identity does not shift when a church adds a photo.
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _buildAvatar(church),
          ),
        ],
      ),
    );
  }

  /// Round church logo (churches.profile_photo_url), sitting on the
  /// cover's bottom edge.
  ///
  /// It used to render NOTHING when no logo was set — and no church in
  /// production has one, so in practice every church profile had no
  /// avatar at all and the identity slot simply wasn't there. It always
  /// renders now: a branded church gets its logo, an unbranded one gets
  /// the church glyph on the brand gradient, which is a placeholder an
  /// admin can see and want to replace.
  ///
  /// The ring is painted by an OUTER container and the image is given an
  /// explicit size, because `Container(alignment:)` hands its child LOOSE
  /// constraints — an unsized image floats inside the circle and leaves a
  /// visible rim. Same reason the fallback is wrapped in `Center`:
  /// `CachedImage` hands its errorBuilder TIGHT constraints, so a bare
  /// child paints top-left.
  Widget _buildAvatar(Church church) {
    final url = church.profilePhotoUrl;
    final hasLogo = url != null && url.isNotEmpty;
    final palette = context.palette;

    Widget fallback() => Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: const Center(
        child: Icon(Icons.church, color: AppColors.white, size: 40),
      ),
    );

    return GestureDetector(
      onTap: hasLogo ? () => FullImageViewer.show(context, url) : null,
      child: Container(
        width: _avatarSize + 8,
        height: _avatarSize + 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // The ring reads as the page's surface, so the logo looks
          // punched through the cover rather than pasted onto it.
          color: palette.scaffoldBg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: ClipOval(
            child: SizedBox(
              width: _avatarSize,
              height: _avatarSize,
              child: hasLogo
                  ? CachedImage(
                      url,
                      width: _avatarSize,
                      height: _avatarSize,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => fallback(),
                    )
                  : fallback(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Church church) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The logo lives on the cover's edge now, not inline beside
              // the name — so the name gets the full width at every
              // church, branded or not.
              Expanded(
                child: Text(church.name, style: AppTextStyles.displayMedium),
              ),
              if (church.isVerified)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 8),
                  child: Icon(
                    Icons.verified,
                    color: AppColors.goldAccent,
                    size: 24,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Wrap, not Row. As a Row these two stats had no Flexible and no
          // room to give: at 2.5x system text they overflowed the right
          // edge by 97px on a 360dp phone. They stack now when the line
          // runs out, which is what a pair of independent facts should do.
          Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: context.palette.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    church.city.isEmpty ? 'Unknown city' : church.city,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.text,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  // Flexible, not bare. This label got longer ("N members
                  // on Advent" vs "N on Advent") and immediately overflowed
                  // by 105px at 2.5x text scale — an unflexed Text in a Row
                  // THROWS rather than clipping, and this project has
                  // shipped that bug before.
                  Flexible(
                    child: Text(
                      // MEMBERS when we have them, followers otherwise.
                      //
                      // The old comment here said the app "has no data on
                      // real congregation membership". It does:
                      // `profiles.church_id` is the member's home church,
                      // and 156 people have set one. `follower_count` is a
                      // different act — you can follow a church you do not
                      // attend — so the two are different sets, and the
                      // label now says which one it is showing.
                      _memberCount != null
                          ? '$_memberCount ${_memberCount == 1 ? "member" : "members"} on Advent'
                          : '${church.membersCount} following on Advent',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFollowSection() {
    // Unclaimed churches can't post yet, but we let the viewer follow
    // anyway — newly-claiming admins inherit those pre-followers as
    // a built-in audience for their first announcement. Just warn
    // first so expectations are calibrated, and surface the claim
    // flow inline so the right person can take it over.
    //
    // A CLAIMED church now keeps a claim entry too. Hiding it entirely
    // meant a pastor who arrived after someone else had claimed their
    // congregation had no route at all to say so — and the claim screen
    // already handles that case properly ("This church is already
    // claimed… if you believe it was claimed by the wrong person,
    // contact support"). The door was closed on a room that was
    // furnished.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_hasAdmin) _buildUnclaimedNotice(),
        _buildFollowButton(),
        _buildClaimLink(),
      ],
    );
  }

  Widget _buildFollowButton() {
    final following = _isFollowing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: SizedBox(
        width: double.infinity,
        child: following
            ? OutlinedButton.icon(
                onPressed: _followBusy ? null : _toggleFollow,
                icon: _followBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryBlue,
                        ),
                      )
                    : const Icon(Icons.check, color: AppColors.primaryBlue),
                label: Text(
                  _isHomeChurch ? 'Home church' : 'Following',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primaryBlue,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: AppColors.primaryBlue,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _followBusy ? null : _toggleFollow,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: _followBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.add,
                                    color: AppColors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Follow',
                                    style: AppTextStyles.buttonText,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildUnclaimedNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.goldAccent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.goldAccent.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              color: AppColors.goldAccent,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This church isn\'t claimed yet',
                    style: AppTextStyles.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You can follow, but don\'t expect announcements until a pastor or elder claims it.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: context.palette.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClaimLink() {
    final church = _church;
    // Approved admin → open the dashboard instead of the claim link.
    if (_myRole != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () =>
                context.pushNamed('admin_dashboard', extra: _myRole),
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: Text('Manage this church', style: AppTextStyles.buttonText),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
    }
    // Pending claim by this user → reassure instead of inviting another
    // claim. Mirrors the claim screen's "we're still reviewing" message.
    if (_myPendingForThis) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                color: AppColors.primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your application to manage this church is under review. '
                  'We\'ll let you know once it\'s approved.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.text,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // A CARD, not a text link.
    //
    // This was a 13.5pt TextButton tucked under the follow button, and
    // members reported not knowing the feature existed at all. Claiming
    // is how a congregation gets a voice in the app — it deserves to look
    // like an offer, not a footnote. On a claimed church it stays present
    // but quiet: the wording changes to an appeal, and the claim screen
    // explains the situation and routes to support.
    final claimed = _hasAdmin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Material(
        color: claimed
            ? Colors.transparent
            : AppColors.primaryBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: church == null
              ? null
              : () => context.pushNamed(
                  'claim_church',
                  pathParameters: {'id': church.id},
                  extra: church,
                ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: claimed
                    ? context.palette.divider
                    : AppColors.primaryBlue.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  claimed
                      ? Icons.help_outline_rounded
                      : Icons.verified_user_outlined,
                  size: 20,
                  color: claimed
                      ? context.palette.textMuted
                      : AppColors.primaryBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        claimed
                            ? 'Is this your church?'
                            : 'Is this your church? Claim it',
                        style: AppTextStyles.titleSmall.copyWith(
                          color: claimed
                              ? context.palette.text
                              : AppColors.primaryBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        claimed
                            ? 'Already claimed. If you believe you have the '
                                  'right to manage it, tell us and we\'ll look '
                                  'into it.'
                            : 'Pastors and elders can claim it to post '
                                  'announcements and events.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                          height: 1.35,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: context.palette.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocation(Church church) {
    final hasCoords = church.hasLocation;
    final addressLine = _addressLine(church);
    // Skip the section entirely if we have nothing to show.
    if (!hasCoords && addressLine.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasCoords)
              ChurchMapPreview(church: church)
            else
              _AddressOnlyHeader(
                church: church,
                onTap: () => MapsLauncher.openLocation(church: church),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Text('Location', style: AppTextStyles.titleLarge),
                    ],
                  ),
                  if (addressLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      addressLine,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.text,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _LocationActionButton(
                          icon: Icons.map_outlined,
                          label: 'Open in Maps',
                          filled: false,
                          onTap: () =>
                              _onOpenMaps(MapsLauncher.openLocation, church),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _LocationActionButton(
                          icon: Icons.directions_rounded,
                          label: 'Directions',
                          filled: true,
                          onTap: () =>
                              _onOpenMaps(MapsLauncher.openDirections, church),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _addressLine(Church church) {
    final parts = <String>[
      if ((church.address ?? '').trim().isNotEmpty) church.address!.trim(),
      if (church.city.trim().isNotEmpty) church.city.trim(),
    ];
    return parts.join(', ');
  }

  Future<void> _onOpenMaps(
    Future<bool> Function({required Church church}) launcher,
    Church church,
  ) async {
    final ok = await launcher(church: church);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open Maps on this device.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Widget _buildAbout(Church church) {
    if (church.description == null || church.description!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About', style: AppTextStyles.titleLarge),
              const SizedBox(height: 8),
              Text(
                church.description!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.text,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContact(Church church) {
    final rows = <Widget>[];
    // Physical address gets top billing — it's the single most-asked
    // piece of info on a church profile after the name.
    final addressLine = _addressLine(church);
    if (addressLine.isNotEmpty) {
      rows.add(_infoRow(Icons.place_outlined, 'Address', addressLine));
    }
    if (church.pastorName != null && church.pastorName!.isNotEmpty) {
      rows.add(_infoRow(Icons.person_outline, 'Pastor', church.pastorName!));
    }
    if (church.contactPhone != null && church.contactPhone!.isNotEmpty) {
      rows.add(_infoRow(Icons.phone_outlined, 'Phone', church.contactPhone!));
    }
    if (church.contactEmail != null && church.contactEmail!.isNotEmpty) {
      rows.add(_infoRow(Icons.email_outlined, 'Email', church.contactEmail!));
    }
    if (church.foundedYear != null) {
      rows.add(
        _infoRow(
          Icons.calendar_today_outlined,
          'Founded',
          '${church.foundedYear}',
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Details', style: AppTextStyles.titleLarge),
              const SizedBox(height: 12),
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: context.palette.divider),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddressOnlyHeader extends StatelessWidget {
  const _AddressOnlyHeader({required this.church, required this.onTap});
  final Church church;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.2),
                        radius: 1.2,
                        colors: [
                          AppColors.white.withValues(alpha: 0.10),
                          AppColors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.map_outlined,
                      size: 36,
                      color: AppColors.goldAccent,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap to view on the map',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
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

class _LocationActionButton extends StatelessWidget {
  const _LocationActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: filled ? AppColors.primaryGradient : null,
        // Adaptive surface for the outlined "Open in Maps" variant — white
        // here was a glaring white button on the dark card in dark mode.
        color: filled ? null : context.palette.card,
        borderRadius: BorderRadius.circular(12),
        border: filled
            ? null
            : Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.35)),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: filled ? AppColors.white : AppColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: filled ? AppColors.white : AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
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
