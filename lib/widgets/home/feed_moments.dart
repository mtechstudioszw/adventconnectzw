import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';

import '../../data/fundamental_beliefs.dart';
import '../../models/advent_news_model.dart';
import '../../models/church_model.dart';
import '../../models/hymn_model.dart';
import '../../models/quiz_question_model.dart';
import '../../screens/library/beliefs_screen.dart';
import '../../screens/library/library_open.dart';
import '../../services/bible_service.dart';
import '../../services/memory_verse_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../cached_image.dart';
import '../motion/pressable.dart';

/// The recurring cards of Home's endless feed (29 Oct 2026): news, a
/// verse, a quiz question, a hymn, a belief, a church. Each is one item —
/// the feed brings the next one further down, never the same one again.

BoxDecoration _card(BuildContext context) => BoxDecoration(
  color: context.palette.card,
  borderRadius: BorderRadius.circular(AppRadius.lg),
  boxShadow: AppShadows.card(context),
);

const _margin = EdgeInsets.fromLTRB(
  AppSpace.lg,
  AppSpace.sm,
  AppSpace.lg,
  AppSpace.sm,
);

Widget _eyebrow(BuildContext context, String text, {Color? color}) => Text(
  text,
  style: AppTextStyles.overline.copyWith(
    color: color ?? context.palette.brandBlue,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
  ),
);

String _ago(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}M';
  if (d.inHours < 24) return '${d.inHours}H';
  if (d.inDays == 1) return 'YESTERDAY';
  if (d.inDays < 7) return '${d.inDays}D';
  return '${(d.inDays / 7).floor()}W';
}

/// One news story: photo, category, headline, source.
class NewsFeedCard extends StatelessWidget {
  const NewsFeedCard({super.key, required this.news});
  final AdventNews news;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cover = news.coverPhotoUrl ?? '';
    return Padding(
      padding: _margin,
      child: Pressable(
        pressedScale: 0.98,
        onTap: () => context.pushNamed(
          'news_details',
          pathParameters: {'id': news.id},
          extra: news,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: _card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover.isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedImage(cover, fit: BoxFit.cover),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow(
                      context,
                      '${news.category.label.toUpperCase()} · '
                      '${_ago(news.publishedAt)}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      news.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    if (news.summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        news.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if ((news.sourceLabel ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        news.sourceLabel!,
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "A verse for you" — from the member's Bible, with Memorise and Read.
/// Dark Navy is a permitted dark section (CLAUDE.md); it is not a header.
class VerseMomentCard extends StatefulWidget {
  const VerseMomentCard({super.key, required this.reference});
  final String reference;

  @override
  State<VerseMomentCard> createState() => _VerseMomentCardState();
}

class _VerseMomentCardState extends State<VerseMomentCard> {
  BibleReference? _ref;
  String? _text;

  @override
  void initState() {
    super.initState();
    BibleService.resolveReference(widget.reference).then((r) {
      if (!mounted || r == null || r.verse == null) return;
      final verses = r.book.chapters[r.chapter - 1];
      if (r.verse! > verses.length) return;
      setState(() {
        _ref = r;
        _text = BibleService.cleanVerse(verses[r.verse! - 1]);
      });
    });
  }

  void _memorise() {
    final r = _ref;
    if (r == null) return;
    HapticFeedback.lightImpact();
    final added = MemoryVerseService.add(
      book: r.book.index,
      chapter: r.chapter - 1,
      from: r.verse! - 1,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? 'Added to your memory verses.'
              : 'Already in your memory verses.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null) return const SizedBox.shrink();
    final r = _ref!;
    return Padding(
      padding: _margin,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.darkNavy,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _eyebrow(
              context,
              'A VERSE FOR YOU',
              color: AppColors.white.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 10),
            Text(
              '"$text"',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.white,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${r.book.name} ${r.chapter}:${r.verse}',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _memorise,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Memorise'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () => LibraryOpen.verse(
                    context,
                    r.book,
                    r.chapter - 1,
                    verse: r.verse! - 1,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.darkNavy,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: Text('Read ${r.book.name} ${r.chapter}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiz question answered right in the feed.
class QuizMomentCard extends StatefulWidget {
  const QuizMomentCard({super.key, required this.question});
  final QuizQuestion question;

  @override
  State<QuizMomentCard> createState() => _QuizMomentCardState();
}

class _QuizMomentCardState extends State<QuizMomentCard> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final q = widget.question;
    final answered = _picked != null;
    final right = answered && q.isCorrect(_picked!);
    return Padding(
      padding: _margin,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _eyebrow(context, 'QUICK QUIZ')),
                if (!answered)
                  Text(
                    'Tap an answer',
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              q.question,
              style: AppTextStyles.titleSmall.copyWith(
                color: palette.text,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _option(context, i),
              ),
            if (answered) ...[
              const SizedBox(height: 4),
              Text(
                [
                  right
                      ? 'Correct!'
                      : 'The answer: ${q.options[q.correctIndex]}.',
                  if ((q.reference ?? '').isNotEmpty) q.reference!,
                ].join(' '),
                style: AppTextStyles.bodySmall.copyWith(
                  color: right ? palette.brandGreen : palette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((q.explanation ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  q.explanation!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.pushNamed('quiz'),
                  child: const Text('Play more'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, int i) {
    final palette = context.palette;
    final q = widget.question;
    final answered = _picked != null;
    final isRight = i == q.correctIndex;
    final isPicked = i == _picked;
    Color border = palette.divider;
    Color? fill;
    if (answered && isRight) {
      border = AppColors.successGreen;
      fill = AppColors.successGreen.withValues(alpha: 0.10);
    } else if (answered && isPicked) {
      border = AppColors.red;
      fill = AppColors.red.withValues(alpha: 0.08);
    }
    return Semantics(
      button: true,
      selected: isPicked,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: answered
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() => _picked = i);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: fill ?? palette.cardMuted,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Text(
            q.options[i],
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Sing today" — one hymn, tap to open it.
class HymnMomentCard extends StatelessWidget {
  const HymnMomentCard({super.key, required this.hymn});
  final Hymn hymn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final firstLine = hymn.lyrics
        .split('\n')
        .map((l) => l.trim())
        .firstWhere(
          (l) => l.isNotEmpty && int.tryParse(l) == null,
          orElse: () => '',
        );
    return Padding(
      padding: _margin,
      child: Pressable(
        pressedScale: 0.98,
        onTap: () => LibraryOpen.hymn(context, hymn),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(context),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Text(
                  hymn.number?.toString() ?? '♪',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.brandBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow(
                      context,
                      'SING TODAY · ${HymnCollection.fromKey(hymn.collection).label.toUpperCase()}',
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hymn.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (firstLine.isNotEmpty)
                      Text(
                        firstLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "What we believe" — one of the 28, tap for the full summary.
class BeliefMomentCard extends StatelessWidget {
  const BeliefMomentCard({super.key, required this.belief});
  final FundamentalBelief belief;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: _margin,
      child: Pressable(
        pressedScale: 0.98,
        onTap: () => Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => BeliefDetailScreen(belief: belief),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow(context, 'WHAT WE BELIEVE · ${belief.number} OF 28'),
              const SizedBox(height: 4),
              Text(
                belief.title,
                style: AppTextStyles.titleSmall.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                belief.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: palette.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Read more',
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.brandBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A church suggestion for a member who has no home church yet. The
/// action makes it their home church (there is no following churches).
class ChurchFollowCard extends StatelessWidget {
  const ChurchFollowCard({
    super.key,
    required this.church,
    required this.following,
    required this.onFollow,
  });

  final Church church;
  final bool following;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final photo = church.profilePhotoUrl ?? '';
    return Padding(
      padding: _margin,
      child: Pressable(
        pressedScale: 0.98,
        onTap: () => context.pushNamed(
          'church_details',
          pathParameters: {'id': church.id},
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _card(context),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.button),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: photo.isEmpty
                      ? ColoredBox(
                          color: AppColors.primaryBlue.withValues(alpha: 0.12),
                          child: Icon(
                            Icons.church_rounded,
                            color: palette.brandBlue,
                          ),
                        )
                      : CachedImage(photo, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow(context, 'A CHURCH NEAR YOU'),
                    Text(
                      church.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        if (church.city.trim().isNotEmpty) church.city.trim(),
                        if (church.membersCount > 0)
                          '${church.membersCount} members',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: following ? null : onFollow,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
                child: Text(following ? 'My church' : 'My church?'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quiet line between the last post and the endless part.
class FeedCaughtUpDivider extends StatelessWidget {
  const FeedCaughtUpDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Divider(color: palette.divider)),
              const SizedBox(width: 8),
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: palette.brandGreen,
              ),
              const SizedBox(width: 6),
              Text(
                "You're up to date on your people",
                style: AppTextStyles.caption.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: palette.divider)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'More to explore',
            style: AppTextStyles.titleSmall.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'People, sermons, news and Scripture — it keeps going',
            style: AppTextStyles.caption.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
