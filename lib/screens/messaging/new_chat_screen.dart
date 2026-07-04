import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../services/directory_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/verified_tick.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/shimmer_loaders.dart';

/// "New chat" people picker — search any member and tap to open a 1:1
/// chat. Replaces the opt-in member directory as the New-chat target so
/// the list is never empty (it searches all discoverable profiles).
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  // Your accepted friends — loaded once, filtered locally in Friends mode.
  List<MemberDirectoryEntry> _friends = const [];
  List<MemberDirectoryEntry> _results = const [];
  bool _loading = true;
  bool _opening = false;
  // false = your friends only (default). true = explore everyone on Advent.
  bool _explore = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
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
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
      // (and yourself). This is the "find friends" list the tester wanted —
      // all non-friends alphabetically, not a handful of suggestions.
      final all = await DirectoryService.fetchAllDiscoverableProfiles();
      if (!mounted || !_explore) return;
      final friendIds = _friends.map((f) => f.userId).toSet();
      setState(() {
        _results = all.where((m) => !friendIds.contains(m.userId)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
        });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  /// Tapping a person no longer jumps straight into a chat. Ask first:
  /// message them, or view their profile (tester request).
  Future<void> _onTapUser(MemberDirectoryEntry m) async {
    final name = (m.fullName ?? '').trim().isEmpty
        ? 'Member'
        : m.fullName!.trim();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  _Avatar(name: name, photoUrl: m.profilePhotoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
            ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: AppColors.primaryBlue,
              ),
              title: const Text('View profile'),
              onTap: () => Navigator.pop(ctx, 'profile'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'chat') {
      _openChatWith(m);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not start the chat. Try again.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        title: const Text('New chat'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _ModeToggle(explore: _explore, onChanged: _setExplore),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: _explore
                      ? 'Search everyone on Advent'
                      : 'Search friends',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.palette.inputFill,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              // People-shaped shimmer that crossfades into the results;
              // the first screenful of rows cascades in.
              child: ContentReveal(
                loading: _loading,
                skeleton: ShimmerLoaders.peopleList(),
                child: _results.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final m = _results[i];
                          final name = (m.fullName ?? '').trim().isEmpty
                              ? 'Member'
                              : m.fullName!.trim();
                          final tile = PressEffect(
                            pressedScale: 0.97,
                            child: ListTile(
                              leading: _Avatar(
                                name: name,
                                photoUrl: m.profilePhotoUrl,
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  // Gold tick for verified accounts — was
                                  // missing from the people picker rows.
                                  if (m.isVerified) const VerifiedTick(),
                                ],
                              ),
                              subtitle: (m.churchName ?? '').trim().isEmpty
                                  ? null
                                  : Text(
                                      m.churchName!.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: context.palette.textMuted,
                                      ),
                                    ),
                              onTap: () => _onTapUser(m),
                            ),
                          );
                          if (i >= 10) return tile;
                          return StaggeredReveal(
                            index: i,
                            rise: 16,
                            child: tile,
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final message = _explore
        ? 'No people found. Try a different name.'
        : _searchController.text.trim().isEmpty
        ? 'No friends yet. Tap “Find people” to discover members on Advent.'
        : 'No friends match that name. Tap “Find people” to search everyone.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
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
          ],
        ),
      ),
    );
  }
}

/// Segmented "My friends" / "Find people" switch at the top of New chat.
/// A single blue thumb SLIDES between the two segments (with a gentle
/// spring) instead of each side snapping its own background colour.
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
  const _Avatar({required this.name, this.photoUrl});
  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : AppColors.primaryGradient,
      ),
      child: hasPhoto
          ? CachedImage(photoUrl!, fit: BoxFit.cover)
          : Text(
              initial,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
