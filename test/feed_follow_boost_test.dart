// Following must change Home (28 Oct 2026). Before this, following a person
// or a Page was a notification and a number — the feed ranked their posts
// exactly like a stranger's.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/feed_service.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _row(String id, String author, {String? page}) => {
  'id': id,
  'author_id': author,
  'page_id': page,
  'body': 'post $id',
  // Same moment, so recency can't decide the order.
  'created_at': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  setUp(() {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/posts')) {
        return [
          _row('s1', 'stranger1'),
          _row('s2', 'stranger2'),
          _row('f1', 'followed'),
          _row('s3', 'stranger3'),
          _row('pg', 'pageadmin', page: 'page1'),
          _row('s4', 'stranger4'),
        ];
      }
      return null;
    });
  });

  test('a followed person and a followed Page rise above strangers', () async {
    final posts = await FeedService.fetchFeed(
      limit: 6,
      followedUserIds: {'followed'},
      followedPageIds: {'page1'},
    );
    final top2 = posts.take(2).map((p) => p.id).toSet();
    expect(top2, {'f1', 'pg'});
  });

  test('without follows, those posts get no lift', () async {
    // Across several refresh nonces, f1 and pg should not always both be
    // on top — the boost is what put them there.
    var bothTop = 0;
    for (var n = 0; n < 8; n++) {
      final posts = await FeedService.fetchFeed(limit: 6, refreshNonce: n);
      final top2 = posts.take(2).map((p) => p.id).toSet();
      if (top2.containsAll({'f1', 'pg'})) bothTop++;
    }
    expect(bothTop, lessThan(8));
  });

  test('more followers, more visibility (capped below follows)', () async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/posts')) {
        return [
          _row('s1', 'stranger1'),
          _row('big', 'popular'),
          _row('s2', 'stranger2'),
          _row('s3', 'stranger3'),
        ];
      }
      if (req.url.path.endsWith('/rpc/author_reach')) {
        return [
          {'id': 'popular', 'kind': 'user', 'followers': 5000},
          {'id': 'stranger1', 'kind': 'user', 'followers': 0},
        ];
      }
      return null;
    });
    var top = 0;
    for (var n = 0; n < 6; n++) {
      final posts = await FeedService.fetchFeed(limit: 4, refreshNonce: n);
      if (posts.first.id == 'big') top++;
    }
    // +0.25 beats the 0..0.20 jitter every time.
    expect(top, 6);
  });

  test('reach failing never breaks the feed', () async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/posts')) {
        return [_row('a', 'x'), _row('b', 'y')];
      }
      if (req.url.path.endsWith('/rpc/author_reach')) {
        return const FakeError(404, {'code': 'PGRST202', 'message': 'missing'});
      }
      return null;
    });
    final posts = await FeedService.fetchFeed(limit: 2);
    expect(posts, hasLength(2));
  });
}
