import 'dart:async';
import '../../widgets/motion/brand_spinner.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../services/directory_service.dart';
import '../../services/group_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/screen_shell.dart';

/// WhatsApp-style "New group": name + optional icon + description, pick
/// members, create. On success it opens the new group chat.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key, this.preselectUserId});

  /// When opened from a contact ("Create group with X"), this member is
  /// pre-selected once the people list loads.
  final String? preselectUserId;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _searchController = TextEditingController();
  Timer? _debounce;

  String? _photoUrl;
  bool _uploadingPhoto = false;
  bool _creating = false;

  // Groups are friends-only: the picker lists the user's accepted friends
  // (the server rejects non-friends in add_group_members, patch_118).
  List<MemberDirectoryEntry> _friends = const [];
  List<MemberDirectoryEntry> _results = const [];
  bool _loadingPeople = true;
  final Map<String, MemberDirectoryEntry> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggested() async {
    try {
      final list = await DirectoryService.fetchFriends();
      if (!mounted) return;
      setState(() {
        _friends = list;
        _results = list;
        _loadingPeople = false;
        // Pre-select the contact this group was started with.
        final pre = widget.preselectUserId;
        if (pre != null && !_selected.containsKey(pre)) {
          for (final m in list) {
            if (m.userId == pre) {
              _selected[m.userId] = m;
              break;
            }
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPeople = false);
    }
  }

  // Friends-only group: filter the loaded friend list locally by name.
  void _onSearch(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _results = query.isEmpty
          ? _friends
          : _friends
              .where((m) =>
                  (m.fullName ?? '').toLowerCase().contains(query))
              .toList();
    });
  }

  void _toggle(MemberDirectoryEntry m) {
    setState(() {
      if (_selected.containsKey(m.userId)) {
        _selected.remove(m.userId);
      } else {
        _selected[m.userId] = m;
      }
    });
  }

  Future<void> _pickIcon() async {
    setState(() => _uploadingPhoto = true);
    try {
      final url = await StorageService.pickAndUploadProfilePhoto();
      if (!mounted) return;
      if (url != null) setState(() => _photoUrl = url);
    } catch (_) {
      if (mounted) _toast('Could not upload the icon.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Give the group a name.');
      return;
    }
    if (_selected.isEmpty) {
      _toast('Add at least one member.');
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await GroupService.createGroup(
        name: name,
        photoUrl: _photoUrl,
        description: _descController.text.trim(),
        memberIds: _selected.keys.toList(),
      );
      if (!mounted) return;
      // Replace this screen with the new group chat.
      context.pushReplacementNamed('chat', pathParameters: {'id': id});
    } catch (_) {
      if (mounted) {
        setState(() => _creating = false);
        _toast('Could not create the group. Try again.');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.scaffoldBg,
      body: Column(
        children: [
          const ScreenHero(
            title: 'New group',
            tagline: 'Advent Chat',
            fallbackRoute: 'messages',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              children: [
                // Identity first: the icon, the name and what it's for, in
                // one card. Three loose inputs stacked down the screen read
                // as a form; this reads as the thing being made.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _GroupIconPicker(
                            photoUrl: _photoUrl,
                            uploading: _uploadingPhoto,
                            onTap: _pickIcon,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              onChanged: (_) => setState(() {}),
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: 'Group name',
                                hintStyle: AppTextStyles.titleMedium.copyWith(
                                  color: palette.textMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(color: palette.divider, height: 22),
                      TextField(
                        controller: _descController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        minLines: 1,
                        style: AppTextStyles.bodyMedium.copyWith(fontSize: 13.5),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'What is this group for? (optional)',
                          hintStyle: AppTextStyles.bodyMedium.copyWith(
                            color: palette.textMuted,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      _selected.isEmpty
                          ? 'ADD MEMBERS'
                          : '${_selected.length} SELECTED',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    if (_selected.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(_selected.clear),
                        child: Text(
                          'Clear',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_selected.isNotEmpty)
                  SizedBox(
                    height: 84,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final m in _selected.values)
                          _SelectedChip(member: m, onRemove: () => _toggle(m)),
                      ],
                    ),
                  ),
                _SearchField(
                  controller: _searchController,
                  onChanged: _onSearch,
                ),
                const SizedBox(height: 10),
                if (_loadingPeople)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: BrandSpinner(size: 30)),
                  )
                else if (_results.isEmpty)
                  _buildPeopleEmptyState(context)
                else
                  for (final m in _results)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PersonPickTile(
                        member: m,
                        selected: _selected.containsKey(m.userId),
                        onTap: () => _toggle(m),
                      ),
                    ),
              ],
            ),
          ),
          _buildCreateBar(context),
        ],
      ),
    );
  }

  /// Groups are friends-only (the server rejects non-friends in
  /// add_group_members, patch_118). An empty picker with no explanation was
  /// indistinguishable from a broken screen — say why, and offer the fix.
  Widget _buildPeopleEmptyState(BuildContext context) {
    final searching = _searchController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 10),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.diversity_3,
              size: 32,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            searching
                ? 'No friends match that name.'
                : 'You can only add friends to a group. Add a few friends '
                      'first and they\'ll show up here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
              height: 1.5,
            ),
          ),
          if (!searching) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 190,
              child: PrimaryGradientButton(
                label: 'Find people',
                icon: Icons.person_search_rounded,
                onTap: () => context.pushNamed('new_chat'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Sticky create bar. A FAB that only appears once somebody is selected
  /// gave no hint that a group needs members at all — this states the
  /// requirement up front and stays disabled until it's met.
  Widget _buildCreateBar(BuildContext context) {
    final palette = context.palette;
    final ready = _nameController.text.trim().isNotEmpty && _selected.isNotEmpty;
    final hint = _nameController.text.trim().isEmpty
        ? 'Name the group to continue'
        : _selected.isEmpty
        ? 'Add at least one member'
        : '${_selected.length} member${_selected.length == 1 ? '' : 's'}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                hint,
                style: AppTextStyles.labelSmall.copyWith(
                  color: palette.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 148,
              child: PrimaryGradientButton(
                label: 'Create group',
                busy: _creating,
                onTap: ready && !_creating ? _create : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill search field, matching the inbox and the people picker.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

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
              onChanged: onChanged,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.text,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search your friends',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: palette.textMuted,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _GroupIconPicker extends StatelessWidget {
  const _GroupIconPicker({
    required this.photoUrl,
    required this.uploading,
    required this.onTap,
  });
  final String? photoUrl;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryBlue.withValues(alpha: 0.10),
        ),
        child: uploading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryBlue,
                  ),
                ),
              )
            : (photoUrl == null || photoUrl!.isEmpty)
                ? const Icon(
                    Icons.add_a_photo_outlined,
                    color: AppColors.primaryBlue,
                  )
                : CachedImage(photoUrl!, fit: BoxFit.cover),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.member, required this.onRemove});
  final MemberDirectoryEntry member;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = (member.fullName ?? 'Member').split(' ').first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              UserAvatar(photoUrl: member.profilePhotoUrl, name: name, size: 50),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.darkNavy,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                color: context.palette.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonPickTile extends StatelessWidget {
  const _PersonPickTile({
    required this.member,
    required this.selected,
    required this.onTap,
  });
  final MemberDirectoryEntry member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = (member.fullName ?? '').trim().isEmpty
        ? 'Member'
        : member.fullName!.trim();
    final church = (member.churchName ?? '').trim();
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          // Selected rows tint rather than only flipping a small trailing
          // glyph — at a glance you can see who's in without reading down
          // the right-hand edge.
          color: selected
              ? Color.alphaBlend(
                  AppColors.primaryBlue.withValues(alpha: 0.10),
                  palette.card,
                )
              : palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primaryBlue : palette.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            UserAvatar(photoUrl: member.profilePhotoUrl, name: name, size: 42),
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
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (church.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      church,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.primaryBlue : palette.divider,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
