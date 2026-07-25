import 'package:flutter/material.dart';

import '../../../services/quiz_cloud_service.dart';
import '../../../services/quiz_sfx.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/motion/brand_spinner.dart';
import 'arena_theme.dart';
import 'quiz_challenge_screen.dart' show QuizAvatar;
import 'widgets/arena_scaffold.dart';

/// Weekly (and all-time) standings.
///
/// Ranks come from a `SECURITY DEFINER` RPC so a player can see the board
/// without being able to read anyone else's raw score rows.
class QuizLeaderboardScreen extends StatefulWidget {
  const QuizLeaderboardScreen({super.key});

  @override
  State<QuizLeaderboardScreen> createState() => _QuizLeaderboardScreenState();
}

class _QuizLeaderboardScreenState extends State<QuizLeaderboardScreen> {
  static const _periods = <(String, int)>[
    ('This week', 7),
    ('This month', 30),
    ('All time', 3650),
  ];

  int _periodIndex = 0;
  bool _loading = true;
  List<QuizLeaderboardEntry> _entries = const [];
  QuizRankSummary? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final days = _periods[_periodIndex].$2;
    final results = await Future.wait([
      QuizCloudService.leaderboard(days: days),
      QuizCloudService.myRank(days: days),
    ]);
    if (!mounted) return;
    setState(() {
      _entries = results[0] as List<QuizLeaderboardEntry>;
      _me = results[1] as QuizRankSummary?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ArenaScaffold(
      title: 'Leaderboard',
      showMute: false,
      child: Column(
        children: [
          _buildPeriods(),
          const SizedBox(height: 12),
          Expanded(child: _buildBody()),
          if (_me != null && !_loading) _buildMyRank(_me!),
        ],
      ),
    );
  }

  Widget _buildPeriods() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < _periods.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(ArenaTheme.radiusPill),
                  onTap: _periodIndex == i
                      ? null
                      : () {
                          QuizSfx.tap();
                          setState(() => _periodIndex = i);
                          _load();
                        },
                  child: AnimatedContainer(
                    duration: AppMotion.maybe(context, AppMotion.quick),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _periodIndex == i
                          ? ArenaTheme.gold.withValues(alpha: 0.18)
                          : ArenaTheme.glass,
                      borderRadius:
                          BorderRadius.circular(ArenaTheme.radiusPill),
                      border: Border.all(
                        color: _periodIndex == i
                            ? ArenaTheme.gold.withValues(alpha: 0.55)
                            : ArenaTheme.glassBorder,
                      ),
                    ),
                    child: Text(
                      _periods[i].$1,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: _periodIndex == i
                            ? ArenaTheme.goldBright
                            : ArenaTheme.textMutedOnNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: BrandSpinner(size: 32));
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.leaderboard_outlined,
                  size: 52,
                  color: ArenaTheme.textFaintOnNavy.withValues(alpha: 0.5)),
              const SizedBox(height: 14),
              Text(
                'No scores yet',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ArenaTheme.textOnNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Play a round and you\'ll be the first on the board.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: ArenaTheme.textMutedOnNavy),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: ArenaTheme.gold,
      backgroundColor: ArenaTheme.canvasTop,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        itemCount: _entries.length,
        itemBuilder: (context, i) => _LeaderRow(
          entry: _entries[i],
          // Crowned only on the all-time board — being top of one quiet
          // week shouldn't make you King of Quiz.
          isKing: _entries[i].rank == 1 && _periodIndex == 2,
        ),
      ),
    );
  }

  Widget _buildMyRank(QuizRankSummary me) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: ArenaPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          borderColor: ArenaTheme.gold.withValues(alpha: 0.45),
          child: Row(
            children: [
              Text(
                '#${me.rank}',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ArenaTheme.goldBright,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your position',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: ArenaTheme.textOnNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'of ${me.totalPlayers} '
                      '${me.totalPlayers == 1 ? "player" : "players"} · '
                      '${me.rounds} ${me.rounds == 1 ? "round" : "rounds"}',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: ArenaTheme.textFaintOnNavy),
                    ),
                  ],
                ),
              ),
              Text(
                '${me.points}',
                style: AppTextStyles.titleMedium.copyWith(
                  color: ArenaTheme.goldBright,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry, required this.isKing});

  final QuizLeaderboardEntry entry;

  /// True for #1 — the reigning King of Quiz, crowned rather than merely
  /// listed first.
  final bool isKing;

  /// Gold, silver, bronze for the podium; glass for everyone else.
  Color get _rankColor => switch (entry.rank) {
        1 => ArenaTheme.gold,
        2 => const Color(0xFFC4CCDA),
        3 => const Color(0xFFCE9C6B),
        _ => ArenaTheme.textFaintOnNavy,
      };

  @override
  Widget build(BuildContext context) {
    final podium = entry.rank <= 3;
    return Padding(
      padding: EdgeInsets.only(bottom: isKing ? 12 : 9),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 13,
          vertical: isKing ? 15 : 11,
        ),
        decoration: BoxDecoration(
          gradient: isKing
              ? LinearGradient(
                  colors: [
                    ArenaTheme.gold.withValues(alpha: 0.26),
                    ArenaTheme.gold.withValues(alpha: 0.07),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isKing
              ? null
              : entry.isMe
                  ? ArenaTheme.gold.withValues(alpha: 0.13)
                  : ArenaTheme.glass,
          borderRadius: ArenaTheme.tileRadius,
          border: Border.all(
            color: isKing || entry.isMe
                ? ArenaTheme.gold.withValues(alpha: isKing ? 0.75 : 0.5)
                : ArenaTheme.glassBorder,
            width: isKing ? 1.6 : 1,
          ),
          boxShadow:
              isKing ? ArenaTheme.glow(ArenaTheme.gold, strength: 0.9) : null,
        ),
        child: Column(
          children: [
            if (isKing)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.workspace_premium_rounded,
                        size: 16, color: ArenaTheme.goldBright),
                    const SizedBox(width: 6),
                    Text(
                      'KING OF QUIZ',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: ArenaTheme.goldBright,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                SizedBox(
                  width: 30,
                  child: podium
                      ? Icon(Icons.emoji_events_rounded,
                          size: isKing ? 25 : 21, color: _rankColor)
                      : Text(
                          '${entry.rank}',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: _rankColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                QuizAvatar(
                  url: entry.photoUrl,
                  name: entry.name,
                  size: isKing ? 44 : 34,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.isMe ? 'You' : entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: ArenaTheme.textOnNavy,
                            fontSize: isKing ? 15.5 : 14,
                            fontWeight: entry.isMe || isKing
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (entry.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded,
                            size: 14, color: ArenaTheme.gold),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.points}',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: ArenaTheme.goldBright,
                    fontSize: isKing ? 16 : 14,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
