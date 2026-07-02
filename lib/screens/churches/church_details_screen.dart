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
  });

  final String churchId;
  final Church? initialChurch;

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

  bool get _isHomeChurch =>
      _homeChurchId != null &&
      _homeChurchId!.isNotEmpty &&
      _homeChurchId == widget.churchId;

  @override
  void initState() {
    super.initState();
    _church = widget.initialChurch;
    _loading = widget.initialChurch == null;
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

  Widget _buildHero(Church church) {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 180,
          child: church.coverPhotoUrl == null || church.coverPhotoUrl!.isEmpty
              ? Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.appBarGradient,
                  ),
                  child: const Center(
                    child: Icon(Icons.church, size: 56, color: AppColors.white),
                  ),
                )
              : GestureDetector(
                  onTap: () =>
                      FullImageViewer.show(context, church.coverPhotoUrl),
                  child: CachedImage(
                    church.coverPhotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: context.palette.cardMuted,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 56,
                        color: context.palette.textMuted,
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
      ],
    );
  }

  /// Round church logo/avatar (churches.profile_photo_url) shown next to
  /// the name. Renders nothing when no logo is set so unbranded churches
  /// keep the original full-width title.
  Widget _buildAvatar(Church church) {
    final url = church.profilePhotoUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => FullImageViewer.show(context, url),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.palette.cardMuted,
          border: Border.all(color: context.palette.divider, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedImage(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.church, color: context.palette.textMuted, size: 26),
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
              _buildAvatar(church),
              if (church.profilePhotoUrl != null &&
                  church.profilePhotoUrl!.isNotEmpty)
                const SizedBox(width: 14),
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
          Row(
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
              const SizedBox(width: 16),
              const Icon(
                Icons.people_outline,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                '${church.membersCount} members',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
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
    if (_hasAdmin) {
      return _buildFollowButton();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildUnclaimedNotice(),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: TextButton.icon(
        onPressed: church == null
            ? null
            : () => context.pushNamed(
                'claim_church',
                pathParameters: {'id': church.id},
                extra: church,
              ),
        icon: const Icon(
          Icons.verified_user_outlined,
          size: 16,
          color: AppColors.primaryBlue,
        ),
        label: Text(
          'Is this your church? Claim it',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
