import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/church_model.dart';
import '../../services/church_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

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
        SliverToBoxAdapter(child: _buildFollowButton()),
        SliverToBoxAdapter(child: _buildAbout(church)),
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

  Widget _buildFollowButton() {
    final following = _isFollowing;
    // Unclaimed churches can't post announcements, so following them
    // would just collect dead silence. Push the viewer toward the
    // claim flow instead — unless they're already following from
    // before the gate existed, in which case let them unfollow.
    if (!_hasAdmin && !following) {
      return _buildClaimCta();
    }
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

  Widget _buildClaimCta() {
    final church = _church;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.goldAccent.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.goldAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.verified_outlined,
                    color: AppColors.goldAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This church isn\'t claimed yet',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Until a pastor or elder claims it, no one can post announcements here — following would be quiet. If you\'re an admin, claim it to start posting.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: const Color.fromRGBO(26, 26, 46, 0.7),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: church == null
                        ? null
                        : () => context.pushNamed(
                              'claim_church',
                              pathParameters: {'id': church.id},
                              extra: church,
                            ),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              color: AppColors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Claim this church',
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
          ],
        ),
      ),
    );
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
    if (church.pastorName != null && church.pastorName!.isNotEmpty) {
      rows.add(_infoRow(Icons.person_outline, 'Pastor', church.pastorName!));
    }
    if (church.address != null && church.address!.isNotEmpty) {
      rows.add(_infoRow(Icons.place_outlined, 'Address', church.address!));
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
