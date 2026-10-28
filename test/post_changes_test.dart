// The author's new post never reached their own Home feed, and a post made
// or deleted on one tab stayed stale on the other. FeedService now
// announces every server-confirmed create / edit / delete.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/feed_service.dart';

import 'helpers/fake_supabase.dart';

Map<String, Object?> _row(String body) => {
  'id': 'p1',
  'author_id': 'me',
  'body': body,
  'created_at': '2026-10-28T08:00:00Z',
  'visibility': 'public',
  'profiles': {'full_name': 'Me'},
  'post_likes': [],
  'post_comments': [],
};

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  test('create, edit and delete are each announced once confirmed', () async {
    final seen = <PostChange>[];
    final sub = FeedService.postChanges.listen(seen.add);
    addTearDown(sub.cancel);

    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/posts')) {
        if (req.method == 'POST') return _row('Hello');
        if (req.method == 'PATCH') return _row('Hello again');
        if (req.method == 'DELETE') {
          return [
            {'id': 'p1'},
          ];
        }
      }
      return null;
    });

    await FeedService.createPost(body: 'Hello');
    await FeedService.updatePost('p1', body: 'Hello again');
    await FeedService.deletePost('p1');
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((c) => c.kind), [
      PostChangeKind.created,
      PostChangeKind.updated,
      PostChangeKind.deleted,
    ]);
    expect(seen[0].post!.body, 'Hello');
    expect(seen[1].post!.body, 'Hello again');
    expect(seen[2].id, 'p1');
  });

  test('a failed create announces nothing', () async {
    final seen = <PostChange>[];
    final sub = FeedService.postChanges.listen(seen.add);
    addTearDown(sub.cancel);
    setFakeSupabaseHandler((_) => throw Exception('offline'));
    await expectLater(FeedService.createPost(body: 'x'), throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
  });
}
