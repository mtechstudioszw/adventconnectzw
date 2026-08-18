import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/screen_shell.dart';
import 'package:go_router/go_router.dart';
import '../../models/friendship_model.dart';
import '../../models/message_model.dart';
import '../../models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/group_service.dart';
import '../../services/messaging_service.dart';
import '../../widgets/church_group_avatar.dart';
import '../../services/presence_service.dart';
import '../../services/typing_signal.dart';
import '../widgets/main_bottom_nav.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/home/composer_sheet.dart';
import '../../widgets/home/story_viewer.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/full_image_viewer.dart';
import '../../widgets/verified_tick.dart';
import 'chat_search_delegate.dart';
import '../../widgets/motion/branded_refresh_indicator.dart';
import '../../widgets/motion/content_reveal.dart';
import '../../widgets/motion/hide_on_scroll.dart';
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

/// Quick filter chips above the inbox.
///
/// Stories no longer costs a top-level tab — a messaging screen's most
/// valuable slot was spent on something Home already carries. It folds into
/// the Active rail instead, and the freed space goes to these.
enum _ChatFilter { all, unread, groups, churches, friends }

extension _ChatFilterLabel on _ChatFilter {
  String get label => switch (this) {
    _ChatFilter.all => 'All',
    _ChatFilter.unread => 'Unread',
    _ChatFilter.groups => 'Groups',
    _ChatFilter.churches => 'Churches',
    _ChatFilter.friends => 'Friends',
  };
}

class _ConversationsScreenState extends State<ConversationsScreen>
    with NavVisibilityMixin {
  List<Conversation> _conversations = [];
  Map<String, ConversationState> _convStates = const {};
  Map<String, InboxReactionPreview> _reactionPreviews = const {};
  List<Story> _stories = const [];

  /// user id → display name, for the "who spoke last" prefix on group rows.
  Map<String, String> _senderNames = const {};

  /// conversation id → member count, for user-created group rows.
  Map<String, int> _groupCounts = const {};
  Set<String> _viewedStoryIds = const {};
  List<PendingFriendRequest> _friendRequests = const [];

  /// User ids the viewer has an ACCEPTED friendship with. Drives the
  /// Friends chip, which previously matched any 1:1 chat and so listed
  /// people the viewer had merely messaged.
  Set<String> _friendIds = const {};
  bool _loading = true;
  String? _error;
  _ChatFilter _chatFilter = _ChatFilter.all;

  // ----- Inline search -------------------------------------------------
  // searchMessages() has existed in the service since patch_130 and the
  // inbox never exposed it. One field over people, groups AND message
  // bodies — the "where did that message go" problem, already solved
  // server-side and previously unreachable.
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  Timer? _searchDebounce;
  bool _searching = false;
  List<MessageSearchHit> _messageHits = const [];

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
    // Drafts are written on the chat screen and read here, so the row needs
    // telling — otherwise "Draft:" only appears after some other refetch.
    MessagingService.draftRevision.addListener(_onLocalInboxChange);
  }

  void _onLocalInboxChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _searchDebounce?.cancel();
    _activitySub?.cancel();
    MessagingService.inboxLocalRevision.removeListener(_onLocalInboxChange);
    MessagingService.draftRevision.removeListener(_onLocalInboxChange);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Inbox search. Names and group titles filter locally and instantly; the
  /// message-body search is a server round-trip, so it debounces.
  void _onQueryChanged(String raw) {
    final q = raw.trim();
    setState(() => _query = q);
    _searchDebounce?.cancel();
    if (q.length < 2) {
      setState(() {
        _messageHits = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      final hits = await MessagingService.searchMessages(q);
      if (!mounted) return;
      // A slower earlier request can land after a newer one — ignore it
      // rather than showing results for a query the user has moved past.
      if (_query != q) return;
      setState(() {
        _messageHits = hits;
        _searching = false;
      });
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _query = '';
      _messageHits = const [];
      _searching = false;
    });
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
        // Their message IS the end of them typing. Without this the row
        // reads "typing…" for up to 4 more seconds *underneath the
        // message they just sent* — the same bug the chat screen fixed
        // with its own early clear.
        for (final r in rows) {
          if (r['sender_id']?.toString() == me) continue;
          final convo = r['conversation_id']?.toString() ?? '';
          if (convo.isNotEmpty) TypingSignal.clear(convo);
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
        // Who the viewer is ACTUALLY friends with — the Friends chip
        // needs real friendships, not "is a 1:1 chat".
        FeedService.fetchMyFriendships(),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _conversations = results[0] as List<Conversation>;
        _stories = results[1] as List<Story>;
        _friendRequests = results[2] as List<PendingFriendRequest>;
        _convStates = results[3] as Map<String, ConversationState>;
        _viewedStoryIds = results[4] as Set<String>;
        _reactionPreviews = results[5] as Map<String, InboxReactionPreview>;
        _friendIds = {
          for (final f in results[6] as List<Friendship>)
            if (f.isAccepted)
              f.requesterId == _currentUserId ? f.addresseeId : f.requesterId,
        };
        _loading = false;
        unawaited(_resolveSenderNames());
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

  /// Resolve "who spoke last" for group rows in one batched lookup.
  ///
  /// Runs after the inbox has already painted — the rows are useful without
  /// the speaker name, so this must never hold up first paint.
  Future<void> _resolveSenderNames() async {
    final wanted = <String>{
      for (final c in _conversations)
        if (c.isGroup &&
            !c.isChurchChannel &&
            (c.lastSenderId ?? '').isNotEmpty &&
            c.lastSenderId != _currentUserId &&
            !_senderNames.containsKey(c.lastSenderId))
          c.lastSenderId!,
    };
    // Church groups are excluded: their membership is the whole
    // congregation, so counting them client-side would mean pulling
    // hundreds of rows to render one number.
    final groupIds = <String>{
      for (final c in _conversations)
        if (c.isGroup && !c.isChurchGroup && !_groupCounts.containsKey(c.id))
          c.id,
    };

    final results = await Future.wait([
      wanted.isEmpty
          ? Future.value(const <String, String>{})
          : MessagingService.fetchDisplayNames(wanted),
      groupIds.isEmpty
          ? Future.value(const <String, int>{})
          : MessagingService.fetchGroupMemberCounts(groupIds),
    ]);
    if (!mounted) return;
    final names = results[0] as Map<String, String>;
    final counts = results[1] as Map<String, int>;
    if (names.isEmpty && counts.isEmpty) return;
    setState(() {
      _senderNames = {..._senderNames, ...names};
      _groupCounts = {..._groupCounts, ...counts};
    });
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
    final rest = list
        .where((c) => !isChurchDefault(c) && !userPinned(c))
        .toList();
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

  /// Message requests from people who are NOT also in the friend-request
  /// list — one person, one row, wherever requests are counted or drawn.
  ///
  /// The Requests view already filtered this way; the banner above the
  /// inbox did not, so somebody who sent a friend request AND a first
  /// message was counted twice and had their face in the stack twice
  /// ("Tino and 1 other · 2 requests", both of them Tino). One getter now,
  /// so the two cannot disagree again.
  List<Conversation> get _messageRequestsDeduped {
    final friendIds = _friendRequests.map((r) => r.requesterId).toSet();
    return _requests.where((c) => !friendIds.contains(c.otherUserId)).toList();
  }

  /// Friendship ids with an accept in flight, so a second tap on the same
  /// tile is ignored.
  ///
  /// The tile was only removed AFTER the round-trip, so during it the
  /// button stayed live and firing it again sent a second
  /// `acceptRequest` — which re-runs the conversation seed too.
  final Set<String> _acceptingFriendIds = <String>{};

  Future<void> _acceptFriendRequest(PendingFriendRequest req) async {
    if (!_acceptingFriendIds.add(req.friendshipId)) return;
    try {
      await FeedService.acceptRequest(req.friendshipId);
      if (!mounted) return;
      setState(() {
        _friendRequests = _friendRequests
            .where((r) => r.friendshipId != req.friendshipId)
            .toList();
        // Promote their message request in the same breath. The server now
        // does this when the friendship is accepted (patch_194), but this
        // list is already in memory — without it, the row that had been
        // hidden only because a friend request existed pops straight back
        // with another Accept button on it, which is what "you accept it
        // twice" was. Same edit `_accept` makes, so the thread simply
        // moves into the inbox.
        _conversations = _conversations
            .map(
              (x) =>
                  !x.isGroup &&
                      x.otherUserId == req.requesterId &&
                      x.isIncomingRequestFor(_currentUserId)
                  ? x.copyWith(requestStatus: 'accepted')
                  : x,
            )
            .toList();
        if (_requests.isEmpty && _friendRequests.isEmpty) {
          _showRequests = false;
        }
      });
      _toast('You\'re now friends with ${req.requesterName.split(' ').first}.');
    } catch (_) {
      if (!mounted) return;
      _toast('Could not accept the request. Try again.');
    } finally {
      _acceptingFriendIds.remove(req.friendshipId);
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

  /// FAB → the creation entry point.
  ///
  /// Was three stock ListTiles with primary-coloured CircleAvatars, which is
  /// the default Material sheet with different words in it. Each option now
  /// says what it's FOR, not just what it's called — "New chat" and "New
  /// group" are indistinguishable to somebody who hasn't used the app before.
  Future<void> _openNewChatSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ComposeSheet(),
    );
    if (!mounted || choice == null) return;
    if (choice == 'group') {
      context.pushNamed('create_group');
    } else if (choice == 'join') {
      await _joinWithLink();
    } else if (choice == 'self') {
      await _openSelfChat();
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
      backgroundColor: Colors.transparent,
      // Advent Chat is a top-level tab now (it replaced Churches), so the
      // inbox carries the island like every other tab destination — and
      // hides it on scroll the way the others do.
      bottomNavigationBar: HideOnScroll(
        visible: navVisible,
        child: const MainBottomNav(currentIndex: MainBottomNav.chatIndex),
      ),
      // Hidden while multi-selecting or searching — in both modes the screen
      // is doing something else and a "compose" button is noise.
      floatingActionButton: _chatSelect || _query.isNotEmpty
          ? null
          : _ComposeFab(onTap: _openNewChatSheet),
      body: Column(
        children: [
          FlatStatusBar(
            child: _chatSelect ? _buildChatSelectionBar() : _buildHero(),
          ),
          if (!_chatSelect && !_showRequests) _buildSearchField(),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: handleNavScroll,
              child: BrandedRefreshIndicator(
                color: AppColors.primaryBlue,
                onRefresh: _bootstrap,
                // Entrance now happens per-tile (StaggeredReveal in
                // _conversationListView) instead of one block fade.
                child: _buildBody(),
              ),
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
          // Chat is a root tab, so there is nowhere to go "back" TO — the
          // arrow was left over from when it was pushed from Home. Tabs
          // don't carry one; the island is the way between them.
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
          child: Row(
            children: [
              Text(
                'Advent Chat',
                style: AppTextStyles.titleLarge.copyWith(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const Spacer(),
              // The person-search circle button was removed (founder, Aug).
              // The inline field directly below already searches people,
              // groups and messages, so the icon sat on top of the same job.
              // Its OTHER job — the scoped search over people you aren't
              // friends with yet, status and archived — was not duplicated
              // anywhere, so it moved into the overflow menu as "Find
              // people" rather than being deleted with the button.
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
                  if (v == 'find') _openChatSearch();
                },
                itemBuilder: (context) => const [
                  // Find people — the ONLY route to the scoped search
                  // (explore / status / archived) now that the header's
                  // person-search button is gone. The inline field below
                  // searches people, groups and messages, but NOT people
                  // you aren't friends with yet, so dropping this entirely
                  // would have quietly removed the only way to find them.
                  PopupMenuItem(
                    value: 'find',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_search),
                      title: Text('Find people'),
                    ),
                  ),
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

  /// The inline search field. One field over people, groups AND message
  /// bodies — see [_onQueryChanged].
  Widget _buildSearchField() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        decoration: BoxDecoration(
          color: palette.cardMuted,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: _searchFocus.hasFocus
                ? AppColors.primaryBlue.withValues(alpha: 0.55)
                : palette.divider,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.search, size: 19, color: palette.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.text,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search people, groups, messages',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textMuted,
                    fontSize: 14,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: palette.textMuted),
                splashRadius: 18,
                onPressed: _clearSearch,
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Chat-shaped shimmer instead of a bare spinner, crossfading into
    // the inbox when it lands.
    return ContentReveal(
      loading: _loading && _conversations.isEmpty,
      skeleton: ShimmerLoaders.cardList(count: 7),
      child: _buildBodyContent(),
    );
  }

  Widget _buildBodyContent() {
    if (_error != null && _conversations.isEmpty) {
      return _buildErrorState();
    }
    if (_query.isNotEmpty) return _buildSearchResults();
    if (_showRequests) return _buildRequestsView();
    return _buildChatsTab();
  }

  /// Results for the inline field: names first (instant, local), then
  /// message bodies (the server round-trip).
  Widget _buildSearchResults() {
    final q = _query.toLowerCase();
    final nameHits = _inbox
        .where((c) => c.otherUserName.toLowerCase().contains(q))
        .toList();
    final convById = {for (final c in _conversations) c.id: c};

    if (nameHits.isEmpty && _messageHits.isEmpty && !_searching) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 70),
          Icon(Icons.search_off, size: 46, color: context.palette.textMuted),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Nothing matches “$_query”.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 32),
      children: [
        if (nameHits.isNotEmpty) ...[
          _SearchSectionLabel(label: 'Chats and groups'),
          for (final c in nameHits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ConversationTile(
                key: ValueKey('search-${c.id}'),
                conversation: c,
                isLastFromMe: c.lastSenderId == _currentUserId,
                pinned: false,
                muted: _isMuted(c),
                onTap: () {
                  _clearSearch();
                  _openChat(c);
                },
                previewCleared: _isPreviewCleared(c),
              ),
            ),
        ],
        if (_searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
        if (_messageHits.isNotEmpty) ...[
          _SearchSectionLabel(label: 'Messages'),
          for (final hit in _messageHits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MessageHitTile(
                hit: hit,
                conversation: convById[hit.conversationId],
                query: _query,
                onTap: () {
                  _clearSearch();
                  _openChatAtMessage(hit.conversationId, hit.messageId);
                },
              ),
            ),
        ],
      ],
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
    // Deduped, so one person who sent both a friend request and a first
    // message counts once. This used to be `_requests.length +
    // _friendRequests.length`, which counted them twice while the Requests
    // view below showed them once.
    final messageRequests = _messageRequestsDeduped;
    final requestCount = messageRequests.length + _friendRequests.length;
    if (all.isEmpty && requestCount == 0 && _archived.isEmpty) {
      return _buildEmptyState(
        title: 'No conversations yet',
        body:
            'Tap the pencil button to start a new chat, or reach out from a '
            'member directory or church page.',
      );
    }
    final list = _applyFilter(all, _chatFilter);
    final headers = <Widget>[
      _buildActiveRail(),
      _buildChatFilterChips(all),
      if (requestCount > 0)
        _RequestsBanner(
          requests: _friendRequests,
          messageRequests: messageRequests,
          onTap: () => setState(() => _showRequests = true),
          onAccept: _acceptFriendRequest,
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
              switch (_chatFilter) {
                _ChatFilter.unread =>
                  'No unread chats — you\'re all caught up.',
                _ChatFilter.groups => 'No groups here yet.',
                _ChatFilter.churches =>
                  'No church channels yet. Join a church to see its '
                      'announcements here.',
                _ChatFilter.friends =>
                  'No chats with friends yet. Tap the compose button to '
                      'start one.',
                _ChatFilter.all => 'Nothing here yet.',
              },
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

  /// Narrow the inbox to the selected chip.
  ///
  /// "Churches" is the announcements channel plus the church members group;
  /// "Friends" is a 1:1 chat with someone you are ACTUALLY friends with.
  ///
  /// It used to mean "any 1:1 chat that isn't a group, a church or your
  /// own notes", which listed everyone you had ever exchanged a message
  /// with — including people whose message request you accepted and never
  /// befriended. Now it checks the friendship.
  List<Conversation> _applyFilter(List<Conversation> all, _ChatFilter filter) {
    return switch (filter) {
      _ChatFilter.all => all,
      _ChatFilter.unread => all.where((c) => c.unreadCount > 0).toList(),
      _ChatFilter.groups =>
        all.where((c) => c.isGroup && !c.isChurchGroup).toList(),
      _ChatFilter.churches => all.where((c) => c.isChurchGroup).toList(),
      _ChatFilter.friends =>
        all
            .where(
              (c) =>
                  !c.isGroup &&
                  !c.isChurchGroup &&
                  !c.isSelfChat &&
                  _friendIds.contains(c.otherUserId),
            )
            .toList(),
    };
  }

  /// Quick filter chips above the list. Each carries its own count, so the
  /// row doubles as a summary of what's waiting — the unread badge on the
  /// nav island finally has somewhere to land.
  Widget _buildChatFilterChips(List<Conversation> all) {
    int countFor(_ChatFilter f) {
      if (f == _ChatFilter.all) return 0; // "All" needs no number
      final matching = _applyFilter(all, f);
      // Every chip but Unread counts what's UNREAD in that slice — a bare
      // total ("Groups 12") is noise, "Groups 2" means two want you.
      if (f == _ChatFilter.unread) return matching.length;
      return matching.where((c) => c.unreadCount > 0).length;
    }

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

    // Five chips don't fit a 360dp screen — scroll rather than shrink the
    // labels to unreadable.
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
        children: [
          for (final f in _ChatFilter.values)
            chip(f.label, f, badge: countFor(f)),
        ],
      ),
    );
  }

  // ----- The Active rail ----------------------------------------------
  /// One rail doing two jobs: who has a story, and who is online.
  ///
  /// Stories used to cost a whole top-level tab on a *messaging* screen, and
  /// Home already carries a stories rail. A separate "online now" rail was
  /// the other option, but in a congregation on mobile data it is empty most
  /// of the day, and an empty rail reads as broken. Merged, it always has
  /// something in it: a blue ring means an unseen story, a green dot means
  /// they're online right now.
  ///
  /// Members who chose "hide online" are absent by construction — they never
  /// join the presence roster, so there is no privacy check to forget here.
  Widget _buildActiveRail() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PresenceService.onChange,
      builder: (context, online, _) {
        final seen = _viewedStoryIds.union(FeedService.viewedStoryIdsCached());
        final me = _currentUserId;

        // Story authors, newest first, one entry per person.
        //
        // The viewer's OWN stories used to be dropped here and the "Your
        // story" tile was hard-wired to the composer, so once you posted
        // there was no way in the app to watch it back. They're kept now
        // and handed to the leading tile.
        final byAuthor = <String, List<Story>>{};
        final ownStories = <Story>[];
        for (final s in _stories) {
          if (s.authorId == me) {
            ownStories.add(s);
            continue;
          }
          byAuthor.putIfAbsent(s.authorId, () => []).add(s);
        }

        final entries = <_ActiveEntry>[];
        for (final e in byAuthor.entries) {
          final reel = e.value;
          entries.add(
            _ActiveEntry(
              userId: e.key,
              name: reel.first.authorName,
              photoUrl: reel.first.authorPhotoUrl,
              stories: reel,
              hasUnseenStory: reel.any((s) => !seen.contains(s.id)),
              isOnline: online.contains(e.key),
            ),
          );
        }

        // Anyone online who isn't already in the rail via a story. Only
        // people the viewer actually has a thread with — a rail of
        // strangers is a directory, not an inbox.
        for (final c in _conversations) {
          if (c.isGroup || c.isSelfChat) continue;
          if (c.otherUserId.isEmpty || c.otherUserId == me) continue;
          if (!online.contains(c.otherUserId)) continue;
          if (byAuthor.containsKey(c.otherUserId)) continue;
          entries.add(
            _ActiveEntry(
              userId: c.otherUserId,
              name: c.otherUserName,
              photoUrl: c.otherUserPhotoUrl,
              stories: const [],
              hasUnseenStory: false,
              isOnline: true,
            ),
          );
        }

        // Unseen stories first, then online, then the rest.
        entries.sort((a, b) {
          int rank(_ActiveEntry e) =>
              e.hasUnseenStory ? 0 : (e.isOnline ? 1 : 2);
          return rank(a).compareTo(rank(b));
        });

        // Oldest-first is the order a reel is meant to play in; `_stories`
        // arrives newest-first for the inbox.
        List<Story> playOrder(List<Story> list) => list.reversed.toList();

        // Tapping someone plays their reel and then keeps going through
        // everyone after them who still has something unseen — so you
        // watch through the rail once, like WhatsApp, instead of the
        // viewer closing after every single person.
        List<Story> reelFrom(int index) {
          final reel = <Story>[];
          for (var i = index; i < entries.length; i++) {
            final e = entries[i];
            if (!e.hasStory) continue;
            if (i != index && !e.hasUnseenStory) continue;
            reel.addAll(playOrder(e.stories));
          }
          return reel;
        }

        return _ActiveRail(
          entries: entries,
          viewerName: _viewerName(),
          viewerPhotoUrl: _viewerPhotoUrl(),
          ownStories: playOrder(ownStories),
          onAddStory: _openStoryComposer,
          onOpenStory: _openStoryViewer,
          onOpenStoryAt: (i) => _openStoryViewer(reelFrom(i)),
          onOpenChat: (userId, name) => _startChatWith(userId, name),
        );
      },
    );
  }

  // ----- Requests view (opened from the Chats banner) -----------------
  Widget _buildRequestsView() {
    final list = _messageRequestsDeduped;
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
              lastSenderName: _senderNames[c.lastSenderId],
              memberCount: _groupCounts[c.id],
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

/// The compose sheet behind the FAB.
class _ComposeSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Start something',
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _ComposeOption(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'New chat',
              subtitle: 'Message a friend, or find someone new',
              onTap: () => Navigator.pop(context, 'chat'),
            ),
            _ComposeOption(
              icon: Icons.group_add_rounded,
              title: 'New group',
              subtitle: 'Bring a ministry or study group together',
              onTap: () => Navigator.pop(context, 'group'),
            ),
            _ComposeOption(
              icon: Icons.link_rounded,
              title: 'Join with a link',
              subtitle: 'Paste an invite you were sent',
              onTap: () => Navigator.pop(context, 'join'),
            ),
            _ComposeOption(
              icon: Icons.bookmark_outline,
              title: 'Notes to self',
              subtitle: 'Save verses, links and reminders',
              onTap: () => Navigator.pop(context, 'self'),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

class _ComposeOption extends StatelessWidget {
  const _ComposeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryBlue, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
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
      ),
    );
  }
}

class _SearchSectionLabel extends StatelessWidget {
  const _SearchSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: context.palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// A full-text hit from `searchMessages()`, with the matched term marked in
/// the snippet so you can see *why* it matched.
class _MessageHitTile extends StatelessWidget {
  const _MessageHitTile({
    required this.hit,
    required this.conversation,
    required this.query,
    required this.onTap,
  });

  final MessageSearchHit hit;
  final Conversation? conversation;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final where = conversation?.otherUserName ?? 'Conversation';
    return PressEffect(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(20),
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
                _Avatar(
                  name: where,
                  photoUrl: conversation?.otherUserPhotoUrl,
                  isGroup: conversation?.isGroup ?? false,
                  size: 42,
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
                              where,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            _shortDate(hit.createdAt),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: palette.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      _Highlighted(
                        text: hit.content,
                        query: query,
                        base: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
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

  String _shortDate(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    if (diff == 1) return 'Yest.';
    if (diff < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[local.weekday - 1];
    }
    return '${local.day}/${local.month}';
  }
}

/// Bolds the matched run inside a snippet. Cheap, but it is the difference
/// between "here are 40 messages" and "here is the line you meant".
class _Highlighted extends StatelessWidget {
  const _Highlighted({
    required this.text,
    required this.query,
    required this.base,
  });

  final String text;
  final String query;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    final at = text.toLowerCase().indexOf(query.toLowerCase());
    if (at < 0 || query.isEmpty) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    // Keep a little context before the match so the snippet reads as a
    // sentence rather than starting mid-word.
    final start = at > 24 ? at - 20 : 0;
    final head = start > 0
        ? '…${text.substring(start, at)}'
        : text.substring(0, at);
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: head),
          TextSpan(
            text: text.substring(at, at + query.length),
            style: base.copyWith(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: text.substring(at + query.length)),
        ],
      ),
    );
  }
}

/// One person in the Active rail — they have a story, or they're online, or
/// both.
class _ActiveEntry {
  const _ActiveEntry({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.stories,
    required this.hasUnseenStory,
    required this.isOnline,
  });

  final String userId;
  final String name;
  final String? photoUrl;
  final List<Story> stories;
  final bool hasUnseenStory;
  final bool isOnline;

  bool get hasStory => stories.isNotEmpty;
}

/// The merged stories + presence rail that sits above the inbox.
class _ActiveRail extends StatelessWidget {
  const _ActiveRail({
    required this.entries,
    required this.viewerName,
    required this.viewerPhotoUrl,
    required this.ownStories,
    required this.onAddStory,
    required this.onOpenStory,
    required this.onOpenStoryAt,
    required this.onOpenChat,
  });

  final List<_ActiveEntry> entries;
  final String viewerName;
  final String? viewerPhotoUrl;

  /// The viewer's own live stories, oldest-first. Empty until they post.
  final List<Story> ownStories;

  final VoidCallback onAddStory;
  final void Function(List<Story> reel) onOpenStory;

  /// Play from this rail position onward, continuing through everyone
  /// after it who still has something unseen.
  final void Function(int index) onOpenStoryAt;
  final void Function(String userId, String name) onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: entries.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (context, i) {
            if (i == 0) {
              final hasOwn = ownStories.isNotEmpty;
              return _ActiveAvatar(
                name: hasOwn ? 'Your story' : 'Add story',
                photoUrl: viewerPhotoUrl,
                initialsSource: viewerName,
                // Your own ring lights up while your story is still live,
                // the way it does for everyone else in the rail.
                ring: hasOwn,
                online: false,
                showAddBadge: true,
                // Tap the face to watch yours back, the + badge to post
                // another. Before you've posted anything there is nothing
                // to watch, so the whole tile composes.
                onTap: hasOwn ? () => onOpenStory(ownStories) : onAddStory,
                onAddTap: onAddStory,
              );
            }
            final index = i - 1;
            final e = entries[index];
            return _ActiveAvatar(
              name: e.name,
              photoUrl: e.photoUrl,
              initialsSource: e.name,
              ring: e.hasUnseenStory,
              online: e.isOnline,
              showAddBadge: false,
              // A story is the thing with a deadline, so it wins the tap;
              // without one the face is just a fast way into the chat.
              // A story already seen is still tappable — the grey ring
              // means "watched", not "gone".
              onTap: () => e.hasStory
                  ? onOpenStoryAt(index)
                  : onOpenChat(e.userId, e.name),
            );
          },
        ),
      ),
    );
  }
}

class _ActiveAvatar extends StatelessWidget {
  const _ActiveAvatar({
    required this.name,
    required this.photoUrl,
    required this.initialsSource,
    required this.ring,
    required this.online,
    required this.showAddBadge,
    required this.onTap,
    this.onAddTap,
  });

  final String name;
  final String? photoUrl;
  final String initialsSource;
  final bool ring;
  final bool online;
  final bool showAddBadge;
  final VoidCallback onTap;

  /// Tapping the + badge specifically. When null the badge is decorative
  /// and the whole tile's [onTap] handles it.
  final VoidCallback? onAddTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.93,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ring ? AppColors.primaryGradient : null,
                    border: ring
                        ? null
                        : Border.all(color: palette.divider, width: 1.5),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.scaffoldBg,
                    ),
                    child: _Avatar(
                      name: initialsSource,
                      photoUrl: photoUrl,
                      size: 48,
                    ),
                  ),
                ),
                if (online)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.successGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.scaffoldBg,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                if (showAddBadge)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      // Its own target, so "watch mine" and "post another"
                      // don't fight over one tap.
                      onTap: onAddTap,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.scaffoldBg,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 12,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(
                color: palette.textMuted,
                fontSize: 11,
                fontWeight: ring ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compose button.
///
/// A gradient squircle rather than Material's flat circular FAB — the stock
/// one reads as a system control dropped on the screen, and this is the one
/// button on the inbox that should look deliberate.
class _ComposeFab extends StatelessWidget {
  const _ComposeFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.92,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.38),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.edit_square, color: AppColors.white, size: 24),
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
    this.lastSenderName,
    this.memberCount,
  });

  final Conversation conversation;
  final bool isLastFromMe;

  /// Who spoke last, for group rows. Resolved in one batched lookup by the
  /// screen (see MessagingService.fetchDisplayNames) — null for 1:1 rows.
  final String? lastSenderName;

  /// How many people are in this group, shown next to its name. Null when
  /// unknown or not a group.
  final int? memberCount;
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

  /// A glyph in front of the preview that says what KIND of row this is.
  ///
  /// The whole point of the redesign: five different things were rendering
  /// as avatar + name + preview + time, so a church announcement, a pending
  /// request and your own notes were visually identical. The icon does most
  /// of that work before any text is read.
  ({IconData icon, Color color})? _previewGlyph(BuildContext context) {
    if (conversation.isSelfChat) {
      return (icon: Icons.bookmark_outline, color: context.palette.textMuted);
    }
    if (conversation.isChurchChannel) {
      return (icon: Icons.campaign_outlined, color: AppColors.goldAccent);
    }
    final body = conversation.lastMessage.toLowerCase();
    if (body.startsWith('🎤') || body.contains('voice note')) {
      return (icon: Icons.mic_none, color: AppColors.primaryBlue);
    }
    if (body.startsWith('📷') || body.contains('photo')) {
      return (icon: Icons.image_outlined, color: AppColors.primaryBlue);
    }
    return null;
  }

  /// Drop the leading media emoji once the row is already showing a glyph
  /// for it — otherwise a captioned photo reads "🖼 📷 at the beach".
  String _previewText(String raw) {
    for (final prefix in const ['📷 ', '🎤 ', '🎙️ ']) {
      if (raw.startsWith(prefix)) return raw.substring(prefix.length);
    }
    return raw;
  }

  /// Group rows name the speaker; 1:1 rows never should.
  ///
  /// "Tapiwa: bring the projector" and "bring the projector" are different
  /// messages, and in a 24-person group the second one is unreadable.
  String? _groupSpeakerPrefix() {
    if (!conversation.isGroup || conversation.isChurchChannel) return null;
    if (conversation.lastMessage.isEmpty) return null;
    if (isLastFromMe) return 'You';
    final name = (lastSenderName ?? '').trim();
    if (name.isEmpty) return null;
    return name.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount > 0 && !isLastFromMe;
    // An unsent draft outranks the last message in the preview: it's the
    // thing waiting on YOU, and it's how you find the half-written reply
    // you walked away from. WhatsApp's behaviour, and its colour.
    final draft = MessagingService.readDraft(conversation.id);
    final glyph = _previewGlyph(context);
    final speaker = _groupSpeakerPrefix();
    // Self-chat reads quietly — it is a notepad, not a correspondent, and
    // it sits pinned at the top of every inbox forever.
    final previewStyle = AppTextStyles.bodySmall.copyWith(
      color: conversation.isSelfChat
          ? context.palette.textMuted
          : unread
          ? context.palette.text
          : context.palette.textMuted,
      fontSize: 13,
      fontWeight: unread && !conversation.isSelfChat
          ? FontWeight.w600
          : FontWeight.w400,
    );
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
                          // Church channels carry the gold tick whether or
                          // not the row's "other user" is a verified
                          // account — the channel IS the church speaking.
                          if (conversation.otherUserIsVerified ||
                              conversation.isChurchGroup)
                            const VerifiedTick(size: 15),
                          // Group size, in the name row where it reads as
                          // part of the identity rather than as metadata.
                          if (memberCount != null && conversation.isGroup) ...[
                            const SizedBox(width: 5),
                            Text(
                              '$memberCount',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: context.palette.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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
                      // "typing…" outranks the whole preview line — the
                      // draft, the ticks, the glyph, the last message.
                      // Someone writing to you right now is the most
                      // current thing this row can say, and it is what the
                      // indicator was missing: it existed only INSIDE an
                      // open chat, where you can already see them typing.
                      //
                      // Listens on its own so a ping repaints one preview
                      // line, not the inbox.
                      ValueListenableBuilder<Map<String, String>>(
                        valueListenable: TypingSignal.active,
                        builder: (context, typing, child) {
                          final kind = typing[conversation.id];
                          if (kind == null) return child!;
                          return _TypingPreview(kind: kind);
                        },
                        child: Row(
                        children: [
                          // Tick on the last message, but ONLY when the
                          // viewer sent it (patch_075 surfaces its real
                          // delivered/read state): ✓ sent, ✓✓ delivered,
                          // ✓✓ blue read (blue only in 1:1, like in-chat).
                          // Never on a placeholder ("Say hello") or a reaction
                          // preview — those aren't messages the viewer sent.
                          if (isLastFromMe &&
                              draft == null &&
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
                          // Type glyph — 📢 for a church announcement, a mic
                          // for a voice note, a bookmark for your own notes.
                          if (glyph != null &&
                              draft == null &&
                              !previewCleared) ...[
                            Icon(glyph.icon, size: 13, color: glyph.color),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: draft != null
                                ? RichText(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      style: previewStyle,
                                      children: [
                                        TextSpan(
                                          text: 'Draft: ',
                                          style: previewStyle.copyWith(
                                            color: AppColors.successGreen,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        TextSpan(text: draft),
                                      ],
                                    ),
                                  )
                                : (reactionPreview != null && !previewCleared)
                                ? Text(
                                    _reactionPreviewLabel(reactionPreview!),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: previewStyle,
                                  )
                                : (previewCleared ||
                                      conversation.lastMessage.isEmpty)
                                ? Text(
                                    conversation.isChurchChannel
                                        ? 'Church announcements appear here'
                                        : conversation.isSelfChat
                                        ? 'Notes and links you save yourself'
                                        : 'Say hello',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: previewStyle,
                                  )
                                : RichText(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      style: previewStyle,
                                      children: [
                                        if (speaker != null)
                                          TextSpan(
                                            text: '$speaker: ',
                                            style: previewStyle.copyWith(
                                              color: AppColors.primaryBlue,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        TextSpan(
                                          text: isLastFromMe
                                              ? _selfSystemLabel(
                                                  _previewText(
                                                    conversation.lastMessage,
                                                  ),
                                                )
                                              : _previewText(
                                                  conversation.lastMessage,
                                                ),
                                        ),
                                      ],
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

/// "typing…" / "recording audio…" in place of an inbox row's preview.
///
/// Brand blue and italic, matching the same line in the chat header, so
/// the two surfaces read as one behaviour rather than two features.
class _TypingPreview extends StatelessWidget {
  const _TypingPreview({required this.kind});

  /// 'typing' or 'recording' — the same two kinds the chat header shows.
  final String kind;

  @override
  Widget build(BuildContext context) {
    final recording = kind == 'recording';
    return Row(
      children: [
        Icon(
          recording ? Icons.mic : Icons.more_horiz,
          size: 14,
          color: AppColors.primaryBlue,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            recording ? 'recording audio…' : 'typing…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.primaryBlue,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
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
    this.size = 50,
  });
  final String name;
  final String? photoUrl;
  final bool isSelfChat;
  final bool isGroup;
  final double size;

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
      width: size,
      height: size,
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
          ? Icon(Icons.bookmark, color: AppColors.white, size: size * 0.44)
          : (isGroup && !hasPhoto)
          ? Icon(Icons.groups, color: AppColors.white, size: size * 0.52)
          : hasPhoto
          ? CachedImage(
              photoUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              // Centred — see the note on the chat header avatar. A bare
              // Text under the image box's tight constraints paints at
              // the top-left, not the middle of the circle.
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  initials,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
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

/// Friend/message requests, shown with faces at the top of the inbox.
///
/// A request is the one thing in an inbox that expires *socially* — leave it
/// long enough and answering it is worse than never seeing it. It used to be
/// a count behind a tab you had to know existed. Now it names the person,
/// shows their face, and offers Accept inline for the single-request case,
/// which is the overwhelmingly common one.
class _RequestsBanner extends StatelessWidget {
  const _RequestsBanner({
    required this.requests,
    required this.messageRequests,
    required this.onTap,
    required this.onAccept,
  });

  final List<PendingFriendRequest> requests;
  final List<Conversation> messageRequests;
  final VoidCallback onTap;
  final void Function(PendingFriendRequest) onAccept;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = requests.length + messageRequests.length;
    final faces = <({String name, String? photo})>[
      for (final r in requests.take(3))
        (name: r.requesterName, photo: r.requesterPhotoUrl),
      for (final c in messageRequests.take(3))
        (name: c.otherUserName, photo: c.otherUserPhotoUrl),
    ].take(3).toList();

    final lead = requests.isNotEmpty
        ? requests.first.requesterName.split(' ').first
        : messageRequests.first.otherUserName.split(' ').first;
    final title = total == 1
        ? '$lead wants to connect'
        : '$lead and ${total - 1} other${total - 1 == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: PressEffect(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32.0 + (faces.length - 1) * 20,
                    height: 40,
                    child: Stack(
                      children: [
                        for (var i = 0; i < faces.length; i++)
                          Positioned(
                            left: i * 20.0,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: palette.scaffoldBg,
                                  width: 2,
                                ),
                              ),
                              child: _Avatar(
                                name: faces[i].name,
                                photoUrl: faces[i].photo,
                                size: 36,
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
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          total == 1
                              ? 'Tap to review'
                              : '$total requests · tap to review',
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
                  const SizedBox(width: 8),
                  // One request is the common case, and it deserves a
                  // one-tap answer rather than a trip through another screen.
                  if (total == 1 && requests.isNotEmpty)
                    _ActionButton(
                      label: 'Accept',
                      filled: true,
                      onTap: () => onAccept(requests.first),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$total',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                ],
              ),
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
