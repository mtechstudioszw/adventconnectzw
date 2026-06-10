import 'dart:async';

import 'package:flutter/material.dart';
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

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, this.initialTab});

  /// When set to 'requests' the screen opens straight on the Requests
  /// tab. Used by deep links from friend-request notification taps.
  final String? initialTab;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

enum _ConversationsTab { chats, groups, status, archived }

class _ConversationsScreenState extends State<ConversationsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Conversation> _conversations = [];
  Map<String, ConversationState> _convStates = const {};
  List<Story> _stories = const [];
  Set<String> _viewedStoryIds = const {};
  List<PendingFriendRequest> _friendRequests = const [];
  bool _loading = true;
  String? _error;
  _ConversationsTab _tab = _ConversationsTab.chats;
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
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _bootstrap();
    _startActivityWatcher();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _activitySub?.cancel();
    _entrance.dispose();
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
              .where((r) =>
                  r['sender_id']?.toString() != me &&
                  r['delivered_at'] == null)
              .map((r) => r['id'].toString())
              .where((id) => id.isNotEmpty)
              .toList();
          if (undelivered.isNotEmpty) {
            unawaited(MessagingService.markMessagesDelivered(undelivered));
          }
        }
        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(
          const Duration(milliseconds: 600),
          () {
            if (mounted) _refreshFromRealtime();
          },
        );
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
      ]);
      if (!mounted) return;
      setState(() {
        _conversations = results[0] as List<Conversation>;
        _stories = results[1] as List<Story>;
        _friendRequests = results[2] as List<PendingFriendRequest>;
        _convStates = results[3] as Map<String, ConversationState>;
        _viewedStoryIds = results[4] as Set<String>;
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
          final hasRequests = _friendRequests.isNotEmpty ||
              _conversations.any(
                (c) => c.isIncomingRequestFor(_currentUserId),
              );
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

  Future<void> _openStoryViewer(List<Story> reel) {
    // The rail now hands us a play-order (oldest-first) reel, including
    // auto-advance across unviewed authors — show it as-is.
    return StoryViewer.show(context, reel);
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

  /// Pinned conversations float to the top, preserving their existing
  /// (recency) order within each group.
  List<Conversation> _pinnedFirst(List<Conversation> list) {
    final pinned = list.where(_isPinned).toList();
    final rest = list.where((c) => !_isPinned(c)).toList();
    return [...pinned, ...rest];
  }

  List<Conversation> get _chats {
    // 1:1 chats + church groups (church groups are pinned to the very
    // top). User-created groups live in the Groups tab, not here.
    final filtered = _conversations
        .where((c) =>
            (!c.isGroup || c.isChurchGroup) &&
            !c.isIncomingRequestFor(_currentUserId) &&
            !_isArchived(c))
        .toList();
    final selfChats = filtered.where((c) => c.isSelfChat).toList();
    final others = _pinnedFirst(
        filtered.where((c) => !c.isSelfChat).toList());
    return [...selfChats, ...others];
  }

  /// User-created group chats (church groups are excluded — they sit at
  /// the top of the Chats tab). Archived ones move to Archived.
  List<Conversation> get _groups => _pinnedFirst(_conversations
      .where((c) => c.isGroup && !c.isChurchGroup && !_isArchived(c))
      .toList());

  /// Everything (1:1 or group) the viewer has archived.
  List<Conversation> get _archived => _conversations
      .where((c) =>
          !c.isIncomingRequestFor(_currentUserId) && _isArchived(c))
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
            .map((x) =>
                x.id == c.id ? x.copyWith(requestStatus: 'accepted') : x)
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
    await context.pushNamed(
      'chat',
      pathParameters: {'id': c.id},
      extra: c,
    );
    if (mounted) _bootstrap();
  }

  Future<void> _decline(Conversation c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Decline message request?',
          style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
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
        _conversations =
            _conversations.where((x) => x.id != c.id).toList();
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
                style:
                    AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
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
                style:
                    AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
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
                style:
                    AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
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
        onPressed: _openNewChatSheet,
        child: const Icon(Icons.edit_square),
      ),
      body: Column(
        children: [
          _buildHero(),
          _buildTabBar(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryBlue,
              onRefresh: _bootstrap,
              child: AnimatedBuilder(
                animation: _entrance,
                builder: (context, child) => Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slide.value),
                    child: child,
                  ),
                ),
                child: _buildTabPager(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Slim chat app bar — title + search + overflow (self-chat, privacy).
  /// Replaces the old two-line "ADVENT CHAT / Your chats" hero so the
  /// list starts ~90px higher.
  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 10),
          child: Row(
            children: [
              _CircleIconButton(
                icon: Icons.arrow_back,
                onTap: () => context.canPop()
                    ? context.pop()
                    : context.goNamed('home'),
              ),
              const SizedBox(width: 6),
              Text(
                'Advent Chat',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const Spacer(),
              _CircleIconButton(
                icon: Icons.search,
                onTap: () => context.pushNamed('search'),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.white),
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

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
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
              label: 'Groups',
              selected: _tab == _ConversationsTab.groups,
              onTap: () {
                if (_showRequests) setState(() => _showRequests = false);
                _selectTab(_ConversationsTab.groups);
              },
            ),
            _TabPill(
              label: 'Status',
              selected: _tab == _ConversationsTab.status,
              onTap: () {
                if (_showRequests) setState(() => _showRequests = false);
                _selectTab(_ConversationsTab.status);
              },
            ),
            _TabPill(
              label: 'Archived',
              selected: _tab == _ConversationsTab.archived,
              onTap: () {
                if (_showRequests) setState(() => _showRequests = false);
                _selectTab(_ConversationsTab.archived);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPager() {
    if (_loading && _conversations.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null && _conversations.isEmpty) {
      return _buildErrorState();
    }
    if (_showRequests) return _buildRequestsView();
    // Swipe between Chats / Groups / Status / Archived with a smooth
    // animated transition (order matches _ConversationsTab).
    return PageView(
      controller: _pageController,
      onPageChanged: (i) =>
          setState(() => _tab = _ConversationsTab.values[i]),
      children: [
        _buildChatsTab(),
        _buildGroupsTab(),
        _buildStatusTab(),
        _buildArchivedTab(),
      ],
    );
  }

  Widget _buildArchivedTab() {
    final archived = _archived;
    if (archived.isEmpty) {
      return _buildEmptyState(
        title: 'No archived chats',
        body: 'Long-press a chat and tap Archive to keep it here, out of '
            'your main list.',
      );
    }
    return _conversationListView(archived);
  }

  // ----- Chats tab: requests banner + 1:1 conversation list -----------
  Widget _buildChatsTab() {
    final list = _chats;
    final requestCount = _requests.length + _friendRequests.length;
    if (list.isEmpty && requestCount == 0) {
      return _buildEmptyState(
        title: 'No conversations yet',
        body:
            'Tap the pencil button to start a new chat, or reach out from a '
            'member directory or church page.',
      );
    }
    return _conversationListView(
      list,
      banner: requestCount == 0
          ? null
          : _RequestsBanner(
              count: requestCount,
              onTap: () => setState(() => _showRequests = true),
            ),
    );
  }

  // ----- Groups tab ---------------------------------------------------
  Widget _buildGroupsTab() {
    final list = _groups;
    if (list.isEmpty) {
      return _buildEmptyState(
        title: 'No groups yet',
        body: 'Create a group from the pencil button to chat with several '
            'people at once.',
      );
    }
    return _conversationListView(list);
  }

  // ----- Status tab: the stories rail (moved off the chat list) -------
  Widget _buildStatusTab() {
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
          viewedStoryIds: _viewedStoryIds,
        ),
        if (_stories.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Text(
              'No status updates yet. Tap the + to share one — it disappears '
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
    final list = _requests;
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
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
            ),
          ),
        ),
        if (!hasFriendRequests && !hasMessageRequests)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: _buildEmptyState(
              title: 'No requests',
              body: 'Friend requests and messages from people you haven\'t '
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
          _RequestsSectionHeader(
            label: 'Message requests',
            count: list.length,
          ),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: list.length + (banner == null ? 0 : 1),
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (banner != null && i == 0) return banner;
            final c = list[i - (banner == null ? 0 : 1)];
            return _ConversationTile(
              key: ValueKey(c.id),
              conversation: c,
              isLastFromMe: c.lastSenderId == _currentUserId,
              pinned: _isPinned(c),
              muted: _isMuted(c),
              onTap: () => _openChat(c),
              onLongPress: () => _openConversationActions(c),
            );
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
                leading: const Icon(Icons.mark_email_read_outlined,
                    color: AppColors.primaryBlue),
                title: const Text('Mark as read'),
                onTap: () => Navigator.of(sheetCtx).pop('read'),
              ),
              // Church groups are anchored — no pin/archive/delete; only
              // mute is allowed.
              if (!c.isChurchGroup)
                ListTile(
                  leading: Transform.rotate(
                    angle: 0.785398,
                    child: const Icon(Icons.push_pin_outlined,
                        color: AppColors.primaryBlue),
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
              if (!c.isChurchGroup)
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: AppColors.red),
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
          await MessagingService.declineRequest(c.id);
          if (!mounted) return;
          await _bootstrap();
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.red,
              content: Text(
                'Could not delete. Try again.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
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
                  child: Icon(
                    _tab == _ConversationsTab.groups
                        ? Icons.groups_outlined
                        : Icons.forum_outlined,
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
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: selected ? AppColors.primaryGradient : null,
              color: selected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(
                color: selected ? AppColors.white : context.palette.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
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
  });

  final Conversation conversation;
  final bool isLastFromMe;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool pinned;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount > 0 && !isLastFromMe;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.palette.card,
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
              Stack(
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
                        if (conversation.isBusiness) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue
                                  .withValues(alpha: 0.10),
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
                        // Inbox tick was always showing done_all for any
                        // outgoing last message, which made it look
                        // "delivered" even when the recipient was offline
                        // and the chat screen still showed a single grey
                        // tick. Hidden here intentionally — the in-chat
                        // tick remains accurate. Will reinstate once we
                        // surface per-conversation last-message status on
                        // the conversations row.
                        Expanded(
                          child: Text(
                            conversation.lastMessage.isEmpty
                                ? 'Say hello'
                                : conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: unread
                                  ? context.palette.text
                                  : context.palette.textMuted,
                              fontSize: 13,
                              fontWeight:
                                  unread ? FontWeight.w600 : FontWeight.w400,
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
    return Material(
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
    return Material(
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
                : Border.all(
                    color: context.palette.divider,
                  ),
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
    return Material(
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.10),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 11),
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
                            color: AppColors.primaryBlue
                                .withValues(alpha: 0.30),
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
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    this.photoUrl,
    this.isSelfChat = false,
  });
  final String name;
  final String? photoUrl;
  final bool isSelfChat;

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
          ? const Icon(
              Icons.bookmark,
              color: AppColors.white,
              size: 22,
            )
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
    return Material(
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
              const Icon(Icons.person_add_alt_1,
                  color: AppColors.primaryBlue, size: 20),
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
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.10)),
          ),
          child: Icon(icon, color: AppColors.white, size: 18),
        ),
      ),
    );
  }
}

