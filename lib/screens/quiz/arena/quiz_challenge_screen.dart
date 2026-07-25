import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/quiz_challenge_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/cached_image.dart';
import '../../../widgets/motion/brand_spinner.dart';
import 'arena_theme.dart';
import 'widgets/arena_scaffold.dart';

/// Pick a friend to challenge.
///
/// Accepted friends only — deliberately not the whole member directory, so
/// this can't become a way to ping strangers. Enforced server-side by
/// `quiz_challengeable_friends()`, not just hidden in the UI.
class QuizOpponentPickerScreen extends StatefulWidget {
  const QuizOpponentPickerScreen({super.key});

  @override
  State<QuizOpponentPickerScreen> createState() =>
      _QuizOpponentPickerScreenState();
}

class _QuizOpponentPickerScreenState extends State<QuizOpponentPickerScreen> {
  late Future<List<QuizOpponent>> _future = QuizChallengeService.opponents();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'Challenge a friend',
      showMute: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _query = value.trim()),
              style: AppTextStyles.bodyMedium
                  .copyWith(color: ArenaTheme.textOnNavy),
              decoration: InputDecoration(
                hintText: 'Search friends',
                hintStyle: AppTextStyles.bodyMedium
                    .copyWith(color: ArenaTheme.textFaintOnNavy),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: ArenaTheme.textFaintOnNavy, size: 20),
                filled: true,
                fillColor: ArenaTheme.glass,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ArenaTheme.radiusPill),
                  borderSide: const BorderSide(
                      color: ArenaTheme.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ArenaTheme.radiusPill),
                  borderSide: const BorderSide(
                      color: ArenaTheme.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ArenaTheme.radiusPill),
                  borderSide: BorderSide(
                      color: ArenaTheme.gold.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<QuizOpponent>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: BrandSpinner(size: 30));
                }
                final all = snapshot.data ?? const <QuizOpponent>[];
                final list = _query.isEmpty
                    ? all
                    : all
                        .where((o) => o.name
                            .toLowerCase()
                            .contains(_query.toLowerCase()))
                        .toList();

                if (all.isEmpty) return _buildNoFriends();
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      'No friends match "$_query".',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: ArenaTheme.textMutedOnNavy),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: ArenaTheme.gold,
                  backgroundColor: ArenaTheme.canvasTop,
                  onRefresh: () async {
                    setState(
                        () => _future = QuizChallengeService.opponents());
                    await _future;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _OpponentRow(
                      opponent: list[i],
                      onTap: () {
                        QuizSfx.tap();
                        Navigator.of(context).pop(list[i]);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFriends() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined,
                size: 52,
                color: ArenaTheme.textFaintOnNavy.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              'No friends yet',
              style: AppTextStyles.titleMedium.copyWith(
                color: ArenaTheme.textOnNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add friends in the member directory, then challenge them '
              'to a Bible Quiz.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: ArenaTheme.textMutedOnNavy, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpponentRow extends StatelessWidget {
  const _OpponentRow({required this.opponent, required this.onTap});

  final QuizOpponent opponent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Already challenged and waiting — let them pick someone else rather
    // than stacking duplicate challenges on one friend.
    final blocked = opponent.hasPendingChallenge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Opacity(
        opacity: blocked ? 0.5 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: ArenaTheme.tileRadius,
            onTap: blocked ? null : onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: ArenaTheme.glass,
                borderRadius: ArenaTheme.tileRadius,
                border: Border.all(color: ArenaTheme.glassBorder),
              ),
              child: Row(
                children: [
                  QuizAvatar(
                      url: opponent.photoUrl, name: opponent.name, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                opponent.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: ArenaTheme.textOnNavy,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (opponent.isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified_rounded,
                                  size: 14, color: ArenaTheme.gold),
                            ],
                          ],
                        ),
                        if (blocked)
                          Text(
                            'Waiting on their answer',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: ArenaTheme.textFaintOnNavy,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    blocked
                        ? Icons.hourglass_empty_rounded
                        : Icons.sports_kabaddi_rounded,
                    size: 19,
                    color: blocked
                        ? ArenaTheme.textFaintOnNavy
                        : ArenaTheme.gold,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Incoming challenges + settled history.
class QuizChallengesScreen extends StatefulWidget {
  const QuizChallengesScreen({super.key, required this.onPlay});

  /// Called when the player accepts a challenge.
  final void Function(QuizChallenge challenge) onPlay;

  @override
  State<QuizChallengesScreen> createState() => _QuizChallengesScreenState();
}

class _QuizChallengesScreenState extends State<QuizChallengesScreen> {
  bool _loading = true;
  List<QuizChallenge> _incoming = const [];
  List<QuizChallenge> _history = const [];

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      QuizChallengeService.incoming(),
      QuizChallengeService.history(),
    ]);
    if (!mounted) return;
    setState(() {
      _incoming = results[0];
      _history = results[1];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'Challenges',
      showMute: false,
      child: _loading
          ? const Center(child: BrandSpinner(size: 30))
          : RefreshIndicator(
              color: ArenaTheme.gold,
              backgroundColor: ArenaTheme.canvasTop,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (_incoming.isEmpty && _history.isEmpty)
                    _buildEmpty()
                  else ...[
                    if (_incoming.isNotEmpty) ...[
                      _label('WAITING FOR YOU'),
                      const SizedBox(height: 10),
                      for (final challenge in _incoming)
                        _IncomingCard(
                          challenge: challenge,
                          onPlay: () {
                            Navigator.of(context).pop();
                            widget.onPlay(challenge);
                          },
                          onDecline: () async {
                            await QuizChallengeService.decline(challenge.id);
                            await _load();
                          },
                        ),
                      const SizedBox(height: 18),
                    ],
                    if (_history.isNotEmpty) ...[
                      _label('RESULTS'),
                      const SizedBox(height: 10),
                      for (final challenge in _history)
                        _HistoryCard(challenge: challenge, uid: _uid),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(
          color: ArenaTheme.gold,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          fontSize: 11.5,
        ),
      );

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.sports_kabaddi_rounded,
              size: 52,
              color: ArenaTheme.textFaintOnNavy.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Text(
            'No challenges yet',
            style: AppTextStyles.titleMedium.copyWith(
              color: ArenaTheme.textOnNavy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Play a round, then challenge a friend to beat your score on '
            'the exact same questions.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: ArenaTheme.textMutedOnNavy, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({
    required this.challenge,
    required this.onPlay,
    required this.onDecline,
  });

  final QuizChallenge challenge;
  final VoidCallback onPlay;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ArenaPanel(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        borderColor: ArenaTheme.gold.withValues(alpha: 0.5),
        glow: ArenaTheme.gold,
        child: Column(
          children: [
            Row(
              children: [
                QuizAvatar(
                    url: challenge.otherPhotoUrl,
                    name: challenge.otherName,
                    size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.otherName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: ArenaTheme.textOnNavy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scored ${challenge.challengerPoints} points on '
                        '${challenge.questions.length} questions',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: ArenaTheme.textMutedOnNavy),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                TextButton(
                  onPressed: onDecline,
                  child: Text('Decline',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: ArenaTheme.textFaintOnNavy)),
                ),
                const Spacer(),
                SizedBox(
                  width: 150,
                  child: ArenaButton(
                    label: 'Accept',
                    icon: Icons.sports_kabaddi_rounded,
                    gold: true,
                    height: 44,
                    onTap: onPlay,
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.challenge, required this.uid});

  final QuizChallenge challenge;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final (mine, theirs) = challenge.scoresFor(uid);
    final outcome = challenge.outcomeFor(uid) ?? 0;
    final color = outcome > 0
        ? ArenaTheme.correctOnNavy
        : outcome < 0
            ? ArenaTheme.wrongOnNavy
            : ArenaTheme.textMutedOnNavy;
    final label = outcome > 0
        ? 'WON'
        : outcome < 0
            ? 'LOST'
            : 'DRAW';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: ArenaTheme.glass,
          borderRadius: ArenaTheme.tileRadius,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            QuizAvatar(
                url: challenge.otherPhotoUrl,
                name: challenge.otherName,
                size: 36),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    challenge.otherName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$mine – $theirs',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: ArenaTheme.textMutedOnNavy),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(ArenaTheme.radiusPill),
              ),
              child: Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular avatar with an initial fallback. Shared by the challenge and
/// leaderboard screens.
class QuizAvatar extends StatelessWidget {
  const QuizAvatar({
    super.key,
    required this.url,
    required this.name,
    this.size = 34,
  });

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url == null || url!.isEmpty)
            ? ColoredBox(
                color: ArenaTheme.glassStrong,
                child: Center(
                  child: Text(
                    initial,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: ArenaTheme.textOnNavy,
                      fontWeight: FontWeight.w800,
                      fontSize: size * 0.4,
                    ),
                  ),
                ),
              )
            : CachedImage(url!, fit: BoxFit.cover),
      ),
    );
  }
}
