import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/member_directory_model.dart';
import '../../models/message_model.dart';
import '../../services/auth_service.dart';
import '../../services/directory_service.dart';
import '../../services/group_service.dart';
import '../../services/messaging_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/full_image_viewer.dart';

/// Group info / management. Members + admin badges, add/remove/promote,
/// invite link share, leave/delete. Admin-only actions are gated in the
/// UI and again by the SECURITY DEFINER RPCs.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Conversation? _group;
  List<GroupMember> _members = const [];
  bool _loading = true;

  String get _myId => AuthService.currentUser?.id ?? '';
  bool get _amAdmin =>
      !_isChurch && _members.any((m) => m.userId == _myId && m.isAdmin);
  // Active member (not left/removed). fetchMembers excludes left members.
  bool get _amMember => _members.any((m) => m.userId == _myId);
  bool get _isChurch => _group?.isChurchGroup ?? false;
  bool get _isChannel => _group?.isChurchChannel ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final convo =
          await MessagingService.fetchConversation(widget.conversationId);
      // Church groups have implicit membership (patch_078) — fetch from
      // profiles.church_id, not conversation_members. The announcements
      // channel shows only the count, so skip the list there.
      final isChurch = convo?.isChurchGroup ?? false;
      final isChannel = convo?.isChurchChannel ?? false;
      final List<GroupMember> members;
      if (isChannel) {
        members = await GroupService.fetchChurchMembers(widget.conversationId);
      } else if (isChurch) {
        members = await GroupService.fetchChurchMembers(widget.conversationId);
      } else {
        members = await GroupService.fetchMembers(widget.conversationId);
      }
      if (!mounted) return;
      setState(() {
        _group = convo;
        _members = members;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Founder's WhatsApp number for announcement-admin verification.
  // Country code first, NO '+' or spaces (e.g. Zimbabwe 077... -> 26377...).
  // TODO(founder): replace with your real WhatsApp number.
  static const String _announcementsWhatsApp = '263770000000';

  Future<void> _claimAdmin() async {
    final churchName = _group?.otherUserName ?? 'my church';
    final me = AuthService.currentUser;
    final myName =
        (me?.userMetadata?['full_name'] as String?)?.trim() ?? 'a member';
    final text = Uri.encodeComponent(
      'Hello, I would like to be verified to post announcements for '
      '"$churchName" on Advent Connect ZW. My name is $myName.',
    );
    final uri =
        Uri.parse('https://wa.me/$_announcementsWhatsApp?text=$text');
    final ok = await _confirm(
      'Request to post announcements',
      'To post announcements you must be verified by the Advent Connect '
          'team. This will open WhatsApp so you can send your request — '
          'once verified you\'ll be granted access manually.',
      'Open WhatsApp',
    );
    if (ok != true) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _toast('Could not open WhatsApp.', error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? AppColors.red : AppColors.successGreen,
        content: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
        ),
      ),
    );
  }

  Future<void> _shareInvite() async {
    try {
      final token = await GroupService.inviteToken(widget.conversationId);
      final link = 'https://mtechstudioszw.github.io/adventconnect-legal/'
          'join.html?g=$token';
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.palette.sheet,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite link',
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Anyone with this link can join the group.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: ctx.palette.textMuted),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ctx.palette.inputFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    link,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: ctx.palette.text),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: link));
                          Navigator.pop(ctx);
                          _toast('Link copied.');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Share.share(
                            'Join our group on Advent Connect: $link',
                          );
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      _toast('Could not create invite link.', error: true);
    }
  }

  Future<void> _resetInvite() async {
    final ok = await _confirm(
      'Reset invite link?',
      'The current link stops working. A new link is created that you can '
          'share.',
      'Reset',
    );
    if (ok != true) return;
    try {
      await GroupService.resetInvite(widget.conversationId);
      if (mounted) _toast('Invite link reset.');
    } catch (_) {
      if (mounted) _toast('Could not reset the link.', error: true);
    }
  }

  Future<void> _addMembers() async {
    final existing = _members.map((m) => m.userId).toSet();
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddMembersSheet(excludeIds: existing),
    );
    if (picked == null || picked.isEmpty) return;
    try {
      await GroupService.addMembers(widget.conversationId, picked);
      _toast('Members added.');
      _load();
    } catch (_) {
      _toast('Could not add members.', error: true);
    }
  }

  Future<void> _memberActions(GroupMember m) async {
    // Tapping yourself does nothing. Everyone can message / view a member;
    // admins additionally get role + remove actions.
    if (m.userId == _myId) return;
    final firstName = m.fullName.split(' ').first;
    final action = await showModalBottomSheet<String>(
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
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline,
                  color: AppColors.primaryBlue),
              title: Text('Message $firstName'),
              onTap: () => Navigator.pop(ctx, 'message'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline,
                  color: AppColors.primaryBlue),
              title: const Text('View profile'),
              onTap: () => Navigator.pop(ctx, 'profile'),
            ),
            if (_amAdmin) ...[
              ListTile(
                leading: Icon(
                  m.isAdmin ? Icons.remove_moderator : Icons.shield_outlined,
                  color: AppColors.primaryBlue,
                ),
                title: Text(m.isAdmin ? 'Dismiss as admin' : 'Make admin'),
                onTap: () => Navigator.pop(ctx, 'role'),
              ),
              ListTile(
                leading: const Icon(Icons.person_remove, color: AppColors.red),
                title: const Text(
                  'Remove from group',
                  style: TextStyle(color: AppColors.red),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      if (action == 'message') {
        final convo = await MessagingService.createConversation(
          otherUserId: m.userId,
          otherUserName: m.fullName,
        );
        if (!mounted) return;
        context.pushNamed('chat', pathParameters: {'id': convo.id});
      } else if (action == 'profile') {
        context.pushNamed('user_profile',
            pathParameters: {'userId': m.userId});
      } else if (action == 'role') {
        await GroupService.setAdmin(
          widget.conversationId,
          m.userId,
          makeAdmin: !m.isAdmin,
        );
        _load();
      } else if (action == 'remove') {
        await GroupService.removeMember(widget.conversationId, m.userId);
        _load();
      }
    } catch (_) {
      if (mounted) _toast('Action failed.', error: true);
    }
  }

  Future<void> _leave() async {
    final ok = await _confirm(
      'Leave group?',
      'You will stop receiving messages from this group.',
      'Leave',
    );
    if (ok != true) return;
    try {
      await GroupService.leaveGroup(widget.conversationId);
      if (!mounted) return;
      context.goNamed('messages');
    } catch (_) {
      _toast('Could not leave.', error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      'Delete group for everyone?',
      'Members are notified the group was deleted. They keep a read-only '
          'copy until they remove it. You can\'t undo this.',
      'Delete',
    );
    if (ok != true) return;
    try {
      await GroupService.deleteGroup(widget.conversationId);
      if (!mounted) return;
      context.goNamed('messages');
    } catch (_) {
      _toast('Could not delete.', error: true);
    }
  }

  /// Remove a group I've LEFT from my own list (WhatsApp parity).
  Future<void> _deleteConversation() async {
    final ok = await _confirm(
      'Delete conversation?',
      'This removes the group from your chats. It stays for other members.',
      'Delete',
    );
    if (ok != true) return;
    try {
      await GroupService.deleteGroupConversation(widget.conversationId);
      if (!mounted) return;
      context.goNamed('messages');
    } catch (_) {
      _toast('Could not delete.', error: true);
    }
  }

  Future<bool?> _confirm(String title, String body, String confirmLabel) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _editGroup() async {
    final nameController =
        TextEditingController(text: _group?.otherUserName ?? '');
    String? newPhotoUrl;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final url =
                      await StorageService.pickAndUploadProfilePhoto();
                  if (url != null) setLocal(() => newPhotoUrl = url);
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(newPhotoUrl == null ? 'Change icon' : 'Icon set ✓'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await GroupService.updateGroup(
        widget.conversationId,
        name: nameController.text.trim(),
        photoUrl: newPhotoUrl,
      );
      _load();
    } catch (_) {
      _toast('Could not save changes.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkNavy,
        foregroundColor: AppColors.white,
        title: Text(_isChannel
            ? 'Channel info'
            : _isChurch
                ? 'Group info'
                : 'Group info'),
        actions: [
          if (_amAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editGroup,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryBlue),
            )
          : ListView(
              children: [
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () =>
                        FullImageViewer.show(context, group?.otherUserPhotoUrl),
                    child: _GroupIcon(
                      photoUrl: group?.otherUserPhotoUrl,
                      name: group?.otherUserName ?? 'Group',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    group?.otherUserName ?? 'Group',
                    style: AppTextStyles.titleLarge
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    _isChannel
                        ? '${_members.length} members · Channel'
                        : '${_members.length} members',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: context.palette.textMuted),
                  ),
                ),
                const SizedBox(height: 16),

                // ---- CHURCH ANNOUNCEMENTS CHANNEL ----------------------
                // WhatsApp-channel style: description + member count only,
                // a claim-admin request, and NO member list / leave /
                // delete / invite.
                if (_isChannel) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Official announcements channel. Only approved church '
                      'admins can post here; everyone in the church receives '
                      'the announcements.',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: context.palette.textMuted),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionTile(
                    icon: Icons.verified_user_outlined,
                    label: 'Request to post announcements',
                    onTap: _claimAdmin,
                  ),
                  const SizedBox(height: 24),
                ]

                // ---- CHURCH MEMBERS GROUP -----------------------------
                // WhatsApp-group style: show the member list. No admins,
                // no leave/delete/invite (membership is automatic).
                else if (_isChurch) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Text(
                      '${_members.length} MEMBERS',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.palette.textMuted,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final m in _members)
                    _MemberTile(
                      member: m,
                      isSelf: m.userId == _myId,
                      onTap: () => _memberActions(m),
                    ),
                  const SizedBox(height: 32),
                ]

                // ---- NORMAL USER-CREATED GROUP ------------------------
                else ...[
                  _ActionTile(
                    icon: Icons.link,
                    label: 'Invite to group via link',
                    onTap: _shareInvite,
                  ),
                  if (_amAdmin) ...[
                    _ActionTile(
                      icon: Icons.person_add_alt_1,
                      label: 'Add members',
                      onTap: _addMembers,
                    ),
                    _ActionTile(
                      icon: Icons.link_off,
                      label: 'Reset invite link',
                      onTap: _resetInvite,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                    child: Text(
                      '${_members.length} MEMBERS',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.palette.textMuted,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final m in _members)
                    _MemberTile(
                      member: m,
                      isSelf: m.userId == _myId,
                      onTap: () => _memberActions(m),
                    ),
                  const SizedBox(height: 16),
                  // While a member: Leave (the only way to later delete is
                  // to leave first). Once you've left: Delete conversation.
                  if (_amMember) ...[
                    _ActionTile(
                      icon: Icons.logout,
                      label: 'Leave group',
                      danger: true,
                      onTap: _leave,
                    ),
                    // Admins can delete the group for everyone (members are
                    // notified + keep a read-only copy).
                    if (_amAdmin)
                      _ActionTile(
                        icon: Icons.delete_outline,
                        label: 'Delete group for everyone',
                        danger: true,
                        onTap: _delete,
                      ),
                  ] else
                    _ActionTile(
                      icon: Icons.delete_outline,
                      label: 'Delete conversation',
                      danger: true,
                      onTap: _deleteConversation,
                    ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
    );
  }
}

class _GroupIcon extends StatelessWidget {
  const _GroupIcon({required this.photoUrl, required this.name});
  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    return Container(
      width: 104,
      height: 104,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto ? null : AppColors.primaryGradient,
      ),
      child: hasPhoto
          ? CachedImage(photoUrl!, fit: BoxFit.cover)
          : const Icon(Icons.groups, color: AppColors.white, size: 48),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : AppColors.primaryBlue;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: AppTextStyles.bodyMedium.copyWith(
          color: danger ? AppColors.red : context.palette.text,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isSelf,
    required this.onTap,
  });
  final GroupMember member;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (member.photoUrl ?? '').trim().isNotEmpty;
    final initial =
        member.fullName.trim().isEmpty ? '?' : member.fullName.trim()[0];
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: hasPhoto ? null : AppColors.primaryGradient,
        ),
        child: hasPhoto
            ? CachedImage(member.photoUrl!, fit: BoxFit.cover)
            : Text(
                initial.toUpperCase(),
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.white, fontWeight: FontWeight.w700),
              ),
      ),
      title: Text(
        isSelf ? '${member.fullName} (You)' : member.fullName,
        style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
      ),
      trailing: member.isAdmin
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'admin',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
    );
  }
}

/// Member picker used by "Add members".
class _AddMembersSheet extends StatefulWidget {
  const _AddMembersSheet({required this.excludeIds});
  final Set<String> excludeIds;

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<MemberDirectoryEntry> _results = const [];
  bool _loading = true;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggested() async {
    try {
      final list = await DirectoryService.fetchSuggestedMembers(limit: 40);
      if (!mounted) return;
      setState(() {
        _results =
            list.where((m) => !widget.excludeIds.contains(m.userId)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = q.trim();
      if (query.isEmpty) {
        _loadSuggested();
        return;
      }
      setState(() => _loading = true);
      try {
        final list = await DirectoryService.searchProfilesByName(query);
        if (!mounted) return;
        setState(() {
          _results = list
              .where((m) => !widget.excludeIds.contains(m.userId))
              .toList();
          _loading = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, controller) => Column(
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
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: 'Search people',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: ctx.palette.inputFill,
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
                    child:
                        CircularProgressIndicator(color: AppColors.primaryBlue),
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final m = _results[i];
                      final name = (m.fullName ?? 'Member').trim();
                      final selected = _selected.contains(m.userId);
                      return ListTile(
                        onTap: () => setState(() {
                          if (selected) {
                            _selected.remove(m.userId);
                          } else {
                            _selected.add(m.userId);
                          }
                        }),
                        title: Text(name),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? AppColors.primaryBlue
                              : ctx.palette.divider,
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.toList()),
                  child: Text('Add ${_selected.length}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
