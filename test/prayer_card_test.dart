// TEMPORARY DIAGNOSTIC — renders the REAL PrayerCard with the REAL production
// rows to see whether the card itself throws. Delete once the cause is fixed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/models/prayer_model.dart';
import 'package:advent_connect_zw/widgets/prayer_card.dart';
import 'package:advent_connect_zw/widgets/motion/branded_refresh_indicator.dart';
import 'package:advent_connect_zw/widgets/motion/content_reveal.dart';
import 'package:advent_connect_zw/widgets/motion/staggered_reveal.dart';
import 'package:advent_connect_zw/theme/app_theme.dart';

// Verbatim from production (id 13 and 11).
final _rows = <Map<String, dynamic>>[
  {
    'id': 13,
    'author_id': '493e11b7-79da-4e8d-9ea0-8189b3fedc0a',
    'title': 'A Prayer for Endurance',
    'content':
        "God, You call me to faithful and obedient living—because you know what's best for me. Thank You for providing Your Word as a guide that helps me bring You glory.",
    'visibility': 'public',
    'church_id': null,
    'prayer_count': 3,
    'comment_count': 1,
    'is_urgent': false,
    'is_answered': false,
    'created_at': '2026-07-09T16:22:06.168799+00:00',
    'category': 'other',
    'answered_at': null,
    'testimony': null,
    'circle_id': null,
    'is_mine': false,
    'author_name': 'Watson',
    'author_photo_url':
        'https://eqbyvasteolqyktbqbem.supabase.co/storage/v1/object/public/profile_photos/493e11b7-79da-4e8d-9ea0-8189b3fedc0a/1780738248093.jpg',
    'author_is_verified': false,
  },
  {
    'id': 11,
    'author_id': '493e11b7-79da-4e8d-9ea0-8189b3fedc0a',
    'title': 'A Prayer for Hope and Justice',
    'content':
        'God, You put the thirst and hunger for righteousness in my heart, and You alone can satisfy it.',
    'visibility': 'public',
    'church_id': null,
    'prayer_count': 13,
    'comment_count': 1,
    'is_urgent': false,
    'is_answered': false,
    'created_at': '2026-06-05T10:00:00.000000+00:00',
    'category': 'other',
    'answered_at': null,
    'testimony': null,
    'circle_id': null,
    'is_mine': false,
    'author_name': 'Watson',
    'author_photo_url': null,
    'author_is_verified': false,
  },
];

void main() {
  testWidgets('real PrayerCard renders the real production rows', (t) async {
    final prayers = _rows.map(Prayer.fromJson).toList();

    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 50),
              Expanded(
                child: BrandedRefreshIndicator(
                  onRefresh: () async {},
                  child: ContentReveal(
                    loading: false,
                    skeleton: const SizedBox.shrink(),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: prayers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => StaggeredReveal(
                        index: i,
                        rise: 18,
                        child: PrayerCard(
                          prayer: prayers[i],
                          isPraying: false,
                          busy: false,
                          onTogglePray: () {},
                          onTap: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    final cards = find.byType(PrayerCard);
    expect(cards, findsNWidgets(2));
    debugPrint('card0 size = ${t.getSize(cards.first)}');
    debugPrint('content found = ${find.textContaining("God, You call").evaluate().length}');
    expect(t.getSize(cards.first).height, greaterThan(0));
  });
}
