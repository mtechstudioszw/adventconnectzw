import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/member_directory_model.dart';
import '../../models/message_model.dart';
import '../../services/auth_service.dart';
import '../../services/church_service.dart';
import '../../services/directory_service.dart';
import '../../services/group_service.dart';
import '../../services/messaging_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/screen_shell.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/verified_tick.dart';
import '../../widgets/motion/brand_spinner.dart';

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

  /// A failed load, kept apart from an empty group.
  String? _error;

  String get _myId => AuthService.currentUser?.id ?? '';
  bool get _amAdmin =>
      !_isChurch && _members.any((m) => m.userId == _myId && m.isAdmin);
  // Active member (not left/removed). fetchMembers excludes left members.
  bool get _amMember => _members.any((m) => m.userId == _myId);

  /// You, then admins, then everyone else — each group alphabetical.
  ///
  /// The row already labelled itself "Name (You)"; what it could not do was
  /// put itself where you would look. The server returns members in join
  /// order, so in a group of any size your own row was somewhere in the
  /// middle and you had to hunt for it to confirm you were even in the
  /// list. Admins ride up with you because "who runs this group" is the
  /// other question this screen is opened to answer.
  ///
  /// Church groups come through [GroupService.fetchChurchMembers], which
  /// has no admin concept, so there the sort is simply you-then-alphabetical.
  List<GroupMember> _selfFirst(List<GroupMember> members) {
    final id = _myId;
    return [...members]..sort((a, b) {
      if (a.userId == id) return -1;
      if (b.userId == id) return 1;
      if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
  }
  bool get _isChurch => _group?.isChurchGroup ?? false;
  bool get _isChannel => _group?.isChurchChannel ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final convo = await MessagingService.fetchConversation(
        widget.conversationId,
      );
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
        _members = _selfFirst(members);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this group.';
      });
    }
  }

  /// Sends the member into the real claim-church flow.
  ///
  /// This used to open WhatsApp to the founder's personal number with a
  /// pre-filled "please verify me" message. Same problems as the seller
  /// report it mirrored: it published the founder's phone number to every
  /// member who tapped it, it collected the member's number in return, the
  /// text was editable before sending, and — worst — if they never pressed
  /// send, NOTHING was recorded. The app had told them their request was on
  /// its way while no request existed.
  ///
  /// `claim_church` already does this properly: a contact form that writes
  /// to `church_admins` as a pending row, which surfaces in the admin
  /// approvals screen. It is reviewed, auditable, and does not require
  /// anyone to hand out a phone number.
  Future<void> _claimAdmin() async {
    final churchId = _group?.churchId;
    // No church attached to this channel — send them to the directory,
    // where every church has its own Claim button.
    if (churchId == null || churchId.isEmpty) {
      if (!mounted) return;
      context.pushNamed('churches');
      return;
    }
    final ok = await _confirm(
      'Request to post announcements',
      'Only verified church leaders can post announcements. The next screen '
          'takes a few details and sends them to our team for review.',
      'Continue',
    );
    if (ok != true) return;
    try {
      final church = await ChurchService.fetchChurchById(churchId);
      if (!mounted) return;
      if (church == null) {
        context.pushNamed('churches');
        return;
      }
      context.pushNamed('claim_church', extra: church);
    } catch (_) {
      if (mounted) _toast('Could not open the claim form.', error: true);
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
      final link =
          'https://mtechstudioszw.github.io/adventconnect-legal/'
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
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Anyone with this link can join the group.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ctx.palette.textMuted,
                  ),
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
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ctx.palette.text,
                    ),
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
                            'Join our group on Adventist Super App: $link',
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
              leading: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.primaryBlue,
              ),
              title: Text('Message $firstName'),
              onTap: () => Navigator.pop(ctx, 'message'),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: AppColors.primaryBlue,
              ),
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
        context.pushNamed('user_profile', pathParameters: {'userId': m.userId});
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
      // Lock the composer instantly if the chat is re-opened.
      unawaited(
        MessagingService.setGroupBlockedCached(widget.conversationId, true),
      );
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
    final nameController = TextEditingController(
      text: _group?.otherUserName ?? '',
    );
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
                  final url = await StorageService.pickAndUploadProfilePhoto();
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
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
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
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: BrandSpinner(size: 30))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ErrorBanner(message: _error!, onRetry: _load),
                  ),
                ScreenHero(
                  title: _isChannel ? 'Channel info' : 'Group info',
                  tagline: 'Chat',
                  fallbackRoute: 'messages',
                  trailing: _amAdmin
                      ? ScreenHeroTrailing(
                          icon: Icons.edit_outlined,
                          onTap: _editGroup,
                        )
                      : null,
                ),
                // Identity card rather than a bare centred stack. The photo,
                // the name and what kind of group this is are one object, and
                // the card is what makes it read as the group's own page
                // rather than a settings list with a picture on top.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => FullImageViewer.show(
                            context,
                            group?.otherUserPhotoUrl,
                          ),
                          child: UserAvatar(
                            photoUrl: group?.otherUserPhotoUrl,
                            name: group?.otherUserName ?? 'Group',
                            fallbackIcon: Icons.groups,
                            size: 104,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                group?.otherUserName ?? 'Group',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.titleLarge.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            if (_isChurch) const VerifiedTick(size: 17),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Type + size as one pill, so a channel is legible
                        // as a channel without reading the paragraph below.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isChannel
                                    ? Icons.campaign_outlined
                                    : Icons.groups_outlined,
                                size: 14,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isChannel
                                    ? 'Announcements · ${_members.length} members'
                                    : '${_members.length} member'
                                          '${_members.length == 1 ? '' : 's'}',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

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
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.textMuted,
                      ),
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
                  // Only members can invite — hidden once you leave the group.
                  if (_amMember)
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
    return ListTile(
      onTap: onTap,
      leading: UserAvatar(
        photoUrl: member.photoUrl,
        name: member.fullName,
        size: 44,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isSelf ? '${member.fullName} (You)' : member.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (member.isVerified) const VerifiedTick(size: 14),
        ],
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
  // Friends-only: groups can only include your accepted friends (the
  // server rejects non-friends in add_group_members, patch_118).
  List<MemberDirectoryEntry> _friends = const [];
  List<MemberDirectoryEntry> _results = const [];
  bool _loading = true;

  /// A failed friends fetch, so the picker can say so instead of
  /// rendering an empty list that reads as "you have no friends".
  String? _addError;
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
      final list = await DirectoryService.fetchFriends();
      if (!mounted) return;
      final filtered = list
          .where((m) => !widget.excludeIds.contains(m.userId))
          .toList();
      setState(() {
        _friends = filtered;
        _results = filtered;
        _loading = false;
        _addError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _addError = 'Could not load your friends.';
      });
    }
  }

  // Friends-only group: filter the loaded friend list locally by name.
  void _search(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _results = query.isEmpty
          ? _friends
          : _friends
                .where((m) => (m.fullName ?? '').toLowerCase().contains(query))
                .toList();
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
                ? const Center(child: BrandSpinner(size: 30))
                : _addError != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: ErrorBanner(
                      message: _addError!,
                      onRetry: _loadSuggested,
                    ),
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
