import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/message_model.dart';
import '../../services/auth_service.dart';
import '../../services/messaging_service.dart';
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
    _bootstrap();
  }

  @override
  void dispose() {
    _stream?.cancel();
    _typingExpiry?.cancel();
    _typingThrottle?.cancel();
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
  void _onInputChanged(String _) {
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
    setState(() => _sending = true);
    try {
      await MessagingService.sendMessage(
        conversationId: widget.conversationId,
        content: text,
      );
      _inputController.clear();
    } catch (_) {
      if (!mounted) return;
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
                        child: _otherTyping
                            ? Text(
                                'typing…',
                                key: const ValueKey('typing'),
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.white,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : Text(
                                'Active member',
                                key: const ValueKey('idle'),
                                style: AppTextStyles.labelSmall.copyWith(
                                  color:
                                      AppColors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
          child: Row(
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
              _SendButton(busy: _sending, onTap: _send),
            ],
          ),
        ),
      ),
    );
  }

  String _stamp(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
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
