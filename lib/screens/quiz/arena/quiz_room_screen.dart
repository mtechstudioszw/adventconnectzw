import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/quiz_match.dart';
import '../../../models/quiz_question_model.dart';
import '../../../models/quiz_room.dart';
import '../../../services/quiz_match_service.dart';
import '../../../services/quiz_music.dart';
import '../../../services/quiz_room_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/user_avatar.dart';
import 'arena_theme.dart';
import 'widgets/answer_tile.dart';
import 'widgets/arena_hud.dart';
import 'widgets/arena_scaffold.dart';

/// Live quiz for 2 to 5 players (owner, 3 Nov 2026: "what happens when
/// 5 people live match").
///
/// One screen, four moments, all driven by the server's room state:
///  * **Lobby** — the room code (big, to read aloud), who's in (five
///    seats), invite friends, and Start for the host.
///  * **Countdown** — 3, 2, 1 on every phone at once (server clock).
///  * **Question → reveal** — tap to lock in; when everyone is in or the
///    clock runs out, the answer shows and the board re-orders with what
///    each player just earned.
///  * **Podium** — top three on steps, everyone else below.
///
/// The phone never knows the answer early: the server holds the key and
/// marks every tap. Each phone ticks the room about once a second, and
/// that is what moves the game on — so if one phone drops, the rest carry
/// on and the dropped player is shown as "left".
class QuizRoomScreen extends StatefulWidget {
  const QuizRoomScreen({super.key, required this.room});

  final QuizRoom room;

  /// Create a room and open it.
  static Future<void> host(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final room = await QuizRoomService.create();
      await nav.push(
        MaterialPageRoute<void>(builder: (_) => QuizRoomScreen(room: room)),
      );
    } on QuizRoomError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't create a room. Try again.")),
      );
    }
  }

  /// Join with a code (typed, or from an invite) and open the room.
  static Future<void> joinCode(BuildContext context, String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final room = await QuizRoomService.join(code);
      await nav.push(
        MaterialPageRoute<void>(builder: (_) => QuizRoomScreen(room: room)),
      );
    } on QuizRoomError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't join that room. Try again.")),
      );
    }
  }

  /// "Join with a code" sheet.
  static Future<void> askCode(BuildContext context) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinCodeDialog(),
    );
    if (code == null || !context.mounted) return;
    await joinCode(context, code);
  }

  /// The lobby and podium on their own, for layout tests (no network).
  @visibleForTesting
  static Widget debugLobby(QuizRoom room, {bool isHost = true}) =>
      _Lobby(room: room, isHost: isHost, starting: false, onStart: () {});

  @visibleForTesting
  static Widget debugBoard(QuizRoom room) => _LiveBoard(room: room);

  @visibleForTesting
  static Widget debugPodium(QuizRoom room) =>
      _Podium(room: room, onDone: () {});

  @override
  State<QuizRoomScreen> createState() => _QuizRoomScreenState();
}

class _QuizRoomScreenState extends State<QuizRoomScreen>
    with TickerProviderStateMixin {
  late QuizRoom _room = widget.room;
  Timer? _poll;
  Timer? _frame;
  bool _ticking = false;
  bool _starting = false;
  int? _chosen; // what I tapped on the current question, before the server
  int _shownIndex = -1; // question the tiles were last animated in for
  bool _wasRevealing = false;
  int _lastCountBeat = -1;
  int _lastTickSecond = -1;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _clock = AnimationController(
    vsync: this,
    value: 1,
  );

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    QuizSfx.init();
    unawaited(QuizMusic.start());
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _tick());
    // The ring and countdown read the server clock; repaint ~10x/s.
    _frame = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      _clock.value = _room.remainingFraction;
      _beats();
      if (_room.inCountdown || _room.isActive) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _frame?.cancel();
    _entrance.dispose();
    _clock.dispose();
    unawaited(QuizMusic.stop());
    super.dispose();
  }

  Future<void> _tick() async {
    if (_ticking || !mounted) return;
    if (_room.isComplete || _room.isCancelled) {
      _poll?.cancel();
      return;
    }
    _ticking = true;
    try {
      _apply(await QuizRoomService.tick(_room.id));
    } on QuizRoomError catch (e) {
      if (e.isFatal && mounted) {
        _poll?.cancel();
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      // A dropped tick is fine; the next one catches up.
    } finally {
      _ticking = false;
    }
  }

  void _apply(QuizRoom next) {
    if (!mounted) return;
    final movedOn = next.currentIndex != _room.currentIndex;
    final justStarted = _room.isLobby && next.isActive;
    final justRevealed = !_wasRevealing && next.isRevealing;
    final justFinished = !_room.isComplete && next.isComplete;
    setState(() {
      _room = next;
      if (movedOn || justStarted) _chosen = null;
      // The server's word wins over the optimistic tap.
      if (next.myChoice != null) _chosen = next.myChoice;
    });
    if (justStarted) QuizSfx.play(QuizSound.go);
    if (justRevealed) _onReveal();
    _wasRevealing = next.isRevealing;
    if (next.isActive &&
        !next.inCountdown &&
        _shownIndex != next.currentIndex) {
      _shownIndex = next.currentIndex;
      _entrance.forward(from: 0);
    }
    if (justFinished) QuizSfx.play(QuizSound.finish);
  }

  void _onReveal() {
    final me = _room.me;
    if (me == null || me.lastCorrect == null) return;
    if (me.lastCorrect!) {
      QuizSfx.correct();
    } else {
      QuizSfx.wrong();
    }
  }

  void _beats() {
    if (_room.inCountdown) {
      final s = _room.countdownSeconds;
      if (s != _lastCountBeat && s > 0) {
        _lastCountBeat = s;
        QuizSfx.countBeat();
      }
      return;
    }
    if (_room.isActive && !_room.isRevealing && _chosen == null) {
      final left = _room.secondsLeft;
      if (left <= 3 && left > 0 && left != _lastTickSecond) {
        _lastTickSecond = left;
        QuizSfx.play(QuizSound.tick);
      }
    }
  }

  Future<void> _answer(int i) async {
    if (_chosen != null || _room.isRevealing || _room.inCountdown) return;
    QuizSfx.tap();
    setState(() => _chosen = i);
    try {
      _apply(
        await QuizRoomService.answer(
          roomId: _room.id,
          index: _room.currentIndex,
          choice: i,
        ),
      );
    } catch (_) {
      // "Question has moved on" etc. — the next tick shows the truth.
    }
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      _apply(await QuizRoomService.start(_room.id));
    } on QuizRoomError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _leave() async {
    if (_room.isActive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave the game?'),
          content: const Text(
            'The others carry on without you, and this game won\'t count '
            'for you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _poll?.cancel();
    if (!_room.isComplete) unawaited(QuizRoomService.leave(_room.id));
    if (mounted) Navigator.of(context).pop();
  }

  AnswerTileState _stateFor(int index) {
    final reveal = _room.revealedIndex;
    if (!_room.isRevealing || reveal == null) {
      return _chosen == index ? AnswerTileState.selected : AnswerTileState.idle;
    }
    if (index == reveal) {
      return _chosen == index
          ? AnswerTileState.correct
          : AnswerTileState.revealed;
    }
    if (_chosen == index) return AnswerTileState.wrong;
    return AnswerTileState.dimmed;
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_room.isLobby) {
      body = _Lobby(
        room: _room,
        isHost: _room.isHost(_uid),
        starting: _starting,
        onStart: _start,
      );
    } else if (_room.isCancelled) {
      body = const _Notice(text: 'This room was closed.');
    } else if (_room.isComplete) {
      body = _Podium(room: _room, onDone: _leave);
    } else if (_room.inCountdown) {
      body = _Countdown(seconds: _room.countdownSeconds);
    } else {
      body = _questionView();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: ArenaScaffold(
        title: _room.isLobby ? 'Live room' : null,
        onClose: _leave,
        showMute: !_room.isLobby,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: KeyedSubtree(
            key: ValueKey(
              _room.isActive && !_room.inCountdown ? 'play' : _room.status,
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _questionView() {
    final q = _room.question;
    if (q == null) {
      return const Center(
        child: CircularProgressIndicator(color: ArenaTheme.gold),
      );
    }
    final locked = _chosen != null || _room.isRevealing;
    final waitingOn = _room.present.length - _room.answeredCount;
    return Column(
      children: [
        _LiveBoard(room: _room),
        const SizedBox(height: 8),
        RoundProgress(index: _room.currentIndex, total: _room.questionCount),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: TimerRing(
                    remaining: _clock,
                    totalSeconds: _room.secondsPerQuestion,
                    frozen: locked,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: ArenaTheme.glass,
                    borderRadius: ArenaTheme.cardRadius,
                    border: Border.all(color: ArenaTheme.glassBorder),
                    boxShadow: ArenaTheme.panelShadow,
                  ),
                  child: Text(
                    q.question,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: ArenaTheme.textOnNavy,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnswerTile(
                      label: q.options[i],
                      letter: String.fromCharCode(65 + i),
                      state: _stateFor(i),
                      entrance: _entrance,
                      onTap: locked ? null : (_) => _answer(i),
                    ),
                  ),
                if (_chosen != null && !_room.isRevealing && waitingOn > 0)
                  Text(
                    'Locked in · waiting for $waitingOn more',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ArenaTheme.textFaintOnNavy,
                    ),
                  ),
                if (_room.isRevealing && (q.reference ?? '').isNotEmpty)
                  Text(
                    q.reference!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: ArenaTheme.textMutedOnNavy,
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

// ---------------------------------------------------------------- lobby

class _Lobby extends StatelessWidget {
  const _Lobby({
    required this.room,
    required this.isHost,
    required this.starting,
    required this.onStart,
  });

  final QuizRoom room;
  final bool isHost;
  final bool starting;
  final VoidCallback onStart;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: room.code));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Room code copied')));
  }

  void _share() {
    Share.share(
      'Join my live Bible quiz on Adventist Super App. '
      'Open Quiz → Play with friends → Join with a code, and enter '
      '${room.code}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final players = room.present;
    final canStart = isHost && players.length >= 2 && !starting;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'ROOM CODE',
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(
            color: ArenaTheme.textFaintOnNavy,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _copy(context),
          child: Text(
            '${room.code.substring(0, 3)} ${room.code.substring(3)}',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(
              color: ArenaTheme.gold,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Friends join from Quiz → Play with friends → Join with a code.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: ArenaTheme.textMutedOnNavy,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _GlassButton(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Invite',
                onTap: room.isFull
                    ? null
                    : () => _InviteSheet.show(context, room),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GlassButton(
                icon: Icons.ios_share_rounded,
                label: 'Share code',
                onTap: _share,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'PLAYERS ${players.length}/${QuizRoom.maxPlayers}',
          style: AppTextStyles.labelSmall.copyWith(
            color: ArenaTheme.textFaintOnNavy,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < QuizRoom.maxPlayers; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: i < players.length
                ? _Seat(
                    player: players[i],
                    host: players[i].userId == room.hostId,
                  )
                : const _EmptySeat(),
          ),
        const SizedBox(height: 16),
        if (isHost)
          _StartButton(
            enabled: canStart,
            busy: starting,
            label: players.length < 2
                ? 'Waiting for players…'
                : 'Start with ${players.length} players',
            onTap: onStart,
          )
        else
          Text(
            'Waiting for the host to start…',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: ArenaTheme.textMutedOnNavy,
            ),
          ),
        const SizedBox(height: 10),
        Text(
          '10 questions · 15 seconds each · faster right answers score more',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(
            color: ArenaTheme.textFaintOnNavy,
          ),
        ),
      ],
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.player, required this.host});

  final QuizRoomPlayer player;
  final bool host;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: player.isMe ? ArenaTheme.glassStrong : ArenaTheme.glass,
        borderRadius: ArenaTheme.tileRadius,
        border: Border.all(
          color: player.isMe
              ? ArenaTheme.glassBorderActive
              : ArenaTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          UserAvatar(photoUrl: player.photoUrl, size: 34, name: player.name),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              player.isMe ? '${player.name} (you)' : player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ArenaTheme.textOnNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (host)
            Text(
              'HOST',
              style: AppTextStyles.labelSmall.copyWith(
                color: ArenaTheme.gold,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: ArenaTheme.tileRadius,
        border: Border.all(color: ArenaTheme.glassBorder),
      ),
      child: Text(
        'Open seat',
        style: AppTextStyles.bodySmall.copyWith(
          color: ArenaTheme.textFaintOnNavy,
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: ArenaTheme.glass,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ArenaTheme.glassBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: ArenaTheme.textOnNavy),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w700,
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
}

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.enabled,
    required this.busy,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: ArenaTheme.blueGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled ? ArenaTheme.glow(const Color(0xFF1565C0)) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: AppTextStyles.buttonText.copyWith(
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Invite people who have a quiz profile; online first.
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.room});

  final QuizRoom room;

  static Future<void> show(BuildContext context, QuizRoom room) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: ArenaTheme.canvasLift,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _InviteSheet(room: room),
      );

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  List<QuizPlayer>? _players;
  final Set<String> _sent = {};
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await QuizMatchService.players(
      query: _query.isEmpty ? null : _query,
    );
    if (mounted) setState(() => _players = list);
  }

  Future<void> _invite(QuizPlayer p) async {
    setState(() => _sent.add(p.userId));
    try {
      await QuizRoomService.invite(widget.room.id, p.userId);
    } on QuizRoomError catch (e) {
      if (!mounted) return;
      setState(() => _sent.remove(p.userId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inRoom = {for (final p in widget.room.players) p.userId};
    final list = (_players ?? const <QuizPlayer>[])
        .where((p) => !inRoom.contains(p.userId))
        .toList();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ArenaTheme.glassBorderActive,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: TextField(
                style: const TextStyle(color: ArenaTheme.textOnNavy),
                decoration: InputDecoration(
                  hintText: 'Search players',
                  hintStyle: const TextStyle(color: ArenaTheme.textFaintOnNavy),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: ArenaTheme.textMutedOnNavy,
                  ),
                  filled: true,
                  fillColor: ArenaTheme.glass,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) {
                  _query = v.trim();
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _load);
                },
              ),
            ),
            Expanded(
              child: _players == null
                  ? const Center(
                      child: CircularProgressIndicator(color: ArenaTheme.gold),
                    )
                  : list.isEmpty
                  ? Center(
                      child: Text(
                        'No players found. Share the code instead.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ArenaTheme.textMutedOnNavy,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final p = list[i];
                        final sent = _sent.contains(p.userId);
                        return ListTile(
                          leading: UserAvatar(
                            photoUrl: p.photoUrl,
                            size: 38,
                            name: p.name,
                          ),
                          title: Text(
                            p.name,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: ArenaTheme.textOnNavy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            p.isOnline ? 'Online now' : 'Gets a notification',
                            style: AppTextStyles.caption.copyWith(
                              color: p.isOnline
                                  ? ArenaTheme.correctOnNavy
                                  : ArenaTheme.textFaintOnNavy,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: sent ? null : () => _invite(p),
                            child: Text(sent ? 'Invited' : 'Invite'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- in the game

class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Get ready',
            style: AppTextStyles.titleMedium.copyWith(
              color: ArenaTheme.textMutedOnNavy,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, a) => ScaleTransition(
              scale: Tween(begin: 1.6, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Text(
              '${seconds.clamp(1, 3)}',
              key: ValueKey(seconds),
              style: AppTextStyles.headlineLarge.copyWith(
                color: ArenaTheme.gold,
                fontSize: 96,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everyone in the room on one strip: avatar, score, and a dot that lights
/// when they've locked in. During the reveal each shows what they just
/// earned.
class _LiveBoard extends StatelessWidget {
  const _LiveBoard({required this.room});

  final QuizRoom room;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final p in room.players)
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: p.left ? 0.4 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: 2,
                              color: p.isMe
                                  ? ArenaTheme.gold
                                  : ArenaTheme.glassBorder,
                            ),
                          ),
                          child: UserAvatar(
                            photoUrl: p.photoUrl,
                            size: 36,
                            name: p.name,
                          ),
                        ),
                        if (!room.isRevealing && p.answered && !p.left)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: ArenaTheme.canvasTop,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.isMe ? 'You' : p.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: ArenaTheme.textMutedOnNavy,
                        fontSize: 11,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        room.isRevealing && (p.lastPoints ?? 0) > 0
                            ? '+${p.lastPoints}'
                            : '${p.points}',
                        key: ValueKey('${p.points}-${room.isRevealing}'),
                        style: AppTextStyles.labelLarge.copyWith(
                          color: room.isRevealing && (p.lastPoints ?? 0) > 0
                              ? ArenaTheme.correctOnNavy
                              : ArenaTheme.textOnNavy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- podium

class _Podium extends StatelessWidget {
  const _Podium({required this.room, required this.onDone});

  final QuizRoom room;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final ranked = room.players;
    final me = room.me;
    final myPlace = me == null ? null : room.placeOf(me);
    final top = ranked.take(3).toList();
    // Classic podium order: 2nd, 1st, 3rd.
    final order = [
      if (top.length > 1) top[1],
      if (top.isNotEmpty) top[0],
      if (top.length > 2) top[2],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          myPlace == 1
              ? 'You won!'
              : myPlace == null
              ? 'Game over'
              : 'You came ${_ordinal(myPlace)}',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineMedium.copyWith(
            color: myPlace == 1 ? ArenaTheme.gold : ArenaTheme.textOnNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your points count on this week\'s leaderboard.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: ArenaTheme.textMutedOnNavy,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          // 1st place: trophy 26 + avatar 52 + name + points + step 110.
          height: 260,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in order)
                Expanded(
                  child: _Step(player: p, place: room.placeOf(p)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final p in ranked.skip(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RankRow(place: room.placeOf(p), player: p),
          ),
        if (room.review.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            'YOUR ANSWERS',
            style: AppTextStyles.labelSmall.copyWith(
              color: ArenaTheme.gold,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in room.review)
            if (item.index < room.questions.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReviewCard(
                  number: item.index + 1,
                  question: room.questions[item.index],
                  item: item,
                ),
              ),
        ],
        const SizedBox(height: 18),
        _StartButton(enabled: true, busy: false, label: 'Done', onTap: onDone),
      ],
    );
  }

  static String _ordinal(int n) => switch (n) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => '${n}th',
  };
}

class _Step extends StatelessWidget {
  const _Step({required this.player, required this.place});

  final QuizRoomPlayer player;
  final int place;

  @override
  Widget build(BuildContext context) {
    final height = switch (place) {
      1 => 110.0,
      2 => 80.0,
      _ => 60.0,
    };
    final first = place == 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (first)
            const Icon(
              Icons.emoji_events_rounded,
              color: ArenaTheme.gold,
              size: 26,
            ),
          UserAvatar(
            photoUrl: player.photoUrl,
            size: first ? 52 : 42,
            name: player.name,
          ),
          const SizedBox(height: 4),
          Text(
            player.isMe ? 'You' : player.name.split(' ').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMedium.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${player.points}',
            style: AppTextStyles.caption.copyWith(
              color: first ? ArenaTheme.gold : ArenaTheme.textMutedOnNavy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: height,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: first ? null : ArenaTheme.glassStrong,
              gradient: first ? ArenaTheme.goldGradient : null,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              border: Border.all(color: ArenaTheme.glassBorder),
            ),
            child: Text(
              '$place',
              style: AppTextStyles.headlineSmall.copyWith(
                color: first ? ArenaTheme.canvasTop : ArenaTheme.textOnNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.place, required this.player});

  final int place;
  final QuizRoomPlayer player;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: player.isMe ? ArenaTheme.glassStrong : ArenaTheme.glass,
        borderRadius: ArenaTheme.tileRadius,
        border: Border.all(color: ArenaTheme.glassBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$place',
              style: AppTextStyles.labelLarge.copyWith(
                color: ArenaTheme.textMutedOnNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          UserAvatar(photoUrl: player.photoUrl, size: 30, name: player.name),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              player.isMe ? 'You' : player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: ArenaTheme.textOnNavy,
              ),
            ),
          ),
          if (player.left)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'left',
                style: AppTextStyles.caption.copyWith(
                  color: ArenaTheme.textFaintOnNavy,
                ),
              ),
            ),
          Text(
            '${player.points}',
            style: AppTextStyles.labelLarge.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(
          color: ArenaTheme.textMutedOnNavy,
        ),
      ),
    );
  }
}

class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog();

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = QuizRoomService.looksLikeCode(_ctrl.text);
    return AlertDialog(
      title: const Text('Join a room'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 7,
        decoration: const InputDecoration(hintText: '6-letter code'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          if (QuizRoomService.looksLikeCode(v)) Navigator.pop(context, v);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: ok ? () => Navigator.pop(context, _ctrl.text) : null,
          child: const Text('Join'),
        ),
      ],
    );
  }
}

/// Opened from an invite notification (`/quiz/room/:code`): joins the room,
/// then becomes it. Joining twice is harmless — the server just returns the
/// room you are already in.
class QuizRoomJoinScreen extends StatefulWidget {
  const QuizRoomJoinScreen({super.key, required this.code});

  final String code;

  @override
  State<QuizRoomJoinScreen> createState() => _QuizRoomJoinScreenState();
}

class _QuizRoomJoinScreenState extends State<QuizRoomJoinScreen> {
  QuizRoom? _room;
  String? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      final room = await QuizRoomService.join(widget.code);
      if (mounted) setState(() => _room = room);
    } on QuizRoomError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't join that room.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room != null) return QuizRoomScreen(room: room);
    return ArenaScaffold(
      title: 'Live room',
      showMute: false,
      child: _error == null
          ? const Center(
              child: CircularProgressIndicator(color: ArenaTheme.gold),
            )
          : _Notice(text: _error!),
    );
  }
}

/// One question in the end-of-game review: what you picked, and the right
/// answer when that wasn't it.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.number,
    required this.question,
    required this.item,
  });

  final int number;
  final QuizQuestion question;
  final QuizRoomReviewItem item;

  String? _option(int? i) => i != null && i >= 0 && i < question.options.length
      ? question.options[i]
      : null;

  @override
  Widget build(BuildContext context) {
    final mine = _option(item.myChoice);
    final right = _option(item.correctIndex);
    final colour = item.correct
        ? ArenaTheme.correctOnNavy
        : ArenaTheme.wrongOnNavy;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ArenaTheme.glass,
        borderRadius: ArenaTheme.tileRadius,
        border: Border.all(color: ArenaTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.correct
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: colour,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$number. ${question.question}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: ArenaTheme.textOnNavy,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              if (item.points > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '+${item.points}',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: ArenaTheme.correctOnNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mine == null
                      ? "You didn't answer in time"
                      : 'You said: $mine',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: item.correct
                        ? ArenaTheme.correctOnNavy
                        : ArenaTheme.textMutedOnNavy,
                    fontWeight: item.correct ? FontWeight.w700 : null,
                  ),
                ),
                if (!item.correct && right != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'Answer: $right',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: ArenaTheme.correctOnNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if ((question.reference ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      question.reference!,
                      style: AppTextStyles.caption.copyWith(
                        color: ArenaTheme.textFaintOnNavy,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
