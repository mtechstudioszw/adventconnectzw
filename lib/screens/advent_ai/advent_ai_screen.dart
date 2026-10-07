import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../config/platform_flags.dart';
import '../../services/ai/ai_balance_service.dart';
import '../../services/ai/ai_chat_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/advent_ai_bubble.dart';
import '../../widgets/advent_ai_mark.dart';
import '../../widgets/screen_shell.dart';
import 'ai_gate_copy.dart';
import 'widgets/ai_markdown.dart';
import 'widgets/ai_gate_sheet.dart';

/// Advent AI.
///
/// One conversation at a time, with the member's history reachable from
/// the header. Deliberately NOT modelled on Advent Chat's screen: this
/// is a document you read, not a stream of short messages, and the answer
/// bubbles are wide and quiet rather than tight and alternating.
class AdventAiScreen extends StatefulWidget {
  const AdventAiScreen({super.key, this.conversationId});

  /// Resume a specific conversation. Null starts (or lazily creates) a
  /// new one — a conversation row is not written until the first send,
  /// so opening the screen and leaving costs nothing.
  final String? conversationId;

  @override
  State<AdventAiScreen> createState() => _AdventAiScreenState();
}

class _AdventAiScreenState extends State<AdventAiScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  final List<AiMessage> _messages = [];

  String? _conversationId;
  bool _loading = false;
  bool _sending = false;

  /// The answer being streamed. Held apart from [_messages] so a partial
  /// answer is never mistaken for a stored one — it is committed on
  /// success and discarded on failure.
  AiMessage? _streaming;

  /// Live only while an answer is streaming. Cancelled by the stop
  /// button, and again on dispose so leaving the screen mid-answer does
  /// not leave a socket open behind it.
  AiSendCancel? _cancel;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    // The app-wide bubble already refuses `/advent-ai` by route prefix.
    // This says it a second way, from the screen itself, because the
    // founder still saw the bubble here on 25 Aug 2026 and a mounted
    // screen is a fact where a router location is an inference.
    AdventAiBubble.suppress();
    AiBalanceService.refresh();
    if (_conversationId != null) _loadHistory();
  }

  @override
  void dispose() {
    AdventAiBubble.unsuppress();
    _cancel?.cancel();
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final page = await AiChatService.messages(_conversationId!);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page);
      });
      _jumpToEnd();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _followStream() {
    if (!_scroll.hasClients) return;
    // Only follow if the member is already near the bottom. Yanking the
    // view down while they are reading something further up is the
    // single most irritating thing a streaming chat can do.
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 160) {
      _scroll.jumpTo(pos.maxScrollExtent);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final balance = AiBalanceService.current;
    if (!balance.canUse) {
      _showGate(balance.reason, balance);
      return;
    }

    final cancel = AiSendCancel();
    setState(() {
      _sending = true;
      _cancel = cancel;
      _messages.add(AiMessage(role: 'user', content: text));
      _streaming = AiMessage(
        role: 'assistant',
        content: '',
        status: AiMessageStatus.pending,
      );
    });
    _controller.clear();
    _jumpToEnd();

    try {
      // Created lazily so an opened-and-abandoned screen leaves no row.
      _conversationId ??= await AiChatService.createConversation();

      await AiChatService.send(
        conversationId: _conversationId!,
        message: text,
        cancel: cancel,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() => _streaming!.content += delta);
          _followStream();
        },
      );

      if (!mounted) return;
      setState(() {
        final answer = _streaming!;
        // A stopped answer is KEPT, exactly as much of it as arrived.
        // The only thing thrown away is a stop that beat the first word,
        // which would otherwise leave an empty answer bubble sitting
        // under the question forever.
        if (cancel.isCancelled && answer.content.trim().isEmpty) {
          _streaming = null;
        } else {
          answer.status = AiMessageStatus.complete;
          _messages.add(answer);
          _streaming = null;
        }
        _sending = false;
        _cancel = null;
      });
      // A stopped answer never receives the final frame that carries the
      // authoritative balance, so it is re-read rather than left stale.
      AiBalanceService.refresh();
    } on AiSendException catch (e) {
      if (!mounted) return;
      setState(() {
        // The question comes back to the composer rather than being
        // stranded in a transcript above an error. Nothing was charged,
        // so nothing should look spent.
        _messages.removeLast();
        _streaming = null;
        _sending = false;
        _cancel = null;
        _controller.text = text;
      });
      _handleSendError(e.error);
    }
  }

  /// Stop the answer where it is. The unit stays spent — see
  /// [AiSendCancel] for why that is deliberate rather than an oversight.
  void _stop() => _cancel?.cancel();

  void _handleSendError(AiSendError error) {
    switch (error) {
      case AiSendError.outOfCredit:
        _showGate(AiGateReason.outOfFree, AiBalanceService.current);
      case AiSendError.freePoolClosed:
        _showGate(AiGateReason.freePoolClosed, AiBalanceService.current);
      case AiSendError.serviceSuspended:
        _showGate(AiGateReason.serviceSuspended, AiBalanceService.current);
      case AiSendError.blocked:
        _showGate(AiGateReason.blocked, AiBalanceService.current);
      case AiSendError.offline:
        _snack("You're offline. Check your connection and try again.");
      case AiSendError.rateLimited:
        _snack('That was quick — give it a moment and try again.');
      case AiSendError.tooLong:
        _snack('That question is a bit long. Try shortening it.');
      case AiSendError.unauthenticated:
        _snack('Please sign in again.');
      case AiSendError.providerFailed:
      case AiSendError.unknown:
        _snack('Advent AI could not answer just then. Please try again.');
    }
    // The balance is re-read either way: a refund has probably just
    // landed, and leaving a stale figure on screen makes it look as
    // though the member paid for the failure.
    AiBalanceService.refresh();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showGate(AiGateReason reason, AiBalance balance) {
    showAiGateSheet(
      context,
      AiGateCopy.of(
        reason,
        resetsOn: balance.resetsOn,
        used: balance.grant > 0 ? balance.grant - balance.remaining : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return FlatStatusBar(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              ScreenHero(
                title: 'Advent AI',
                tagline: 'Scripture, study and help with the app',
                fallbackRoute: '/home',
                trailing: ScreenHeroTrailing(
                  icon: Icons.history_rounded,
                  onTap: _openHistory,
                ),
              ),
              const _BalanceStrip(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty && _streaming == null
                        ? const _EmptyState()
                        : _transcript(palette),
              ),
              _Composer(
                controller: _controller,
                focusNode: _focus,
                sending: _sending,
                onSend: _send,
                onStop: _stop,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transcript(AppPalette palette) {
    final items = [..._messages, ?_streaming];
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
      itemCount: items.length,
      itemBuilder: (context, i) => _Turn(
        message: items[i],
        onCopy: () => _copy(items[i].content),
        onVerseTap: (ref) => context.push('/library'),
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('Copied');
  }

  Future<void> _openHistory() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => const _HistorySheet(),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _conversationId = chosen.isEmpty ? null : chosen;
      _messages.clear();
      _streaming = null;
    });
    if (_conversationId != null) _loadHistory();
  }
}

// ---------------------------------------------------------------------
//  Balance strip
// ---------------------------------------------------------------------

/// The member's remaining questions, and the way to buy more of them.
///
/// Transparency is the brief's rule (§27) and also the kindest design:
/// a member who can see "3 left" is never ambushed by a wall.
///
/// # Who sees what
///
/// **Free members always see both** — the count and an Upgrade button
/// (founder call, 25 Aug 2026). Ten questions a month is a figure worth
/// watching, and the only route to Premium from here used to be the
/// paywall sheet that appears once you have already been refused. Asking
/// somebody to upgrade at the moment you block them is the worst
/// possible time to ask; a quiet button they can reach whenever they
/// like is a better offer and a less resented one.
///
/// **Subscribers see the count only when it is running low**, and never
/// an Upgrade button — there is nothing to sell them, and a subscriber
/// with 480 remaining does not need a counter on their screen.
class _BalanceStrip extends StatelessWidget {
  const _BalanceStrip();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AiBalance>(
      valueListenable: AiBalanceService.balance,
      builder: (context, balance, _) {
        final canUpgrade = !balance.isPremium;
        // `grant`/`remaining` are both 0 before the first fetch lands.
        // Rendering "0 questions left" over an unknown balance would
        // announce a wall the member may not be behind.
        final known = balance.grant > 0 || balance.remaining > 0;
        final showCount = balance.isRunningLow || (canUpgrade && known);

        if (!showCount && !canUpgrade) return const SizedBox.shrink();

        final palette = context.palette;
        final n = balance.remaining;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(
              AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
          padding: const EdgeInsets.fromLTRB(
              AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
          decoration: BoxDecoration(
            color: palette.chipBg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  !showCount
                      ? 'Advent AI'
                      : n == 0
                          ? 'No questions left this month'
                          : '$n question${n == 1 ? '' : 's'} left this month',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: palette.textMuted),
                ),
              ),
              // Hidden on iOS: Premium has no In-App Purchase there.
              if (canUpgrade && !kHidePayments) const _UpgradeButton(),
            ],
          ),
        );
      },
    );
  }
}

/// Straight to the Premium screen.
///
/// Pushed on this screen's own navigator, so Premium arrives on top of
/// Advent AI and the back arrow returns the member to the question they
/// were part-way through asking.
class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: () => context.push('/premium'),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md, vertical: 6),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_upward_rounded,
                  size: 14, color: Colors.white),
              const SizedBox(width: AppSpace.xs),
              Text(
                'Upgrade',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Turn
// ---------------------------------------------------------------------

class _Turn extends StatelessWidget {
  const _Turn({
    required this.message,
    required this.onCopy,
    required this.onVerseTap,
  });

  final AiMessage message;
  final VoidCallback onCopy;
  final void Function(String) onVerseTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpace.lg, left: 48),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Text(
            message.content,
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
          ),
        ),
      );
    }

    final thinking = message.status == AiMessageStatus.pending &&
        message.content.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AdventAiBrand.icon,
                  size: 16, color: AppColors.goldAccent),
              const SizedBox(width: AppSpace.xs),
              Text(AdventAiBrand.name,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: palette.textMuted)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (thinking)
            const _Thinking()
          else
            AiMarkdown(text: message.content, onVerseTap: onVerseTap),
          if (message.status == AiMessageStatus.complete) ...[
            const SizedBox(height: AppSpace.sm),
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded,
                        size: 14, color: palette.textMuted),
                    const SizedBox(width: AppSpace.xs),
                    Text('Copy',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: palette.textMuted)),
                  ],
                ),
              ),
            ),
            // Under EVERY answer, not once at the top of the screen.
            // Founder rule, 25 Aug 2026 — see AdventAiBrand.disclaimer.
            AdventAiDisclaimer(color: palette.textMuted),
          ],
        ],
      ),
    );
  }
}

/// Three dots, because a bare spinner on a slow connection reads as
/// "broken" while this reads as "working".
class _Thinking extends StatefulWidget {
  const _Thinking();
  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = ((_c.value + i * 0.2) % 1.0);
          final lift = (t < 0.5 ? t : 1 - t) * 2;
          return Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Transform.translate(
              offset: Offset(0, -3 * lift),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.5 + 0.5 * lift),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Empty state
// ---------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  /// Openers that show what this is FOR. Both halves of its purpose are
  /// represented, so a member's first impression is not "another
  /// chatbot" but "this knows my Bible and my app".
  static const _suggestions = <String>[
    'What does the Bible say about forgiveness?',
    'Explain the Sabbath from Scripture',
    'Help me understand Daniel 2',
    'How do I create a post?',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.xl),
          Icon(AdventAiBrand.icon, size: 40, color: AppColors.goldAccent),
          const SizedBox(height: AppSpace.md),
          Text('Ask about Scripture, or about the app',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium.copyWith(color: palette.text)),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Advent AI can help you study the Bible and find your way '
            'around Adventist Super App. It is not a pastor, and it can '
            'be wrong — always check what matters against Scripture.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: AppSpace.xl),
          for (final s in _suggestions)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpace.sm),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: palette.divider),
              ),
              child: ListTile(
                title: Text(s,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: palette.text)),
                trailing: Icon(Icons.north_east_rounded,
                    size: 16, color: palette.textMuted),
                onTap: () {
                  final state = context
                      .findAncestorStateOfType<_AdventAiScreenState>();
                  state?._controller.text = s;
                  state?._focus.requestFocus();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Composer
// ---------------------------------------------------------------------

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.md),
      decoration: BoxDecoration(
        color: palette.scaffoldBg,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              // Mirrors ai_max_request_chars server-side. The server is
              // still authoritative — this only spares the member typing
              // something that would be refused.
              maxLength: 2000,
              buildCounter: (_, {required currentLength, required isFocused,
                      required maxLength}) =>
                  null,
              decoration: InputDecoration(
                hintText: 'Ask Advent AI…',
                filled: true,
                fillColor: palette.inputFill,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md, vertical: AppSpace.sm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          _SendButton(sending: sending, onSend: onSend, onStop: onStop),
        ],
      ),
    );
  }
}

/// Send, and — while an answer is streaming — **stop**.
///
/// # Why this is a button and not a spinner
///
/// It used to go flat grey with a spinner in it: a disabled control that
/// told the member to wait. Every assistant they have used does the
/// opposite — the send button becomes a stop button, and pressing it
/// ends the answer where it is (founder call, 25 Aug 2026: "when Advent
/// AI is responding the send button should turn into a generating icon
/// that, if you click it, stops the response midway — like Claude,
/// ChatGPT").
///
/// The ring keeps turning around the square so the control still reads
/// as "working" at a glance; the square is what says it can be pressed.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.sending,
    required this.onSend,
    required this.onStop,
  });

  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 44,
      height: 44,
      child: Semantics(
        button: true,
        label: sending ? 'Stop generating' : 'Send',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: sending ? onStop : onSend,
            child: Container(
              decoration: BoxDecoration(
                gradient: sending ? null : AppColors.primaryGradient,
                color: sending ? palette.chipBg : null,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: sending
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primaryBlue,
                              ),
                            ),
                          ),
                          Icon(Icons.stop_rounded,
                              size: 16, color: palette.text),
                        ],
                      )
                    : const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  History
// ---------------------------------------------------------------------

/// Returns the chosen conversation id, or an empty string for "new".
class _HistorySheet extends StatefulWidget {
  const _HistorySheet();
  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late Future<List<AiConversation>> _future = AiChatService.conversations();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          const SizedBox(height: AppSpace.md),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: AppColors.primaryBlue),
            title: Text('New conversation',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.primaryBlue)),
            onTap: () => Navigator.of(context).pop(''),
          ),
          Divider(height: 1, color: palette.divider),
          Expanded(
            child: FutureBuilder<List<AiConversation>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return Center(
                    child: Text('No conversations yet',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: palette.textMuted)),
                  );
                }
                return ListView.builder(
                  controller: scroll,
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return Dismissible(
                      key: ValueKey(c.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: AppColors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: AppSpace.lg),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        await AiChatService.deleteConversation(c.id);
                        if (mounted) {
                          setState(() =>
                              _future = AiChatService.conversations());
                        }
                      },
                      child: ListTile(
                        title: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: palette.text),
                        ),
                        subtitle: c.preview == null
                            ? null
                            : Text(
                                c.preview!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: palette.textMuted),
                              ),
                        onTap: () => Navigator.of(context).pop(c.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}