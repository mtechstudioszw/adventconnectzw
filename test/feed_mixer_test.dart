// The endless Home feed layout (owner, 29 Oct 2026).

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/data/feed_verses.dart';
import 'package:advent_connect_zw/services/bible_service.dart';
import 'package:advent_connect_zw/services/feed_mixer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every feed verse resolves', () async {
    for (final ref in kFeedVerses) {
      final r = await BibleService.resolveReference(ref);
      expect(r?.verse, isNotNull, reason: ref);
      expect(
        r!.verse! <= r.book.chapters[r.chapter - 1].length,
        isTrue,
        reason: ref,
      );
    }
  });

  const plenty = {
    FeedBlockKind.people: 80,
    FeedBlockKind.news: 39,
    FeedBlockKind.video: 200,
    FeedBlockKind.verse: 60,
    FeedBlockKind.quiz: 400,
    FeedBlockKind.hymn: 900,
    FeedBlockKind.belief: 28,
    FeedBlockKind.church: 100,
  };

  test('posts lead, a module every few posts', () {
    final out = FeedMixer.mix(posts: 9, available: plenty);
    expect(out.first, const FeedBlock(FeedBlockKind.post, 0));
    // 9 posts + one module after posts 3, 6 and 9.
    expect(out.length, 12);
    expect(out[3].kind, FeedBlockKind.people);
  });

  test('people come back again and again with new groups', () {
    final out = FeedMixer.mix(
      posts: 6,
      available: plenty,
      postsExhausted: true,
      extraModules: 60,
    );
    final groups = out.where((b) => b.kind == FeedBlockKind.people).toList();
    expect(groups.length, greaterThan(10));
    // Never the same group twice.
    expect(groups.map((b) => b.index).toSet().length, groups.length);
  });

  test('nothing is ever repeated, of any kind', () {
    final out = FeedMixer.mix(
      posts: 20,
      discovery: 5,
      available: plenty,
      postsExhausted: true,
      extraModules: 300,
    );
    expect(out.toSet().length, out.length);
  });

  test('a source that runs dry drops out; the rest keep going', () {
    final out = FeedMixer.mix(
      posts: 0,
      available: {FeedBlockKind.news: 2, FeedBlockKind.video: 10},
      postsExhausted: true,
      extraModules: 50,
    );
    expect(out.where((b) => b.kind == FeedBlockKind.news).length, 2);
    expect(out.where((b) => b.kind == FeedBlockKind.video).length, 10);
    expect(out.length, 12, reason: 'stops when every source is empty');
  });

  test('the feed says once that posts are done, then keeps going', () {
    final out = FeedMixer.mix(
      posts: 4,
      available: plenty,
      postsExhausted: true,
      extraModules: 5,
    );
    final i = out.indexOf(const FeedBlock(FeedBlockKind.caughtUp, 0));
    expect(i, greaterThan(3));
    expect(out.length - i - 1, 5);
    expect(out.where((b) => b.kind == FeedBlockKind.caughtUp).length, 1);
  });

  test('not exhausted: no caught-up line, no extra blocks', () {
    final out = FeedMixer.mix(posts: 6, available: plenty, extraModules: 20);
    expect(out.any((b) => b.kind == FeedBlockKind.caughtUp), isFalse);
    expect(out.length, 8);
  });

  test('one-off modules are woven in, each once', () {
    final out = FeedMixer.mix(posts: 30, discovery: 4, available: plenty);
    final d = out.where((b) => b.kind == FeedBlockKind.discovery).toList();
    expect(d.map((b) => b.index), [0, 1, 2, 3]);
  });

  test('the ad slot lands once, where asked', () {
    final out = FeedMixer.mix(posts: 12, available: plenty, adAfterPost: 8);
    expect(out.where((b) => b.kind == FeedBlockKind.ad).length, 1);
    final ad = out.indexOf(const FeedBlock(FeedBlockKind.ad, 0));
    expect(out[ad - 1], const FeedBlock(FeedBlockKind.post, 7));
  });

  test('hasMore is false only when every source is spent', () {
    expect(
      FeedMixer.hasMore(posts: 0, available: plenty, extraModules: 10),
      isTrue,
    );
    expect(
      FeedMixer.hasMore(
        posts: 0,
        available: {FeedBlockKind.news: 2},
        extraModules: 2,
      ),
      isFalse,
    );
  });

  test('stable: same inputs, same layout', () {
    List<FeedBlock> run() => FeedMixer.mix(
      posts: 10,
      discovery: 3,
      available: plenty,
      postsExhausted: true,
      extraModules: 20,
    );
    expect(run(), run());
  });
}
