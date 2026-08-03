import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/quiz_match.dart';
import '../../../services/quiz_match_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/user_avatar.dart';
import 'arena_theme.dart';
import 'quiz_match_screen.dart';
import 'widgets/arena_scaffold.dart';
import 'widgets/quiz_profile_sheet.dart';

/// Finding someone to play right now.
///
/// The founder chose pure live head-to-head over an async-first design. The
/// risk that carries is obvious — an empty lobby — so this screen is built
/// around telling the truth about it: it matches only against the presence
/// roster, it counts how long it has been looking, and when nobody is there
/// it says so and offers the async challenge that already works, rather
/// than spinning forever.
class QuizMatchmakingScreen extends StatefulWidget {
  const QuizMatchmakingScreen({super.key, this.autoStart = true});

  /// False in tests — [initState] otherwise reaches Supabase immediately.
  final bool autoStart;

  @override
  State<QuizMatchmakingScreen> createState() => _QuizMatchmakingScreenState();
}

class _QuizMatchmakingScreenState extends State<QuizMatchmakingScreen> {
  QuizMatch? _match;
  List<QuizPlayer> _players = const [];
  String? _error;
  bool _searching = false;
  int _waitedSeconds = 0;
  Timer? _poll;
  Timer? _counter;

  /// How long to sit in the queue before admitting nobody is coming. Short
  /// on purpose: a minute of nothing is a worse experience than an honest
  /// answer at twenty seconds and a list of people to challenge instead.
  static const _giveUpAfter = 25;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      unawaited(QuizMatchService.sweep());
      unawaited(_loadPlayers());
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _counter?.cancel();
    final match = _match;
    if (match != null && match.isWaiting) {
      // Stop occupying a slot other players would otherwise match into.
      unawaited(QuizMatchService.cancel(match.id));
    }
    super.dispose();
  }

  Future<void> _loadPlayers() async {
    final list = await QuizMatchService.players();
    if (mounted) setState(() => _players = list);
  }

  Future<void> _start() async {
    setState(() {
      _searching = true;
      _error = null;
      _waitedSeconds = 0;
    });
    try {
      final match = await QuizMatchService.find();
      if (!mounted) return;
      if (match.isActive) {
        _enter(match);
        return;
      }
      setState(() => _match = match);
      _counter = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _waitedSeconds++);
      });
      // Someone joining flips the row to `active`; the tick is what notices.
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
    } on QuizProfileRequired {
      if (!mounted) return;
      setState(() => _searching = false);
      final made = await QuizProfileSheet.show(context);
      if (made == true && mounted) unawaited(_start());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Could not reach the arena. Check your connection.';
      });
    }
  }

  Future<void> _check() async {
    final match = _match;
    if (match == null || !mounted) return;
    try {
      final next = await QuizMatchService.state(match.id);
      if (!mounted) return;
      if (next.isActive) {
        _enter(next);
      } else if (next.isOver) {
        _stopSearching();
      }
    } catch (_) {}
  }

  void _stopSearching() {
    _poll?.cancel();
    _counter?.cancel();
    _poll = null;
    _counter = null;
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _enter(QuizMatch match) async {
    _stopSearching();
    QuizSfx.play(QuizSound.go);
    final result = await Navigator.of(context).push<QuizMatch>(
      MaterialPageRoute(builder: (_) => QuizMatchScreen(match: match)),
    );
    if (!mounted) return;
    setState(() => _match = null);
    if (result != null) Navigator.of(context).pop(result);
  }

  Future<void> _challenge(QuizPlayer player) async {
    try {
      final match = await QuizMatchService.invite(player.userId);
      if (!mounted) return;
      setState(() => _match = match);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Challenge sent to ${player.name}.')),
      );
      _poll ??=
          Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
    } on QuizProfileRequired {
      if (!mounted) return;
      final made = await QuizProfileSheet.show(context);
      if (made == true && mounted) unawaited(_challenge(player));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send that challenge.')),
      );
    }
  }

  bool get _gaveUp => _searching && _waitedSeconds >= _giveUpAfter;

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'Live match',
      onClose: () => Navigator.of(context).maybePop(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _buildStatus(),
          const SizedBox(height: 26),
          if (_players.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Challenge someone',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: ArenaTheme.textOnNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_players.where((p) => p.isOnline).length} online',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: ArenaTheme.textFaintOnNavy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final player in _players)
              _PlayerRow(player: player, onChallenge: () => _challenge(player)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatus() {
    if (_error != null) {
      return _StatusCard(
        icon: Icons.wifi_off_rounded,
        title: 'No connection',
        body: _error!,
        actionLabel: 'Try again',
        onAction: _start,
      );
    }
    if (_gaveUp) {
      return _StatusCard(
        icon: Icons.person_search_rounded,
        title: 'Nobody available right now',
        // The honest version. A live-only design has empty moments and
        // pretending otherwise with a spinner is how people conclude the
        // feature is broken.
        body: _players.isEmpty
            ? 'No other players have set up a quiz profile yet. Try again '
                'later, or send a challenge from the arena that they can '
                'play whenever they like.'
            : 'Nobody is in the arena this minute. Challenge someone below — '
                'they get a notification and can join straight away.',
        actionLabel: 'Keep looking',
        onAction: () {
          setState(() => _waitedSeconds = 0);
        },
      );
    }
    if (_searching) {
      return _SearchingCard(seconds: _waitedSeconds);
    }
    return _StatusCard(
      icon: Icons.sports_esports_rounded,
      title: 'Head to head',
      body: 'Seven questions, fifteen seconds each, both of you on the same '
          'clock. Fastest correct answer scores most.',
      actionLabel: 'Find an opponent',
      onAction: _start,
    );
  }
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ArenaTheme.glass,
        borderRadius: ArenaTheme.cardRadius,
        border: Border.all(color: ArenaTheme.glassBorder),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              color: ArenaTheme.gold,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Looking for an opponent',
            style: AppTextStyles.titleSmall.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // A counter rather than an indeterminate wait: it makes the
            // screen feel like it is doing something specific, and it sets
            // the expectation that this ends.
            '${seconds}s',
            style: AppTextStyles.bodySmall.copyWith(
              color: ArenaTheme.textFaintOnNavy,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ArenaTheme.glass,
        borderRadius: ArenaTheme.cardRadius,
        border: Border.all(color: ArenaTheme.glassBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: ArenaTheme.gold, size: 34),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleSmall.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: ArenaTheme.textMutedOnNavy,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: ArenaTheme.actionGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  actionLabel,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.onChallenge});

  final QuizPlayer player;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ArenaTheme.glass,
          borderRadius: ArenaTheme.tileRadius,
          border: Border.all(
            color: player.isOnline
                ? ArenaTheme.correctOnNavy.withValues(alpha: 0.5)
                : ArenaTheme.glassBorder,
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  photoUrl: player.photoUrl,
                  size: 40,
                  name: player.name,
                ),
                if (player.isOnline)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: ArenaTheme.correctOnNavy,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: ArenaTheme.canvasTop, width: 2),
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
                  Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    player.isOnline
                        ? 'Online now'
                        : '${player.weekPoints} pts this week',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: player.isOnline
                          ? ArenaTheme.correctOnNavy
                          : ArenaTheme.textFaintOnNavy,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onChallenge,
              style: TextButton.styleFrom(
                foregroundColor: ArenaTheme.gold,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Challenge'),
            ),
          ],
        ),
      ),
    );
  }
}
