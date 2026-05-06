import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/message_model.dart';
import '../../services/auth_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  List<Conversation> _conversations = [];
  bool _loading = true;
  String? _error;

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
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await MessagingService.fetchConversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load messages. Pull to retry.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGrey,
      body: Column(
        children: [
          _buildHero(),
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
                child: _buildList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return ClipPath(
      clipper: _HeroClipper(),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.goNamed('home'),
                    ),
                    const Spacer(),
                    _CircleIconButton(
                      icon: Icons.search,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MESSAGES',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your conversations',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: AppColors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
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

  Widget _buildList() {
    if (_loading && _conversations.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }
    if (_error != null && _conversations.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                    color: Color.fromRGBO(26, 26, 46, 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_conversations.isEmpty) {
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
                    'No conversations yet',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reach out from a profile or church page to start chatting.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color.fromRGBO(26, 26, 46, 0.6),
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
    final currentUserId = AuthService.currentUser?.id ?? '';
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = _conversations[i];
        return _ConversationTile(
          conversation: c,
          isLastFromMe: c.lastSenderId == currentUserId,
          onTap: () async {
            await context.pushNamed(
              'chat',
              pathParameters: {'id': c.id},
              extra: c,
            );
            if (mounted) _bootstrap();
          },
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isLastFromMe,
    required this.onTap,
  });

  final Conversation conversation;
  final bool isLastFromMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = conversation.unreadCount > 0 && !isLastFromMe;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
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
              _Avatar(name: conversation.otherUserName),
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
                        const SizedBox(width: 6),
                        Text(
                          _shortTime(conversation.lastMessageAt),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: unread
                                ? AppColors.primaryBlue
                                : const Color.fromRGBO(26, 26, 46, 0.55),
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
                        if (isLastFromMe) ...[
                          const Icon(
                            Icons.done_all,
                            size: 14,
                            color: Color.fromRGBO(26, 26, 46, 0.5),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            conversation.lastMessage.isEmpty
                                ? 'Say hello'
                                : conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: unread
                                  ? AppColors.textDark
                                  : const Color.fromRGBO(26, 26, 46, 0.6),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

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
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
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

class _HeroClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 24);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 24,
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
