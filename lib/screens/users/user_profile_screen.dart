import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/countries.dart';
import '../../models/friendship_model.dart';
import '../../models/member_directory_model.dart';
import '../../models/ministry_tag_model.dart';
import '../../models/post_model.dart';
import '../../services/directory_service.dart';
import '../../services/ministry_service.dart';
import '../../widgets/ministry_chips.dart';
import '../../utils/date_format.dart';
import '../../services/auth_service.dart';
import '../../services/block_service.dart';
import '../../services/feed_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/home/report_sheet.dart';
import '../../services/messaging_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/motion/brand_spinner.dart';

/// Viewing another user's profile (not the logged-in user — that's the
/// regular ProfileScreen). Surfaces:
///   - cover + avatar + name + age
///   - friendship action (Add / Pending / Accept / Friends)
///   - Message button → opens a chat
///   - For non-private profiles: bio, location, recent posts grid
///   - For private profiles (is_discoverable=false): name + age only
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicUserProfile? _profile;
  Friendship? _friendship;
  List<Post> _posts = const [];
  bool _loading = true;
  bool _friendBusy = false;
  String? _error;

  /// patch_166. Church + mutual-friend COUNT for the person being viewed.
  /// The same signal the chat header carries — "do we belong to the same
  /// congregation, and do we know any of the same people" is the question
  /// a profile should answer first. The RPC returns a count only, never
  /// the identities, so the friend graph stays private.
  ({String? churchName, int mutualFriends})? _peerContext;

  /// The mutual friends themselves (patch_182) — faces and names, not
  /// just the count above. A number tells you there is common ground;
  /// seeing *who* is what actually makes a stranger's profile feel
  /// placed. Empty until the RPC resolves, and for your own profile.
  List<MemberDirectoryEntry> _mutuals = const [];
  int _mutualTotal = 0;

  /// Their ministry involvement + spiritual gifts (patch_168). RLS
  /// returns nothing for a non-discoverable profile, so this stays
  /// empty and the section renders nothing.
  List<MinistryTag> _tags = const [];

  String? get _viewerId => AuthService.currentUser?.id;
  bool get _isSelf => _viewerId == widget.userId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        UserProfileService.fetch(widget.userId),
        FeedService.fetchMyFriendships(),
        BlockService.amIBlockedBy(widget.userId),
      ]);
      if (!mounted) return;
      // If this user blocked the viewer, their profile reads as
      // unavailable (no about/posts/stories — those are RLS-hidden too).
      if (results[2] as bool) {
        setState(() {
          _loading = false;
          _error = 'This account is unavailable.';
        });
        return;
      }
      final profile = results[0] as PublicUserProfile?;
      final friendships = results[1] as List<Friendship>;
      Friendship? f;
      for (final candidate in friendships) {
        if (candidate.involves(widget.userId)) {
          f = candidate;
          break;
        }
      }
      setState(() {
        _profile = profile;
        _friendship = f;
        _loading = false;
        _error = profile == null ? 'Profile not found.' : null;
      });

      // Posts load is best-effort — RLS already filters friends-only
      // posts so we can issue the same query for everyone.
      if (profile != null && profile.isDiscoverable) {
        _loadPosts();
      }
      // Peer context is useful even on a private profile — knowing you
      // share a church is exactly what helps you decide whether to send
      // the request that would open it up.
      if (profile != null && !_isSelf) {
        _loadPeerContext();
      }
      if (profile != null) {
        _loadMinistryTags();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this profile.';
      });
    }
  }

  Future<void> _loadPosts() async {
    try {
      // Profile posts are strictly newest-first (NOT the personalised
      // home-feed order) so the profile reads latest → oldest.
      final posts = await FeedService.fetchPostsByAuthor(widget.userId);
      if (!mounted) return;
      setState(() {
        _posts = posts;
      });
    } catch (_) {
      // ignore — empty posts state is fine.
    }
  }

  Future<void> _loadPeerContext() async {
    try {
      final ctx = await MessagingService.fetchPeerContext(widget.userId);
      if (!mounted) return;
      setState(() => _peerContext = ctx);
    } catch (_) {
      // Best-effort — the strip just doesn't render.
    }
    // Who those mutuals actually are. Separate call so a failure here
    // never costs the church/count strip above.
    final mutual = await DirectoryService.fetchMutualFriends(widget.userId);
    if (!mounted) return;
    setState(() {
      _mutuals = mutual.people;
      _mutualTotal = mutual.total;
    });
  }

  Future<void> _loadMinistryTags() async {
    try {
      final tags = await MinistryService.fetchForProfile(widget.userId);
      if (!mounted) return;
      setState(() => _tags = tags);
    } catch (_) {
      // Best-effort — the section just doesn't render.
    }
  }

  Future<void> _addFriend() async {
    setState(() => _friendBusy = true);
    try {
      final created = await FeedService.sendRequest(widget.userId);
      if (!mounted) return;
      setState(() {
        _friendship = created;
        _friendBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendBusy = false);
      _showError('Could not send friend request.');
    }
  }

  Future<void> _cancelOrUnfriend() async {
    final f = _friendship;
    if (f == null) return;
    final wasAccepted = f.isAccepted;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          wasAccepted ? 'Unfriend?' : 'Cancel friend request?',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          wasAccepted
              ? 'You\'ll no longer see each other\'s friends-only posts.'
              : 'The pending request to ${_profile?.fullName ?? "this member"} will be withdrawn.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Keep',
              style: AppTextStyles.buttonText.copyWith(color: ctx.palette.text),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(wasAccepted ? 'Unfriend' : 'Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _friendBusy = true);
    try {
      await FeedService.removeFriendship(f.id);
      if (!mounted) return;
      setState(() {
        _friendship = null;
        _friendBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendBusy = false);
      _showError('Could not update friendship.');
    }
  }

  Future<void> _acceptIncoming() async {
    final f = _friendship;
    if (f == null) return;
    setState(() => _friendBusy = true);
    try {
      await FeedService.acceptRequest(f.id);
      if (!mounted) return;
      setState(() {
        _friendship = Friendship(
          id: f.id,
          requesterId: f.requesterId,
          addresseeId: f.addresseeId,
          status: FriendshipStatus.accepted,
          createdAt: f.createdAt,
        );
        _friendBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendBusy = false);
      _showError('Could not accept request.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.red,
        content: Text(
          msg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _openChat() async {
    final profile = _profile;
    if (profile == null) return;
    // WhatsApp behaviour: tap the contact, land directly inside an
    // empty chat with them — no "Hi {name} 👋" auto-message, no
    // confirmation sheet. The user types their own opener.
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: widget.userId,
        otherUserName: profile.fullName,
        source: 'direct',
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      context.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not open chat. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _reportUser() async {
    final sent = await showReportSheet(
      context,
      contentType: 'profile',
      contentId: widget.userId,
      contentLabel: 'this profile',
    );
    if (!mounted || sent != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.successGreen,
        content: Text(
          'Report sent. The admin team will review it.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.palette.scaffoldBg,
        body: const Center(child: BrandSpinner(size: 30)),
      );
    }
    if (_error != null || _profile == null) {
      return Scaffold(
        backgroundColor: context.palette.scaffoldBg,
        appBar: AppBar(),
        body: Center(
          child: Text(
            _error ?? 'Profile not found.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(),
            const SizedBox(height: 8),
            _buildNameBlock(),
            const SizedBox(height: 16),
            if (!_isSelf) _buildActionToolbar(),
            const SizedBox(height: 18),
            // Shared church + mutual friends, above the bio — it is the
            // context you read the rest of the profile through.
            ?_buildPeerContextStrip(),
            ?_buildMutualFriendsRow(),
            if (_profile!.isDiscoverable)
              ..._buildPublicSections()
            else
              _buildPrivateNotice(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Flat header + optional cover band + avatar. Mirrors the own-profile
  /// header: no navy slab when there's no cover photo, and the back /
  /// report controls are header chips on the scaffold colour rather than
  /// translucent circles floating on a gradient.
  Widget _buildHero() {
    final cover = _profile!.coverPhotoUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    return FlatStatusBar(
      child: Container(
        color: context.palette.scaffoldBg,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                child: Row(
                  children: [
                    const ScreenHeroBackButton(),
                    const Spacer(),
                    if (!_isSelf)
                      HeaderIconButton(
                        icon: Icons.flag_outlined,
                        tooltip: 'Report this profile',
                        onTap: _reportUser,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: hasCover ? 190 : 124,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    if (hasCover)
                      Positioned(
                        top: 0,
                        left: 16,
                        right: 16,
                        height: 132,
                        child: GestureDetector(
                          onTap: () => FullImageViewer.show(context, cover),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: CachedImage(
                              cover,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(color: context.palette.cardMuted),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 118,
                        height: 118,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.palette.cardMuted,
                          border: Border.all(
                            color: context.palette.scaffoldBg,
                            width: 5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          onTap:
                              (_profile!.profilePhotoUrl != null &&
                                  _profile!.profilePhotoUrl!.isNotEmpty)
                              ? () => FullImageViewer.show(
                                  context,
                                  _profile!.profilePhotoUrl,
                                )
                              : null,
                          child:
                              _profile!.profilePhotoUrl != null &&
                                  _profile!.profilePhotoUrl!.isNotEmpty
                              ? CachedImage(
                                  _profile!.profilePhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          _initialAvatar(),
                                )
                              : _initialAvatar(),
                        ),
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

  /// Overlapping faces + names of the friends you have in common, the way
  /// Facebook does it: "Rutendo, Blessing and 6 others".
  ///
  /// Only the intersection is ever fetched (patch_182), so this shows the
  /// viewer people they already know — it never discloses who else this
  /// member is friends with. Renders nothing when there are none, rather
  /// than announcing "0 mutual friends".
  Widget? _buildMutualFriendsRow() {
    if (_isSelf || _mutuals.isEmpty) return null;
    final shown = _mutuals.take(3).toList();
    final names = shown
        .map((m) => (m.fullName ?? '').trim().split(RegExp(r'\s+')).first)
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    final others = _mutualTotal - names.length;
    final summary = others > 0
        ? '${names.join(', ')} and $others other${others == 1 ? '' : 's'}'
        : names.join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          SizedBox(
            width: 28.0 + (shown.length - 1) * 18.0,
            height: 28,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * 18.0,
                    child: Container(
                      width: 28,
                      height: 28,
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                        border: Border.all(
                          color: context.palette.scaffoldBg,
                          width: 2,
                        ),
                      ),
                      child: (shown[i].profilePhotoUrl ?? '').isEmpty
                          ? Center(child: _miniInitial(shown[i].fullName))
                          : CachedImage(
                              shown[i].profilePhotoUrl!,
                              fit: BoxFit.cover,
                              width: 28,
                              height: 28,
                              errorBuilder: (_, _, _) =>
                                  Center(child: _miniInitial(shown[i].fullName)),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$summary ${others > 0 || names.length > 1 ? 'are' : 'is'} '
              'mutual friend${_mutualTotal == 1 ? '' : 's'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInitial(String? name) {
    final trimmed = (name ?? '').trim();
    return Text(
      trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
      textAlign: TextAlign.center,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w800,
        fontSize: 11,
        height: 1,
      ),
    );
  }

  /// "You both go to Glen View SDA · 3 mutual friends" — the two facts
  /// that answer "who is this to me". Renders nothing when the RPC hasn't
  /// resolved or has nothing to say, rather than showing "0 mutual
  /// friends", which reads as a judgement.
  Widget? _buildPeerContextStrip() {
    final ctx = _peerContext;
    if (ctx == null) return null;
    final church = ctx.churchName?.trim();
    final mutual = ctx.mutualFriends;
    final bits = <({IconData icon, String label})>[
      if (church != null && church.isNotEmpty)
        (icon: Icons.church_outlined, label: church),
      if (mutual > 0)
        (
          icon: Icons.people_alt_outlined,
          label: '$mutual mutual friend${mutual == 1 ? '' : 's'}',
        ),
    ];
    if (bits.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < bits.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: context.palette.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Icon(bits[i].icon, size: 14, color: AppColors.primaryBlue),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  bits[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: context.palette.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _initialAvatar() {
    final initial = _profile!.fullName.trim().isEmpty
        ? '?'
        : _profile!.fullName.trim().substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(gradient: AppColors.primaryGradient),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.displayLarge.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 42,
        ),
      ),
    );
  }

  Widget _buildNameBlock() {
    final age = _profile!.age;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _profile!.fullName,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
              if (_profile!.showsVerifiedTick) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.verified,
                  color: AppColors.goldAccent,
                  size: 20,
                ),
              ],
              if (_profile!.isBusiness) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Business',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (age != null && (_isSelf || _profile!.showAge)) ...[
            const SizedBox(height: 4),
            Text(
              '$age years old',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionToolbar() {
    final f = _friendship;
    final isIncomingPending =
        f != null && _viewerId != null && f.isIncomingPendingFor(_viewerId!);

    final (String label, IconData icon, VoidCallback? onTap) = (() {
      if (_friendBusy) return ('Working…', Icons.hourglass_empty, null);
      if (f == null) return ('Add friend', Icons.person_add_alt_1, _addFriend);
      if (f.isAccepted) return ('Friends', Icons.check, _cancelOrUnfriend);
      if (isIncomingPending) return ('Accept', Icons.check, _acceptIncoming);
      return ('Requested', Icons.hourglass_top_rounded, _cancelOrUnfriend);
    })();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _PrimaryButton(
              icon: icon,
              label: label,
              onTap: onTap,
              highlighted: f?.isAccepted ?? false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: _SquareButton(
              icon: Icons.chat_bubble_outline,
              onTap: _openChat,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPublicSections() {
    return [
      if ((_profile!.bio ?? '').trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _profile!.bio!.trim(),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
          ),
        ),
      const SizedBox(height: 14),
      if ((_profile!.city ?? '').isNotEmpty ||
          (_profile!.province ?? '').isNotEmpty ||
          (_profile!.country ?? '').isNotEmpty ||
          (_profile!.churchName ?? '').isNotEmpty ||
          _profile!.joinedAt != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((_profile!.churchName ?? '').isNotEmpty)
                _InfoChip(
                  icon: Icons.church_outlined,
                  label: _profile!.churchName!,
                ),
              // One location chip, flag-led. The flag replaces the pin
              // icon rather than sitting beside it — on a global app the
              // country IS the location signal, and a pin plus a flag is
              // two marks saying the same thing.
              //
              // Province is deliberately dropped from this line. It only
              // ever appeared next to city, where for most Zimbabwean
              // members it rendered "Harare, Harare"; the country is the
              // half that actually tells you something now.
              if ((_profile!.city ?? '').isNotEmpty ||
                  (_profile!.country ?? '').isNotEmpty)
                _InfoChip(
                  emoji: Countries.flagOf(_profile!.country),
                  icon: Icons.location_on_outlined,
                  label: <String?>[
                    _profile!.city,
                    Countries.nameOf(_profile!.country),
                  ].where((s) => (s ?? '').isNotEmpty).join(', '),
                ),
              if (_profile!.joinedAt != null)
                _InfoChip(
                  icon: Icons.calendar_today_outlined,
                  label: 'Joined ${formatJoinDate(_profile!.joinedAt!)}',
                ),
            ],
          ),
        ),
      // Ministry & gifts (patch_168) — read-only here. Turns "who is
      // this" into "who can help with this", which is the question a
      // church directory exists to answer.
      if (_tags.isNotEmpty) ...[
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MinistrySection(tags: _tags, isOwn: false),
        ),
      ],
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Text(
              'Posts',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_posts.length}',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (_posts.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Text(
            'Nothing posted yet.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        )
      else
        Column(
          children: [
            for (final post in _posts)
              PostCard(
                post: post,
                viewerId: _viewerId,
                onLikeToggled: () => _toggleLike(post),
                onCommentsTapped: () => _openComments(post),
                onImageTapped: (_) => _openImage(post),
              ),
          ],
        ),
    ];
  }

  /// Optimistic like/unlike — same pattern as home_screen so the
  /// search-to-profile path supports liking instead of the empty
  /// `() {}` no-op it had before.
  Future<void> _toggleLike(Post post) async {
    final newLiked = !post.viewerLiked;
    final newCount = (post.likeCount + (newLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() {
      _posts = _posts
          .map(
            (p) => p.id == post.id
                ? p.copyWith(
                    viewerReaction: newLiked ? PostReaction.like : null,
                    likeCount: newCount,
                  )
                : p,
          )
          .toList();
    });
    try {
      if (newLiked) {
        await FeedService.likePost(post.id);
      } else {
        await FeedService.unlikePost(post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map(
              (p) => p.id == post.id
                  ? p.copyWith(
                      viewerReaction: post.viewerReaction,
                      likeCount: post.likeCount,
                    )
                  : p,
            )
            .toList();
      });
    }
  }

  Future<void> _openComments(Post post) {
    return showCommentsSheet(
      context,
      postId: post.id,
      postAuthorId: post.authorId,
      onCommentCountChanged: (newCount) {
        if (!mounted) return;
        setState(() {
          _posts = _posts
              .map(
                (p) => p.id == post.id ? p.copyWith(commentCount: newCount) : p,
              )
              .toList();
        });
      },
    );
  }

  Widget _buildPrivateNotice() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.divider),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.lock_outline,
              color: AppColors.primaryBlue,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              'This profile is private',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Only their name and age are shown. Send a friend request '
              'to see their bio, posts and more.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openImage(Post post) async {
    final url = post.imageUrl;
    if (url == null || url.isEmpty) return;
    await PostImageViewer.show(
      context,
      imageUrl: url,
      heroTag: 'post_image_${post.id}',
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: highlighted ? null : AppColors.primaryGradient,
            color: highlighted ? context.palette.cardMuted : null,
            borderRadius: BorderRadius.circular(12),
            border: highlighted
                ? Border.all(color: context.palette.divider)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: highlighted ? context.palette.text : AppColors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
                  color: highlighted ? context.palette.text : AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.divider),
          ),
          child: Icon(icon, color: AppColors.primaryBlue, size: 20),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({this.icon, this.emoji, required this.label})
      : assert(icon != null || emoji != null, 'chip needs a leading mark');

  final IconData? icon;

  /// Leading emoji, used instead of [icon] for the country chip. A flag
  /// carries the country faster than any icon could, and it means adding
  /// a country costs no asset — see `Country.flag`.
  final String? emoji;

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null)
            Text(emoji!, style: const TextStyle(fontSize: 13))
          else
            Icon(icon, size: 13, color: AppColors.primaryBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              color: context.palette.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
