import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../services/auth_service.dart';
import '../../services/directory_service.dart';
import '../../services/feed_service.dart';
import '../../services/messaging_service.dart';
import '../../services/presence_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/verified_tick.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/shimmer_loaders.dart';

/// Where a person stands with the viewer, which decides what the row's
/// trailing control offers.
enum _Bond { none, requested, incoming, friends }

/// "New chat" people picker.
///
/// Two jobs, and they used to be one undifferentiated list: pick somebody you
/// already know, or find somebody you don't. The second is where the friends
/// system actually lives — you could previously only send a friend request by
/// opening a profile, which is two screens away from the place you realise you
/// want to.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key, this.startInFindPeople = false});

  /// Opens straight into "Find people" instead of "My friends".
  ///
  /// Home's end-of-feed card sends people here to MEET someone, and landing
  /// them on their existing friends list would be answering a different
  /// question from the one they asked.
  final bool startInFindPeople;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  // Your accepted friends — loaded once, filtered locally in Friends mode.
  List<MemberDirectoryEntry> _friends = const [];
  List<MemberDirectoryEntry> _results = const [];
  bool _loading = true;

  /// Set when a load FAILED, so the screen can say so.
  ///
  /// Without this the catches below just stopped the spinner, `_results`
  /// stayed empty, and the empty state cheerfully announced "No friends
  /// yet. Tap Find people to discover members" — which is a lie when the
  /// request never landed. A failed load and an empty directory look
  /// identical to the member and need opposite reactions from them.
  String? _error;
  bool _opening = false;
  // false = your friends only (default). true = explore everyone on Advent.
  // Seeded from the widget so a caller can open straight into Find people.
  late bool _explore = widget.startInFindPeople;

  /// user id → where we stand with them. Drives the Add/Requested/Friends
  /// control on each row without a lookup per tile.
  Map<String, _Bond> _bonds = const {};
  /// Rows with a request in flight, so the button can't be double-tapped.
  final Set<String> _sending = <String>{};

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _loadBonds();
    // Opened straight into Find people: _setExplore is the normal entry
    // point and it early-returns when the flag already matches, so kick the
    // explore fetch off directly. Without this the screen would sit on an
    // empty list with the toggle already pointing at Find people.
    if (_explore) {
      _loading = true;
      _loadExploreSuggestions();
    }
    FeedService.friendshipsChanged.addListener(_onFriendshipsChanged);
  }

  void _onFriendshipsChanged() {
    if (mounted) _loadBonds();
  }

  @override
  void dispose() {
    FeedService.friendshipsChanged.removeListener(_onFriendshipsChanged);
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final list = await DirectoryService.fetchFriends();
      if (!mounted) return;
      setState(() {
        _friends = list;
        if (!_explore) _results = list;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your friends.';
      });
    }
  }

  /// One pass over every friendship the viewer is party to, so each row knows
  /// whether to offer "Add", "Requested", or nothing at all. Without this the
  /// explore list offers to befriend people you already asked last week.
  ///
  /// Re-runs whenever a friendship changes anywhere in the app — this map
  /// used to be loaded once in initState, so a row stayed on "Requested"
  /// after the other person had already accepted.
  Future<void> _loadBonds() async {
    try {
      final me = AuthService.currentUser?.id ?? '';
      final links = await FeedService.fetchMyFriendships();
      if (!mounted) return;
      final map = <String, _Bond>{};
      for (final f in links) {
        final other = f.requesterId == me ? f.addresseeId : f.requesterId;
        if (f.isAccepted) {
          map[other] = _Bond.friends;
        } else if (f.isPending) {
          map[other] = f.requesterId == me ? _Bond.requested : _Bond.incoming;
        }
      }
      setState(() => _bonds = map);
    } catch (_) {
      // Best-effort: without it rows just show "Add", and a duplicate
      // request is rejected server-side anyway.
    }
  }

  Future<void> _sendRequest(MemberDirectoryEntry m) async {
    if (_sending.contains(m.userId)) return;
    setState(() => _sending.add(m.userId));
    try {
      await FeedService.sendRequest(m.userId);
      if (!mounted) return;
      setState(() {
        _sending.remove(m.userId);
        _bonds = {..._bonds, m.userId: _Bond.requested};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending.remove(m.userId));
      _toast('Could not send the request. Try again.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.darkNavy,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  /// Switch between "My friends" and "Find people" (global explore).
  void _setExplore(bool explore) {
    if (_explore == explore) return;
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _explore = explore;
      _loading = explore; // friends are already in hand; explore needs a fetch
      _results = explore ? const [] : _friends;
    });
    if (explore) _loadExploreSuggestions();
  }

  Future<void> _loadExploreSuggestions() async {
    try {
      // Everyone on Advent, A→Z, minus the people you're already friends with
      // (and yourself).
      final all = await DirectoryService.fetchAllDiscoverableProfiles();
      if (!mounted || !_explore) return;
      final friendIds = _friends.map((f) => f.userId).toSet();
      setState(() {
        _results = all.where((m) => !friendIds.contains(m.userId)).toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load members.';
      });
    }
  }

  void _onSearch(String q) {
    final query = q.trim();
    // Friends mode filters the already-loaded friend list instantly.
    if (!_explore) {
      setState(() {
        _results = query.isEmpty
            ? _friends
            : _friends
                  .where(
                    (m) => (m.fullName ?? '').toLowerCase().contains(
                      query.toLowerCase(),
                    ),
                  )
                  .toList();
      });
      return;
    }
    // Explore mode searches everyone on Advent (debounced network call).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (query.isEmpty) {
        _loadExploreSuggestions();
        return;
      }
      setState(() => _loading = true);
      try {
        final list = await DirectoryService.searchProfilesByName(query);
        if (!mounted || !_explore) return;
        setState(() {
          _results = list;
          _loading = false;
          _error = null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Could not search members.';
        });
      }
    });
  }

  /// Tapping a person asks first: message them, or view their profile.
  Future<void> _onTapUser(MemberDirectoryEntry m) async {
    final name = (m.fullName ?? '').trim().isEmpty
        ? 'Member'
        : m.fullName!.trim();
    final bond = _bonds[m.userId] ?? _Bond.none;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  _Avatar(name: name, photoUrl: m.profilePhotoUrl, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if ((m.churchName ?? '').trim().isNotEmpty)
                          Text(
                            m.churchName!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: ctx.palette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.primaryBlue,
              ),
              title: const Text('Message'),
              onTap: () => Navigator.pop(ctx, 'chat'),
            ),
            if (bond == _Bond.none)
              ListTile(
                leading: const Icon(
                  Icons.person_add_alt_1,
                  color: AppColors.primaryBlue,
                ),
                title: const Text('Add friend'),
                onTap: () => Navigator.pop(ctx, 'add'),
              ),
            ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: AppColors.primaryBlue,
              ),
              title: const Text('View profile'),
              onTap: () => Navigator.pop(ctx, 'profile'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'chat') {
      _openChatWith(m);
    } else if (choice == 'add') {
      _sendRequest(m);
    } else if (choice == 'profile') {
      context.pushNamed('user_profile', pathParameters: {'userId': m.userId});
    }
  }

  Future<void> _openChatWith(MemberDirectoryEntry m) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: m.userId,
        otherUserName: (m.fullName ?? '').trim().isEmpty
            ? 'Member'
            : m.fullName!.trim(),
      );
      if (!mounted) return;
      context.pushReplacementNamed('chat', pathParameters: {'id': convo.id});
    } catch (_) {
      if (mounted) {
        setState(() => _opening = false);
        _toast('Could not start the chat. Try again.');
      }
    }
  }

  Future<void> _openSelfChat() async {
    try {
      final convo = await MessagingService.openSelfChat();
      if (!mounted) return;
      context.pushReplacementNamed('chat', pathParameters: {'id': convo.id});
    } catch (_) {
      if (mounted) _toast('Could not open Notes to self. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: Column(
        children: [
          const ScreenHero(
            title: 'New chat',
            tagline: 'Advent Chat',
            fallbackRoute: 'messages',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _ModeToggle(explore: _explore, onChanged: _setExplore),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _SearchField(
              controller: _searchController,
              focusNode: _searchFocus,
              hint: _explore
                  ? 'Search everyone on Advent'
                  : 'Search your friends',
              onChanged: _onSearch,
              onClear: () {
                _searchController.clear();
                _onSearch('');
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: ContentReveal(
              loading: _loading,
              skeleton: ShimmerLoaders.peopleList(),
              child: _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    // The quick actions only belong on the un-searched Friends view: they are
    // "the other things you might have come here to do", and once you're
    // typing a name you have already decided.
    final showQuickActions =
        !_explore && _searchController.text.trim().isEmpty;

    // A failed load is NOT an empty directory. Show the failure and a way
    // to re-run it; the search field, the Friends/Find-people toggle and
    // the quick actions above stay live throughout.
    if (_error != null && _results.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          if (showQuickActions) _quickActions(),
          ErrorBanner(message: _error!, onRetry: _retryLoad),
        ],
      );
    }

    if (_results.isEmpty && !showQuickActions) return _buildEmptyState(context);

    return ValueListenableBuilder<Set<String>>(
      valueListenable: PresenceService.onChange,
      builder: (context, online, _) {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
          itemCount: _results.length + (showQuickActions ? 1 : 0) + 1,
          itemBuilder: (context, rawIndex) {
            if (showQuickActions && rawIndex == 0) return _quickActions();
            final i = rawIndex - (showQuickActions ? 1 : 0);
            if (i == _results.length) {
              return _results.isEmpty
                  ? _buildEmptyState(context)
                  : const SizedBox(height: 8);
            }
            final m = _results[i];
            final name = (m.fullName ?? '').trim().isEmpty
                ? 'Member'
                : m.fullName!.trim();
            final tile = Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PersonCard(
                name: name,
                photoUrl: m.profilePhotoUrl,
                church: m.churchName,
                verified: m.isVerified,
                // Presence is for FRIENDS only. This used to light up for
                // anyone in the Explore list, so browsing strangers
                // broadcast who was at their phone right now to someone
                // they have no relationship with — and "Online now" on a
                // person you've never met reads as surveillance, not a
                // feature. A pending request doesn't count either;
                // accepting is what grants it.
                online: (_bonds[m.userId] == _Bond.friends) &&
                    online.contains(m.userId),
                bond: _bonds[m.userId] ?? _Bond.none,
                busy: _sending.contains(m.userId),
                // In Friends mode the bond is a given, so the trailing
                // control would only ever say "Friends" — noise on every row.
                showBond: _explore,
                onTap: () => _onTapUser(m),
                onAdd: () => _sendRequest(m),
              ),
            );
            if (i >= 10) return tile;
            return StaggeredReveal(index: i, rise: 16, child: tile);
          },
        );
      },
    );
  }

  /// The three things people come to "New chat" for that aren't a person.
  /// They lived only in the compose sheet before, which meant arriving here
  /// by mistake was a dead end.
  Widget _quickActions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          _QuickAction(
            icon: Icons.group_add_rounded,
            label: 'New group',
            subtitle: 'Start a group with your friends',
            onTap: () => context.pushNamed('create_group'),
          ),
          const SizedBox(height: 8),
          _QuickAction(
            icon: Icons.bookmark_outline,
            label: 'Notes to self',
            subtitle: 'Save links, verses and reminders',
            onTap: _openSelfChat,
          ),
          const SizedBox(height: 8),
          _QuickAction(
            icon: Icons.person_search_rounded,
            label: 'Find people',
            subtitle: 'Discover members across Advent',
            onTap: () => _setExplore(true),
          ),
        ],
      ),
    );
  }

  /// Re-runs whichever load failed, without leaving the screen.
  void _retryLoad() {
    setState(() {
      _error = null;
      _loading = true;
    });
    if (_explore) {
      final q = _searchController.text.trim();
      if (q.isEmpty) {
        _loadExploreSuggestions();
      } else {
        _onSearch(q);
      }
    } else {
      _loadFriends();
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final searching = _searchController.text.trim().isNotEmpty;
    final message = _explore
        ? (searching
              ? 'No one matches that name.'
              : 'No members to show yet.')
        : searching
        ? 'No friends match that name. Try “Find people” to search everyone.'
        : 'No friends yet. Tap “Find people” to discover members on Advent.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _explore ? Icons.person_search_rounded : Icons.diversity_3,
                size: 34,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.palette.textMuted,
                height: 1.5,
              ),
            ),
            if (!_explore && !searching) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 190,
                child: PrimaryGradientButton(
                  label: 'Find people',
                  icon: Icons.public_rounded,
                  onTap: () => _setExplore(true),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pill search field, matching the inbox so the two read as one system.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.cardMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search, size: 19, color: palette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.text,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: palette.textMuted,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: palette.textMuted),
              splashRadius: 18,
              onPressed: onClear,
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// A non-person destination at the top of the friends list.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: AppColors.primaryBlue, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
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
            Icon(Icons.chevron_right, color: palette.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// One person, as a card rather than a ListTile.
///
/// Carries the three things that decide whether you message somebody in a
/// faith community: who they are, whether you share a congregation, and
/// whether they're reachable right now.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.name,
    required this.photoUrl,
    required this.church,
    required this.verified,
    required this.online,
    required this.bond,
    required this.busy,
    required this.showBond,
    required this.onTap,
    required this.onAdd,
  });

  final String name;
  final String? photoUrl;
  final String? church;
  final bool verified;
  final bool online;
  final _Bond bond;
  final bool busy;
  final bool showBond;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final churchName = (church ?? '').trim();
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                _Avatar(name: name, photoUrl: photoUrl, size: 46),
                if (online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppColors.successGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.card, width: 2.2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
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
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (verified) const VerifiedTick(size: 14),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    churchName.isNotEmpty
                        ? churchName
                        : online
                        ? 'Online now'
                        : 'Adventist Super App member',
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
            if (showBond) ...[
              const SizedBox(width: 8),
              _BondButton(bond: bond, busy: busy, onAdd: onAdd),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Add / Requested / Friends control.
///
/// Only "Add" is actionable — the other two are status labels. Showing a live
/// button for a request already sent is how people end up spamming somebody
/// they asked once.
class _BondButton extends StatelessWidget {
  const _BondButton({
    required this.bond,
    required this.busy,
    required this.onAdd,
  });

  final _Bond bond;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (busy) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
    }
    switch (bond) {
      case _Bond.none:
        return Pressable(
          onTap: onAdd,
          pressedScale: 0.9,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 14, color: AppColors.white),
                const SizedBox(width: 4),
                Text(
                  'Add',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        );
      case _Bond.requested:
        return _StatusChip(label: 'Requested', color: palette.textMuted);
      case _Bond.incoming:
        return _StatusChip(label: 'Asked you', color: AppColors.primaryBlue);
      case _Bond.friends:
        return _StatusChip(label: 'Friends', color: AppColors.successGreen);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Segmented "My friends" / "Find people" switch. A single blue thumb SLIDES
/// between the two segments instead of each side snapping its own colour.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.explore, required this.onChanged});
  final bool explore;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.palette.inputFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 38,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: AppMotion.maybe(context, AppMotion.standard),
              curve: AppMotion.spring,
              alignment: explore ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _seg(
                  context,
                  label: 'My friends',
                  icon: Icons.people_alt_rounded,
                  selected: !explore,
                  onTap: () => onChanged(false),
                ),
                _seg(
                  context,
                  label: 'Find people',
                  icon: Icons.public_rounded,
                  selected: explore,
                  onTap: () => onChanged(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.white : context.palette.textMuted,
              ),
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: AppMotion.maybe(context, AppMotion.quick),
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.white : context.palette.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl, this.size = 44});
  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : AppColors.primaryGradient,
      ),
      child: hasPhoto
          ? CachedImage(photoUrl!, fit: BoxFit.cover, width: size, height: size)
          : Text(
              initial,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38,
              ),
            ),
    );
  }
}
