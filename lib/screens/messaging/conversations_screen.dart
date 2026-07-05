import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
import 'package:go_router/go_router.dart';
import '../../models/message_model.dart';
import '../../models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/group_service.dart';
import '../../services/messaging_service.dart';
import '../../widgets/church_group_avatar.dart';
import '../../services/presence_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/home/stories_rail.dart';
import '../../widgets/home/story_viewer.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/verified_tick.dart';
import 'chat_search_delegate.dart';
import '../../theme/app_motion.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/pressable.dart';
import '../../widgets/motion/staggered_reveal.dart';
import '../../widgets/shimmer_loaders.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, this.initialTab});

  /// When set to 'requests' the screen opens straight on the Requests
  /// tab. Used by deep links from friend-request notification taps.
  final String? initialTab;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

enum _ConversationsTab { chats, stories }

/// WhatsApp-style quick filter chips on the Chats tab.
enum _ChatFilter { all, unread, groups }

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation> _conversations = [];
  Map<String, ConversationState> _convStates = const {};
  Map<String, InboxReactionPreview> _reactionPreviews = const {};
  List<Story> _stories = const [];
  Set<String> _viewedStoryIds = const {};
  List<PendingFriendRequest> _friendRequests = const [];
  bool _loading = true;
  String? _error;
  _ConversationsTab _tab = _ConversationsTab.chats;
  _ChatFilter _chatFilter = _ChatFilter.all;

  /// Requests aren't a tab anymore — they open from a banner on the Chats
  /// tab into an inline requests view. This flag drives that view.
  bool _showRequests = false;

  /// Once we've auto-jumped to the Requests tab on first load (because
  /// inbox was empty but friend requests existed), we stop doing it so
  /// the user can navigate freely afterwards.
  bool _autoTabResolved = false;

  // Realtime subscription to messages — fires whenever ANY message
  // visible to the current user (per RLS) is inserted/updated, so
  // unread badges and last-message previews can refresh without a
  // pull-to-refresh from the user.
  StreamSubscription<List<Map<String, dynamic>>>? _activitySub;
  Timer? _refreshDebounce;
  late final PageController _pageController;
  // Inbox multi-select (delete several chats at once).
  bool _chatSelect = false;
  final Set<String> _selectedChats = <String>{};

  void _enterChatSelect(Conversation c) {
    if (c.isChurchGroup) return; // church groups can't be deleted
    setState(() {
      _chatSelect = true;
      _selectedChats.add(c.id);
    });
  }

  void _toggleChat(Conversation c) {
    if (c.isChurchGroup) return;
    setState(() {
      if (_selectedChats.contains(c.id)) {
        _selectedChats.remove(c.id);
      } else {
        _selectedChats.add(c.id);
      }
      if (_selectedChats.isEmpty) _chatSelect = false;
    });
  }

  void _exitChatSelect() {
    setState(() {
      _chatSelect = false;
      _selectedChats.clear();
    });
  }

  Future<void> _deleteSelectedChats() async {
    final ids = _selectedChats.toList();
    final count = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Delete $count chat${count == 1 ? '' : 's'}?'),
        content: const Text('This removes them and their messages for you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _exitChatSelect();
    for (final id in ids) {
      try {
        final c = _conversations.firstWhere((x) => x.id == id);
        if (c.isGroup) {
          await GroupService.deleteGroupConversation(id);
        } else {
          await MessagingService.declineRequest(id);
        }
      } catch (_) {}
    }
    if (mounted) await _bootstrap();
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _tab.index);
    if (widget.initialTab == 'requests') {
      _showRequests = true;
      // Caller asked for Requests explicitly — don't let the "auto-pick"
      // heuristic in _bootstrap override that choice.
      _autoTabResolved = true;
    }
    _bootstrap();
    _startActivityWatcher();
    // Local inbox changes (delete-for-me preview floor) emit no realtime
    // event, so listen for them explicitly and rebuild — otherwise a message
    // you deleted-for-me still showed in the list until a new message arrived.
    MessagingService.inboxLocalRevision.addListener(_onLocalInboxChange);
  }

  void _onLocalInboxChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _activitySub?.cancel();
    MessagingService.inboxLocalRevision.removeListener(_onLocalInboxChange);
    _pageController.dispose();
    super.dispose();
  }

  /// Switch sub-tab via the pager so the transition animates (and a swipe
  /// updates the selected pill).
  void _selectTab(_ConversationsTab tab) {
    setState(() => _tab = tab);
    void go() {
      if (!_pageController.hasClients) return;
      if (_pageController.page?.round() == tab.index) return;
      _pageController.animateToPage(
        tab.index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    if (_pageController.hasClients) {
      go();
    } else {
      // Pager not attached yet (e.g. coming back from the requests view) —
      // animate once it is.
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    }
  }

  /// Listen for any message activity (insert / status change) and
  /// debounce-trigger a conversations refetch + unread recompute.
  /// A 600ms debounce coalesces bursts (e.g. someone pasting a long
  /// message that the realtime layer delivers as several events).
  void _startActivityWatcher() {
    _activitySub?.cancel();
    _activitySub = MessagingService.streamInboxActivity().listen(
      (rows) {
        // patch_032: fire the delivered receipt as soon as inbound
        // messages arrive in the inbox stream — not just when the
        // chat screen is mounted — so the sender sees two grey ticks
        // even if the recipient never opens the chat. The chat screen
        // still re-runs this on its own stream as a safety net.
        final me = _currentUserId;
        if (me.isNotEmpty) {
          final undelivered = rows
              .where(
                (r) =>
                    r['sender_id']?.toString() != me &&
                    r['delivered_at'] == null,
              )
              .map((r) => r['id'].toString())
              .where((id) => id.isNotEmpty)
              .toList();
          if (undelivered.isNotEmpty) {
            unawaited(MessagingService.markMessagesDelivered(undelivered));
          }
        }
        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(const Duration(milliseconds: 600), () {
          if (mounted) _refreshFromRealtime();
        });
      },
      onError: (_) {
        // Realtime hiccups should never blank the inbox.
      },
    );
  }

  /// Lightweight refresh — re-fetches conversations + unread counts,
  /// without toggling the loading spinner. Used when realtime fires.
  Future<void> _refreshFromRealtime() async {
    try {
      final fresh = await MessagingService.fetchConversations();
      if (!mounted) return;
      setState(() => _conversations = fresh);
    } catch (_) {
      // Background refresh — silent failure is fine.
    }
  }

  Future<void> _bootstrap() async {
    // Cache-first paint: surface whatever inbox we last saw so the
    // screen never blanks on cold start, even offline. The fresh
    // network fetch below replaces it once it lands.
    final cachedInbox = MessagingService.readCachedInbox();
    if (cachedInbox.isNotEmpty) {
      setState(() {
        _conversations = cachedInbox;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // Make sure the viewer's church channel + members conversations
      // exist before we fetch, so they show on first open.
      await MessagingService.ensureMyChurchConversations();
      final results = await Future.wait([
        MessagingService.fetchConversations(),
        FeedService.fetchStories(),
        FeedService.fetchPendingFriendRequests(),
        MessagingService.fetchConversationStates(),
        FeedService.fetchMyViewedStoryIds(),
        MessagingService.fetchInboxReactionPreviews(),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _conversations = results[0] as List<Conversation>;
        _stories = results[1] as List<Story>;
        _friendRequests = results[2] as List<PendingFriendRequest>;
        _convStates = results[3] as Map<String, ConversationState>;
        _viewedStoryIds = results[4] as Set<String>;
        _reactionPreviews = results[5] as Map<String, InboxReactionPreview>;
        _loading = false;
        // Auto-route to Requests tab on first paint if the inbox is
        // empty but there are pending requests. Fixes the "chat icon
        // shows 6, but inbox is empty when I tap it" complaint —
        // the 6 was friend requests, and the user couldn't tell.
        if (!_autoTabResolved) {
          _autoTabResolved = true;
          final inboxHasContent = _conversations.any(
            (c) => !c.isIncomingRequestFor(_currentUserId),
          );
          final hasRequests =
              _friendRequests.isNotEmpty ||
              _conversations.any((c) => c.isIncomingRequestFor(_currentUserId));
          if (!inboxHasContent && hasRequests) {
            _showRequests = true;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Only surface the error if we had nothing cached to show.
        if (cachedInbox.isEmpty) {
          _error = 'Could not load messages. Pull to retry.';
        }
        _loading = false;
      });
    }
  }

  Future<void> _openStoryComposer() async {
    final story = await showStoryComposer(context);
    if (!mounted || story == null) return;
    setState(() => _stories = [story, ..._stories]);
  }

  Future<void> _openStoryViewer(List<Story> reel) async {
    // The rail now hands us a play-order (oldest-first) reel, including
    // auto-advance across unviewed authors — show it as-is.
    await StoryViewer.show(context, reel);
    // The viewer marked these watched in the shared cache; rebuild so the
    // rail re-reads it and greys the ring immediately.
    if (mounted) setState(() {});
  }

  String? _viewerPhotoUrl() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['profile_photo_url'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  String _viewerName() {
    final user = AuthService.currentUser;
    final meta = user?.userMetadata ?? const {};
    final raw = (meta['full_name'] as String?)?.trim() ?? '';
    if (raw.isEmpty) return user?.email ?? 'You';
    return raw;
  }

  String get _currentUserId => AuthService.currentUser?.id ?? '';

  /// Inbox tab list. Pins the "Notes to self" self-chat to the top so
  /// it doesn't bounce around the list every time a regular thread
  /// gets a new message (per user complaint — the row was flipping
  /// position on each refresh because it was sorted by last_message_at
  /// alongside everything else). WhatsApp also fixes self-chat to a
  /// constant position.
  /// 1:1 chats (excludes groups + incoming requests). Self-chat pinned.
  // Church groups (channel + members) are always pinned and can't be
  // archived/unpinned — they anchor the top of the list.
  bool _isArchived(Conversation c) =>
      !c.isChurchGroup && (_convStates[c.id]?.archived ?? false);
  bool _isPinned(Conversation c) =>
      c.isChurchGroup || (_convStates[c.id]?.pinned ?? false);
  bool _isMuted(Conversation c) => _convStates[c.id]?.muted ?? false;
  // The chat was cleared and the (shared) last message predates the
  // clear — hide the stale preview for this user only. Also covers
  // "delete for me" of the last message: the shared last_message can't
  // reflect a per-user hide, so we keep a local preview floor and suppress
  // the stale preview until a newer message arrives.
  bool _isPreviewCleared(Conversation c) {
    final cl = _convStates[c.id]?.clearedAt;
    if (cl != null && !c.lastMessageAt.isAfter(cl)) return true;
    // Delete-for-me preview floor. Use a 2s tolerance: the conversation's
    // last_message_at (from the conversations row) and the hidden message's
    // created_at (from the messages row) are set by a trigger to the same
    // instant, but parsing/clock skew can leave last_message_at a few ms
    // AFTER the floor — which left the deleted message still showing.
    final floor = MessagingService.inboxPreviewFloor(c.id);
    if (floor == null) return false;
    // Primary, timestamp-free signal: the shared last_message text is exactly
    // the message we hid for ourselves. Robust against clock/parsing skew.
    final hiddenText = MessagingService.inboxPreviewHiddenText(c.id);
    if (hiddenText != null &&
        hiddenText.isNotEmpty &&
        hiddenText == c.lastMessage.trim()) {
      return true;
    }
    // Fallback for media/system previews (no matchable text): compare instants
    // in UTC so a local-vs-UTC parse can't leave the deleted message showing.
    return c.lastMessageAt.toUtc().isBefore(
      floor.toUtc().add(const Duration(seconds: 2)),
    );
  }

  /// Pinned conversations float to the top, preserving their existing
  /// (recency) order within each group.
  List<Conversation> _pinnedFirst(List<Conversation> list) {
    // Three tiers so a user's pin can NEVER jump above the church defaults:
    //   1. Church defaults — the announcements channel + the church members
    //      group (always pinned to the very top, can't be unpinned).
    //   2. The user's own pinned chats.
    //   3. Everything else.
    bool isChurchDefault(Conversation c) =>
        c.isChurchChannel || c.isChurchGroup;
    bool userPinned(Conversation c) =>
        !isChurchDefault(c) && (_convStates[c.id]?.pinned ?? false);
    final churchDefaults = list.where(isChurchDefault).toList();
    final pinned = list.where(userPinned).toList();
    final rest =
        list.where((c) => !isChurchDefault(c) && !userPinned(c)).toList();
    return [...churchDefaults, ...pinned, ...rest];
  }

  List<Conversation> get _chats {
    // 1:1 chats + the church ANNOUNCEMENTS channel (WhatsApp-channel
    // style — pinned to the very top). The church MEMBERS group and all
    // user-created groups live in the Groups tab, not here.
    final filtered = _conversations
        .where(
          (c) =>
              (!c.isGroup || c.isChurchChannel) &&
              !c.isIncomingRequestFor(_currentUserId) &&
              !_isArchived(c),
        )
        .toList();
    final selfChats = filtered.where((c) => c.isSelfChat).toList();
    final others = _pinnedFirst(filtered.where((c) => !c.isSelfChat).toList());
    return [...selfChats, ...others];
  }

  /// Group chats: user-created groups + the church MEMBERS group (pinned
  /// to the top, can't be unpinned). The announcements channel is NOT
  /// here — it sits in the Chats tab. Archived ones move to Archived.
  List<Conversation> get _groups => _pinnedFirst(
    _conversations
        .where((c) => c.isGroup && !c.isChurchChannel && !_isArchived(c))
        .toList(),
  );

  /// Merged inbox for the Chats tab: 1:1 chats, the church announcements
  /// channel AND every group chat, together in one activity-ordered list
  /// (self-chat + pinned first). Groups no longer live in a separate tab —
  /// the "Groups" filter chip narrows this list to groups only.
  List<Conversation> get _inbox {
    final filtered = _conversations
        .where(
          (c) => !c.isIncomingRequestFor(_currentUserId) && !_isArchived(c),
        )
        .toList();
    final selfChats = filtered.where((c) => c.isSelfChat).toList();
    final others = _pinnedFirst(filtered.where((c) => !c.isSelfChat).toList());
    return [...selfChats, ...others];
  }

  /// Everything (1:1 or group) the viewer has archived.
  List<Conversation> get _archived => _conversations
      .where((c) => !c.isIncomingRequestFor(_currentUserId) && _isArchived(c))
      .toList();

  List<Conversation> get _requests => _conversations
      .where((c) => !c.isGroup && c.isIncomingRequestFor(_currentUserId))
      .toList();

  Future<void> _accept(Conversation c) async {
    try {
      await MessagingService.acceptRequest(c.id);
      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .map(
              (x) => x.id == c.id ? x.copyWith(requestStatus: 'accepted') : x,
            )
            .toList();
        // Accepting the last request returns to the Chats list.
        if (_requests.isEmpty) _showRequests = false;
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not accept this request. Try again.');
    }
  }

  Future<void> _acceptFriendRequest(PendingFriendRequest req) async {
    try {
      await FeedService.acceptRequest(req.friendshipId);
      if (!mounted) return;
      setState(() {
        _friendRequests = _friendRequests
            .where((r) => r.friendshipId != req.friendshipId)
            .toList();
      });
      _toast('You\'re now friends with ${req.requesterName.split(' ').first}.');
    } catch (_) {
      if (!mounted) return;
      _toast('Could not accept the request. Try again.');
    }
  }

  Future<void> _declineFriendRequest(PendingFriendRequest req) async {
    try {
      await FeedService.declineRequest(req.friendshipId);
      if (!mounted) return;
      setState(() {
        _friendRequests = _friendRequests
            .where((r) => r.friendshipId != req.friendshipId)
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not decline the request. Try again.');
    }
  }

  Future<void> _openSelfChat() async {
    try {
      final convo = await MessagingService.openSelfChat();
      if (!mounted) return;
      await _openChat(convo);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not open Notes to self. Try again.');
    }
  }

  /// WhatsApp-style scoped search: friends / messages / groups / archived /
  /// status, plus an Explore scope for people who aren't your friends yet.
  void _openChatSearch() {
    showSearch<void>(
      context: context,
      delegate: ChatSearchDelegate(
        chats: _chats,
        groups: _groups,
        archived: _archived,
        stories: _stories,
        onOpenConversation: _openChat,
        onOpenStatus: _openStoryViewer,
        onStartChatWithUser: _startChatWith,
        onOpenMessage: _openChatAtMessage,
      ),
    );
  }

  /// Open a conversation from a message-search hit and scroll to that exact
  /// message. Resolves the conversation object so the chat header paints
  /// instantly; the chat screen scrolls + flashes the message once loaded.
  void _openChatAtMessage(String conversationId, String messageId) {
    Conversation? convo;
    for (final c in [..._chats, ..._groups, ..._archived]) {
      if (c.id == conversationId) {
        convo = c;
        break;
      }
    }
    context.pushNamed(
      'chat',
      pathParameters: {'id': conversationId},
      extra: (convo, messageId),
    );
  }

  /// Start (or reopen) a 1:1 chat with a member found via search/explore.
  Future<void> _startChatWith(String userId, String name) async {
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: userId,
        otherUserName: name,
      );
      if (!mounted) return;
      await _openChat(convo);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not start the chat. Try again.');
    }
  }

  /// BUG 4 FIX — Open a conversation with an optimistic badge clear.
  /// We zero out the unread count before navigating so the badge
  /// disappears instantly instead of persisting until the async
  /// _bootstrap() network call completes after the user pops back.
  /// The full _bootstrap() refresh still runs on return to sync any
  /// new messages that arrived while the chat was open.
  Future<void> _openChat(Conversation c) async {
    // Optimistically clear the unread count before entering the chat.
    // Even if the network _bootstrap() takes a second, the user never
    // sees the badge on the way back in from the chat screen.
    if (c.unreadCount > 0) {
      setState(() {
        _conversations = _conversations.map((x) {
          return x.id == c.id ? x.copyWith(unreadCount: 0) : x;
        }).toList();
      });
    }
    await context.pushNamed('chat', pathParameters: {'id': c.id}, extra: c);
    if (mounted) _bootstrap();
  }

  Future<void> _decline(Conversation c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Decline message request?',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'You won\'t see this conversation again. ${c.otherUserName} won\'t be notified.',
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Decline',
              style: AppTextStyles.buttonText.copyWith(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MessagingService.declineRequest(c.id);
      if (!mounted) return;
      setState(() {
        _conversations = _conversations.where((x) => x.id != c.id).toList();
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not decline this request. Try again.');
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

  /// FAB → New chat / New group (WhatsApp's creation entry point).
  Future<void> _openNewChatSheet() async {
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
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primaryBlue,
                child: Icon(Icons.group_add, color: AppColors.white),
              ),
              title: Text(
                'New group',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'group'),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.successGreen,
                child: const Icon(Icons.person_add_alt, color: AppColors.white),
              ),
              title: Text(
                'New chat',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'chat'),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.darkNavy,
                child: const Icon(Icons.link, color: AppColors.white),
              ),
              title: Text(
                'Join group with link',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'join'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'group') {
      context.pushNamed('create_group');
    } else if (choice == 'join') {
      await _joinWithLink();
    } else {
      context.pushNamed('new_chat');
    }
  }

  /// Paste an invite link (or raw code) to join a group. Full tap-to-open
  /// deep linking needs platform config; this works today.
  Future<void> _joinWithLink() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: context.palette.card,
        title: const Text('Join group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste invite link or code',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            onPressed: () => Navigator.pop(dctx, controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (!mounted || input == null || input.isEmpty) return;
    final token = _extractInviteToken(input);
    if (token == null) {
      _toastMsg('That doesn\'t look like a valid invite link.');
      return;
    }
    try {
      final id = await GroupService.joinViaInvite(token);
      if (!mounted) return;
      await _bootstrap();
      if (!mounted) return;
      context.pushNamed('chat', pathParameters: {'id': id});
    } catch (_) {
      if (mounted) {
        _toastMsg('Could not join — the link may be invalid or expired.');
      }
    }
  }

  /// Accept either a full invite URL (…join.html?g=TOKEN) or a bare token.
  String? _extractInviteToken(String input) {
    final uri = Uri.tryParse(input);
    final fromQuery = uri?.queryParameters['g'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (!input.contains(' ') && !input.contains('/')) return input;
    return null;
  }

  void _toastMsg(String message) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        // Stories tab: the + adds a photo/text story (story composer).
        // Chats: the + starts a new chat / group as before.
        onPressed: _tab == _ConversationsTab.stories
            ? _openStoryComposer
            : _openNewChatSheet,
        child: Icon(
          _tab == _ConversationsTab.stories
              ? Icons.add_a_photo_outlined
              : Icons.edit_square,
        ),
      ),
      body: Column(
        children: [
          FlatStatusBar(
            child: _chatSelect ? _buildChatSelectionBar() : _buildHero(),
          ),
          _buildTabBar(),
          Expanded(
            child: BrandedRefreshIndicator(
              color: AppColors.primaryBlue,
              onRefresh: _bootstrap,
              // Entrance now happens per-tile (StaggeredReveal in
              // _conversationListView) instead of one block fade.
              child: _buildTabPager(),
            ),
          ),
        ],
      ),
    );
  }

  /// Slim selection bar shown while multi-selecting chats: close + count
  /// + delete, matching the hero's navy gradient.
  Widget _buildChatSelectionBar() {
    final count = _selectedChats.length;
    return Container(
      color: context.palette.scaffoldBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
          child: Row(
            children: [
              _CircleIconButton(icon: Icons.close, onTap: _exitChatSelect),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count selected',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: context.palette.text),
                tooltip: 'Delete',
                onPressed: count == 0 ? null : _deleteSelectedChats,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Slim chat app bar — title + search + overflow (self-chat, privacy).
  /// Replaces the old two-line "ADVENT CHAT / Your chats" hero so the
  /// list starts ~90px higher.
  Widget _buildHero() {
    return Container(
      color: context.palette.scaffoldBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 10),
          child: Row(
            children: [
              _CircleIconButton(
                icon: Icons.arrow_back,
                onTap: () =>
                    context.canPop() ? context.pop() : context.goNamed('home'),
              ),
              const SizedBox(width: 6),
              Text(
                'Advent Chat',
                style: AppTextStyles.titleLarge.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const Spacer(),
              _CircleIconButton(icon: Icons.search, onTap: _openChatSearch),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: context.palette.text),
                color: context.palette.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (v) {
                  if (v == 'self') _openSelfChat();
                  if (v == 'privacy') context.pushNamed('chat_privacy');
                  if (v == 'starred') context.pushNamed('starred_messages');
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'self',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.bookmark_outline),
                      title: Text('Notes to self'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'starred',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.star_border),
                      title: Text('Starred messages'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'privacy',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.lock_outline),
                      title: Text('Chat privacy'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// WhatsApp-style tabs on the flat light header (same background as the
  /// scaffold — one continuous colour), evenly distributed, with a blue
  /// underline under the active tab. Two tabs only: Chats | Stories.
  Widget _buildTabBar() {
    return Container(
      color: context.palette.scaffoldBg,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            _TabPill(
              label: 'Chats',
              selected: _tab == _ConversationsTab.chats && !_showRequests,
              onTap: () {
                if (_showRequests) setState(() => _showRequests = false);
                _selectTab(_ConversationsTab.chats);
              },
            ),
            _TabPill(
              label: 'Stories',
              selected: _tab == _ConversationsTab.stories,
              onTap: () {
                if (_showRequests) setState(() => _showRequests = false);
                _selectTab(_ConversationsTab.stories);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPager() {
    // Chat-shaped shimmer instead of a bare spinner, crossfading into
    // the inbox when it lands.
    return ContentReveal(
      loading: _loading && _conversations.isEmpty,
      skeleton: ShimmerLoaders.cardList(count: 7),
      child: _buildTabPagerContent(),
    );
  }

  Widget _buildTabPagerContent() {
    if (_error != null && _conversations.isEmpty) {
      return _buildErrorState();
    }
    if (_showRequests) return _buildRequestsView();
    // Swipe between Chats / Groups / Status / Archived with a smooth
    // animated transition (order matches _ConversationsTab).
    return PageView(
      controller: _pageController,
      onPageChanged: (i) => setState(() => _tab = _ConversationsTab.values[i]),
      children: [_buildChatsTab(), _buildStoriesTab()],
    );
  }

  /// WhatsApp-style: archived chats are hidden from the list and reached
  /// through a small "Archived" row that opens them in a sheet.
  void _openArchivedSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.scaffoldBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Archived',
                    style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _archived.isEmpty
                  ? Center(
                      child: Text(
                        'No archived chats',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: ctx.palette.textMuted,
                        ),
                      ),
                    )
                  : ListView(
                      controller: controller,
                      children: [
                        for (final c in _archived)
                          _ConversationTile(
                            key: ValueKey('arch-${c.id}'),
                            conversation: c,
                            isLastFromMe: c.lastSenderId == _currentUserId,
                            pinned: false,
                            muted: _isMuted(c),
                            onTap: () {
                              Navigator.pop(ctx);
                              _openChat(c);
                            },
                            onLongPress: () {
                              Navigator.pop(ctx);
                              _openConversationActions(c);
                            },
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ----- Chats tab: requests banner + 1:1 conversation list -----------
  Widget _buildChatsTab() {
    final all = _inbox;
    final requestCount = _requests.length + _friendRequests.length;
    if (all.isEmpty && requestCount == 0 && _archived.isEmpty) {
      return _buildEmptyState(
        title: 'No conversations yet',
        body:
            'Tap the pencil button to start a new chat, or reach out from a '
            'member directory or church page.',
      );
    }
    // Apply the WhatsApp-style filter chip.
    final List<Conversation> list;
    switch (_chatFilter) {
      case _ChatFilter.unread:
        list = all.where((c) => c.unreadCount > 0).toList();
      case _ChatFilter.groups:
        list = _groups;
      case _ChatFilter.all:
        list = all;
    }
    final headers = <Widget>[
      _buildChatFilterChips(
        unreadCount: all.where((c) => c.unreadCount > 0).length,
      ),
      if (requestCount > 0)
        _RequestsBanner(
          count: requestCount,
          onTap: () => setState(() => _showRequests = true),
        ),
      if (_archived.isNotEmpty)
        ListTile(
          onTap: _openArchivedSheet,
          leading: Icon(
            Icons.archive_outlined,
            color: context.palette.textMuted,
          ),
          title: const Text('Archived'),
          trailing: Text(
            '${_archived.length}',
            style: AppTextStyles.labelMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ),
      // Filter found nothing (but the inbox isn't empty) — let the user know
      // instead of a blank screen under the chips.
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
          child: Center(
            child: Text(
              _chatFilter == _ChatFilter.unread
                  ? 'No unread chats — you\'re all caught up.'
                  : 'No groups here yet.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ),
        ),
    ];
    return _conversationListView(list, banner: Column(children: headers));
  }

  /// WhatsApp-style quick filter chips (All · Unread · Groups) above the
  /// chat list. Unread carries a count badge.
  Widget _buildChatFilterChips({required int unreadCount}) {
    Widget chip(String label, _ChatFilter f, {int badge = 0}) {
      final selected = _chatFilter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? AppColors.primaryBlue : context.palette.chipBg,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _chatFilter = f),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: selected ? AppColors.white : context.palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.white.withValues(alpha: 0.25)
                            : AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$badge',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          chip('All', _ChatFilter.all),
          chip('Unread', _ChatFilter.unread, badge: unreadCount),
          chip('Groups', _ChatFilter.groups),
        ],
      ),
    );
  }

  // ----- Stories tab: the stories rail (moved off the chat list) -------
  Widget _buildStoriesTab() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        StoriesRail(
          stories: _stories,
          viewerId: _currentUserId,
          viewerName: _viewerName(),
          viewerPhotoUrl: _viewerPhotoUrl(),
          onAddStory: _openStoryComposer,
          onAuthorTapped: (_, list) => _openStoryViewer(list),
          viewedStoryIds: _viewedStoryIds.union(
            FeedService.viewedStoryIdsCached(),
          ),
        ),
        if (_stories.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Text(
              'No stories yet. Tap the + to share one — it disappears '
              'after 24 hours.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }

  // ----- Requests view (opened from the Chats banner) -----------------
  Widget _buildRequestsView() {
    // Don't show the same person twice: if they already appear under
    // Friend requests, drop their message request from this view.
    final friendIds = _friendRequests.map((r) => r.requesterId).toSet();
    final list = _requests
        .where((c) => !friendIds.contains(c.otherUserId))
        .toList();
    final hasFriendRequests = _friendRequests.isNotEmpty;
    final hasMessageRequests = list.isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showRequests = false),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to chats'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
          ),
        ),
        if (!hasFriendRequests && !hasMessageRequests)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: _buildEmptyState(
              title: 'No requests',
              body:
                  'Friend requests and messages from people you haven\'t '
                  'chatted with yet land here.',
            ),
          ),
        if (hasFriendRequests) ...[
          _RequestsSectionHeader(
            label: 'Friend requests',
            count: _friendRequests.length,
          ),
          const SizedBox(height: 10),
          for (final req in _friendRequests) ...[
            _FriendRequestTile(
              request: req,
              onAccept: () => _acceptFriendRequest(req),
              onDecline: () => _declineFriendRequest(req),
              onOpenProfile: () => context.pushNamed(
                'user_profile',
                pathParameters: {'userId': req.requesterId},
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
        ],
        if (hasMessageRequests) ...[
          _RequestsSectionHeader(label: 'Message requests', count: list.length),
          const SizedBox(height: 10),
          for (final c in list) ...[
            _RequestTile(
              conversation: c,
              onAccept: () => _accept(c),
              onDecline: () => _decline(c),
              onPreview: () => _openChat(c),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  /// Shared conversation list (used by Chats + Groups). Rebuilds on the
  /// presence roster so green dots update without a refetch. Tiles are
  /// keyed by id so reorders on realtime refetch don't flicker.
  Widget _conversationListView(List<Conversation> list, {Widget? banner}) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PresenceService.onChange,
      builder: (context, _, _) {
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          // Slimmer gutters so the inbox flows edge-to-edge like
          // WhatsApp instead of sitting inside a boxed column.
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 32),
          itemCount: list.length + (banner == null ? 0 : 1),
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (banner != null && i == 0) return banner;
            final c = list[i - (banner == null ? 0 : 1)];
            // First screenful cascades in; tiles further down mount
            // plainly so fast scrolling never feels laggy.
            final revealIndex = i < 9 ? i : -1;
            final tile = _ConversationTile(
              key: ValueKey(c.id),
              conversation: c,
              isLastFromMe: c.lastSenderId == _currentUserId,
              pinned: _isPinned(c),
              muted: _isMuted(c),
              selected: _chatSelect && _selectedChats.contains(c.id),
              onTap: _chatSelect ? () => _toggleChat(c) : () => _openChat(c),
              onLongPress: _chatSelect
                  ? null
                  : () => _openConversationActions(c),
              // Tap the avatar to view the full profile/group photo
              // (WhatsApp). Disabled in multi-select so the tap toggles.
              onAvatarTap: _chatSelect
                  ? () => _toggleChat(c)
                  : (c.otherUserPhotoUrl ?? '').isNotEmpty
                  ? () => FullImageViewer.show(context, c.otherUserPhotoUrl)
                  : () => _openChat(c),
              previewCleared: _isPreviewCleared(c),
              reactionPreview: _reactionPreviews[c.id],
            );
            if (revealIndex < 0) return tile;
            return StaggeredReveal(index: revealIndex, rise: 18, child: tile);
          },
        );
      },
    );
  }

  /// WhatsApp-style long-press menu on an inbox tile. Bottom sheet with
  /// Mark as read / Delete — same pattern (and same set of actions) as
  /// the chat-screen overflow menu uses inside the conversation.
  /// Optimistically flip a pin/mute/archive flag, then persist. On
  /// failure the next _bootstrap reconciles from the server.
  Future<void> _applyConversationFlag(
    Conversation c, {
    bool? pinned,
    bool? muted,
    bool? archived,
  }) async {
    final current = _convStates[c.id] ?? const ConversationState();
    setState(() {
      _convStates = {
        ..._convStates,
        c.id: ConversationState(
          pinned: pinned ?? current.pinned,
          muted: muted ?? current.muted,
          archived: archived ?? current.archived,
        ),
      };
    });
    try {
      await MessagingService.setConversationFlags(
        c.id,
        pinned: pinned,
        muted: muted,
        archived: archived,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.red,
            content: Text(
              'Could not update. Try again.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openConversationActions(Conversation c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.mark_email_read_outlined,
                  color: AppColors.primaryBlue,
                ),
                title: const Text('Mark as read'),
                onTap: () => Navigator.of(sheetCtx).pop('read'),
              ),
              if (!c.isChurchGroup)
                ListTile(
                  leading: const Icon(
                    Icons.checklist_rtl,
                    color: AppColors.primaryBlue,
                  ),
                  title: const Text('Select'),
                  onTap: () => Navigator.of(sheetCtx).pop('select'),
                ),
              // Church groups are anchored — no pin/archive/delete; only
              // mute is allowed.
              if (!c.isChurchGroup)
                ListTile(
                  leading: Transform.rotate(
                    angle: 0.785398,
                    child: const Icon(
                      Icons.push_pin_outlined,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  title: Text(_isPinned(c) ? 'Unpin' : 'Pin to top'),
                  onTap: () => Navigator.of(sheetCtx).pop('pin'),
                ),
              ListTile(
                leading: Icon(
                  _isMuted(c)
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                  color: AppColors.primaryBlue,
                ),
                title: Text(_isMuted(c) ? 'Unmute' : 'Mute notifications'),
                onTap: () => Navigator.of(sheetCtx).pop('mute'),
              ),
              if (!c.isChurchGroup)
                ListTile(
                  leading: Icon(
                    _isArchived(c)
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    color: AppColors.primaryBlue,
                  ),
                  title: Text(_isArchived(c) ? 'Unarchive' : 'Archive'),
                  onTap: () => Navigator.of(sheetCtx).pop('archive'),
                ),
              // Groups can't be deleted from the inbox — you delete a group
              // chat only from inside it, and only after you've left or
              // been removed (the in-chat "Delete conversation" button).
              if (!c.isGroup)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.red,
                  ),
                  title: const Text(
                    'Delete conversation',
                    style: TextStyle(color: AppColors.red),
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop('delete'),
                ),
              ListTile(
                leading: Icon(Icons.close, color: context.palette.text),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(sheetCtx).pop(null),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'select':
        _enterChatSelect(c);
        break;
      case 'read':
        await MessagingService.markConversationRead(c.id);
        if (!mounted) return;
        await _bootstrap();
        break;
      case 'pin':
        await _applyConversationFlag(c, pinned: !_isPinned(c));
        break;
      case 'mute':
        await _applyConversationFlag(c, muted: !_isMuted(c));
        break;
      case 'archive':
        await _applyConversationFlag(c, archived: !_isArchived(c));
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Delete conversation?'),
            content: Text(
              'This deletes ${c.otherUserName == 'Notes to self' ? 'your notes-to-self thread' : "your chat with ${c.otherUserName}"} and all messages.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: () => Navigator.of(dctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          // Groups: remove my membership row so the group disappears from
          // my list cleanly (patch_079) — declineRequest only worked for
          // 1:1 rows and left a stale group preview behind.
          if (c.isGroup) {
            await GroupService.deleteGroupConversation(c.id);
          } else {
            await MessagingService.declineRequest(c.id);
          }
          if (!mounted) return;
          await _bootstrap();
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.red,
              content: Text(
                'Could not delete. Try again.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.white,
                ),
              ),
            ),
          );
        }
        break;
    }
  }

  Widget _buildErrorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 56,
                  color: context.palette.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required String title, required String body}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    color: AppColors.primaryBlue,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
    // Lives on the navy header: white text, animated white underline —
    // WhatsApp's tab language, evenly distributed by the Expanded.
    return Expanded(
      child: PressEffect(
        pressedScale: 0.95,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedDefaultTextStyle(
                duration: AppMotion.quick,
                style: AppTextStyles.titleMedium.copyWith(
                  color: selected
                      ? AppColors.primaryBlue
                      : const Color(0xFF7C8698),
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                child: Text(label, maxLines: 1),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: AppMotion.quick,
                curve: AppMotion.easeOut,
                height: 3,
                width: selected ? 32 : 0,
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    super.key,
    required this.conversation,
    required this.isLastFromMe,
    required this.onTap,
    this.onLongPress,
    this.pinned = false,
    this.muted = false,
    this.selected = false,
    this.onAvatarTap,
    this.previewCleared = false,
    this.reactionPreview,
  });

  final Conversation conversation;
  final bool isLastFromMe;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool pinned;
  final bool muted;
  final bool selected;
  final VoidCallback? onAvatarTap;
  // True when the user cleared this chat — hide the stale last-message
  // preview (the messages themselves are already hidden inside).
  final bool previewCleared;

  /// Latest reaction on this conversation (newer than the last message), shown
  /// in place of the preview like WhatsApp. Null when there's none.
  final InboxReactionPreview? reactionPreview;

  String _reactionPreviewLabel(InboxReactionPreview r) {
    // Only ever someone ELSE's reaction (the RPC excludes the caller's own),
    // so your own reactions never hijack your preview — WhatsApp behaviour.
    if (r.onMyMessage) return 'Reacted ${r.emoji} to your message';
    return 'Reacted ${r.emoji} to a message';
  }

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount > 0 && !isLastFromMe;
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // Strong, obvious tint + border when multi-selected so it's
              // clear which chats are picked.
              color: selected
                  ? Color.alphaBlend(
                      AppColors.primaryBlue.withValues(alpha: 0.16),
                      context.palette.card,
                    )
                  : context.palette.card,
              border: selected
                  ? Border.all(color: AppColors.primaryBlue, width: 1.6)
                  : null,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onAvatarTap,
                  child: Stack(
                    children: [
                      conversation.isChurchGroup
                          ? ChurchGroupAvatar(
                              photoUrl: conversation.otherUserPhotoUrl,
                              size: 52,
                            )
                          : _Avatar(
                              name: conversation.otherUserName,
                              photoUrl: conversation.otherUserPhotoUrl,
                              isSelfChat: conversation.isSelfChat,
                              isGroup: conversation.isGroup,
                            ),
                      // Multi-select check badge over the avatar.
                      if (selected)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.palette.card,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 14,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      // Small green dot on the avatar's bottom-right when
                      // the other user is currently online (WhatsApp-style).
                      // Hidden for self-chats and pending requests.
                      if (!conversation.isSelfChat &&
                          conversation.requestStatus == 'accepted' &&
                          PresenceService.isOnline(conversation.otherUserId))
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.successGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.palette.card,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.otherUserName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (conversation.otherUserIsVerified)
                            const VerifiedTick(size: 15),
                          if (conversation.isBusiness) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'BUSINESS',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                          if (muted) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.volume_off_outlined,
                              size: 14,
                              color: context.palette.textMuted,
                            ),
                          ],
                          const SizedBox(width: 6),
                          Text(
                            _shortTime(conversation.lastMessageAt),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: unread
                                  ? AppColors.primaryBlue
                                  : context.palette.textMuted,
                              fontSize: 11,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Tick on the last message, but ONLY when the
                          // viewer sent it (patch_075 surfaces its real
                          // delivered/read state): ✓ sent, ✓✓ delivered,
                          // ✓✓ blue read (blue only in 1:1, like in-chat).
                          // Never on a placeholder ("Say hello") or a reaction
                          // preview — those aren't messages the viewer sent.
                          if (isLastFromMe &&
                              !conversation.isSelfChat &&
                              reactionPreview == null &&
                              !previewCleared &&
                              conversation.lastMessage.isNotEmpty) ...[
                            Icon(
                              (conversation.lastDelivered ||
                                      conversation.lastRead)
                                  ? Icons.done_all
                                  : Icons.done,
                              size: 14,
                              color:
                                  (conversation.lastRead &&
                                      !conversation.isGroup)
                                  ? AppColors.primaryBlue
                                  : context.palette.textMuted,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              (reactionPreview != null && !previewCleared)
                                  ? _reactionPreviewLabel(reactionPreview!)
                                  : (previewCleared ||
                                          conversation.lastMessage.isEmpty)
                                      ? (conversation.isChurchChannel
                                            ? 'Church announcements appear here'
                                            : 'Say hello')
                                      : (isLastFromMe
                                            ? _selfSystemLabel(
                                                conversation.lastMessage,
                                              )
                                            : conversation.lastMessage),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: unread
                                    ? context.palette.text
                                    : context.palette.textMuted,
                                fontSize: 13,
                                fontWeight: unread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${conversation.unreadCount}',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (pinned) ...[
                            const SizedBox(width: 6),
                            Transform.rotate(
                              angle: 0.785398, // 45° — WhatsApp pin look
                              child: Icon(
                                Icons.push_pin,
                                size: 14,
                                color: context.palette.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortTime(DateTime then) {
    final now = DateTime.now();
    final diff = now.difference(then);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}

class _RequestsSectionHeader extends StatelessWidget {
  const _RequestsSectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.titleSmall.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.request,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenProfile,
  });

  final PendingFriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if ((request.requesterChurchName ?? '').trim().isNotEmpty)
        request.requesterChurchName!.trim(),
      _relativeTime(request.createdAt),
    ].join('  ·  ');
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenProfile,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(
                      name: request.requesterName,
                      photoUrl: request.requesterPhotoUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.requesterName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Sent you a friend request',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.palette.textMuted,
                            ),
                          ),
                          if (subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: context.palette.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'Accept',
                        filled: true,
                        onTap: onAccept,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        label: 'Decline',
                        filled: false,
                        onTap: onDecline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// WhatsApp-style absolute time: today shows "10:34", yesterday
  /// shows "yesterday", same week shows the weekday name ("Mon"),
  /// otherwise shows the date ("12/03/26"). Replaces the previous
  /// "Xm ago" relative format that the user found vague.
  String _relativeTime(DateTime when) {
    final local = when.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(messageDay).inDays;
    if (diffDays == 0) {
      // Same calendar day: 24-hour clock to mirror WhatsApp's
      // device-locale convention.
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    if (diffDays == 1) return 'yesterday';
    if (diffDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[local.weekday - 1];
    }
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString().substring(2);
    return '$d/$m/$y';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: filled ? AppColors.primaryBlue : context.palette.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled
                  ? null
                  : Border.all(color: context.palette.divider),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTextStyles.buttonText.copyWith(
                color: filled ? AppColors.white : context.palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.conversation,
    required this.onAccept,
    required this.onDecline,
    required this.onPreview,
  });

  final Conversation conversation;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPreview,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Avatar(
                      name: conversation.otherUserName,
                      photoUrl: conversation.otherUserPhotoUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  conversation.otherUserName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              if (conversation.otherUserIsVerified)
                                const VerifiedTick(size: 15),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'NEW REQUEST',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.primaryBlue,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            conversation.lastMessage.isEmpty
                                ? 'Sent you a message request.'
                                : conversation.lastMessage,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: context.palette.textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDecline,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColors.red.withValues(alpha: 0.35),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: Text(
                          'Decline',
                          style: AppTextStyles.buttonText.copyWith(
                            color: AppColors.red,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue.withValues(
                                alpha: 0.30,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: onAccept,
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Accept',
                            style: AppTextStyles.buttonText.copyWith(
                              color: AppColors.white,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Render the inbox preview of a self-authored group system event as
/// "You …" (the raw row stores the actor's name, e.g. "Michael left").
String _selfSystemLabel(String content) {
  if (content.contains('joined via link')) return 'You joined via link';
  if (content.endsWith(' was removed')) return 'You were removed';
  if (content.endsWith(' left')) return 'You left';
  if (content.endsWith(' joined')) return 'You joined';
  if (content.contains('created the group')) return 'You created the group';
  return content;
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    this.photoUrl,
    this.isSelfChat = false,
    this.isGroup = false,
  });
  final String name;
  final String? photoUrl;
  final bool isSelfChat;
  final bool isGroup;

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
    return Container(
      width: 50,
      height: 50,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: hasPhoto && !isSelfChat ? null : AppColors.primaryGradient,
        color: hasPhoto && !isSelfChat ? context.palette.cardMuted : null,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: isSelfChat
          ? const Icon(Icons.bookmark, color: AppColors.white, size: 22)
          : (isGroup && !hasPhoto)
          ? const Icon(Icons.groups, color: AppColors.white, size: 26)
          : hasPhoto
          ? CachedImage(
              photoUrl!,
              fit: BoxFit.cover,
              width: 50,
              height: 50,
              errorBuilder: (context, error, stackTrace) => Text(
                initials,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            )
          : Text(
              initials,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
    );
  }
}

/// Slim "Message requests (N) ›" banner shown atop the Chats tab.
class _RequestsBanner extends StatelessWidget {
  const _RequestsBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_add_alt_1,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    count == 1
                        ? '1 message / friend request'
                        : '$count message / friend requests',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.primaryBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          // Frosted circle — same family as the Home header buttons so
          // back/search chips read consistently across every hero.
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? context.palette.cardMuted
                  : const Color(0xFFE4E9F2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: context.palette.text, size: 18),
          ),
        ),
      ),
    );
  }
}
