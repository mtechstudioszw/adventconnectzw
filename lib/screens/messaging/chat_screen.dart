import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/message_model.dart';
import '../../services/auth_service.dart';
import '../../services/messaging_service.dart';
import '../../services/presence_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cached_image.dart';
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
    _pending.removeWhere((p) => serverIds.contains(p.id));
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
  Future<void> _showMessageActions(Message m, bool isMine) async {
    HapticFeedback.selectionClick();
    final hasText = (m.content.trim().isNotEmpty) && m.messageType != 'voice';
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
                  color: const Color.fromRGBO(26, 26, 46, 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
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
              if (isMine)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: AppColors.red),
                  title: Text('Delete for everyone',
                      style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.red,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Removes the message from this chat for both of you.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
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
    switch (action) {
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
        // Optimistic removal so the bubble vanishes immediately; the
        // realtime stream will replay the DELETE for the other party.
        setState(() {
          _serverMessages.removeWhere((x) => x.id == m.id);
          _pending.removeWhere((x) => x.id == m.id);
        });
        try {
          await MessagingService.deleteMessage(m.id);
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

  // Voice-note recording state. We use a single AudioRecorder per
  // chat screen and tear it down in dispose().
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? _activeRecordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;
  bool _hasText = false;

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
    _bootstrap();
    _resolveConversation();
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
  }

  void _wirePresence() {
    final otherId = _conversation?.otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    // Re-fetch last seen periodically so the header stays fresh even
    // if the user has the chat open for a while (presence sync only
    // fires on join/leave; long-running idle doesn't bump it).
    unawaited(_refreshLastSeen(otherId));
    unawaited(_refreshBlockedState(otherId));
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

  Future<void> _refreshLastSeen(String otherId) async {
    final t = await PresenceService.fetchLastSeen(otherId);
    if (!mounted || t == null) return;
    setState(() => _otherLastSeen = t);
  }

  @override
  void dispose() {
    _stream?.cancel();
    _typingExpiry?.cancel();
    _typingThrottle?.cancel();
    _recordingTimer?.cancel();
    _lastSeenRefreshTimer?.cancel();
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
      _scrollToBottom();
    }
    try {
      final list =
          await MessagingService.fetchMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _applyServerMessages(list);
        _loading = false;
      });
      _scrollToBottom();
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
        setState(() => _recordingElapsed =
            DateTime.now().difference(_recordingStartedAt!));
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
      if (!isRlsBlock) {
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
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

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    final me = AuthService.currentUser?.id ?? '';

    // Optimistic UI — show the bubble immediately in the _pending
    // list. Use _optimisticTimestamp() so the new bubble is GUARANTEED
    // to sort after everything else on screen (previously the bubble
    // could briefly render above older messages if client/server
    // clocks disagreed by a few hundred ms — what the user saw as
    // "voice note jumps from top to bottom").
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: me,
      senderName: 'You',
      content: text,
      createdAt: _optimisticTimestamp(),
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
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final canonical = await MessagingService.sendMessage(
        conversationId: widget.conversationId,
        content: text,
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
        return; // bubble stays, single tick stays, no toast
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
          _buildHeader(),
          Expanded(child: _buildBody()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final convo = _conversation;
    final name = convo?.otherUserName ?? 'Conversation';
    final photoUrl = convo?.otherUserPhotoUrl;
    final otherUserId = convo?.otherUserId;
    final canOpenProfile =
        otherUserId != null && otherUserId.isNotEmpty && !(convo?.isSelfChat ?? false);
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
                    onTap: canOpenProfile
                        ? () => showChatContactSheet(
                              context,
                              userId: otherUserId,
                              fallbackName: name,
                              fallbackPhotoUrl: photoUrl,
                            )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          _Avatar(name: name, size: 40, photoUrl: photoUrl),
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
                                  child: _buildPresenceSubtitle(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
        }
      },
      itemBuilder: (context) => [
        if (canOpenProfile)
          const PopupMenuItem(
            value: 'profile',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_outline, color: AppColors.textDark),
              title: Text('View contact'),
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
            leading: Icon(Icons.cleaning_services_outlined,
                color: AppColors.textDark),
            title: Text('Clear chat'),
          ),
        ),
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
              color: const Color.fromRGBO(26, 26, 46, 0.6),
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
                  color: const Color.fromRGBO(26, 26, 46, 0.6),
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
          final isMine = m.senderId == currentUserId;
          // Per user request: every message gets its own timestamp,
          // not just the last one in a sender-grouped cluster. This
          // matches how WhatsApp actually renders — each bubble has
          // its own time underneath, not a single trailing stamp.
          final showStamp = true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _showMessageActions(m, isMine),
                  child: _MessageBubble(message: m, isMine: isMine),
                ),
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
                            color: const Color.fromRGBO(26, 26, 46, 0.45),
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
                          Icon(
                            m.id.startsWith('pending-')
                                ? Icons.access_time
                                : (m.deliveredAt != null || m.read
                                    ? Icons.done_all
                                    : Icons.done),
                            size: 13,
                            color: m.read
                                ? AppColors.primaryBlue
                                : const Color.fromRGBO(26, 26, 46, 0.45),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
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
                  const Icon(Icons.block,
                      size: 16, color: AppColors.textDark),
                  const SizedBox(width: 8),
                  Text(
                    'You blocked this contact. Tap to unblock.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textDark.withValues(alpha: 0.7),
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

  Widget _buildComposeBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.palette.inputFill,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color.fromRGBO(26, 26, 46, 0.06),
              ),
            ),
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: 'Write a message',
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: const Color.fromRGBO(26, 26, 46, 0.5),
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
                    color: AppColors.textDark,
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    if (message.messageType == 'voice' &&
        (message.mediaUrl ?? '').isNotEmpty) {
      return _VoiceBubble(message: message, isMine: isMine);
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
        child: Text(
          message.content,
          style: AppTextStyles.bodyMedium.copyWith(
            color: isMine ? AppColors.white : AppColors.textDark,
            fontSize: 14.5,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;

  bool _loading = false;
  bool _playing = false;
  String? _signedUrl;
  Duration _position = Duration.zero;
  Duration? _total;

  @override
  void initState() {
    super.initState();
    final declared = widget.message.mediaDurationSeconds;
    if (declared != null && declared > 0) {
      _total = Duration(seconds: declared);
    }
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
      if (s == PlayerState.completed) {
        setState(() => _position = Duration.zero);
      }
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_signedUrl == null) {
        setState(() => _loading = true);
        final url = await MessagingService.signedVoiceUrl(
          widget.message.mediaUrl!,
        );
        if (!mounted) return;
        _signedUrl = url;
      }
      await _player.play(UrlSource(_signedUrl!));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not play this voice note.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.isMine;
    final maxWidth = MediaQuery.of(context).size.width * 0.74;
    final fg = isMine ? AppColors.white : AppColors.textDark;
    final muted = isMine
        ? AppColors.white.withValues(alpha: 0.7)
        : const Color.fromRGBO(26, 26, 46, 0.55);
    final trackBg = isMine
        ? AppColors.white.withValues(alpha: 0.25)
        : const Color.fromRGBO(26, 26, 46, 0.10);
    final total = _total ?? const Duration(seconds: 1);
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 220),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _toggle,
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
                child: _loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isMine ? AppColors.white : AppColors.primaryBlue,
                        ),
                      )
                    : Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: isMine ? AppColors.white : AppColors.primaryBlue,
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: trackBg,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(_playing || _position > Duration.zero
                            ? _position
                            : total),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Icon(Icons.mic_rounded, size: 14, color: muted),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
        border: Border.all(
          color: const Color.fromRGBO(26, 26, 46, 0.08),
        ),
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
              color: busy
                  ? const Color.fromRGBO(26, 26, 46, 0.4)
                  : AppColors.primaryBlue,
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
