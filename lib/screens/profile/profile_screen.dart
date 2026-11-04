import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/platform_flags.dart';
import '../../models/friendship_model.dart';
import '../../models/church_model.dart';
import '../../models/ministry_tag_model.dart';
import '../../services/ministry_service.dart';
import '../../widgets/profile/followers_status_card.dart';
import '../../widgets/ministry_chips.dart';
import '../../models/post_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../../services/premium_service.dart';
import '../../widgets/premium/premium_badge.dart';
import '../../utils/date_format.dart';
import '../../services/cache_service.dart';
import '../../services/church_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/event_service.dart';
import '../../services/feed_service.dart';
import '../../services/gallery_service.dart';
import '../../services/sabbath_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/comments_sheet.dart';
import '../../widgets/home/edit_post_dialog.dart';
import '../../widgets/home/invite_friends_card.dart';
import '../../widgets/home/post_card.dart';
import '../../widgets/home/post_image_viewer.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/last_updated_strip.dart';
import '../../widgets/friend_qr_sheet.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../utils/photo_url.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../theme/app_tokens.dart';
import '../widgets/tab_shell.dart';
import '../../config/countries.dart';
import '../../config/sda_divisions.dart';
import '../../config/share_config.dart';
import '../../services/follow_service.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/profile/profile_header.dart';
import 'package:share_plus/share_plus.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _churchesFollowed = 0;
  int _eventsGoing = 0;
  // Accepted friendships only — the stat strip shows "Friends", and a
  // count that included pending requests would overstate it.
  int _friendCount = 0;
  List<Post> _myPosts = const [];
  List<Church> _myChurches = const [];
  // Approved church-admin roles for this user (patch_112). Non-empty → show
  // the "Church admin dashboard" entry so it's reachable WITHOUT hunting for
  // the approval notification.
  List<ChurchAdminRole> _adminRoles = const [];
  // Ministry involvement + spiritual gifts (patch_168).
  List<MinistryTag> _myTags = const [];
  // The viewer is a verified account (church admin or the super-admin
  // founder) — shows the gold tick on their own profile.
  bool _isVerified = false;
  int _tabIndex = 0;

  /// patch_274 follower numbers. Null until loaded / before the patch, in
  /// which case the header leaves those cells out rather than show zeros.
  FollowStats? _follow;

  /// The public-facing row (username, website, private flag) — auth
  /// metadata doesn't carry these.
  PublicUserProfile? _publicRow;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _loadPublicRow();
    FollowService.revision.addListener(_loadPublicRow);
    _loadAdminRoles();
    _loadVerified();
    _loadMinistryTags();
    TabShell.activeIndex.addListener(_onTabChanged);
    _postChangesSub = FeedService.postChanges.listen(_onPostChange);
    AuthService.profileName.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TabShell.activeIndex.removeListener(_onTabChanged);
    AuthService.profileName.removeListener(_onNameChanged);
    FollowService.revision.removeListener(_loadPublicRow);
    _postChangesSub?.cancel();
    super.dispose();
  }

  StreamSubscription<PostChange>? _postChangesSub;

  /// Same post, same state, on both tabs: a post made from Home lands here,
  /// one deleted here leaves Home (see FeedService.postChanges).
  void _onPostChange(PostChange c) {
    if (!mounted) return;
    final me = AuthService.currentUser?.id;
    setState(() {
      switch (c.kind) {
        case PostChangeKind.created:
          if (c.post!.authorId == me) {
            _myPosts = [c.post!, ..._myPosts.where((p) => p.id != c.id)];
          }
        case PostChangeKind.updated:
          _myPosts = [for (final p in _myPosts) p.id == c.id ? c.post! : p];
        case PostChangeKind.deleted:
          _myPosts = _myPosts.where((p) => p.id != c.id).toList();
      }
    });
  }

  DateTime _lastLoad = DateTime.now();

  /// Profile is a kept-alive tab, so `initState` runs once a session. Home
  /// says "Posted — see it on your profile", and the post was not there
  /// until the app restarted; friend and church counts went stale the same
  /// way. Refresh on return, throttled so flicking between tabs is free.
  void _onTabChanged() {
    if (TabShell.activeIndex.value != TabShell.profileIndex) return;
    final now = DateTime.now();
    if (now.difference(_lastLoad) < const Duration(seconds: 10)) return;
    _lastLoad = now;
    _bootstrap();
    _loadMinistryTags();
  }

  Future<void> _loadMinistryTags() async {
    final id = AuthService.currentUser?.id;
    if (id == null) return;
    // Paint the cached chips first. They used to arrive only after a
    // round-trip, so the ministry / spiritual-gifts section popped in
    // late on every visit and was simply blank offline.
    final cached = MinistryService.cachedMine();
    if (cached.isNotEmpty && mounted) setState(() => _myTags = cached);
    try {
      final tags = await MinistryService.fetchForProfile(id);
      if (mounted) setState(() => _myTags = tags);
    } catch (_) {
      // ignore — the section falls back to its "add" affordance.
    }
  }

  Future<void> _editMinistryTags() async {
    // Ministry and spiritual gifts are written straight to the server —
    // there is no outbox behind them. Offline, the picker opened normally,
    // the member made their choices, and the save failed at the end with
    // nothing explaining why. Say it BEFORE they do the work, not after.
    if (!ConnectivityService.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkNavy,
          content: Text(
            "You're offline — ministry and spiritual gifts need a "
            'connection to save. Try again once you\'re back online.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
      return;
    }
    final saved = await showMinistryPicker(
      context,
      selected: _myTags.map((t) => t.id).toSet(),
    );
    // Null means dismissed without saving — leave what we have.
    if (saved == null || !mounted) return;
    // The sheet already wrote to the server; re-read so the chips render
    // in the vocabulary's sort order rather than tap order.
    await _loadMinistryTags();
  }

  /// Best-effort load of the user's approved church-admin roles so the
  /// dashboard entry can appear. Silent on failure (the entry just stays
  /// hidden, exactly as for non-admins).
  Future<void> _loadAdminRoles() async {
    try {
      final roles = await ChurchService.fetchMyAdminRoles();
      if (mounted) setState(() => _adminRoles = roles);
    } catch (_) {
      // ignore — entry stays hidden.
    }
  }

  /// Whether the viewer is a verified account (church admin / super-admin
  /// founder), so we can show the gold tick on their own profile.
  Future<void> _loadVerified() async {
    final id = AuthService.currentUser?.id;
    if (id == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('is_verified, is_verified_admin')
          .eq('id', id)
          .maybeSingle();
      final v =
          row?['is_verified'] == true;
      if (mounted) setState(() => _isVerified = v);
    } catch (_) {
      // ignore — tick stays hidden.
    }
  }

  /// Open the church-admin dashboard. One role → straight in. Multiple
  /// (rare) → let the admin pick which church first.
  Future<void> _openAdminDashboard() async {
    if (_adminRoles.isEmpty) return;
    if (_adminRoles.length == 1) {
      context.pushNamed('admin_dashboard', extra: _adminRoles.first);
      return;
    }
    final picked = await showModalBottomSheet<ChurchAdminRole>(
      useRootNavigator: true,
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              'Choose a church',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final role in _adminRoles)
              ListTile(
                leading: const Icon(
                  Icons.church_outlined,
                  color: AppColors.primaryBlue,
                ),
                title: Text(
                  role.churchName,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Admin · ${role.role}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ctx.palette.textMuted,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, role),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      context.pushNamed('admin_dashboard', extra: picked);
    }
  }

  /// The "Personal account" card was dismissed on this phone. User-scoped
  /// on purpose (cleared on sign-out).
  static const _kFollowersCardHidden = 'followers_card_hidden_v1';
  late bool _followersCardHidden =
      CacheService.readPref(_kFollowersCardHidden) == '1';

  Future<void> _loadPublicRow() async {
    final me = AuthService.currentUser?.id;
    if (me == null) return;
    try {
      final row = await UserProfileService.fetch(me);
      if (mounted && row != null) setState(() => _publicRow = row);
    } catch (_) {}
    try {
      final stats = await FollowService.stats(me);
      if (mounted) setState(() => _follow = stats);
    } catch (_) {}
  }

  Future<void> _shareProfile() async {
    final me = AuthService.currentUser?.id;
    if (me == null) return;
    await Share.share(
      '${_displayName()} on Adventist Super App\n${friendShareUrl(me)}',
      subject: _displayName(),
    );
  }

  Future<void> _bootstrap() async {
    _hydrateFromCache();
    unawaited(_loadPublicRow());
    final viewerId = AuthService.currentUser?.id;
    try {
      final results = await Future.wait([
        ChurchService.fetchUserFollowedChurchIds(),
        EventService.fetchUserRsvpedEventIds(),
        // Own posts newest-first (profile order), NOT the home feed's
        // personalised order.
        FeedService.fetchPostsByAuthor(AuthService.currentUser?.id ?? ''),
        FeedService.fetchMyFriendships(),
      ]);
      if (!mounted) return;
      final followed = results[0] as Set<String>;
      final allPosts = results[2] as List<Post>;
      final friends = (results[3] as List<Friendship>)
          .where((f) => f.isAccepted)
          .length;
      final myPosts = viewerId == null
          ? const <Post>[]
          : allPosts.where((p) => p.authorId == viewerId).toList();
      // Fetch the two or three churches this member follows, by id.
      // This used to download the ENTIRE directory and filter it down to
      // those few — 2,600 rows to keep 3 today, 185,000 after the OrgMast
      // import. It also had to wait for that download before the profile
      // could paint.
      final myChurches = await ChurchService.fetchChurchesByIds(followed);
      if (!mounted) return;
      setState(() {
        _churchesFollowed = followed.length;
        _eventsGoing = (results[1] as Set).length;
        _myPosts = myPosts;
        _myChurches = myChurches;
        _friendCount = friends;
      });
      unawaited(
        _writeCache(
          myPosts,
          myChurches,
          churchesFollowed: followed.length,
          eventsGoing: (results[1] as Set).length,
          friendCount: friends,
        ),
      );
    } catch (_) {
      // ignore — UI just keeps showing whatever it has from cache.
    }
  }

  static const _cacheKey = 'profile_self';

  void _hydrateFromCache() {
    try {
      final raw = CacheService.readString(_cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final viewerId = AuthService.currentUser?.id;
      final posts = ((decoded['posts'] as List?) ?? const [])
          .map(
            (p) => Post.fromJson(p as Map<String, dynamic>, viewerId: viewerId),
          )
          .toList();
      final churches = ((decoded['churches'] as List?) ?? const [])
          .map((c) => Church.fromJson(c as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        if (_myPosts.isEmpty) _myPosts = posts;
        if (_myChurches.isEmpty) _myChurches = churches;
        // Paint last-known counts immediately. `_bootstrap` overwrites them
        // a moment later with the truth; showing yesterday's number beats
        // showing a zero that is definitely wrong.
        _churchesFollowed =
            (decoded['churches_followed'] as num?)?.toInt() ??
            _churchesFollowed;
        _eventsGoing =
            (decoded['events_going'] as num?)?.toInt() ?? _eventsGoing;
        _friendCount =
            (decoded['friend_count'] as num?)?.toInt() ?? _friendCount;
      });
    } catch (_) {
      // ignore — corrupt cache is just a missed paint.
    }
  }

  Future<void> _writeCache(
    List<Post> posts,
    List<Church> churches, {
    required int churchesFollowed,
    required int eventsGoing,
    required int friendCount,
  }) async {
    try {
      final payload = jsonEncode({
        'posts': posts.take(50).map((p) => p.toJson()).toList(),
        'churches': churches.map((c) => c.toJson()).toList(),
        // The three stat-row numbers. Posts and churches were already
        // cached, but these were not — so every visit painted friends,
        // churches and events as 0 and only corrected them once FIVE
        // network calls had all come back. On a slow connection the first
        // thing your own profile told you was that you had no friends.
        'churches_followed': churchesFollowed,
        'events_going': eventsGoing,
        'friend_count': friendCount,
      });
      await CacheService.writeString(_cacheKey, payload);
    } catch (_) {}
  }

  String _displayName() {
    final user = AuthService.currentUser;
    final name = AuthService.myFullName;
    if (name.isNotEmpty) return name;
    return user?.email ?? 'Welcome';
  }

  String _initials() {
    final name = _displayName();
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _bio() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final bio = (meta['bio'] as String?)?.trim() ?? '';
    if (bio.isNotEmpty) return bio;
    return 'Add a bio to tell the community about yourself.';
  }

  /// The date this account joined, from the Supabase auth user's created_at.
  DateTime? _joinedAt() {
    final raw = AuthService.currentUser?.createdAt;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Parses the user's date of birth from metadata (stored as an ISO
  /// string at signup / age-verification). Returns null if absent or
  /// malformed.
  DateTime? _birthDate() {
    final meta = AuthService.currentUser?.userMetadata ?? const {};
    final raw = (meta['date_of_birth'] ?? meta['birth_date'])?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Age in whole years, or null if no birth date / out of range.
  int? _age() {
    final dob = _birthDate();
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age -= 1;
    }
    return age < 0 || age > 120 ? null : age;
  }

  /// True when today (month + day) matches the user's birthday.
  bool _isBirthdayToday() {
    final dob = _birthDate();
    if (dob == null) return false;
    final now = DateTime.now();
    return now.month == dob.month && now.day == dob.day;
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: AppTextStyles.headlineSmall),
        content: Text(
          'You\'ll need to sign in again to access the community.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelMedium.copyWith(
                color: context.palette.text,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('Sign out', style: AppTextStyles.labelLarge),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Resolve the router BEFORE the await, and navigate WITHOUT a `mounted`
    // check afterwards.
    //
    // This is why "sign out did nothing until you restarted the app".
    // AuthService.signOut() tears down the session, which rebuilds the tree
    // and disposes this screen — so by the time it returned, `mounted` was
    // false, the guard on the next line returned early, and `goNamed` never
    // ran. The sign-out itself had worked perfectly: state was cleared,
    // which is exactly why relaunching showed you signed out. Only the
    // navigation was skipped, so you were left sitting on a profile screen
    // belonging to an account that no longer had a session.
    //
    // `mounted` is the wrong guard here. It protects setState and anything
    // that reads `context` after an await — but GoRouter is an object we
    // can hold, and it outlives this widget by design. Grabbing it first
    // makes the navigation independent of whether the screen survived.
    // This one IS a real post-await context use — the dialog above was
    // awaited — so it keeps its guard. It is the guard AFTER signOut() that
    // was wrong.
    if (!mounted) return;
    final router = GoRouter.of(context);
    try {
      await AuthService.signOut();
    } finally {
      // In `finally`: a failure partway through the reset still leaves the
      // session unusable, so stranding the member on a dead profile screen
      // is the worst possible outcome. Land on auth either way.
      //
      // After sign-out land on the unified auth screen. The standalone
      // age-verification screen is no longer in the first-run flow.
      router.goNamed('login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandedRefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _bootstrap,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Sections cascade in instead of the old one-block fade.
          child: Column(
            children: [
              // Soft glow from the profile photo behind the top section
              // only (owner-approved exception — see ProfileGlow).
              ProfileGlow(
                photoUrl: _profilePhotoUrl(),
                child: Column(
                  children: [
                    StaggeredReveal(
                      index: 0,
                      rise: 14,
                      child: _buildHeader(),
                    ),
                    StaggeredReveal(index: 1, child: _buildProfileHeader()),
                  ],
                ),
              ),
              // Personal account (followers off) or followers on — said
              // plainly, with the switch (patch_287, 29 Oct 2026).
              if (_publicRow != null && !_followersCardHidden)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: FollowersStatusCard(
                    current: _publicRow!.whoCanFollow,
                    onChanged: (_) => _loadPublicRow(),
                    onDismiss: _publicRow!.whoCanFollow.allowsFollowers
                        ? null
                        : () {
                            CacheService.writePref(_kFollowersCardHidden, '1');
                            setState(() => _followersCardHidden = true);
                          },
                  ),
                ),
              const SizedBox(height: 18),
              // Ministry & gifts (patch_168) — what you serve in and
              // what you bring. Sits above the tabs because it is
              // identity, not one of several views of your content.
              StaggeredReveal(
                index: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: MinistrySection(
                    tags: _myTags,
                    isOwn: true,
                    onEdit: _editMinistryTags,
                  ),
                ),
              ),
              StaggeredReveal(index: 4, child: _buildTabSelector()),
              const SizedBox(height: 12),
              StaggeredReveal(index: 4, child: _buildTabContent()),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      // The island is TabShell's.
    );
  }

  /// Three-up stat strip. Replaces the old run-on sentence of counts —
  /// numbers set as numbers are scannable, and each cell is a tap target
  /// rather than decoration.
  ///
  /// Every figure here is real: friends and posts are counted from loaded
  /// data, churches from the followed set. "Prayers" is deliberately
  /// absent — nothing in this screen's data tells us how many prayers the
  /// user has posted, and a fabricated stat is worse than a missing one.
  /// The member's home church name, or null if they haven't set one.
  ///
  /// `profiles.church_id` is mirrored into auth metadata, and the app's own
  /// rule is that the followed set IS the home church (you cannot follow
  /// others) — so match on the id where the metadata has it and fall back
  /// to the single followed church when it doesn't.
  String? get _homeChurchName {
    final id = AuthService.currentUser?.userMetadata?['church_id']
        ?.toString()
        .trim();
    if (id != null && id.isNotEmpty) {
      for (final c in _myChurches) {
        if (c.id == id) return c.name;
      }
    }
    return _myChurches.isEmpty ? null : _myChurches.first.name;
  }

  /// The shared profile header (also used for other people's profiles),
  /// fed from this screen's own data. Every number is real: posts and
  /// friends from loaded data, followers from patch_274 — left out, not
  /// zeroed, when that isn't available.
  Widget _buildProfileHeader() {
    final row = _publicRow;
    final follow = _follow;
    final church = _homeChurchName;
    final age = _age();
    final place = <String?>[
      row?.city,
      Countries.nameOf(row?.country),
    ].where((s) => (s ?? '').isNotEmpty).join(', ');
    final me = AuthService.currentUser?.id ?? '';
    final meta = AuthService.currentUser?.userMetadata ?? const {};
    final bio = (meta['bio'] as String?)?.trim();

    void openList(String tab) => context.pushNamed(
      'follows',
      pathParameters: {'userId': me},
      queryParameters: {'tab': tab},
    );

    return ValueListenableBuilder<bool>(
      valueListenable: PremiumService.isPremium,
      builder: (context, isPremium, _) => ProfileHeader(
        name: _displayName(),
        initials: _initials(),
        username: row?.username,
        photoUrl: _profilePhotoUrl(),
        coverUrl: _coverPhotoUrl(),
        bio: bio,
        verified: _isVerified,
        premiumRing: isPremium,
        // Premium sits AFTER the verified tick: verification says who you
        // are, premium says you support the app — paid is not verified.
        badges: [
          if (isPremium) const PremiumBadge(size: 20),
          // Your own profile only: a quiet outlined tick that goes to the
          // ID check, until the real gold tick replaces it (patch 309).
          if (!kHidePayments && !_isVerified)
            Tooltip(
              message: 'Get the gold tick',
              child: InkResponse(
                radius: 18,
                onTap: () => context.pushNamed('get_verified'),
                child: Icon(
                  Icons.verified_outlined,
                  size: 19,
                  color: context.palette.textMuted,
                ),
              ),
            ),
          if (row?.isPrivate ?? false)
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: context.palette.textMuted,
            ),
        ],
        completion: _profileCompletion(),
        onAvatarTap: () {
          final photo = _profilePhotoUrl();
          // The ring means "unfinished": tapping it goes to finish it.
          if (photo == null || _profileCompletion() < 1.0) {
            context.pushNamed('edit_profile');
          } else {
            FullImageViewer.show(context, photoUrlAtSize(photo, 1024));
          }
        },
        onCoverTap: _coverPhotoUrl() == null
            ? null
            : () => FullImageViewer.show(context, _coverPhotoUrl()),
        facts: [
          ProfileFact(
            Icons.church_outlined,
            church ?? 'Add your church',
            highlight: church == null,
            onTap: () => setState(() => _tabIndex = 3),
          ),
          if (place.isNotEmpty)
            ProfileFact(
              Icons.location_on_outlined,
              '${Countries.flagOf(row?.country)} $place'.trim(),
            ),
          // The member's Adventist world division, from their country.
          if (SdaDivisions.forCountry(row?.country) != null)
            ProfileFact(
              Icons.public_rounded,
              SdaDivisions.forCountry(row?.country)!,
            ),
          if (row?.website != null)
            ProfileFact(
              Icons.link_rounded,
              websiteLabel(row!.website!),
              onTap: () => openProfileWebsite(row.website!),
            ),
          if (_isBirthdayToday())
            const ProfileFact(
              Icons.cake_outlined,
              'Happy birthday!',
              highlight: true,
            )
          else if (age != null)
            ProfileFact(Icons.cake_outlined, '$age years old'),
          if (_joinedAt() != null)
            ProfileFact(
              Icons.calendar_today_outlined,
              'Joined ${formatJoinDate(_joinedAt()!)}',
            ),
        ],
        stats: [
          ProfileStat(
            _myPosts.length == 1 ? 'Post' : 'Posts',
            _myPosts.length,
            onTap: () => setState(() => _tabIndex = 0),
          ),
          // No "0 followers" on a personal account — it can't have any.
          if (_publicRow?.whoCanFollow.allowsFollowers ?? false)
            ProfileStat(
              'Followers',
              follow?.followers,
              onTap: () => openList('followers'),
            ),
          ProfileStat(
            'Following',
            follow?.following,
            onTap: () => openList('following'),
          ),
          ProfileStat(
            _friendCount == 1 ? 'Friend' : 'Friends',
            _friendCount,
            onTap: () => context.pushNamed('friends'),
          ),
        ],
        actions: [
          ProfileActionButton(
            label: 'Edit profile',
            icon: Icons.edit_outlined,
            primary: true,
            onTap: () => context.pushNamed('edit_profile'),
          ),
          ProfileActionButton(
            label: 'Share',
            icon: Icons.ios_share_rounded,
            onTap: _shareProfile,
          ),
          ProfileActionButton.icon(
            icon: Icons.more_horiz,
            label: 'More',
            onTap: _openMoreMenu,
          ),
        ],
      ),
    );
  }

  Future<void> _openMoreMenu() async {
    final result = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      backgroundColor: Colors.transparent,
      // Scroll-controlled and scrollable: the menu has outgrown a short
      // phone (29 Oct 2026, "bottom overflowed by 35 pixels").
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: context.palette.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              // Subscription entry point. Shown to everyone — paying is
              // the only route to ad-free, so a church admin sees this
              // exactly like anyone else. Listens so the label flips the
              // moment a purchase lands, without reopening the sheet.
              // Hidden on iOS: no In-App Purchase is configured there.
              if (!kHidePayments)
                ValueListenableBuilder<bool>(
                  valueListenable: PremiumService.isPremium,
                  builder: (context, isPremium, _) => _MoreMenuRow(
                    icon: isPremium
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    label: isPremium ? 'Your Premium' : 'Go Premium',
                    accent: AppColors.goldAccent,
                    onTap: () => Navigator.pop(ctx, 'premium'),
                  ),
                ),
              // The gold tick's ID check (patch 289). Hidden on iOS with
              // every other paid feature; hidden once the tick is on.
              if (!kHidePayments && !(_publicRow?.showsVerifiedTick ?? false))
                _MoreMenuRow(
                  icon: Icons.verified_outlined,
                  label: 'Get the gold tick',
                  onTap: () => Navigator.pop(ctx, 'get_verified'),
                ),
              if (_publicRow?.isPrivate ?? false)
                _MoreMenuRow(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Follow requests',
                  onTap: () => Navigator.pop(ctx, 'follow_requests'),
                ),
              _MoreMenuRow(
                icon: Icons.apartment_rounded,
                label: 'Pages',
                onTap: () => Navigator.pop(ctx, 'pages'),
              ),
              _MoreMenuRow(
                icon: Icons.event_available_outlined,
                label: _eventsGoing > 0
                    ? "Events I'm going to ($_eventsGoing)"
                    : "Events I'm going to",
                onTap: () => Navigator.pop(ctx, 'events'),
              ),
              _MoreMenuRow(
                icon: Icons.bookmark_border_rounded,
                label: 'Saved posts',
                onTap: () => Navigator.pop(ctx, 'saved_posts'),
              ),
              _MoreMenuRow(
                icon: Icons.favorite_border_rounded,
                label: 'Saved listings',
                onTap: () => Navigator.pop(ctx, 'saved_listings'),
              ),
              _MoreMenuRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => Navigator.pop(ctx, 'settings'),
              ),
              _MoreMenuRow(
                icon: Icons.feedback_outlined,
                label: 'Send feedback',
                onTap: () => Navigator.pop(ctx, 'feedback'),
              ),
              _MoreMenuRow(
                icon: Icons.brightness_3_outlined,
                label: 'Sabbath timer',
                onTap: () => Navigator.pop(ctx, 'sabbath_timer'),
              ),
              _MoreMenuRow(
                icon: Icons.logout,
                label: 'Sign out',
                destructive: true,
                onTap: () => Navigator.pop(ctx, 'sign_out'),
              ),
            ],
          ),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case 'get_verified':
        context.pushNamed('get_verified');
        break;
      case 'premium':
        context.pushNamed('premium');
        break;
      case 'settings':
        context.pushNamed('settings');
        break;
      case 'saved_posts':
        context.pushNamed('saved_posts');
        break;
      case 'follow_requests':
        context.pushNamed('follow_requests');
        break;
      case 'events':
        context.pushNamed('events');
        break;
      case 'pages':
        context.pushNamed('pages');
        break;
      case 'saved_listings':
        context.pushNamed('saved_listings');
        break;
      case 'notifications':
        context.pushNamed('notification_preferences');
        break;
      case 'feedback':
        context.pushNamed('feedback');
        break;
      case 'sabbath_timer':
        context.pushNamed('sabbath_timer');
        break;
      case 'sign_out':
        await _signOut();
        break;
    }
  }

  Widget _buildTabSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.divider),
      ),
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          _TabPill(
            label: 'Posts',
            selected: _tabIndex == 0,
            onTap: () => setState(() => _tabIndex = 0),
          ),
          const SizedBox(width: 5),
          _TabPill(
            label: 'About',
            selected: _tabIndex == 1,
            onTap: () => setState(() => _tabIndex = 1),
          ),
          const SizedBox(width: 5),
          _TabPill(
            label: 'Photos',
            selected: _tabIndex == 2,
            onTap: () => setState(() => _tabIndex = 2),
          ),
          const SizedBox(width: 5),
          _TabPill(
            label: 'Churches',
            selected: _tabIndex == 3,
            onTap: () => setState(() => _tabIndex = 3),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildPostsTab();
      case 1:
        return _buildAboutTab();
      case 2:
        return _buildPhotosTab();
      case 3:
        return _buildChurchesTab();
      default:
        return const SizedBox.shrink();
    }
  }

  /// "Share something…" at the top of your own Posts. Opens the same
  /// composer as Home, and the new post reaches both tabs through
  /// FeedService.postChanges — one post, not a profile copy.
  Widget _buildComposerPrompt() {
    final palette = context.palette;
    final photo = _profilePhotoUrl();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: () => showPostComposer(context),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primaryBlue,
                  backgroundImage: photo == null
                      ? null
                      : CachedNetworkImageProvider(
                          photoUrlAtSize(
                            photo,
                            (36 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                          ),
                        ),
                  child: photo == null
                      ? Text(
                          _initials(),
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share something…',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
                const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primaryBlue,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostsTab() {
    if (_myPosts.isEmpty) {
      return Column(
        children: [
          _buildComposerPrompt(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Text(
              'Your posts will appear here and in your friends\' feeds.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ),
        ],
      );
    }
    final viewerId = AuthService.currentUser?.id;
    final cachedAt = CacheService.cachedAt(_cacheKey);
    return Column(
      children: [
        _buildComposerPrompt(),
        if (cachedAt != null) ...[
          const SizedBox(height: 4),
          LastUpdatedStrip(
            timestamp: cachedAt,
            isOnline: ConnectivityService.isOnline,
            onRefresh: _bootstrap,
          ),
          const SizedBox(height: 4),
        ],
        for (final post in _myPosts)
          PostCard(
            post: post,
            viewerId: viewerId,
            onLikeToggled: () => _toggleLike(post),
            onCommentsTapped: () => _openComments(post),
            onImageTapped: (index) async {
              // Multi-photo posts hand back the tapped index; this screen
              // still opens the first photo full-screen.
              final url = post.imageUrl;
              if (url == null || url.isEmpty) return;
              await PostImageViewer.show(
                context,
                imageUrl: url,
                heroTag: 'post_image_${post.id}',
              );
            },
            onEdit: () => _editPost(post),
            onDelete: () => _confirmDeletePost(post),
            onToggleVisibility: () => _togglePostVisibility(post),
            onSaveImage: () => _savePostImage(post),
          ),
      ],
    );
  }

  Future<void> _toggleLike(Post post) async {
    final newLiked = !post.viewerLiked;
    final newCount = (post.likeCount + (newLiked ? 1 : -1)).clamp(0, 1 << 30);
    setState(() {
      _myPosts = _myPosts
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
        _myPosts = _myPosts
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
          _myPosts = _myPosts
              .map(
                (p) => p.id == post.id ? p.copyWith(commentCount: newCount) : p,
              )
              .toList();
        });
      },
    );
  }

  Future<void> _savePostImage(Post post) async {
    final url = post.imageUrl;
    if (url == null || url.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.darkNavy,
        duration: const Duration(seconds: 2),
        content: Text(
          'Saving image to gallery…',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
    final ok = await GalleryService.saveImageFromUrl(url);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: ok ? AppColors.successGreen : AppColors.red,
        content: Text(
          ok
              ? 'Saved to your Adventist Super App album.'
              : 'Could not save the image. Check storage permission and try again.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _togglePostVisibility(Post post) async {
    final newVisibility = post.visibility == PostVisibility.public
        ? PostVisibility.friendsOnly
        : PostVisibility.public;
    try {
      final updated = await FeedService.updatePost(
        post.id,
        visibility: newVisibility,
      );
      if (!mounted) return;
      setState(() {
        _myPosts = _myPosts
            .map((p) => p.id == updated.id ? updated : p)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVisibility == PostVisibility.public
                ? 'Post is now public.'
                : 'Post is now visible to friends only.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not update post. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _editPost(Post post) async {
    final newBody = await showEditPostDialog(
      context,
      initialBody: post.body ?? '',
    );
    if (newBody == null) return;
    try {
      final updated = await FeedService.updatePost(post.id, body: newBody);
      if (!mounted) return;
      setState(() {
        _myPosts = _myPosts
            .map((p) => p.id == updated.id ? updated : p)
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not save changes.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete post?',
          style: AppTextStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will remove the post for everyone. You can\'t undo it.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.buttonText.copyWith(
                color: context.palette.text,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FeedService.deletePost(post.id);
      if (!mounted) return;
      setState(() {
        _myPosts = _myPosts.where((p) => p.id != post.id).toList();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not delete post. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Widget _buildAboutTab() {
    // The completeness card hides itself at 100%, so the gap after it has
    // to be conditional — a fixed SizedBox would leave a hole on a
    // finished profile. Without it the card sat flush against the About
    // card below, the only pair on the tab with no space between them.
    final showCompleteness = _completenessItems().any((i) => !i.value);
    return Column(
      children: [
        if (showCompleteness) ...[
          _buildCompletenessCard(),
          const SizedBox(height: 16),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildBioCard(),
        ),
        if (_adminRoles.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildChurchAdminCard(),
        ],
        const SizedBox(height: 16),
        _buildAccountCard(),
        const SizedBox(height: 16),
        const InviteFriendsCard(),
      ],
    );
  }

  /// Church-admin dashboard entry (patch_112). Only shown when the user has
  /// at least one approved church-admin role, so a member who hasn't claimed
  /// a church never sees it.
  Widget _buildChurchAdminCard() {
    final multi = _adminRoles.length > 1;
    final subtitle = multi
        ? 'You manage ${_adminRoles.length} churches — post announcements, '
              'events and manage info.'
        : 'Post announcements, events and manage info for '
              '${_adminRoles.first.churchName}.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Church admin',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openAdminDashboard,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Open admin dashboard',
                    style: AppTextStyles.buttonText.copyWith(
                      color: AppColors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
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

  Widget _buildPhotosTab() {
    final withImages = _myPosts
        .where((p) => (p.imageUrl ?? '').isNotEmpty)
        .toList();
    if (withImages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Text(
          'No photos yet — posts with images will show up here.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: context.palette.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: withImages.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemBuilder: (_, i) {
          final post = withImages[i];
          return GestureDetector(
            onTap: () => PostImageViewer.show(
              context,
              imageUrl: post.imageUrl!,
              heroTag: 'post_image_${post.id}',
            ),
            child: Hero(
              tag: 'post_image_${post.id}',
              child: CachedImage(post.imageUrl!, fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChurchesTab() {
    if (_myChurches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Text(
          'You haven\'t followed any churches yet.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: context.palette.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final church in _myChurches)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.divider),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.pushNamed(
                    'church_details',
                    pathParameters: {'id': church.id},
                    extra: church,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.church,
                            color: AppColors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                church.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              if (church.city.isNotEmpty)
                                Text(
                                  church.city,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: context.palette.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.primaryBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _coverPhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['cover_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  String? _profilePhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['profile_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  /// Flat header + optional cover band + avatar.
  ///
  /// The navy slab is gone (founder rule, 28 Jul 2026). What replaces it
  /// depends on whether there IS a cover photo:
  ///   - cover set   → an inset, rounded photo band under the flat header
  ///   - no cover    → nothing. The header simply sits on scaffoldBg and
  ///                   the identity card moves up. A missing photo is not
  ///                   a reason to paint a navy rectangle.
  ///
  /// Note the header is a `Container`, not a childless `DecoratedBox` —
  /// that collapses to zero height and paints nothing, which is exactly
  /// how the Watch header's gradient vanished.
  Widget _buildHeader() {
    return FlatStatusBar(
      child: Container(
        // Transparent so the app-wide ambient field runs behind the header
        // instead of stopping at its bottom edge. This sits in the normal
        // flow above the scroll view, so it has nothing to occlude — the
        // `scaffoldBg` here was hiding the particles across the top of the
        // screen, which is the "background is cut out at the top" report.
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile',
                          style: AppTextStyles.displayMedium.copyWith(
                            color: context.palette.text,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // Sabbath greeting, flat and gold — the same marker
                        // Home uses, so the day reads consistently across
                        // the app instead of only on one tab. NOT a navy →
                        // gold gradient: see CLAUDE.md's Sabbath rule.
                        //
                        // Gated on isSabbathNow() alone, deliberately not on
                        // SabbathService.isEnabled(). That flag is the opt-in
                        // for the countdown CHIP — a member who never turned
                        // the countdown on is still an Adventist on Sabbath,
                        // and greeting them is not the same as pestering
                        // them with a timer.
                        // Rebuilds at sundown and when the place changes.
                        ValueListenableBuilder<int>(
                          valueListenable: SabbathService.changes,
                          builder: (context, _, _) => !SabbathService
                                  .isSabbathNow()
                              ? const SizedBox.shrink()
                              : Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Happy Sabbath',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: AppColors.goldAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Friend QR — Adventists meet in person, and scanning
                    // beats spelling a name into a search box in a noisy
                    // hall at camp meeting.
                    HeaderIconButton(
                      icon: Icons.qr_code_2,
                      tooltip: 'Your friend code',
                      onTap: () => showFriendQrSheet(context),
                    ),
                    const SizedBox(width: 8),
                    // NOTE: the Premium entry is deliberately NOT a fourth
                    // header icon — three icons crowded the top-right and
                    // a star there read as "favourite", not "subscribe".
                    // It lives in the ⋮ sheet with the other account
                    // actions; see [_openMoreMenu].
                    HeaderIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onTap: () => context.pushNamed('settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Profile-completeness checklist. Each entry maps a friendly label to
  /// whether that field is filled in the user's metadata.
  List<MapEntry<String, bool>> _completenessItems() {
    final meta = AuthService.currentUser?.userMetadata ?? const {};
    String s(String k) => (meta[k] as String?)?.trim() ?? '';
    final church = meta['church_id'];
    return [
      MapEntry('Add a profile photo', s('profile_photo_url').isNotEmpty),
      MapEntry(
        'Set your home church',
        church != null && church.toString().isNotEmpty,
      ),
      MapEntry('Write a short bio', s('bio').isNotEmpty),
      MapEntry('Add your date of birth', _birthDate() != null),
      MapEntry('Add your full name', s('full_name').isNotEmpty),
    ];
  }

  /// Fraction (0..1) of the profile-completeness items that are done. Drives
  /// the ring around the avatar so an incomplete profile is obvious at a
  /// glance, without scrolling to the card.
  double _profileCompletion() {
    final items = _completenessItems();
    if (items.isEmpty) return 1.0;
    return items.where((i) => i.value).length / items.length;
  }

  /// A "Complete your profile" card with an animated progress bar + the
  /// remaining steps. Hides itself once the profile is 100% complete so a
  /// finished profile never sees clutter.
  Widget _buildCompletenessCard() {
    final items = _completenessItems();
    final done = items.where((i) => i.value).length;
    final total = items.length;
    if (done >= total) return const SizedBox.shrink();
    final pct = done / total;
    final missing = items.where((i) => !i.value).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => context.pushNamed('edit_profile'),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'COMPLETE YOUR PROFILE',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.palette.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(pct * 100).round()}%',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: pct),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      backgroundColor: context.palette.cardMuted,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...missing
                    .take(3)
                    .map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.radio_button_unchecked,
                              size: 16,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                i.key,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: context.palette.text,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: context.palette.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                if (missing.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+ ${missing.length - 3} more',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.palette.textMuted,
                        fontWeight: FontWeight.w600,
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

  Widget _buildBioCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ABOUT',
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _bio(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.text,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    // Marketplace selling now goes through the seller flow directly —
    // no business-account indirection. This card surfaces a single CTA
    // into the seller dashboard / setup, and the dashboard handles
    // the pending / rejected / approved branching itself.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.storefront,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sell on the marketplace',
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open a storefront in minutes — an admin reviews '
                        'your store profile once before it goes live.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.palette.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.pushNamed('seller_dashboard'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Open seller dashboard',
                    style: AppTextStyles.buttonText.copyWith(
                      color: AppColors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
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
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressEffect(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: selected ? AppColors.primaryGradient : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: selected ? AppColors.white : context.palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreMenuRow extends StatelessWidget {
  const _MoreMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  /// Tints one row so it reads as an offer rather than an errand. Gold is
  /// the scheme's single-highlight colour — keep it to ONE row.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.red
        : (accent ?? context.palette.text);
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
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
