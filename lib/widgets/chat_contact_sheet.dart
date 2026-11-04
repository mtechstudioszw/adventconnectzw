import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/friendship_model.dart';
import '../models/story_model.dart';
import '../services/auth_service.dart';
import '../services/block_service.dart';
import '../services/e2ee/e2ee_service.dart';
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
      useRootNavigator: true,
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

  /// Accepted friendship with this person. Gates presence — see the note
  /// where `presence` is built.
  bool _isFriend = false;

  /// The 60-digit security code for this pair, once computed.
  ///
  /// Null means "no code to show" — either still computing, or this
  /// device has never held their identity key. [_securityCodeLoading]
  /// tells those two apart, because they read very differently to
  /// someone checking whether they are being intercepted.
  String? _securityCode;
  bool _securityCodeLoading = true;

  bool get _hasStory => _stories.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    // Deliberately NOT awaited inside _load: the fingerprint is 5200
    // SHA-512 rounds per side, and the sheet must not wait on it to show
    // a photo and a name.
    _loadSecurityCode();
  }

  Future<void> _loadSecurityCode() async {
    if (!E2eeService.isEncryptionOn) {
      if (mounted) setState(() => _securityCodeLoading = false);
      return;
    }
    final code = await E2eeService.securityCode(widget.userId);
    if (!mounted) return;
    setState(() {
      _securityCode = code;
      _securityCodeLoading = false;
    });
  }

  Future<void> _load() async {
    final results = await Future.wait([
      UserProfileService.fetch(widget.userId),
      PresenceService.fetchLastSeen(widget.userId),
      FeedService.fetchStories(),
      FeedService.fetchMyViewedStoryIds(),
      MessagingService.fetchConversationStates(),
      MessagingService.isBlockedByMe(widget.userId),
      FeedService.fetchMyFriendships(),
    ]);
    if (!mounted) return;
    final allStories = results[2] as List<Story>;
    final viewed = results[3] as Set<String>;
    final mine = allStories.where((s) => s.authorId == widget.userId).toList();
    final states = results[4] as Map;
    final me = AuthService.currentUser?.id;
    final friend = (results[6] as List).cast<Friendship>().any((f) {
      if (!f.isAccepted) return false;
      final other = f.requesterId == me ? f.addresseeId : f.requesterId;
      return other == widget.userId;
    });
    setState(() {
      _profile = results[0] as PublicUserProfile?;
      _lastSeen = results[1] as DateTime?;
      _isFriend = friend;
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            const SnackBar(content: Text('Could not unblock.')),
          );
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
            child: const Text('Cancel'),
          ),
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
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not block.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The profile row came back empty even though we asked for it. Under
    // `profiles_select_discoverable_or_self` (patch_201) that means one
    // of exactly two things: they blocked us, or they are not
    // discoverable. Either way we are not entitled to their details.
    //
    // This matters because of what the fallbacks below used to do. The
    // name and photo passed into this sheet come from the CONVERSATION
    // row, which is denormalised and survives the block — so `_profile
    // ?.profilePhotoUrl ?? widget.fallbackPhotoUrl` quietly served the
    // blocked user their blocker's profile picture out of a cache, right
    // next to a bio and cover the policy had already taken away. Fall
    // back to the name only; a thread with no name at the top is
    // unusable, and the name is on every message bubble regardless.
    final unavailable = !_loading && _profile == null;

    final name = (_profile?.fullName.trim().isNotEmpty == true)
        ? _profile!.fullName.trim()
        : widget.fallbackName;
    final photoUrl = unavailable
        ? null
        : (_profile?.profilePhotoUrl ?? widget.fallbackPhotoUrl);
    final bio = unavailable ? '' : (_profile?.bio?.trim() ?? '');
    final coverUrl = unavailable ? null : _profile?.coverPhotoUrl;

    // Presence is friends-only. This sheet opens from a tap on ANY post
    // author's avatar in the home feed, so it was telling you whether a
    // complete stranger was at their phone right now — and showing their
    // last-seen time on top of that. Neither belongs to someone you have
    // no relationship with. Friends still see the full line.
    //
    // PresenceService.isOnline is block-aware since patch_210, so a block
    // in either direction already reads as offline here; `unavailable`
    // additionally suppresses the "Offline"/"Last seen" line, which would
    // otherwise still be a live signal about someone who has shut us out.
    final isOnline = _isFriend && PresenceService.isOnline(widget.userId);
    final presence = (!_isFriend || unavailable)
        ? null
        : isOnline
        ? 'Online'
        : (_lastSeen != null
              ? 'Last seen ${PresenceService.formatLastSeen(_lastSeen!)}'
              : 'Offline');

    final me = AuthService.currentUser?.id;
    final isMe = me != null && me == widget.userId;
    final username = unavailable ? null : _profile?.username;
    final church = unavailable ? null : _profile?.churchName?.trim();
    final city = unavailable ? null : _profile?.city?.trim();
    final palette = context.palette;

    final quick = <Widget>[
      if (widget.conversationId == null && !isMe && !unavailable)
        _QuickAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Message',
          primary: true,
          onTap: _loading ? null : () => _openChat(name),
        ),
      _QuickAction(
        icon: Icons.person_outline_rounded,
        label: 'Profile',
        primary: widget.conversationId != null || isMe,
        onTap: _loading
            ? null
            : () {
                Navigator.of(context).pop();
                context.pushNamed(
                  'user_profile',
                  pathParameters: {'userId': widget.userId},
                );
              },
      ),
      if (widget.conversationId != null)
        _QuickAction(
          icon: _muted
              ? Icons.notifications_off_outlined
              : Icons.notifications_none_rounded,
          label: _muted ? 'Unmute' : 'Mute',
          onTap: _toggleMute,
        ),
      if (!isMe)
        _QuickAction(
          icon: Icons.group_add_outlined,
          label: 'Group',
          onTap: () {
            Navigator.of(context).pop();
            // Pre-select this contact in the create-group picker.
            context.pushNamed('create_group', extra: widget.userId);
          },
        ),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.66,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (ctx, controller) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover band with the avatar riding over its bottom edge.
              SizedBox(
                height: 186,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 128,
                      child: _CoverBand(
                        coverUrl: coverUrl,
                        onTap: (coverUrl ?? '').isEmpty
                            ? null
                            : () => FullImageViewer.show(context, coverUrl),
                      ),
                    ),
                    // Grab handle, on the cover so it reads on a photo.
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 76,
                      left: 0,
                      right: 0,
                      child: Center(
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleLarge.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 21,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (_profile?.showsVerifiedTick == true) ...[
                          const SizedBox(width: 4),
                          const VerifiedTick(size: 18),
                        ],
                      ],
                    ),
                    if ((username ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: palette.textMuted,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                    // The whole line disappears for non-friends rather than
                    // degrading to "Offline" — which would still be a
                    // statement about where they are.
                    if (presence != null) ...[
                      const SizedBox(height: 10),
                      _PresencePill(text: presence, online: isOnline),
                    ],
                    if (_hasStory) ...[
                      const SizedBox(height: 8),
                      Text(
                        _allViewed
                            ? 'Tap the photo to see their story'
                            : 'New story · tap the photo',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _allViewed
                              ? palette.textMuted
                              : AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (var i = 0; i < quick.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: quick[i]),
                    ],
                  ],
                ),
              ),
              if (bio.isNotEmpty ||
                  (church ?? '').isNotEmpty ||
                  (city ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                _SheetCard(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bio.isNotEmpty)
                          Text(
                            bio,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: palette.text,
                              height: 1.45,
                            ),
                          ),
                        if (bio.isNotEmpty &&
                            ((church ?? '').isNotEmpty ||
                                (city ?? '').isNotEmpty))
                          const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if ((church ?? '').isNotEmpty)
                              _InfoChip(
                                icon: Icons.church_outlined,
                                text: church!,
                              ),
                            if ((city ?? '').isNotEmpty)
                              _InfoChip(
                                icon: Icons.place_outlined,
                                text: city!,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!isMe) ...[
                const SizedBox(height: 12),
                _SheetCard(
                  child: Column(
                    children: [
                      _ActionRow(
                        icon: Icons.flag_outlined,
                        label: 'Report $name',
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
                      if (widget.conversationId != null) ...[
                        const _RowDivider(),
                        _ActionRow(
                          icon: Icons.cleaning_services_outlined,
                          label: 'Clear chat',
                          onTap: _clearChat,
                        ),
                      ],
                      const _RowDivider(),
                      _ActionRow(
                        icon: _blockedByMe
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                        label: _blockedByMe ? 'Unblock $name' : 'Block $name',
                        danger: !_blockedByMe,
                        onTap: () => _toggleBlock(name),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // The founder asked for the encryption note here as well as
              // in the thread: this is the sheet a member opens when they
              // are deciding whether to trust someone. Shown whether or not
              // encryption is on — the copy tells the truth either way;
              // only the security code needs real encryption.
              if (!unavailable && !isMe)
                _EncryptionFooter(
                  otherName: name,
                  encrypted: E2eeService.isEncryptionOn,
                  securityCode: _securityCode,
                  loading: _securityCodeLoading,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openChat(String name) async {
    final nav = Navigator.of(context);
    final router = GoRouter.of(context);
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: widget.userId,
        otherUserName: name,
        source: 'direct',
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      nav.pop();
      router.pushNamed('chat', pathParameters: {'id': convo.id}, extra: convo);
    } catch (_) {
      _toast("Couldn't open the chat. Check your connection.");
    }
  }

  Future<void> _clearChat() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('Messages will be hidden for you only.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    _busy = true;
    try {
      await MessagingService.clearConversation(widget.conversationId!);
      if (!mounted) return;
      nav.pop('cleared'); // tell the chat to refresh
      messenger.showSnackBar(const SnackBar(content: Text('Chat cleared.')));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not clear chat.')),
        );
      }
    } finally {
      _busy = false;
    }
  }
}

/// The band behind the avatar: their cover photo, or — with none — a calm
/// blue wash. Never a navy slab (CLAUDE.md: headers are flat).
class _CoverBand extends StatelessWidget {
  const _CoverBand({required this.coverUrl, this.onTap});
  final String? coverUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final wash = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.22),
            AppColors.primaryBlue.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
    if ((coverUrl ?? '').isEmpty) return wash;
    return GestureDetector(
      onTap: onTap,
      child: CachedImage(
        coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => wash,
      ),
    );
  }
}

class _PresencePill extends StatelessWidget {
  const _PresencePill({required this.text, required this.online});
  final String text;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: online
            ? AppColors.successGreen.withValues(alpha: 0.12)
            : palette.chipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (online) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.successGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: AppTextStyles.bodySmall.copyWith(
              color: online ? AppColors.successGreen : palette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One round quick action: Message / Profile / Mute / Group.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: primary ? AppColors.primaryGradient : null,
            color: primary ? null : palette.chipBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: primary ? AppColors.white : AppColors.primaryBlue,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: primary ? AppColors.white : palette.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primaryBlue),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded group, the way Settings groups rows.
class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.palette.cardMuted,
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 0.6,
    indent: 52,
    color: context.palette.divider,
  );
}

/// The encryption block: what is (and is not) encrypted, this pair's
/// security code, and a real link to the policy.
///
/// Gated on [E2eeService.isEncryptionOn] at the call site, never shown
/// unconditionally: it is a security claim, and it must not appear on a
/// thread that is still going out in the clear.
class _EncryptionFooter extends StatelessWidget {
  const _EncryptionFooter({
    required this.otherName,
    required this.encrypted,
    required this.securityCode,
    required this.loading,
  });

  final String otherName;

  /// Whether this thread is ACTUALLY encrypted right now. Drives the
  /// wording and nothing else is allowed to — see the same note on
  /// `_PrivacyNotice.encrypted` in chat_screen.dart.
  final bool encrypted;

  /// The 60 digits, pre-grouped by [E2eeService.securityCode]. Null when
  /// there is no key to compare against yet.
  final String? securityCode;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = AppTextStyles.bodySmall.copyWith(
      color: palette.textMuted,
      fontSize: 11.5,
      height: 1.45,
    );
    final first = otherName.trim().split(RegExp(r'\s+')).first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 14, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: base,
                    children: [
                      TextSpan(
                        text: encrypted
                            ? 'Messages, photos and voice notes are '
                                  'end-to-end encrypted — nobody outside this '
                                  'chat, not even Adventist Super App, can '
                                  'see them. '
                            : 'Messages here are private between you and '
                                  '$first. ',
                      ),
                      TextSpan(
                        text: 'Learn more',
                        style: base.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primaryBlue,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => context.pushNamed('privacy'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Only when there is real encryption to verify. A "security
          // code" on an unencrypted thread would be a number with nothing
          // behind it — worse than absent, because members are told to act
          // on a mismatch.
          if (encrypted) ...[
            const SizedBox(height: 14),
            _SecurityCodeBlock(
              firstName: first,
              code: securityCode,
              loading: loading,
            ),
          ],
        ],
      ),
    );
  }
}

/// The pair's 60-digit security code, or an honest explanation of why
/// there isn't one yet.
///
/// Shown rather than hidden behind a menu because a code nobody can find
/// is a code nobody compares, and comparing it is the only thing that
/// turns "trust us, it's encrypted" into something a member can check for
/// themselves.
class _SecurityCodeBlock extends StatelessWidget {
  const _SecurityCodeBlock({
    required this.firstName,
    required this.code,
    required this.loading,
  });

  final String firstName;
  final String? code;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = AppTextStyles.labelSmall.copyWith(
      color: palette.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    final helper = AppTextStyles.bodySmall.copyWith(
      color: palette.textMuted,
      fontSize: 11,
      height: 1.45,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SECURITY CODE', style: label),
          const SizedBox(height: 10),
          if (loading)
            Text('Checking…', style: helper)
          else if (code == null)
            Text(
              'Not available yet — it appears once you and $firstName have '
              'exchanged a message on your current devices.',
              style: helper,
            )
          else ...[
            Text(
              code!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: palette.text,
                fontSize: 14,
                height: 1.7,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                // Poppins stays (founder rule), but digits go tabular so
                // the three rows line up into columns. A security code
                // read aloud from ragged rows is read aloud wrong.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Compare these digits with $firstName in person or on a call. '
              'If they match, nobody is reading this chat. The code changes '
              'when either of you reinstalls the app or switches phone.',
              style: helper,
            ),
          ],
        ],
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
    final color = danger ? AppColors.red : context.palette.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 21,
              color: danger ? AppColors.red : context.palette.textMuted,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : (parts.first.substring(0, 1) + parts.last.substring(0, 1))
              .toUpperCase();
    final hasPhoto = (photoUrl ?? '').trim().isNotEmpty;
    final ringColor = !hasStory
        ? Colors.transparent
        : (allViewed ? context.palette.divider : AppColors.primaryBlue);

    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: hasStory ? 3 : 0),
      ),
      // No `alignment` here on purpose — it would wrap the child in an
      // Align and hand it LOOSE constraints, leaving the photo floating
      // inside the circle with a rim of cardMuted around it. cardMuted
      // stays as the placeholder the photo fades in over.
      child: Container(
        clipBehavior: Clip.antiAlias,
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
                    Center(child: _initials(initials)),
              )
            : Center(child: _initials(initials)),
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
