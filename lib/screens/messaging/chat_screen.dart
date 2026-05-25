import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
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
import '../../theme/app_text_styles.dart';

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
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

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
    _enableScreenshotBlock();
    _bootstrap();
    _wirePresence();
  }

  void _wirePresence() {
    final otherId = widget.initialConversation?.otherUserId;
    if (otherId == null || otherId.isEmpty) return;
    // Re-fetch last seen periodically so the header stays fresh even
    // if the user has the chat open for a while (presence sync only
    // fires on join/leave; long-running idle doesn't bump it).
    unawaited(_refreshLastSeen(otherId));
    _lastSeenRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshLastSeen(otherId)),
    );
    _presenceListener = () {
      if (mounted) setState(() {});
    };
    PresenceService.onChange.addListener(_presenceListener!);
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
    _disableScreenshotBlock();
    super.dispose();
  }

  // TODO: Re-wire screenshot blocking once a working FLAG_SECURE package
  // is back in pubspec.yaml. Stubbed out for now so the build doesn't
  // pull AGP 7.3.0 over a slow network.
  void _enableScreenshotBlock() {
    if (!Platform.isAndroid) return;
  }

  void _disableScreenshotBlock() {
    if (!Platform.isAndroid) return;
  }

  Future<void> _bootstrap() async {
    try {
      final list =
          await MessagingService.fetchMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
      });
      _scrollToBottom();
      // Mark anything they sent us as read — best-effort, fire and forget.
      unawaited(MessagingService.markConversationRead(widget.conversationId));
      _stream =
          MessagingService.streamMessages(widget.conversationId).listen((list) {
        if (!mounted) return;
        setState(() => _messages = list);
        _scrollToBottom();
        // Any new inbound rows? Mark them read so the sender sees the
        // double-tick in near-real time.
        final me = AuthService.currentUser?.id;
        if (me != null &&
            list.any((m) => m.senderId != me && !m.read)) {
          unawaited(
            MessagingService.markConversationRead(widget.conversationId),
          );
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
    setState(() => _sending = true);
    try {
      await MessagingService.sendVoiceNote(
        conversationId: widget.conversationId,
        localFilePath: path,
        durationSeconds: duration,
      );
    } catch (_) {
      if (mounted) _toast('Could not send voice note. Please try again.');
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

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    final me = AuthService.currentUser?.id ?? '';

    // Optimistic UI — show the bubble immediately so the user gets
    // feedback even on a slow network. Previously `_send` awaited the
    // round-trip silently, so tapping the send button "did nothing"
    // until the server acknowledged. We give the local message a
    // temporary negative id; the stream subscription replaces it
    // with the real row when it arrives a moment later.
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: me,
      senderName: 'You',
      content: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, optimistic];
      _sending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      await MessagingService.sendMessage(
        conversationId: widget.conversationId,
        content: text,
      );
      // Stream picks up the real row and replaces _messages — the
      // optimistic one drops out because its temp id won't be in
      // the server response. Nothing else to do here.
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
    } catch (_) {
      if (!mounted) return;
      // Send failed — roll back the optimistic bubble and put the
      // text back in the input so the user can retry.
      setState(() {
        _messages =
            _messages.where((m) => m.id != tempId).toList(growable: false);
      });
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
      backgroundColor: AppColors.lightGrey,
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
    final name = widget.initialConversation?.otherUserName ?? 'Conversation';
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
                _Avatar(name: name, size: 40),
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
                        duration: const Duration(milliseconds: 220),
                        child: _buildPresenceSubtitle(),
                      ),
                    ],
                  ),
                ),
                _CircleIconButton(
                  icon: Icons.more_vert,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          final showStamp = i == _messages.length - 1 ||
              _messages[i + 1].createdAt
                      .difference(m.createdAt)
                      .inMinutes >
                  4 ||
              _messages[i + 1].senderId != m.senderId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                _MessageBubble(message: m, isMine: isMine),
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
                          Icon(
                            m.read ? Icons.done_all : Icons.done,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
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
              color: AppColors.lightGrey,
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
    final otherId = widget.initialConversation?.otherUserId;
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
          color: isMine ? null : AppColors.white,
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
          color: isMine ? null : AppColors.white,
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
        color: AppColors.lightGrey,
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
  const _Avatar({required this.name, this.size = 50});
  final String name;
  final double size;

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
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white.withValues(alpha: 0.30)),
      ),
      child: Text(
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
