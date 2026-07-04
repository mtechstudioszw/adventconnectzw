import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/member_directory_model.dart';
import '../../services/directory_service.dart';
import '../../services/group_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';

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
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        title: const Text('New group'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
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
                      decoration: InputDecoration(
                        hintText: 'Group name',
                        filled: true,
                        fillColor: context.palette.inputFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _descController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Description (optional)',
                  filled: true,
                  fillColor: context.palette.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_selected.isNotEmpty)
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final m in _selected.values)
                      _SelectedChip(
                        member: m,
                        onRemove: () => _toggle(m),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Search people',
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
              child: _loadingPeople
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryBlue,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final m = _results[i];
                        final selected = _selected.containsKey(m.userId);
                        return _PersonPickTile(
                          member: m,
                          selected: selected,
                          onTap: () => _toggle(m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: AppColors.white,
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text('Create (${_selected.length})'),
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
              _Avatar(photoUrl: member.profilePhotoUrl, name: name, size: 50),
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
    final name = (member.fullName ?? '').trim().isEmpty
        ? 'Member'
        : member.fullName!.trim();
    return ListTile(
      onTap: onTap,
      leading: _Avatar(photoUrl: member.profilePhotoUrl, name: name, size: 44),
      title: Text(
        name,
        style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: (member.churchName ?? '').trim().isEmpty
          ? null
          : Text(
              member.churchName!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? AppColors.primaryBlue : context.palette.divider,
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.name, this.size = 44});
  final String? photoUrl;
  final String name;
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
