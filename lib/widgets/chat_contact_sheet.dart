import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/story_model.dart';
import '../services/block_service.dart';
import '../services/feed_service.dart';
import '../services/messaging_service.dart';
import '../services/presence_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'cached_image.dart';
import 'full_image_viewer.dart';
import 'verified_tick.dart';
import 'home/report_sheet.dart';
import 'home/story_viewer.dart';

/// WhatsApp-style contact preview sheet. Big photo (with a story ring if
/// they have a status), name, online/last-seen, bio, a "View full profile"
/// CTA, and quick actions (mute, block, report, create group, clear chat).
///
/// Opened by tapping the chat header in chat_screen.dart.
/// Returns an action result the caller can react to: 'blocked',
/// 'unblocked', or 'cleared' (or null if just dismissed).
Future<String?> showChatContactSheet(
  BuildContext context, {
  required String userId,
  required String fallbackName,
  String? fallbackPhotoUrl,
  String? conversationId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _ChatContactSheet(
      userId: userId,
      fallbackName: fallbackName,
      fallbackPhotoUrl: fallbackPhotoUrl,
      conversationId: conversationId,
    ),
  );
}

class _ChatContactSheet extends StatefulWidget {
  const _ChatContactSheet({
    required this.userId,
    required this.fallbackName,
    this.fallbackPhotoUrl,
    this.conversationId,
  });

  final String userId;
  final String fallbackName;
  final String? fallbackPhotoUrl;
  final String? conversationId;

  @override
  State<_ChatContactSheet> createState() => _ChatContactSheetState();
}

class _ChatContactSheetState extends State<_ChatContactSheet> {
  PublicUserProfile? _profile;
  DateTime? _lastSeen;
  bool _loading = true;
  List<Story> _stories = const [];
  bool _allViewed = false;
  bool _muted = false;
  bool _busy = false;
  bool _blockedByMe = false;

  bool get _hasStory => _stories.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      UserProfileService.fetch(widget.userId),
      PresenceService.fetchLastSeen(widget.userId),
      FeedService.fetchStories(),
      FeedService.fetchMyViewedStoryIds(),
      MessagingService.fetchConversationStates(),
      MessagingService.isBlockedByMe(widget.userId),
    ]);
    if (!mounted) return;
    final allStories = results[2] as List<Story>;
    final viewed = results[3] as Set<String>;
    final mine = allStories.where((s) => s.authorId == widget.userId).toList();
    final states = results[4] as Map;
    setState(() {
      _profile = results[0] as PublicUserProfile?;
      _lastSeen = results[1] as DateTime?;
      _stories = mine;
      _allViewed = mine.isNotEmpty && mine.every((s) => viewed.contains(s.id));
      _blockedByMe = results[5] == true;
      if (widget.conversationId != null) {
        final st = states[widget.conversationId];
        _muted = (st as dynamic)?.muted ?? false;
      }
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _onAvatarTap(String? photoUrl) async {
    if (_hasStory) {
      await StoryViewer.show(context, _stories);
      if (mounted) _load();
    } else if ((photoUrl ?? '').isNotEmpty) {
      FullImageViewer.show(context, photoUrl);
    }
  }

  Future<void> _toggleMute() async {
    final id = widget.conversationId;
    if (id == null) return;
    setState(() => _muted = !_muted);
    try {
      await MessagingService.setConversationFlags(id, muted: _muted);
      _toast(_muted ? 'Muted' : 'Unmuted');
    } catch (_) {
      if (mounted) setState(() => _muted = !_muted);
    }
  }

  Future<void> _toggleBlock(String name) async {
    // Unblock is immediate (no confirm); block confirms first.
    if (_blockedByMe) {
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await BlockService.unblock(widget.userId);
        if (!mounted) return;
        nav.pop('unblocked'); // tell the chat to refresh
        messenger.showSnackBar(SnackBar(content: Text('$name unblocked.')));
      } catch (_) {
        if (mounted) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Could not unblock.')));
        }
      }
      return;
    }
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
          "They won't be able to message you or see your profile, posts, "
          'stories and prayers.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BlockService.block(widget.userId);
      if (!mounted) return;
      nav.pop('blocked'); // tell the chat to refresh its blocked state
      messenger.showSnackBar(SnackBar(content: Text('$name blocked.')));
    } catch (_) {
      if (mounted) {
        messenger
            .showSnackBar(const SnackBar(content: Text('Could not block.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (_profile?.fullName.trim().isNotEmpty == true)
        ? _profile!.fullName.trim()
        : widget.fallbackName;
    final photoUrl = _profile?.profilePhotoUrl ?? widget.fallbackPhotoUrl;
    final bio = _profile?.bio?.trim() ?? '';
    final coverUrl = _profile?.coverPhotoUrl;

    final isOnline = PresenceService.isOnline(widget.userId);
    final presence = isOnline
        ? 'Online'
        : (_lastSeen != null
            ? 'Last seen ${PresenceService.formatLastSeen(_lastSeen!)}'
            : 'Offline');

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: context.palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.palette.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(
                height: 120,
                child: (coverUrl ?? '').isNotEmpty
                    ? GestureDetector(
                        onTap: () => FullImageViewer.show(context, coverUrl),
                        child: CachedImage(
                          coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.08),
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                      ),
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: () => _onAvatarTap(photoUrl),
                  child: _StoryRingAvatar(
                    name: name,
                    photoUrl: photoUrl,
                    hasStory: _hasStory,
                    allViewed: _allViewed,
                  ),
                ),
              ),
              if (_hasStory) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _allViewed ? 'Tap to view story' : 'New story · tap to view',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: _allViewed
                          ? context.palette.textMuted
                          : AppColors.successGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.titleLarge.copyWith(
                              color: context.palette.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        if (_profile?.showsVerifiedTick == true)
                          const VerifiedTick(size: 18),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isOnline) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.successGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          presence,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: context.palette.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.palette.cardMuted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      bio,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: context.palette.text,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          context.pushNamed(
                            'user_profile',
                            pathParameters: {'userId': widget.userId},
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('View profile'),
                ),
              ),
              const SizedBox(height: 8),
              // Quick actions.
              if (widget.conversationId != null)
                _ActionRow(
                  icon: _muted
                      ? Icons.notifications_off
                      : Icons.notifications_none,
                  label: _muted ? 'Unmute notifications' : 'Mute notifications',
                  onTap: _toggleMute,
                ),
              _ActionRow(
                icon: Icons.group_add_outlined,
                label: 'Create group with $name',
                onTap: () {
                  Navigator.of(context).pop();
                  // Pre-select this contact in the create-group picker.
                  context.pushNamed('create_group', extra: widget.userId);
                },
              ),
              _ActionRow(
                icon: Icons.flag_outlined,
                label: 'Report',
                onTap: () {
                  Navigator.of(context).pop();
                  showReportSheet(
                    context,
                    contentType: 'user',
                    contentId: widget.userId,
                    contentLabel: name,
                  );
                },
              ),
              if (widget.conversationId != null)
                _ActionRow(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Clear chat',
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Clear chat?'),
                        content: const Text(
                          'Messages will be hidden for you only.',
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppColors.red),
                            onPressed: () => Navigator.pop(dctx, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true || _busy) return;
                    _busy = true;
                    try {
                      await MessagingService.clearConversation(
                          widget.conversationId!);
                      if (!mounted) return;
                      nav.pop('cleared'); // tell the chat to refresh
                      messenger.showSnackBar(
                          const SnackBar(content: Text('Chat cleared.')));
                    } catch (_) {
                      if (mounted) {
                        messenger.showSnackBar(const SnackBar(
                            content: Text('Could not clear chat.')));
                      }
                    } finally {
                      _busy = false;
                    }
                  },
                ),
              _ActionRow(
                icon: _blockedByMe ? Icons.lock_open : Icons.block,
                label: _blockedByMe ? 'Unblock' : 'Block',
                danger: !_blockedByMe,
                onTap: () => _toggleBlock(name),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
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

/// Avatar with a WhatsApp-style status ring: green when there's an
/// unviewed story, grey when all viewed, none when there's no story.
class _StoryRingAvatar extends StatelessWidget {
  const _StoryRingAvatar({
    required this.name,
    required this.photoUrl,
    required this.hasStory,
    required this.allViewed,
  });
  final String name;
  final String? photoUrl;
  final bool hasStory;
  final bool allViewed;

  @override
  Widget build(BuildContext context) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.substring(0, 1).toUpperCase()
            : (parts.first.substring(0, 1) + parts.last.substring(0, 1))
                .toUpperCase();
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final ringColor = !hasStory
        ? Colors.transparent
        : (allViewed ? context.palette.divider : AppColors.successGreen);

    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor,
          width: hasStory ? 3 : 0,
        ),
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: hasPhoto ? null : AppColors.primaryGradient,
          color: hasPhoto ? context.palette.cardMuted : null,
          shape: BoxShape.circle,
          border: Border.all(color: context.palette.sheet, width: 3),
        ),
        child: hasPhoto
            ? CachedImage(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _initials(initials),
              )
            : _initials(initials),
      ),
    );
  }

  Widget _initials(String initials) => Text(
        initials,
        style: AppTextStyles.titleLarge.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
          fontSize: 30,
        ),
      );
}
