import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/friendship_model.dart';
import '../../models/message_model.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/gallery_service.dart';
import '../../services/group_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/messaging_service.dart';
import '../../services/presence_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_player_service.dart';
import '../../widgets/full_image_viewer.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/church_group_avatar.dart';
import '../../widgets/home/report_sheet.dart';
import '../../widgets/chat_contact_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.initialConversation,
  });

  final String conversationId;
  final Conversation? initialConversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription<List<Message>>? _stream;

  // --- Unified message pipeline (single source of truth) ------------
  // _serverMessages: the authoritative list from Supabase (realtime
  //   stream + initial fetch). Always what the backend says exists.
  // _pending: optimistic messages we've shown locally but the server
  //   hasn't echoed back yet. Pruned as soon as a matching server row
  //   arrives.
  // The rendered list (_messages getter) is ALWAYS the union of the
  // two, sorted strictly by createdAt — so ordering is deterministic
  // and nothing reorders after the server confirms.
  List<Message> _serverMessages = [];
  final List<Message> _pending = [];
  // Optimistic ids the send "completed" for locally but the server never
  // accepted (recipient blocked the sender — silent block). They show a
  // single grey ✓ instead of the pending clock (WhatsApp parity).
  final Set<String> _localSentIds = <String>{};
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// The single, strictly-chronological list the UI renders. Server
  /// rows + still-unconfirmed optimistic rows, merged and sorted by
  /// createdAt (ties broken by id so equal-timestamp rows are stable).
  ///
  /// Dedupe by id at RENDER time, not write time. This closes the
  /// race window where:
  ///   1. Optimistic added with tempId 'pending-xxx'
  ///   2. Realtime fires the canonical row → _serverMessages updated
  ///   3. sendMessage hasn't returned yet → _pending still has tempId
  ///   4. Both render → DUPLICATE (the Notes-to-Self bug)
  ///   5. sendMessage returns → tempId swapped for canonical id
  ///   6. _pending now has the canonical id alongside _serverMessages
  ///      → STILL duplicate until the next realtime tick re-dedupes
  ///
  /// Skipping any _pending row whose id is already in _serverMessages
  /// at getter time makes the duplicate window vanish — same data,
  /// rendered once, regardless of the order events arrive.
  List<Message> get _messages {
    final serverIds = _serverMessages.map((m) => m.id).toSet();
    final merged = <Message>[..._serverMessages];
    for (final p in _pending) {
      if (!serverIds.contains(p.id)) merged.add(p);
    }
    merged.sort((a, b) {
      final c = a.createdAt.compareTo(b.createdAt);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });
    return merged;
  }

  /// Replace the server list and drop any optimistic rows the server
  /// has now echoed back. Matching is BY ID — when _send/_send-voice
  /// captures sendMessage's return value, it swaps the pending entry's
  /// tempId for the canonical server id (via _replacePendingWithCanonical
  /// below), so this dedupe is precise: no content-based false matches
  /// (which broke when a blocked send had the same body as an earlier
  /// real message), and no flicker (the canonical replaces the pending
  /// in-place, never both visible).
  void _applyServerMessages(List<Message> list) {
    _serverMessages = list;
    final serverIds = list.map((m) => m.id).toSet();
    // Server-echoed client_ids — drop any optimistic row the server now
    // has, whether matched by id (online send) or client_id (offline
    // outbox flush, where the temp id never became canonical). This stops
    // the "offline message shows twice after reconnect" duplicate.
    final serverClientIds = list
        .map((m) => m.clientId)
        .whereType<String>()
        .toSet();
    _pending.removeWhere((p) =>
        serverIds.contains(p.id) ||
        (p.clientId != null && serverClientIds.contains(p.clientId)));
  }

  /// Called after sendMessage returns the canonical row. Swaps the
  /// optimistic tempId entry in _pending for the canonical message so
  /// the next stream tick can dedupe by id and so the bubble shows
  /// the real server timestamp/status without re-rendering.
  void _replacePendingWithCanonical(String tempId, Message canonical) {
    for (var i = 0; i < _pending.length; i++) {
      if (_pending[i].id == tempId) {
        _pending[i] = canonical;
        return;
      }
    }
  }

  /// Long-press menu on a message bubble. Copy is always available;
  /// Delete only shows for messages the current user sent (RLS rejects
  /// deletes on incoming rows anyway, but hiding the menu item makes
  /// the affordance honest).
  void _enterSelect(Message m) {
    setState(() {
      _selectMode = true;
      _selectedMsgIds.add(m.id);
    });
  }

  void _toggleSelect(Message m) {
    setState(() {
      if (_selectedMsgIds.contains(m.id)) {
        _selectedMsgIds.remove(m.id);
      } else {
        _selectedMsgIds.add(m.id);
      }
      if (_selectedMsgIds.isEmpty) _selectMode = false;
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selectedMsgIds.clear();
    });
  }

  /// Delete the selected messages. Own messages become "deleted for
  /// everyone" tombstones; messages from others are skipped (can't delete
  /// someone else's for everyone).
  Future<void> _deleteSelected() async {
    if (!_ensureOnline('delete messages')) return;
    final me = AuthService.currentUser?.id;
    final mine = _messages
        .where((m) => _selectedMsgIds.contains(m.id) && m.senderId == me)
        .toList();
    final skipped = _selectedMsgIds.length - mine.length;
    setState(() {
      _serverMessages = _serverMessages
          .map((x) => mine.any((m) => m.id == x.id)
              ? x.copyWith(isDeleted: true, content: '')
              : x)
          .toList();
    });
    _exitSelect();
    for (final m in mine) {
      try {
        await MessagingService.softDeleteMessage(m.id);
      } catch (_) {}
    }
    if (mounted && skipped > 0) {
      _toast("You can only delete your own messages for everyone.");
    }
  }

  Future<void> _forwardSelected() async {
    final selected = _messages
        .where((m) => _selectedMsgIds.contains(m.id) && !m.isDeleted)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (selected.isEmpty) return;
    final textMsgs =
        selected.where((m) => m.messageType == 'text').toList();
    final mediaMsgs =
        selected.where((m) => m.messageType != 'text').toList();
    // WhatsApp parity: can't mix text + photos/audio into one forward.
    if (textMsgs.isNotEmpty && mediaMsgs.isNotEmpty) {
      _toast("Can't forward text, photos and audio together — "
          'forward text only, then photos only.');
      return;
    }
    final target = await _pickForwardTarget();
    if (!mounted || target == null) return;
    _exitSelect();
    try {
      if (mediaMsgs.isEmpty) {
        // All text → compile into ONE message with timestamps + sender.
        final compiled = _compileForwardedText(textMsgs);
        await MessagingService.sendMessage(
          conversationId: target,
          content: compiled,
          forwarded: true,
        );
      } else {
        // All media → forward each item to the chosen chat.
        for (final m in mediaMsgs) {
          await MessagingService.forwardMessage(
            targetConversationId: target,
            original: m,
          );
        }
      }
      if (mounted) _toast('Forwarded.');
    } catch (_) {
      if (mounted) _toast('Could not forward.');
    }
  }

  /// Compile several text messages into one forwarded block, WhatsApp-style:
  ///   [10:30] You: first message
  ///   [10:31] Michael: second message
  String _compileForwardedText(List<Message> msgs) {
    final me = AuthService.currentUser?.id;
    final buf = StringBuffer();
    for (final m in msgs) {
      final who = m.senderId == me ? 'You' : m.senderName;
      final t = m.createdAt.toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      buf.writeln('[$hh:$mm] $who: ${m.content}');
    }
    return buf.toString().trimRight();
  }

  Future<void> _showMessageActions(Message m, bool isMine) async {
    HapticFeedback.selectionClick();
    // A "deleted" tombstone: the recipient can't act on it at all; the
    // sender can only remove it from the thread.
    if (m.isDeleted) {
      if (!isMine) return;
      final remove = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: context.palette.sheet,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: Text('Delete',
                  style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.red, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ),
        ),
      );
      if (remove == true) {
        setState(() {
          _serverMessages.removeWhere((x) => x.id == m.id);
          _pending.removeWhere((x) => x.id == m.id);
        });
        try {
          await MessagingService.deleteMessage(m.id);
        } catch (_) {
          if (mounted) _toast('Could not delete. Try again.');
        }
      }
      return;
    }
    final isImage =
        m.messageType == 'image' && (m.mediaUrl ?? '').isNotEmpty;
    final hasText = m.content.trim().isNotEmpty &&
        m.messageType != 'voice' &&
        !isImage;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: ctx.palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Quick-reaction row.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final e in _reactionEmojis)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, 'react:$e'),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
              const Divider(height: 14),
              ListTile(
                leading: const Icon(Icons.reply, color: AppColors.primaryBlue),
                title: Text('Reply',
                    style: AppTextStyles.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.shortcut, color: AppColors.primaryBlue),
                title: Text('Forward',
                    style: AppTextStyles.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, 'forward'),
              ),
              if (hasText)
                ListTile(
                  leading: const Icon(Icons.copy_outlined,
                      color: AppColors.primaryBlue),
                  title: Text('Copy',
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'copy'),
                ),
              ListTile(
                leading: Icon(
                  _starredIds.contains(m.id) ? Icons.star : Icons.star_border,
                  color: AppColors.goldAccent,
                ),
                title: Text(
                  _starredIds.contains(m.id) ? 'Unstar' : 'Star',
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(ctx, 'star'),
              ),
              if (isImage)
                ListTile(
                  leading: const Icon(Icons.download_outlined,
                      color: AppColors.primaryBlue),
                  title: Text('Save to gallery',
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'save'),
                ),
              // Edit only before the other person has read it (WhatsApp).
              if (isMine && hasText && !m.read)
                ListTile(
                  leading: const Icon(Icons.edit_outlined,
                      color: AppColors.primaryBlue),
                  title: Text('Edit',
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              ListTile(
                leading: const Icon(Icons.checklist_rtl,
                    color: AppColors.primaryBlue),
                title: Text('Select',
                    style: AppTextStyles.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, 'select'),
              ),
              if (!isMine)
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: AppColors.red),
                  title: Text('Report',
                      style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.red, fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'report'),
                ),
              if (isMine)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: AppColors.red),
                  title: Text('Delete for everyone',
                      style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.red,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    "Both of you will see \"This message was deleted\".",
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ctx.palette.textMuted,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action.startsWith('react:')) {
      await _react(m, action.substring(6));
      return;
    }
    switch (action) {
      case 'reply':
        _startReply(m);
      case 'select':
        _enterSelect(m);
      case 'star':
        await _toggleStar(m);
      case 'edit':
        _startEdit(m);
      case 'save':
        await _saveImageToGallery(m);
      case 'forward':
        await _forwardMessage(m);
      case 'report':
        await showReportSheet(
          context,
          contentType: 'message',
          contentId: m.id,
          contentLabel: 'this message',
        );
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.content));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.darkNavy,
            content: Text(
              'Message copied.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      case 'delete':
        if (!_ensureOnline('delete messages')) return;
        // Soft delete -> "This message was deleted" tombstone on BOTH
        // sides (optimistically flip locally; the realtime UPDATE echoes
        // it to the other party).
        setState(() {
          _serverMessages = _serverMessages
              .map((x) =>
                  x.id == m.id ? x.copyWith(isDeleted: true, content: '') : x)
              .toList();
          _pending.removeWhere((x) => x.id == m.id);
        });
        try {
          await MessagingService.softDeleteMessage(m.id);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.red,
              content: Text(
                'Could not delete. Please try again.',
                style:
                    AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
              ),
            ),
          );
        }
    }
  }

  /// Pick a UTC timestamp for an optimistic bubble that's guaranteed
  /// to sort AFTER everything currently on screen. Stops voice notes
  /// and rapid sends from briefly rendering at the top while the
  /// server timestamp catches up (which the user reported as
  /// "voice goes to top, then jumps to the right position").
  DateTime _optimisticTimestamp() {
    final now = DateTime.now().toUtc();
    DateTime? latest;
    for (final m in _serverMessages) {
      final t = m.createdAt.toUtc();
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    for (final m in _pending) {
      final t = m.createdAt.toUtc();
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    if (latest == null || now.isAfter(latest)) return now;
    return latest.add(const Duration(milliseconds: 1));
  }

  // Resolved conversation — starts as widget.initialConversation (may
  // be null when arriving via a notification tap with only the id),
  // gets back-filled from MessagingService.fetchConversation so the
  // header shows the real name + photo instead of "Conversation".
  Conversation? _conversation;

  // Typing indicator state.
  RealtimeChannel? _typingChannel;
  Timer? _typingExpiry;
  Timer? _typingThrottle;
  bool _otherTyping = false;
  DateTime _lastTypingBroadcast =
      DateTime.fromMillisecondsSinceEpoch(0);

  // Presence (other-user online / last-seen) state.
  DateTime? _otherLastSeen;
  Timer? _lastSeenRefreshTimer;
  void Function()? _presenceListener;

  // Block state — surfaced in the overflow menu (Block / Unblock).
  bool _isBlocked = false;

  // Friendship state — drives the "not friends yet" banner above the
  // message list. Null until the first fetch resolves; null after
  // resolution means no friendship row exists between the two users
  // (i.e. they're strangers). _friendshipBusy guards the in-banner
  // Accept / Add-friend / Cancel buttons from double-fires.
  Friendship? _friendship;
  bool _friendshipResolved = false;
  bool _friendshipBusy = false;

  // Voice-note recording state. We use a single AudioRecorder per
  // chat screen and tear it down in dispose().
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? _activeRecordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;
  // Max voice-note length (5 min) — auto-sends at the cap.
  static const int _maxRecordingSeconds = 300;
  bool _hasText = false;

  // Group chats: member roster for sender labels + admin badges.
  List<GroupMember> _groupMembers = const [];
  final Map<String, GroupMember> _memberById = {};
  bool get _isGroup => _conversation?.isGroup ?? false;
  bool get _isChurchGroup => _conversation?.isChurchGroup ?? false;
  bool get _isChurchChannel => _conversation?.isChurchChannel ?? false;
  // For a church announcement channel: whether THIS viewer may post
  // (verified church admin / super admin). Members chat is always open.
  bool _channelCanPost = false;

  // Phase 4 message actions.
  Message? _replyTo; // composing a reply to this message
  Message? _editing; // editing this message instead of sending new
  Set<String> _starredIds = <String>{};
  Map<String, Map<String, int>> _reactions = const {};
  // Reply-jump highlight: the message id currently flashing + its timer.
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  // Multi-select mode (delete/forward several messages at once).
  bool _selectMode = false;
  final Set<String> _selectedMsgIds = <String>{};
  // True when this is a group the viewer has left / been removed from —
  // the composer is replaced with a locked banner.
  bool _notAMember = false;
  static const List<String> _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  // #17: product preview shown above the composer when the chat was
  // opened from a marketplace product. Dismissible; cleared once the
  // first message is sent.
  String? _productPreviewId;
  String? _productPreviewImage;
  String? _productPreviewTitle;
  String? _productPreviewPrice;

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
    );
    _conversation = widget.initialConversation;
    // #17: consume the product-launch handoff — prefill the composer
    // with an editable draft and show the product preview chip.
    if (ChatLaunchIntent.draft != null || ChatLaunchIntent.hasProduct) {
      final draft = ChatLaunchIntent.draft ?? '';
      if (draft.isNotEmpty) {
        _inputController.text = draft;
        _hasText = true;
      }
      _productPreviewId = ChatLaunchIntent.productId;
      _productPreviewImage = ChatLaunchIntent.productImageUrl;
      _productPreviewTitle = ChatLaunchIntent.productTitle;
      _productPreviewPrice = ChatLaunchIntent.productPrice;
      ChatLaunchIntent.clear();
    }
    _bootstrap();
    _resolveConversation();
    // Continuous voice playback — when one note finishes, the shared
    // player rolls on to the next voice note in this thread.
    VoicePlayerService.instance.nextResolver = _voiceQueueResolver;
    // Tell the global mini-bar this chat is on screen, so it hides while
    // we're here (the bubble already shows playback) and reappears after
    // we leave with a note still playing.
    VoicePlayerService.openChatId.value = widget.conversationId;
  }

  /// Resolves the next voice note after [currentId] in this thread for
  /// the shared player's continuous-play hand-off.
  VoiceNote? _voiceQueueResolver(String currentId) {
    final msgs = _messages;
    final idx = msgs.indexWhere((m) => m.id == currentId);
    if (idx < 0) return null;
    for (var i = idx + 1; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.messageType == 'voice' && (m.mediaUrl ?? '').isNotEmpty) {
        return VoiceNote(
          messageId: m.id,
          storagePath: m.mediaUrl!,
          durationSeconds: m.mediaDurationSeconds,
        );
      }
    }
    return null;
  }

  /// Notification-tap → chat: we only have the id, so the header
  /// would otherwise render "Conversation" with an initials avatar.
  /// Fetch the row so name + photo + participant id come through, and
  /// THEN wire presence (which needs the other-user id).
  Future<void> _resolveConversation() async {
    if (_conversation == null) {
      final fetched =
          await MessagingService.fetchConversation(widget.conversationId);
      if (!mounted) return;
      if (fetched != null) {
        setState(() => _conversation = fetched);
      }
    }
    _wirePresence();
    _maybeLoadGroupMembers();
  }

  Future<void> _loadReactionsAndStars() async {
    final results = await Future.wait([
      MessagingService.fetchReactions(widget.conversationId),
      MessagingService.fetchStarredIds(widget.conversationId),
    ]);
    if (!mounted) return;
    setState(() {
      _reactions = results[0] as Map<String, Map<String, int>>;
      _starredIds = results[1] as Set<String>;
    });
  }

  void _startReply(Message m) {
    setState(() {
      _replyTo = m;
      _editing = null;
    });
  }

  void _startEdit(Message m) {
    setState(() {
      _editing = m;
      _replyTo = null;
      _inputController.text = m.content;
      _hasText = m.content.trim().isNotEmpty;
    });
  }

  void _cancelComposeExtras() {
    setState(() {
      _replyTo = null;
      if (_editing != null) {
        _editing = null;
        _inputController.clear();
        _hasText = false;
      }
    });
  }

  /// Guard server-only actions (react/forward/star/edit) behind a
  /// connectivity check so they tell the user instead of failing silently.
  bool _ensureOnline(String action) {
    if (ConnectivityService.isOnline) return true;
    _toast("You're offline — can't $action right now. "
        'Try again when you reconnect.');
    return false;
  }

  Future<void> _toggleStar(Message m) async {
    if (!_ensureOnline('star messages')) return;
    final starred = _starredIds.contains(m.id);
    setState(() {
      if (starred) {
        _starredIds.remove(m.id);
      } else {
        _starredIds.add(m.id);
      }
    });
    await MessagingService.toggleStar(m.id, starred: starred);
  }

  Future<void> _react(Message m, String emoji) async {
    if (!_ensureOnline('react')) return;
    try {
      await MessagingService.toggleReaction(m.id, emoji);
      _loadReactionsAndStars();
    } catch (_) {
      if (mounted) _toast('Could not add your reaction. Try again.');
    }
  }

  /// Forward a (text) message: pick a destination chat, then re-send the
  /// content with the "Forwarded" flag.
  /// Shared "Forward to…" chat picker. Returns the chosen conversation id.
  Future<String?> _pickForwardTarget() async {
    if (!_ensureOnline('forward messages')) return null;
    final convos = await MessagingService.fetchConversations();
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
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
              padding: const EdgeInsets.all(16),
              child: Text(
                'Forward to…',
                style: AppTextStyles.titleMedium
                    .copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: convos.length,
                itemBuilder: (context, i) {
                  final c = convos[i];
                  return ListTile(
                    leading: _Avatar(
                      name: c.otherUserName,
                      size: 40,
                      photoUrl: c.otherUserPhotoUrl,
                    ),
                    title: Text(c.otherUserName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, c.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _forwardMessage(Message m) async {
    final targetId = await _pickForwardTarget();
    if (!mounted || targetId == null) return;
    try {
      await MessagingService.forwardMessage(
        targetConversationId: targetId,
        original: m,
      );
      if (!mounted) return;
      _toast('Forwarded.');
    } catch (_) {
      if (mounted) _toast('Could not forward.');
    }
  }

  Future<void> _saveImageToGallery(Message m) async {
    final media = m.mediaUrl ?? '';
    if (media.isEmpty) return;
    try {
      // Remote images live in the private bucket — resolve a signed URL.
      final url = media.startsWith('/')
          ? media
          : await MessagingService.signedChatMediaUrl(media);
      final ok = await GalleryService.saveImageFromUrl(url);
      if (!mounted) return;
      _toast(ok ? 'Saved to gallery.' : 'Could not save the image.');
    } catch (_) {
      if (mounted) _toast('Could not save the image.');
    }
  }

  /// Jump to the original message a reply quotes (if it's loaded).
  void _scrollToMessage(String messageId) {
    final idx = _messages.indexWhere((x) => x.id == messageId);
    if (idx < 0 || !_scrollController.hasClients) return;
    // Approximate offset; good enough to bring it into view.
    final target = (idx / _messages.length) *
        _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    // Flash the target so the user sees which message the reply points to.
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _maybeLoadGroupMembers() async {
    if (!_isGroup) return;
    // Church groups use IMPLICIT membership (profiles.church_id match) —
    // they have no conversation_members rows, so skip the not-a-member
    // lockout. For an announcement channel, gate the composer on posting
    // permission (verified church admin / super admin).
    if (_isChurchGroup) {
      if (_isChurchChannel) {
        final canPost = await MessagingService.canPostToChurchChannel(
            widget.conversationId);
        if (mounted) setState(() => _channelCanPost = canPost);
      }
      // Resolve church member names so message senders show their real
      // name instead of "Member" (church groups have implicit membership
      // so there are no conversation_members rows to read).
      try {
        final members =
            await GroupService.fetchChurchMembers(widget.conversationId);
        if (mounted) {
          setState(() {
            _groupMembers = members;
            _memberById
              ..clear()
              ..addEntries(members.map((m) => MapEntry(m.userId, m)));
          });
        }
      } catch (_) {}
      return;
    }
    try {
      final members = await GroupService.fetchMembers(widget.conversationId);
      if (!mounted) return;
      final myId = AuthService.currentUser?.id;
      setState(() {
        _groupMembers = members;
        _memberById
          ..clear()
          ..addEntries(members.map((m) => MapEntry(m.userId, m)));
        // No longer a member (left or removed) — lock the composer.
        _notAMember = members.isNotEmpty &&
            myId != null &&
            !members.any((m) => m.userId == myId);
      });
    } catch (_) {
      // Non-fatal — bubbles fall back to the stored sender_name.
    }
  }

  void _wirePresence() {
    final otherId = _conversation?.otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    // Re-fetch last seen periodically so the header stays fresh even
    // if the user has the chat open for a while (presence sync only
    // fires on join/leave; long-running idle doesn't bump it).
    unawaited(_refreshLastSeen(otherId));
    unawaited(_refreshBlockedState(otherId));
    unawaited(_refreshFriendship(otherId));
    _lastSeenRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshLastSeen(otherId)),
    );
    _presenceListener = () {
      if (mounted) setState(() {});
    };
    PresenceService.onChange.addListener(_presenceListener!);
  }

  Future<void> _refreshBlockedState(String otherId) async {
    final blocked = await MessagingService.isBlockedByMe(otherId);
    if (!mounted) return;
    setState(() => _isBlocked = blocked);
  }

  /// Pulls the friendship row (if any) between the viewer and the
  /// other participant. Filters client-side from fetchMyFriendships
  /// because the typical user has a small friend list and adding a
  /// dedicated single-pair lookup endpoint is overkill for the
  /// throughput we need here.
  Future<void> _refreshFriendship(String otherId) async {
    try {
      final all = await FeedService.fetchMyFriendships();
      if (!mounted) return;
      Friendship? match;
      for (final f in all) {
        if (f.involves(otherId)) {
          match = f;
          break;
        }
      }
      setState(() {
        _friendship = match;
        _friendshipResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendshipResolved = true);
    }
  }

  Future<void> _addFriend() async {
    final otherId = _conversation?.otherUserId;
    if (otherId == null || otherId.isEmpty || _friendshipBusy) return;
    setState(() => _friendshipBusy = true);
    try {
      final created = await FeedService.sendRequest(otherId);
      if (!mounted) return;
      setState(() => _friendship = created);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not send friend request. Try again.',
            style:
                AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _friendshipBusy = false);
    }
  }

  Future<void> _acceptIncoming() async {
    final f = _friendship;
    if (f == null || _friendshipBusy) return;
    setState(() => _friendshipBusy = true);
    try {
      await FeedService.acceptRequest(f.id);
      if (!mounted) return;
      setState(() {
        _friendship = Friendship(
          id: f.id,
          requesterId: f.requesterId,
          addresseeId: f.addresseeId,
          status: FriendshipStatus.accepted,
          createdAt: f.createdAt,
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not accept. Try again.',
            style:
                AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _friendshipBusy = false);
    }
  }

  Future<void> _refreshLastSeen(String otherId) async {
    final t = await PresenceService.fetchLastSeen(otherId);
    if (!mounted || t == null) return;
    setState(() => _otherLastSeen = t);
  }

  @override
  void dispose() {
    _stream?.cancel();
    _highlightTimer?.cancel();
    _typingExpiry?.cancel();
    _typingThrottle?.cancel();
    _recordingTimer?.cancel();
    _lastSeenRefreshTimer?.cancel();
    // Stop continuous-play hand-off, but DON'T stop playback — a note in
    // progress keeps playing after the user leaves the chat.
    VoicePlayerService.instance.detachResolver(_voiceQueueResolver);
    // Leaving this chat — clear the "open chat" flag so the global voice
    // mini-bar reappears if a note is still playing.
    if (VoicePlayerService.openChatId.value == widget.conversationId) {
      VoicePlayerService.openChatId.value = null;
    }
    final listener = _presenceListener;
    if (listener != null) {
      PresenceService.onChange.removeListener(listener);
    }
    // Best-effort stop in case user leaves the screen mid-record.
    unawaited(_recorder.stop().catchError((_) => null));
    unawaited(_recorder.dispose());
    final ch = _typingChannel;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch);
    }
    _inputController.dispose();
    _scrollController.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Show cached messages immediately so the screen never blanks on
    // open — even on a slow network. The fresh fetch below will
    // replace this with server state in a moment.
    final cached =
        MessagingService.readCachedMessages(widget.conversationId);
    if (cached.isNotEmpty) {
      setState(() {
        _applyServerMessages(cached);
        _loading = false;
      });
      _scrollToBottom(animate: false);
    }
    try {
      final list =
          await MessagingService.fetchMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _applyServerMessages(list);
        _loading = false;
      });
      _scrollToBottom(animate: false);
      _loadReactionsAndStars();
      // Mark anything they sent us as read. Awaited (not fire-and-
      // forget) so when the user pops back to the inbox the badge
      // refresh sees the new state instead of the pre-read snapshot —
      // that race was the "open chat, go back, badge still red" bug.
      await MessagingService.markConversationRead(widget.conversationId);
      _stream =
          MessagingService.streamMessages(widget.conversationId).listen((list) {
        if (!mounted) return;
        // Stream is authoritative. Merge into the unified pipeline —
        // _applyServerMessages drops any optimistic rows the server
        // has now echoed, and the _messages getter re-sorts strictly
        // by createdAt so nothing jumps position.
        final wasAtBottom = _isNearBottom();
        setState(() => _applyServerMessages(list));
        // Only auto-scroll if the user was already at the bottom — so
        // an incoming message doesn't yank them away from older
        // messages they're reading.
        if (wasAtBottom) _scrollToBottom();
        // Any new inbound rows that haven't been marked delivered?
        // Hit them with delivered_at FIRST so the sender sees two
        // grey ticks the moment our app receives the message. THEN
        // mark them read (blue double-tick) since this screen being
        // mounted means they're being viewed.
        final me = AuthService.currentUser?.id;
        if (me != null) {
          final undelivered = list
              .where((m) => m.senderId != me && m.deliveredAt == null)
              .map((m) => m.id)
              .toList();
          if (undelivered.isNotEmpty) {
            unawaited(
              MessagingService.markMessagesDelivered(undelivered),
            );
          }
          if (list.any((m) => m.senderId != me && !m.read)) {
            unawaited(
              MessagingService.markConversationRead(widget.conversationId),
            );
          }
        }
      });
      _typingChannel = MessagingService.subscribeTyping(
        conversationId: widget.conversationId,
        onTyping: (_) {
          if (!mounted) return;
          setState(() => _otherTyping = true);
          // Auto-clear if no follow-up ping arrives — sender is debouncing
          // at 2s so 4s of silence means they stopped.
          _typingExpiry?.cancel();
          _typingExpiry = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _otherTyping = false);
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this chat.';
        _loading = false;
      });
    }
  }

  /// Called from the text field on every keystroke. Throttled to one
  /// broadcast every 1.8s so we don't flood the channel.
  void _onInputChanged(String value) {
    final nowHasText = value.trim().isNotEmpty;
    if (nowHasText != _hasText) {
      setState(() => _hasText = nowHasText);
    }
    final channel = _typingChannel;
    if (channel == null) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingBroadcast) <
        const Duration(milliseconds: 1800)) {
      return;
    }
    _lastTypingBroadcast = now;
    MessagingService.broadcastTyping(channel);
  }

  // ---------- Voice notes ----------

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _startRecording() async {
    if (_recording || _sending) return;
    if (!_ensureOnline('send voice notes')) return;
    final granted = await _ensureMicPermission();
    if (!granted) {
      if (mounted) {
        _toast('Microphone permission is required to send voice notes.');
      }
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _activeRecordingPath = path;
        _recordingStartedAt = DateTime.now();
        _recordingElapsed = Duration.zero;
      });
      _recordingTimer =
          Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _recordingStartedAt == null) return;
        final elapsed = DateTime.now().difference(_recordingStartedAt!);
        setState(() => _recordingElapsed = elapsed);
        // Cap the length (WhatsApp-style limit) so a forgotten recording
        // can't balloon into a huge upload — auto-send at the cap.
        if (elapsed.inSeconds >= _maxRecordingSeconds) {
          _toast('Voice note limit reached — sending.');
          _stopAndSendRecording();
        }
      });
    } catch (_) {
      if (mounted) _toast('Could not start recording.');
      await _cancelRecording();
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped or never started — ignore.
    }
    final path = _activeRecordingPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // File may not exist if start failed — ignore.
      }
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _activeRecordingPath = null;
      _recordingStartedAt = null;
      _recordingElapsed = Duration.zero;
    });
  }

  Future<void> _stopAndSendRecording() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    final duration = _recordingElapsed.inSeconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      await _cancelRecording();
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingStartedAt = null;
      _recordingElapsed = Duration.zero;
    });
    if (path == null || duration < 1) {
      // Too short to be useful — discard.
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) _toast('Hold longer to record a voice note.');
      _activeRecordingPath = null;
      return;
    }
    // Optimistic UI for voice notes — same pattern as text. Upload +
    // insert can take 1-3 seconds; without this the user taps "send"
    // and sees nothing until the stream tick lands, which is exactly
    // the "send shows nothing until refresh" bug reported.
    final me = AuthService.currentUser?.id ?? '';
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: me,
      senderName: 'You',
      content: '🎙️ Voice note',
      messageType: 'voice',
      mediaDurationSeconds: duration,
      // Forced-after-latest timestamp so the bubble never briefly
      // sorts above older messages while the server roundtrip lands
      // ("voice note jumps from top to bottom" bug).
      createdAt: _optimisticTimestamp(),
    );
    setState(() {
      _pending.add(optimistic);
      _sending = true;
    });
    _scrollToBottom();

    try {
      final canonical = await MessagingService.sendVoiceNote(
        conversationId: widget.conversationId,
        localFilePath: path,
        durationSeconds: duration,
      );
      // Swap optimistic for the canonical row so the stream's later
      // tick dedupes by id rather than content.
      if (mounted) {
        setState(() => _replacePendingWithCanonical(tempId, canonical));
      }
    } on PostgrestException catch (e) {
      // Silent block parity for voice notes too — RLS rejection keeps
      // the optimistic bubble in place, no toast.
      if (!mounted) return;
      final isRlsBlock = e.code == '42501' ||
          e.message.toLowerCase().contains('row-level security');
      if (isRlsBlock) {
        setState(() => _localSentIds.add(tempId));
      } else {
        setState(() => _pending.removeWhere((m) => m.id == tempId));
        _toast('Could not send voice note. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pending.removeWhere((m) => m.id == tempId));
        _toast('Could not send voice note. Please try again.');
      }
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) setState(() => _sending = false);
      _activeRecordingPath = null;
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

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      } else {
        // Open / first paint: land AT the bottom instantly (WhatsApp).
        // Animating from the top on open looked like a glitchy "scroll
        // down" every time the chat opened.
        _scrollController.jumpTo(target);
        // Images/bubbles can finish laying out a frame later and grow
        // maxScrollExtent — re-pin to the true bottom once that settles.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        });
      }
    });
  }

  /// True when the view is scrolled at (or within 120px of) the
  /// bottom. Used to decide whether an incoming realtime message
  /// should auto-scroll — we don't yank the user down if they've
  /// scrolled up to read history.
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 120;
  }

  /// Delete a group you've left from your list (WhatsApp: a left group is
  /// read-only until you delete it). Removes your membership row so it
  /// disappears for you only, then returns to the inbox.
  Future<void> _deleteLeftGroupConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This removes the group and its messages from your chats. It stays '
          'for the other members.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await GroupService.deleteGroupConversation(widget.conversationId);
    } catch (_) {}
    if (mounted) {
      context.canPop() ? context.pop() : context.goNamed('messages');
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    // Don't gate text sends on _sending — the optimistic bubble is added
    // synchronously below, so on a slow network you can still fire several
    // messages back-to-back (WhatsApp parity) instead of waiting for each
    // to confirm. The input is cleared immediately, so a double-tap can't
    // resend the same text.
    if (text.isEmpty) return;
    final me = AuthService.currentUser?.id ?? '';

    // Edit mode — update the existing message instead of sending a new
    // one. The realtime stream echoes the UPDATE and refreshes the
    // bubble (with its "edited" label).
    final editing = _editing;
    if (editing != null) {
      if (!_ensureOnline('edit messages')) return;
      setState(() {
        _editing = null;
        _hasText = false;
      });
      _inputController.clear();
      try {
        await MessagingService.editMessage(editing.id, text);
      } catch (_) {
        if (mounted) _toast('Could not edit the message.');
      }
      return;
    }

    final replyId = _replyTo?.id;

    // If the chat was opened from a marketplace product, send the FIRST
    // message as a product card (message_type='product' + meta) so the
    // thumbnail/title/price ride along and the seller can tap through to
    // the listing — instead of folding it into plain text (which dropped
    // the image).
    final outgoing = text;
    final hasProduct = (_productPreviewTitle ?? '').isNotEmpty ||
        (_productPreviewImage ?? '').isNotEmpty;
    final Map<String, dynamic>? productMeta = hasProduct
        ? {
            if ((_productPreviewId ?? '').isNotEmpty)
              'product_id': _productPreviewId,
            if ((_productPreviewImage ?? '').isNotEmpty)
              'image': _productPreviewImage,
            if ((_productPreviewTitle ?? '').isNotEmpty)
              'title': _productPreviewTitle,
            if ((_productPreviewPrice ?? '').isNotEmpty)
              'price': _productPreviewPrice,
          }
        : null;
    final messageType = hasProduct ? 'product' : 'text';

    // Optimistic UI — show the bubble immediately in the _pending list.
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    // Idempotency key so the optimistic row dedupes against the server
    // echo even if the temp id never becomes canonical (offline flush).
    final clientId = 'c-${DateTime.now().microsecondsSinceEpoch}-$me';
    final optimistic = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: me,
      senderName: 'You',
      content: outgoing,
      createdAt: _optimisticTimestamp(),
      messageType: messageType,
      meta: productMeta,
      clientId: clientId,
    );
    setState(() {
      _pending.add(optimistic);
      _sending = true;
      // TextField.onChanged doesn't fire when the controller is
      // cleared programmatically — so without flipping _hasText
      // here, the send button stayed in "send" mode after every
      // text message and the mic button never came back until
      // the user reopened the chat. WhatsApp/Telegram parity:
      // after send, the toolbar reverts to mic immediately.
      _hasText = false;
      // First message sent — drop the product preview chip + reply chip.
      _productPreviewId = null;
      _productPreviewImage = null;
      _productPreviewTitle = null;
      _productPreviewPrice = null;
      _replyTo = null;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final canonical = await MessagingService.sendMessage(
        conversationId: widget.conversationId,
        content: outgoing,
        replyToId: replyId,
        messageType: messageType,
        meta: productMeta,
        clientId: clientId,
      );
      // Replace the optimistic entry with the canonical message in
      // place. The stream tick that follows dedupes by id (now that
      // the pending IS the canonical) — no double-render, no flicker.
      if (mounted) {
        setState(() => _replacePendingWithCanonical(tempId, canonical));
      }
    } on OutboxQueuedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You\'re offline. We\'ll send this when you reconnect.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } on PostgrestException catch (e) {
      // Silent-block path: the recipient blocked this user, so the
      // INSERT was rejected by RLS (Postgres SQLSTATE 42501 = row-
      // level-security violation). Keep the optimistic bubble in
      // place and DON'T toast — WhatsApp parity: the sender should
      // not know they've been blocked. Their bubble sits with a
      // single grey tick forever; if they leave the chat and come
      // back, it's gone, which is consistent with "delivery is
      // taking a while".
      if (!mounted) return;
      final isRlsBlock = e.code == '42501' ||
          (e.message).toLowerCase().contains('row-level security');
      if (isRlsBlock) {
        // Bubble stays as a single grey ✓ (sent), never delivers, no toast.
        setState(() => _localSentIds.add(tempId));
        return;
      }
      // Any other Postgrest error → existing rollback + retry path.
      setState(() => _pending.removeWhere((m) => m.id == tempId));
      _inputController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send message. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      // Send failed — roll back the optimistic bubble and put the
      // text back in the input so the user can retry.
      setState(() => _pending.removeWhere((m) => m.id == tempId));
      _inputController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send message. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.scaffoldBg,
      body: Column(
        children: [
          _selectMode ? _buildSelectionBar() : _buildHeader(),
          _buildFriendshipBanner(),
          Expanded(child: _buildBody()),
          _buildInputBar(),
        ],
      ),
    );
  }

  /// "You're not friends yet" banner — pops above the message list
  /// when the viewer and the other participant aren't connected on
  /// the friend graph. Three states map to three CTAs (Add friend,
  /// Accept, or just a sent-pending status). Hidden once they're
  /// friends. Mirrors how Facebook/Instagram surface stranger DMs.
  Widget _buildFriendshipBanner() {
    final convo = _conversation;
    if (convo == null) return const SizedBox.shrink();
    if (convo.isSelfChat) return const SizedBox.shrink();
    if (!_friendshipResolved) return const SizedBox.shrink();
    final f = _friendship;
    if (f != null && f.isAccepted) return const SizedBox.shrink();

    final viewerId = AuthService.currentUser?.id ?? '';
    final otherName = convo.otherUserName;
    final isIncoming = f != null && f.isIncomingPendingFor(viewerId);
    final isOutgoingPending =
        f != null && f.isPending && !f.isIncomingPendingFor(viewerId);

    String title;
    String body;
    Widget? action;

    if (isIncoming) {
      title = '$otherName wants to be friends';
      body =
          'Accept to follow each other\'s friends-only posts. You can still chat regardless.';
      action = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _friendshipBusy ? null : _acceptIncoming,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: const BorderSide(color: AppColors.primaryBlue),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _friendshipBusy ? 'Accepting…' : 'Accept',
                style: AppTextStyles.buttonText.copyWith(
                  color: AppColors.primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (isOutgoingPending) {
      title = 'Friend request sent';
      body =
          'Waiting for $otherName to accept. You can keep chatting in the meantime.';
      action = null;
    } else {
      title = 'You\'re not friends with $otherName yet';
      body =
          'You can still send messages. Add as a friend to follow each other\'s posts.';
      action = Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _friendshipBusy ? null : _addFriend,
              icon: const Icon(
                Icons.person_add_alt_1,
                size: 16,
                color: AppColors.primaryBlue,
              ),
              label: Text(
                _friendshipBusy ? 'Sending…' : 'Add friend',
                style: AppTextStyles.buttonText.copyWith(
                  color: AppColors.primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                side: const BorderSide(color: AppColors.primaryBlue),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.goldAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.goldAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 16,
                color: AppColors.goldAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.palette.textMuted,
              height: 1.4,
              fontSize: 12,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            action,
          ],
        ],
      ),
    );
  }

  // Per-sender label colour for group bubbles — cycled from the approved
  // palette only (no off-scheme colours).
  static const List<Color> _senderColors = [
    AppColors.primaryBlue,
    AppColors.successGreen,
    AppColors.darkNavy,
  ];

  /// Open (or create) a 1:1 chat with [userId] — used when tapping a
  /// group member's name/avatar.
  Future<void> _openUserChat(String userId, String name) async {
    final me = AuthService.currentUser?.id;
    if (userId.isEmpty || userId == me) return;
    try {
      final convo = await MessagingService.createConversation(
        otherUserId: userId,
        otherUserName: name,
      );
      if (!mounted) return;
      context.pushNamed('chat', pathParameters: {'id': convo.id});
    } catch (_) {
      if (mounted) _toast('Could not open chat with $name.');
    }
  }

  Widget _groupSenderLabel(Message m) {
    final member = _memberById[m.senderId];
    final name = member?.fullName ??
        (m.senderName.trim().isEmpty ? 'Member' : m.senderName);
    final color =
        _senderColors[m.senderId.hashCode.abs() % _senderColors.length];
    final isAdmin = member?.isAdmin ?? false;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: GestureDetector(
        onTap: () => _openUserChat(m.senderId, name),
        behavior: HitTestBehavior.opaque,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(name: name, size: 20, photoUrl: member?.photoUrl),
          const SizedBox(width: 6),
          Text(
            name,
            style: AppTextStyles.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'admin',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryBlue,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  /// Quoted preview shown above a reply bubble; tap jumps to the original.
  Widget _buildQuotedPreview(Message m, bool isMine) {
    Message? original;
    for (final x in _messages) {
      if (x.id == m.replyToId) {
        original = x;
        break;
      }
    }
    final me = AuthService.currentUser?.id;
    final who = original == null
        ? 'Message'
        : (original.senderId == me
            ? 'You'
            : _memberById[original.senderId]?.fullName ??
                _conversation?.otherUserName ??
                'Message');
    return GestureDetector(
      onTap: m.replyToId == null ? null : () => _scrollToMessage(m.replyToId!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.66,
        ),
        decoration: BoxDecoration(
          color: context.palette.cardMuted,
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: AppColors.primaryBlue, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              who,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              original?.content ?? 'Original message unavailable',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reaction chips under a bubble. [_reactions] maps message id to a
  /// map of `emoji -> count` plus a `_mine_` prefixed key for own picks.
  Widget _buildReactionChips(Message m) {
    final data = _reactions[m.id] ?? const {};
    final entries = data.entries
        .where((e) => !e.key.startsWith('_mine_'))
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(
        spacing: 4,
        children: [
          for (final e in entries)
            GestureDetector(
              onTap: () => _react(m, e.key),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: data.containsKey('_mine_${e.key}')
                      ? AppColors.primaryBlue.withValues(alpha: 0.15)
                      : context.palette.cardMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.palette.divider),
                ),
                child: Text(
                  '${e.key} ${e.value}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    final count = _selectedMsgIds.length;
    return ClipPath(
      clipper: _HeaderClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 22),
            child: Row(
              children: [
                _CircleIconButton(icon: Icons.close, onTap: _exitSelect),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$count selected',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.shortcut, color: AppColors.white),
                  tooltip: 'Forward',
                  onPressed: count == 0 ? null : _forwardSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.white),
                  tooltip: 'Delete',
                  onPressed: count == 0 ? null : _confirmDeleteSelected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedMsgIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count message${count == 1 ? '' : 's'}?'),
        content: const Text(
          'Your own messages will show "This message was deleted" for '
          'everyone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteSelected();
  }

  Widget _buildHeader() {
    final convo = _conversation;
    final isGroup = convo?.isGroup ?? false;
    final name = convo?.otherUserName ?? 'Conversation';
    final photoUrl = convo?.otherUserPhotoUrl;
    final otherUserId = convo?.otherUserId;
    final canOpenProfile = !isGroup &&
        otherUserId != null &&
        otherUserId.isNotEmpty &&
        !(convo?.isSelfChat ?? false);
    void openGroupInfo() => context.pushNamed(
          'group_info',
          pathParameters: {'id': widget.conversationId},
        );
    return ClipPath(
      clipper: _HeaderClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 22),
            child: Row(
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back,
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.goNamed('messages'),
                ),
                const SizedBox(width: 8),
                // Tappable avatar + name strip — opens the other user's
                // public profile, the same way WhatsApp does when you
                // tap the contact's name at the top of a chat.
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    // Tap → WhatsApp-style mini contact sheet (photo,
                    // name, online state, bio) with a "View full
                    // profile" button that pushes to UserProfileScreen.
                    // Previously the tap deep-linked straight to the
                    // full profile, which felt too much for a quick
                    // glance.
                    // Tapping a group header (including church groups +
                    // the announcements channel) opens its info screen,
                    // WhatsApp-style.
                    onTap: isGroup
                        ? openGroupInfo
                        : canOpenProfile
                            ? () => showChatContactSheet(
                                  context,
                                  userId: otherUserId,
                                  fallbackName: name,
                                  fallbackPhotoUrl: photoUrl,
                                  conversationId: widget.conversationId,
                                )
                            : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          _isChurchGroup
                              ? ChurchGroupAvatar(photoUrl: photoUrl, size: 40)
                              : _Avatar(
                                  name: name, size: 40, photoUrl: photoUrl),
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
                                  style: AppTextStyles.titleLarge.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 220),
                                  child: isGroup
                                      ? Text(
                                          _isChurchChannel
                                              ? 'Church announcements'
                                              : _isChurchGroup
                                                  ? 'Church group'
                                                  : _groupMembers.isEmpty
                                                      ? 'Tap for group info'
                                                      : '${_groupMembers.length} members',
                                          key: const ValueKey('group-sub'),
                                          style:
                                              AppTextStyles.labelSmall.copyWith(
                                            color: AppColors.white
                                                .withValues(alpha: 0.75),
                                            fontSize: 11,
                                          ),
                                        )
                                      : _buildPresenceSubtitle(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isGroup)
                  _CircleIconButton(
                    icon: Icons.info_outline,
                    onTap: openGroupInfo,
                  )
                else
                  _buildOverflowMenu(canOpenProfile, otherUserId),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowMenu(bool canOpenProfile, String? otherUserId) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.white),
      color: context.palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      onSelected: (action) async {
        switch (action) {
          case 'profile':
            if (canOpenProfile) {
              context.pushNamed(
                'user_profile',
                pathParameters: {'userId': otherUserId!},
              );
            }
            break;
          case 'block':
            await _confirmBlock(otherUserId);
            break;
          case 'unblock':
            await _confirmUnblock(otherUserId);
            break;
          case 'clear':
            await _confirmClearChat();
            break;
          case 'delete':
            await _confirmDeleteConversation();
            break;
          case 'report_group':
            await showReportSheet(
              context,
              contentType: 'group',
              contentId: widget.conversationId,
              contentLabel: _conversation?.otherUserName ?? 'this group',
            );
            break;
        }
      },
      itemBuilder: (context) => [
        if (canOpenProfile)
          const PopupMenuItem(
            value: 'profile',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_outline),
              title: Text('View profile'),
            ),
          ),
        if (canOpenProfile && !_isBlocked)
          const PopupMenuItem(
            value: 'block',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.block, color: AppColors.red),
              title: Text(
                'Block',
                style: TextStyle(color: AppColors.red),
              ),
            ),
          ),
        if (canOpenProfile && _isBlocked)
          const PopupMenuItem(
            value: 'unblock',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_open, color: AppColors.primaryBlue),
              title: Text(
                'Unblock',
                style: TextStyle(color: AppColors.primaryBlue),
              ),
            ),
          ),
        const PopupMenuItem(
          value: 'clear',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cleaning_services_outlined),
            title: Text('Clear chat'),
          ),
        ),
        if (_isGroup)
          const PopupMenuItem(
            value: 'report_group',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_outlined, color: AppColors.red),
              title: Text('Report group',
                  style: TextStyle(color: AppColors.red)),
            ),
          ),
        if (!_isChurchGroup)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: AppColors.red),
              title: Text(
                'Delete conversation',
                style: TextStyle(color: AppColors.red),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmBlock(String? otherUserId) async {
    if (otherUserId == null) return;
    final name = _conversation?.otherUserName ?? 'this user';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
          'Blocked contacts can\'t message you and won\'t see your stories or '
          'last seen. You can unblock anytime from this menu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await MessagingService.blockUser(otherUserId);
      if (!mounted) return;
      setState(() => _isBlocked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            '$name has been blocked.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not block. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _confirmUnblock(String? otherUserId) async {
    if (otherUserId == null) return;
    final name = _conversation?.otherUserName ?? 'this user';
    try {
      await MessagingService.unblockUser(otherUserId);
      if (!mounted) return;
      setState(() => _isBlocked = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successGreen,
          content: Text(
            '$name has been unblocked.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.red,
          content: Text(
            'Could not unblock. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Future<void> _confirmClearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'All messages in this conversation will be removed from your device. '
          'The other person will still see their copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Persist the clear (patch_081 cleared_at) so the messages stay hidden
    // after re-opening — previously this only cleared local state, so a
    // re-fetch brought them all back.
    try {
      await MessagingService.clearConversation(widget.conversationId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _serverMessages = const [];
      _pending.clear();
    });
  }

  Future<void> _confirmDeleteConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This clears the conversation from your inbox. The other '
          'person still keeps their copy — they won\'t be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      // declineRequest deletes the conversation row; messages cascade
      // away. Same primitive whether it's an unaccepted request or
      // an active chat — RLS only allows participants.
      await MessagingService.declineRequest(widget.conversationId);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed('messages');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete conversation. Try again.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.palette.textMuted,
            ),
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: AppColors.primaryBlue,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Say hello',
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Start the conversation with a friendly greeting.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.textMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final currentUserId = AuthService.currentUser?.id ?? '';
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: child,
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        itemCount: _messages.length,
        itemBuilder: (context, i) {
          final m = _messages[i];
          // System events (joined / left / removed / admin changes) render
          // as a centred pill, not a chat bubble.
          if (m.messageType == 'system') {
            final prevSys = i > 0 ? _messages[i - 1] : null;
            final showSep = prevSys == null ||
                !_sameLocalDay(prevSys.createdAt, m.createdAt);
            // A system event is authored by the actor (sender_id). For the
            // actor themselves, show "You left/joined" instead of their own
            // name — WhatsApp parity (others still see "Michael left").
            final sysMine = m.senderId == (AuthService.currentUser?.id ?? '');
            final sysText = sysMine
                ? (m.content.endsWith(' left')
                    ? 'You left'
                    : m.content.endsWith(' joined')
                        ? 'You joined'
                        : m.content.contains('created the group')
                            ? 'You created the group'
                            : m.content)
                : m.content;
            return Column(
              children: [
                if (showSep) _DateSeparator(label: _dayLabel(m.createdAt)),
                _SystemMessage(text: sysText),
              ],
            );
          }
          final isMine = m.senderId == currentUserId;
          // Per user request: every message gets its own timestamp,
          // not just the last one in a sender-grouped cluster. This
          // matches how WhatsApp actually renders — each bubble has
          // its own time underneath, not a single trailing stamp.
          final showStamp = true;
          // WhatsApp-style day separator: shown above the first message
          // of each calendar day (Today / Yesterday / "Mon 8 Jun").
          final prev = i > 0 ? _messages[i - 1] : null;
          final showDateSeparator = prev == null ||
              !_sameLocalDay(prev.createdAt, m.createdAt);
          return _SelectableMessage(
            // Key by message id so deletes/inserts in the middle of the
            // thread don't make Flutter recycle bubbles by index (which
            // flashed the wrong message into a slot for a frame).
            key: ValueKey('msg-${m.id}'),
            selectMode: _selectMode,
            selected: _selectedMsgIds.contains(m.id),
            onToggle: () => _toggleSelect(m),
            child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showDateSeparator) _DateSeparator(label: _dayLabel(m.createdAt)),
                if (_isGroup && !isMine) _groupSenderLabel(m),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: _highlightedMessageId == m.id
                        ? AppColors.primaryBlue.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _SwipeToReply(
                  onReply: () => _startReply(m),
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _showMessageActions(m, isMine),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (m.replyToId != null) _buildQuotedPreview(m, isMine),
                      _MessageBubble(message: m, isMine: isMine),
                    ],
                  ),
                  ),
                  ),
                ),
                if ((_reactions[m.id] ?? const {}).isNotEmpty)
                  _buildReactionChips(m),
                if (showStamp)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMine ? 0 : 8,
                      4,
                      isMine ? 8 : 0,
                      6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _stamp(m.createdAt),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: context.palette.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 4),
                          // WhatsApp three-state delivery indicator:
                          //   ⌛  pending  — optimistic, still uploading
                          //   ✓   sent    — server has the row
                          //   ✓✓  delivered — recipient device received it
                          //   ✓✓  read    — recipient opened the chat (blue)
                          // In GROUPS, read/delivered are single shared
                          // columns (not per-member), so a blue "read by
                          // everyone" tick would be misleading. Show only
                          // sent (✓) / delivered (✓✓ grey) there — never
                          // blue. 1:1 keeps the full three-state tick.
                          Icon(
                            (m.id.startsWith('pending-') &&
                                    !_localSentIds.contains(m.id))
                                ? Icons.access_time
                                : (m.deliveredAt != null || m.read
                                    ? Icons.done_all
                                    : Icons.done),
                            size: 13,
                            color: (m.read && !_isGroup)
                                ? AppColors.primaryBlue
                                : context.palette.textMuted,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  bool _sameLocalDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// "Today" / "Yesterday" / "Mon 8 Jun" / "8 Jun 2025" — WhatsApp's
  /// day-separator label.
  String _dayLabel(DateTime when) {
    final local = when.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dow = days[local.weekday - 1];
    final mon = months[local.month - 1];
    if (local.year == now.year) return '$dow ${local.day} $mon';
    return '${local.day} $mon ${local.year}';
  }

  Widget _buildInputBar() {
    // Church announcement channel + viewer isn't a church admin — read
    // only. Members chat and admins fall through to the normal composer.
    if (_isChurchChannel && !_channelCanPost) {
      return Container(
        color: context.palette.card,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.campaign_outlined,
                    size: 16, color: context.palette.textMuted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Only church admins can post in this announcement channel.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Left / removed from this group — no composer, just a notice
    // (WhatsApp shows "You can't send messages to this group").
    if (_notAMember) {
      return Container(
        color: context.palette.card,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: context.palette.textMuted),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "You can't send messages to this group because you're "
                        'no longer a member.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: context.palette.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // WhatsApp parity: a left group stays read-only until you
                // delete the conversation, which removes it from your list.
                TextButton.icon(
                  onPressed: _deleteLeftGroupConversation,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppColors.red),
                  label: const Text('Delete conversation',
                      style: TextStyle(color: AppColors.red)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // When the viewer has blocked this contact, hide the composer
    // entirely (WhatsApp does exactly this) and replace it with a
    // tappable strip that opens the Unblock confirmation.
    if (_isBlocked) {
      return Container(
        color: context.palette.card,
        child: SafeArea(
          top: false,
          child: InkWell(
            onTap: () => _confirmUnblock(_conversation?.otherUserId),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisSize.max == MainAxisSize.max
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, size: 16, color: context.palette.text),
                  const SizedBox(width: 8),
                  Text(
                    'You blocked this contact. Tap to unblock.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: context.palette.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: _recording ? _buildRecordingBar() : _buildComposeBar(),
        ),
      ),
    );
  }

  /// WhatsApp-style attachment menu. Camera/Gallery work now; Document
  /// needs the file_picker dependency (added in a follow-up) and Audio
  /// reuses the hold-to-record voice flow.
  Future<void> _openAttachmentSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: ctx.palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  _AttachOption(
                    icon: Icons.photo_camera_rounded,
                    label: 'Camera',
                    color: AppColors.primaryBlue,
                    onTap: () => Navigator.pop(ctx, 'camera'),
                  ),
                  _AttachOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: AppColors.successGreen,
                    onTap: () => Navigator.pop(ctx, 'gallery'),
                  ),
                  _AttachOption(
                    icon: Icons.mic_rounded,
                    label: 'Audio',
                    color: AppColors.goldAccent,
                    onTap: () => Navigator.pop(ctx, 'audio'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _pickAndSendImage(fromCamera: true);
      case 'gallery':
        await _pickAndSendImage(fromCamera: false);
      case 'audio':
        await _startRecording();
    }
  }

  Future<void> _pickAndSendImage({required bool fromCamera}) async {
    if (!_ensureOnline('send photos')) return;
    try {
      final result = await StorageService.pickChatImage(fromCamera: fromCamera);
      if (result == null) return;
      await _sendImageBytes(result.bytes, result.ext);
    } on FileTooLargeException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('Could not attach that image.');
    }
  }

  Future<void> _sendImageBytes(Uint8List bytes, String ext) async {
    final me = AuthService.currentUser?.id ?? '';
    // Write to a temp file so the optimistic bubble can render the photo
    // immediately (Image.file) while the upload runs.
    String localPath;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/outgoing_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
      await file.writeAsBytes(bytes, flush: true);
      localPath = file.path;
    } catch (_) {
      localPath = '';
    }
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: me,
      senderName: 'You',
      content: '📷 Photo',
      messageType: 'image',
      mediaUrl: localPath,
      createdAt: _optimisticTimestamp(),
    );
    setState(() {
      _pending.add(optimistic);
      _sending = true;
    });
    _scrollToBottom();
    try {
      final canonical = await MessagingService.sendImageMessage(
        conversationId: widget.conversationId,
        bytes: bytes,
        ext: ext,
      );
      if (mounted) {
        setState(() => _replacePendingWithCanonical(tempId, canonical));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pending.removeWhere((m) => m.id == tempId));
        _toast('Could not send image. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _buildReplyEditPreview() {
    final editing = _editing != null;
    final m = _editing ?? _replyTo!;
    final me = AuthService.currentUser?.id;
    final who = editing
        ? 'Editing message'
        : (m.senderId == me
            ? 'Replying to yourself'
            : 'Replying to ${_memberById[m.senderId]?.fullName ?? _conversation?.otherUserName ?? 'message'}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: context.palette.cardMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: AppColors.primaryBlue, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(editing ? Icons.edit_outlined : Icons.reply,
              size: 16, color: AppColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  who,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  m.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: context.palette.textMuted),
            onPressed: _cancelComposeExtras,
          ),
        ],
      ),
    );
  }

  Widget _buildComposeBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyTo != null || _editing != null) _buildReplyEditPreview(),
        if (_productPreviewTitle != null || _productPreviewImage != null)
          _buildProductPreview(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        _AttachButton(onTap: _sending ? null : _openAttachmentSheet),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.palette.inputFill,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.palette.divider),
            ),
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 14.5,
                color: context.palette.text,
              ),
              decoration: InputDecoration(
                hintText: 'Write a message',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: context.palette.textMuted,
                  fontSize: 14.5,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _onInputChanged,
              onSubmitted: (_) => _send(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_hasText)
          _SendButton(busy: _sending, onTap: _send)
        else
          _MicButton(busy: _sending, onTap: _startRecording),
          ],
        ),
      ],
    );
  }

  /// #17: product chip shown above the composer when the chat was
  /// opened from a marketplace product. Dismissible.
  Widget _buildProductPreview() {
    final img = _productPreviewImage;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.palette.cardMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        children: [
          if (img != null && img.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CachedImage(img, fit: BoxFit.cover),
              ),
            )
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shopping_bag_outlined,
                  color: AppColors.primaryBlue, size: 20),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Asking about',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: context.palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  _productPreviewTitle ?? 'this product',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((_productPreviewPrice ?? '').isNotEmpty)
                  Text(
                    _productPreviewPrice!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: context.palette.textMuted),
            onPressed: () => setState(() {
              _productPreviewImage = null;
              _productPreviewTitle = null;
              _productPreviewPrice = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    final mm = _recordingElapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (_recordingElapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.red.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                _BlinkingDot(),
                const SizedBox(width: 10),
                Text(
                  'Recording',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '$mm:$ss',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _CancelRecordingButton(onTap: _cancelRecording),
        const SizedBox(width: 6),
        _SendButton(busy: _sending, onTap: _stopAndSendRecording),
      ],
    );
  }

  Widget _buildPresenceSubtitle() {
    // Typing always wins — it's the most "live" signal.
    if (_otherTyping) {
      return Text(
        'typing…',
        key: const ValueKey('typing'),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.white,
          fontSize: 11,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    final otherId = _conversation?.otherUserId;
    if (otherId != null && PresenceService.isOnline(otherId)) {
      // Lit green dot + "Online" — same affordance WhatsApp uses.
      return Row(
        key: const ValueKey('online'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.successGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Online',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    final lastSeen = _otherLastSeen;
    final label = lastSeen != null
        ? 'last seen ${PresenceService.formatLastSeen(lastSeen)}'
        : 'Offline';
    return Text(
      label,
      key: ValueKey(label),
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.white.withValues(alpha: 0.7),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  String _stamp(DateTime t) {
    // Supabase returns created_at as UTC. Convert to the device's
    // local timezone so the user sees "11:37" instead of "09:37"
    // when they're in CAT / SAST (UTC+2).
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

/// Centered day-divider chip between messages from different days.
/// Centred grey pill for group system events (joined / left / removed).
class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.palette.cardMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall.copyWith(
              color: context.palette.textMuted,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: context.palette.cardMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.palette.divider),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: context.palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    // Soft-deleted tombstone — same for both sides, regardless of the
    // original message type.
    if (message.isDeleted) {
      final maxW = MediaQuery.of(context).size.width * 0.74;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine
                ? AppColors.primaryBlue.withValues(alpha: 0.10)
                : context.palette.cardMuted,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 15, color: context.palette.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'This message was deleted',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.palette.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (message.messageType == 'voice' &&
        (message.mediaUrl ?? '').isNotEmpty) {
      return _VoiceBubble(message: message, isMine: isMine);
    }
    if (message.messageType == 'image' &&
        (message.mediaUrl ?? '').isNotEmpty) {
      return _ImageBubble(message: message, isMine: isMine);
    }
    if (message.messageType == 'product' && message.meta != null) {
      return _ProductBubble(message: message, isMine: isMine);
    }
    if (message.messageType == 'story_reply') {
      return _StoryReplyBubble(message: message, isMine: isMine);
    }
    final maxWidth = MediaQuery.of(context).size.width * 0.74;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMine ? AppColors.primaryGradient : null,
          color: isMine ? null : context.palette.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: isMine
                  ? AppColors.primaryBlue.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isMine ? 12 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.forwarded)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shortcut,
                        size: 13,
                        color: (isMine ? AppColors.white : context.palette.text)
                            .withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(
                      'Forwarded',
                      style: AppTextStyles.labelSmall.copyWith(
                        color:
                            (isMine ? AppColors.white : context.palette.text)
                                .withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              message.content,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isMine ? AppColors.white : context.palette.text,
                fontSize: 14.5,
                height: 1.35,
              ),
            ),
            if (message.isEdited)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'edited',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: (isMine ? AppColors.white : context.palette.text)
                        .withValues(alpha: 0.55),
                    fontSize: 9.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Voice-note bubble. Stateless — it binds to the app-wide
/// [VoicePlayerService] so playback survives leaving the chat, only one
/// note plays at a time, and the clip is downloaded once then replayed
/// from disk (no re-load on every tap, no 30-second cut-out).
class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  String _fmt(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _speedLabel(double s) =>
      s == s.roundToDouble() ? '${s.toInt()}x' : '${s}x';

  Future<void> _onPlay(BuildContext context) async {
    try {
      await VoicePlayerService.instance.toggle(VoiceNote(
        messageId: message.id,
        storagePath: message.mediaUrl!,
        durationSeconds: message.mediaDurationSeconds,
        conversationId: message.conversationId,
      ));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not play this voice note.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = VoicePlayerService.instance;
    final maxWidth = MediaQuery.of(context).size.width * 0.74;
    final fg = isMine ? AppColors.white : context.palette.text;
    final accent = isMine ? AppColors.white : AppColors.primaryBlue;
    final muted = isMine
        ? AppColors.white.withValues(alpha: 0.7)
        : context.palette.textMuted;
    final trackBg = isMine
        ? AppColors.white.withValues(alpha: 0.30)
        : context.palette.divider;
    final declared = Duration(seconds: message.mediaDurationSeconds ?? 0);
    // Optimistic outgoing note still uploading (tempId). Show a spinner
    // where the play button goes so it clearly reads as "sending".
    final uploading = isMine && message.id.startsWith('pending-');
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMine ? AppColors.primaryGradient : null,
          color: isMine ? null : context.palette.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: isMine
                  ? AppColors.primaryBlue.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isMine ? 12 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: uploading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.mic_rounded, color: muted, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Sending voice note…',
                      style: AppTextStyles.bodySmall.copyWith(color: muted),
                    ),
                  ),
                  Text(_fmt(declared),
                      style: AppTextStyles.labelSmall.copyWith(color: muted)),
                ],
              )
            : AnimatedBuilder(
          animation: Listenable.merge([
            svc.activeId,
            svc.loadingId,
            svc.playing,
            svc.position,
            svc.duration,
            svc.speed,
          ]),
          builder: (context, _) {
            final isActive = svc.activeId.value == message.id;
            final isLoading = svc.loadingId.value == message.id;
            final isPlaying = isActive && svc.playing.value;
            final total = (isActive && svc.duration.value > Duration.zero)
                ? svc.duration.value
                : declared;
            final pos = isActive ? svc.position.value : Duration.zero;
            final progress = total.inMilliseconds == 0
                ? 0.0
                : (pos.inMilliseconds / total.inMilliseconds)
                    .clamp(0.0, 1.0)
                    .toDouble();
            final timeLabel = isActive && (isPlaying || pos > Duration.zero)
                ? _fmt(pos)
                : _fmt(total);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _onPlay(context),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isMine
                          ? AppColors.white.withValues(alpha: 0.20)
                          : AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: accent,
                            size: 22,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Waveform(
                        messageId: message.id,
                        progress: progress,
                        playedColor: fg,
                        trackColor: trackBg,
                        onSeek: isActive ? svc.seekFraction : null,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            timeLabel,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (isActive)
                            GestureDetector(
                              onTap: svc.cycleSpeed,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isMine
                                      ? AppColors.white.withValues(alpha: 0.18)
                                      : AppColors.primaryBlue
                                          .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _speedLabel(svc.speed.value),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          else
                            Icon(Icons.mic_rounded, size: 14, color: muted),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Static WhatsApp-style waveform. Bar heights are seeded from the
/// message id (stable per note, no real audio analysis), and the played
/// portion is tinted. Tapping / dragging seeks when [onSeek] is set.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.messageId,
    required this.progress,
    required this.playedColor,
    required this.trackColor,
    this.onSeek,
  });

  final String messageId;
  final double progress;
  final Color playedColor;
  final Color trackColor;
  final ValueChanged<double>? onSeek;

  static const _barCount = 30;

  @override
  Widget build(BuildContext context) {
    final rnd = Random(messageId.hashCode);
    final heights =
        List.generate(_barCount, (_) => 0.28 + rnd.nextDouble() * 0.72);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seekAt(double dx) {
          if (onSeek != null && width > 0) {
            onSeek!((dx / width).clamp(0.0, 1.0));
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              onSeek == null ? null : (d) => seekAt(d.localPosition.dx),
          onHorizontalDragUpdate:
              onSeek == null ? null : (d) => seekAt(d.localPosition.dx),
          child: SizedBox(
            height: 26,
            width: double.infinity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < _barCount; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        heightFactor: heights[i],
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: (i / _barCount) <= progress
                                ? playedColor
                                : trackColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Compose-bar attachment button (paperclip).
class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.cardMuted,
        shape: BoxShape.circle,
        border: Border.all(color: context.palette.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              Icons.add_rounded,
              color: onTap == null
                  ? context.palette.textMuted
                  : AppColors.primaryBlue,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single round icon option in the attachment sheet.
class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Image-message bubble. Renders the local file optimistically while the
/// upload runs, then a signed-URL image from the private bucket. Tap to
/// open full-screen.
/// Wraps a message row for multi-select mode: a leading check, a
/// highlight, tap-to-toggle, and absorbs the bubble's own gestures so a
/// tap selects instead of replying/playing.
class _SelectableMessage extends StatelessWidget {
  const _SelectableMessage({
    super.key,
    required this.child,
    required this.selectMode,
    required this.selected,
    required this.onToggle,
  });
  final Widget child;
  final bool selectMode;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (!selectMode) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Container(
        color: selected
            ? AppColors.primaryBlue.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? AppColors.primaryBlue
                  : context.palette.divider,
            ),
            const SizedBox(width: 6),
            Expanded(child: AbsorbPointer(child: child)),
          ],
        ),
      ),
    );
  }
}

/// Drag a bubble to the right to reply (WhatsApp). Distance-based (not
/// velocity) so slow, deliberate swipes work; shows a reply arrow that
/// grows as you drag and fires once past the threshold.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});
  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const double _trigger = 56;
  static const double _max = 84;
  double _dx = 0;
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        final next = (_dx + d.delta.dx).clamp(0.0, _max);
        if (next != _dx) setState(() => _dx = next);
        if (!_fired && _dx >= _trigger) {
          _fired = true;
          HapticFeedback.selectionClick();
        }
      },
      onHorizontalDragEnd: (_) {
        if (_dx >= _trigger) widget.onReply();
        setState(() {
          _dx = 0;
          _fired = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _fired = false;
      }),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 4)
            Opacity(
              opacity: (_dx / _trigger).clamp(0.0, 1.0),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.reply,
                  size: 20,
                  color: _dx >= _trigger
                      ? AppColors.primaryBlue
                      : context.palette.textMuted,
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// A product card sent into the chat (image + title + price + the
/// buyer's message). Tapping the card opens the listing.
class _ProductBubble extends StatelessWidget {
  const _ProductBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final meta = message.meta ?? const {};
    final id = (meta['product_id'] ?? '').toString();
    final image = (meta['image'] ?? '').toString();
    final title = (meta['title'] ?? 'Product').toString();
    final price = (meta['price'] ?? '').toString();
    final maxWidth = MediaQuery.of(context).size.width * 0.74;
    final fg = isMine ? AppColors.white : context.palette.text;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          gradient: isMine ? AppColors.primaryGradient : null,
          color: isMine ? null : context.palette.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: isMine
                  ? AppColors.primaryBlue.withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tappable product card.
            GestureDetector(
              onTap: id.isEmpty
                  ? null
                  : () => context.pushNamed('product_details',
                      pathParameters: {'id': id}),
              child: Container(
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: image.isEmpty
                          ? Container(
                              color: context.palette.cardMuted,
                              child: Icon(Icons.shopping_bag_outlined,
                                  color: context.palette.textMuted),
                            )
                          : CachedImage(image, fit: BoxFit.cover),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: context.palette.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (price.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                price,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_right,
                          size: 18, color: context.palette.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            if (message.content.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Text(
                  message.content,
                  style: AppTextStyles.bodyMedium.copyWith(color: fg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A reply sent from someone's Status/story — shows a small preview of the
/// story (tap to view it) above the reply text.
class _StoryReplyBubble extends StatelessWidget {
  const _StoryReplyBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final meta = message.meta ?? const <String, dynamic>{};
    final img = (meta['story_image'] ?? '').toString();
    final onText = isMine ? AppColors.white : context.palette.text;
    final maxWidth = MediaQuery.of(context).size.width * 0.74;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: isMine ? AppColors.primaryGradient : null,
          color: isMine ? null : context.palette.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: img.isEmpty
                  ? null
                  : () => FullImageViewer.show(context, img),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isMine ? AppColors.white : AppColors.primaryBlue)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: isMine ? AppColors.white : AppColors.primaryBlue,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (img.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: CachedImage(img, fit: BoxFit.cover),
                        ),
                      ),
                    if (img.isNotEmpty) const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isMine
                            ? 'You replied to a status'
                            : 'Replied to your status',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: onText.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (message.content.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  message.content,
                  style: AppTextStyles.bodyMedium.copyWith(color: onText),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageBubble extends StatefulWidget {
  const _ImageBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  State<_ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<_ImageBubble> {
  String? _signedUrl;
  bool _isLocal = false;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    final media = widget.message.mediaUrl ?? '';
    // Optimistic outgoing bubbles store an absolute temp-file path
    // (leading '/'); real rows store a bucket-relative path.
    if (media.startsWith('/')) {
      _isLocal = true;
      _localPath = media;
    } else {
      _resolve(media);
    }
  }

  Future<void> _resolve(String path) async {
    try {
      final url = await MessagingService.signedChatMediaUrl(path);
      if (mounted) setState(() => _signedUrl = url);
    } catch (_) {
      // leave as a placeholder
    }
  }

  void _open() {
    if (_signedUrl != null) FullImageViewer.show(context, _signedUrl);
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.isMine;
    final maxWidth = MediaQuery.of(context).size.width * 0.66;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
        child: GestureDetector(
          onTap: _open,
          child: Container(
            constraints: const BoxConstraints(minWidth: 160, minHeight: 160),
            color: context.palette.cardMuted,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                _buildImage(),
                // WhatsApp-style upload overlay: while the optimistic
                // (local) bubble is still uploading, dim the photo and
                // show a spinner so it's clearly "sending", not gone.
                if (_isLocal && isMine)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.38),
                      child: const Center(
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (_isLocal && _localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (_signedUrl != null) {
      return CachedImage(
        _signedUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder(loading: true);
  }

  Widget _placeholder({bool loading = false}) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Center(
        child: loading
            ? const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryBlue,
              )
            : Icon(
                Icons.broken_image_outlined,
                color: context.palette.textMuted,
                size: 36,
              ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.cardMuted,
        shape: BoxShape.circle,
        border: Border.all(color: context.palette.divider),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              Icons.mic_rounded,
              color: busy ? context.palette.textMuted : AppColors.primaryBlue,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelRecordingButton extends StatelessWidget {
  const _CancelRecordingButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.close_rounded,
            color: AppColors.red,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: AppColors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AppColors.white,
                        strokeWidth: 2.2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: AppColors.white,
                      size: 20,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 50, this.photoUrl});
  final String name;
  final double size;
  final String? photoUrl;

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
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white.withValues(alpha: 0.30)),
      ),
      child: hasPhoto
          ? CachedImage(
              photoUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (context, error, stackTrace) => Text(
                initials,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.32,
                ),
              ),
            )
          : Text(
              initials,
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.32,
              ),
            ),
    );
  }
}

class _HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 22);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 22,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
