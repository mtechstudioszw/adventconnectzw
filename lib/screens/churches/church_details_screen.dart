import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/church_model.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/church_map.dart';

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

  @override
  void initState() {
    super.initState();
    _church = widget.initialChurch;
    _loading = widget.initialChurch == null;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        ChurchService.fetchChurchById(widget.churchId),
        ChurchService.isFollowing(widget.churchId),
        ChurchService.hasApprovedAdmin(widget.churchId),
      ]);
      if (!mounted) return;
      setState(() {
        _church = (results[0] as Church?) ?? _church;
        _isFollowing = results[1] as bool;
        _hasAdmin = results[2] as bool;
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

  Future<void> _toggleFollow() async {
    final church = _church;
    if (church == null) return;

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
          _church = church.copyWith(
            membersCount: church.membersCount + 1,
          );
        });
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
      backgroundColor: AppColors.lightGrey,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _church == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null && _church == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.red),
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
                    child: Icon(
                      Icons.church,
                      size: 56,
                      color: AppColors.white,
                    ),
                  ),
                )
              : Image.network(
                  church.coverPhotoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.lightGrey,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      size: 56,
                      color: Color.fromRGBO(26, 26, 46, 0.3),
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
                child: Icon(Icons.arrow_back,
                    color: AppColors.white, size: 22),
              ),
            ),
          ),
        ),
      ],
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
              const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: Color.fromRGBO(26, 26, 46, 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                church.city.isEmpty ? 'Unknown city' : church.city,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.7),
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
                  'Following',
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
                                  const Icon(Icons.add,
                                      color: AppColors.white, size: 20),
                                  const SizedBox(width: 6),
                                  Text('Follow',
                                      style: AppTextStyles.buttonText),
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
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You can follow, but don\'t expect announcements until a pastor or elder claims it.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.72),
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
                      Text(
                        'Location',
                        style: AppTextStyles.titleLarge,
                      ),
                    ],
                  ),
                  if (addressLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      addressLine,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: const Color.fromRGBO(26, 26, 46, 0.75),
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
                          onTap: () => _onOpenMaps(
                            MapsLauncher.openDirections,
                            church,
                          ),
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
                  color: const Color.fromRGBO(26, 26, 46, 0.8),
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
      rows.add(_infoRow(
        Icons.calendar_today_outlined,
        'Founded',
        '${church.foundedYear}',
      ));
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      height: 1,
                      color: Color.fromRGBO(26, 26, 46, 0.08),
                    ),
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
                  color: const Color.fromRGBO(26, 26, 46, 0.5),
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
        color: filled ? null : AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: filled
            ? null
            : Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.35),
              ),
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
