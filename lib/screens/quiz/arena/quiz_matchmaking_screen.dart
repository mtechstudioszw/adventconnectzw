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
///
/// ## Invites had no way in
///
/// `quiz_match_invite` and `quiz_match_accept` shipped together and worked,
/// and `QuizMatchService.accept` had **no caller anywhere in the app**. So
/// challenging someone sent them a notification, created a live match, and
/// gave them nothing to press: the lobby showed a number on a tile, this
/// screen went straight into the queue without ever mentioning that someone
/// was waiting for them, and the invite expired five minutes later. Both
/// halves of "it should connect you automatically" were missing — the
/// invite you were sent, and the way to say yes to it.
///
/// So invites come first here, above the queue. Anyone who has asked to
/// play you is named, with Accept and Decline, and the list keeps polling
/// while you wait so one arriving mid-search interrupts it.
class QuizMatchmakingScreen extends StatefulWidget {
  const QuizMatchmakingScreen({super.key, this.autoStart = true, this.matchId});

  /// False in tests — [initState] otherwise reaches Supabase immediately.
  final bool autoStart;

  /// Opened from a "wants to play you" notification. The screen offers this
  /// invite immediately rather than joining the queue, so the tap that
  /// opened the notification lands on the Accept button.
  final String? matchId;

  @override
  State<QuizMatchmakingScreen> createState() => _QuizMatchmakingScreenState();
}

class _QuizMatchmakingScreenState extends State<QuizMatchmakingScreen> {
  QuizMatch? _match;
  List<QuizPlayer> _players = const [];
  List<QuizMatchInvite> _invites = const [];
  String? _error;
  bool _searching = false;
  bool _accepting = false;
  int _waitedSeconds = 0;
  Timer? _poll;
  Timer? _counter;
  Timer? _invitePoll;

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
      unawaited(_boot());
      // An invite can land while you are sitting in the queue. Without this
      // the only way to discover it is to leave and come back.
      _invitePoll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_loadInvites()),
      );
    }
  }

  /// Arrived from a notification → offer that invite instead of queueing.
  /// Otherwise look for invites first, and only queue if there are none:
  /// joining the queue while somebody is already waiting on your answer is
  /// how two people who both want to play end up never meeting.
  Future<void> _boot() async {
    await _loadInvites();
    if (!mounted) return;
    if (_invites.isNotEmpty) return;
    await _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _counter?.cancel();
    _invitePoll?.cancel();
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

  Future<void> _loadInvites() async {
    final list = await QuizMatchService.invites();
    if (!mounted) return;
    // A notification names one match; float it to the front so the button
    // the member came here to press is the first thing under their thumb.
    final wanted = widget.matchId;
    final ordered = wanted == null
        ? list
        : [
            ...list.where((i) => i.matchId == wanted),
            ...list.where((i) => i.matchId != wanted),
          ];
    setState(() => _invites = ordered);
  }

  Future<void> _accept(QuizMatchInvite invite) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      final match = await QuizMatchService.accept(invite.matchId);
      if (!mounted) return;
      setState(() => _accepting = false);
      // Accepting flips the row to `active` for BOTH players — the
      // challenger's own poll sees it and enters on their side. This is the
      // "both of you accept and the match begins" the founder asked for.
      await _enter(match);
    } on QuizProfileRequired {
      if (!mounted) return;
      setState(() => _accepting = false);
      final made = await QuizProfileSheet.show(context);
      if (made == true && mounted) unawaited(_accept(invite));
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      // Almost always the five-minute expiry. Say which, and drop the dead
      // invite rather than leaving a button that cannot work.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That challenge is no longer open.')),
      );
      unawaited(_loadInvites());
    }
  }

  Future<void> _decline(QuizMatchInvite invite) async {
    setState(
      () => _invites = _invites
          .where((i) => i.matchId != invite.matchId)
          .toList(),
    );
    await QuizMatchService.cancel(invite.matchId);
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
      _poll = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _check(),
      );
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
      _poll ??= Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _check(),
      );
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

  /// Rename the quiz identity. Seeded with the current name so the sheet
  /// opens on what it is now rather than on a fresh suggestion.
  Future<void> _editProfile() async {
    final profile = await QuizMatchService.myProfile();
    if (!mounted) return;
    final saved = await QuizProfileSheet.show(
      context,
      initialName: profile?.displayName,
    );
    if (saved != true || !mounted) return;
    // The name is on the player list and the leaderboard, so re-read both
    // rather than leaving the old one on screen.
    await QuizMatchService.myProfile(refresh: true);
    if (mounted) unawaited(_loadPlayers());
  }

  bool get _gaveUp => _searching && _waitedSeconds >= _giveUpAfter;

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'Live match',
      onClose: () => Navigator.of(context).maybePop(),
      trailing: [
        // Editing the quiz name was reachable in exactly one place: the
        // sheet that appears the first time you try to play and have no
        // profile yet. After that there was no way back to it — so a name
        // typed in a hurry, or one that reads wrong on the leaderboard,
        // was permanent. The live area is where that name is on show, so
        // it is where changing it belongs.
        ArenaIconButton(
          icon: Icons.badge_outlined,
          tooltip: 'Edit quiz profile',
          onTap: _editProfile,
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Above the queue, always. Somebody is already waiting on an
          // answer from this member — that beats looking for a stranger.
          if (_invites.isNotEmpty) ...[
            for (final invite in _invites)
              _InviteCard(
                invite: invite,
                busy: _accepting,
                onAccept: () => _accept(invite),
                onDecline: () => _decline(invite),
              ),
            const SizedBox(height: 20),
          ],
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
      body:
          'Seven questions, fifteen seconds each, both of you on the same '
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

/// "So-and-so wants to play you right now" — with the button that says yes.
///
/// Gold-bordered and at the top of the list because it is time-limited:
/// `quiz_match_accept` refuses an invite older than five minutes, so an
/// invite the member does not notice is an invite that dies.
class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final QuizMatchInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ArenaTheme.gold.withValues(alpha: 0.12),
          borderRadius: ArenaTheme.cardRadius,
          border: Border.all(color: ArenaTheme.gold.withValues(alpha: 0.55)),
          boxShadow: ArenaTheme.glow(ArenaTheme.gold, strength: 0.5),
        ),
        child: Column(
          children: [
            Row(
              children: [
                UserAvatar(
                  photoUrl: invite.fromPhoto,
                  size: 44,
                  name: invite.fromName,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        invite.fromName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: ArenaTheme.textOnNavy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'wants to play you right now',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: ArenaTheme.textMutedOnNavy,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: busy ? null : onDecline,
                  style: TextButton.styleFrom(
                    foregroundColor: ArenaTheme.textFaintOnNavy,
                  ),
                  child: const Text('Not now'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ArenaButton(
                    label: 'Accept and play',
                    icon: Icons.bolt_rounded,
                    gold: true,
                    height: 48,
                    busy: busy,
                    onTap: busy ? null : onAccept,
                  ),
                ),
              ],
            ),
          ],
        ),
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
                        border: Border.all(
                          color: ArenaTheme.canvasTop,
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
