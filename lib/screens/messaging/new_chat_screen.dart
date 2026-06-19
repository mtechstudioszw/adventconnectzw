import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../services/directory_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

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
      final list = await DirectoryService.fetchSuggestedMembers(limit: 40);
      if (!mounted || !_explore) return;
      setState(() {
        _results = list;
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
                .where((m) =>
                    (m.fullName ?? '').toLowerCase().contains(query.toLowerCase()))
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
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
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
        backgroundColor: AppColors.darkNavy,
        foregroundColor: AppColors.white,
        title: const Text('New chat'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _ModeToggle(
                explore: _explore,
                onChanged: _setExplore,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText:
                      _explore ? 'Search everyone on Advent' : 'Search friends',
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
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              _explore
                                  ? 'No people found. Try a different name.'
                                  : _searchController.text.trim().isEmpty
                                      ? 'No friends yet. Tap “Find people” to '
                                          'discover members on Advent.'
                                      : 'No friends match that name. Tap '
                                          '“Find people” to search everyone.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: context.palette.textMuted,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final m = _results[i];
                            final name = (m.fullName ?? '').trim().isEmpty
                                ? 'Member'
                                : m.fullName!.trim();
                            return ListTile(
                              leading: _Avatar(
                                  name: name, photoUrl: m.profilePhotoUrl),
                              title: Text(
                                name,
                                style: AppTextStyles.bodyMedium
                                    .copyWith(fontWeight: FontWeight.w600),
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
                              onTap: () => _openChatWith(m),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented "My friends" / "Find people" switch at the top of New chat.
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
      child: Row(
        children: [
          _seg(context, label: 'My friends', icon: Icons.people_alt_rounded,
              selected: !explore, onTap: () => onChanged(false)),
          _seg(context, label: 'Find people', icon: Icons.public_rounded,
              selected: explore, onTap: () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context,
      {required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? AppColors.white : context.palette.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.white : context.palette.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
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
