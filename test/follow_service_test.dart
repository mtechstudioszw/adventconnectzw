// One-way following (patch_274): the server decides active vs pending,
// counts come from an RPC, and the client never pretends a follow worked.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/follow_service.dart';
import 'package:advent_connect_zw/services/user_profile_service.dart';

import 'helpers/fake_supabase.dart';

void main() {
  setUpAll(() async {
    await initFakeSupabase();
    await signInFake('me');
  });

  setUp(() {
    FollowService.available = true;
    FollowService.followingIds.value = <String>{};
  });

  test(
    'follow returns the state the server chose (private → requested)',
    () async {
      String? sent;
      setFakeSupabaseHandler((req) {
        if (req.method == 'POST' && req.url.path.endsWith('/follows')) {
          sent = req.body;
          return {'status': 'pending'};
        }
        return null;
      });
      final state = await FollowService.follow('them');
      expect(state, FollowState.requested);
      // Only follower + followee are sent; status is the trigger's call.
      expect(jsonDecode(sent!), {'follower_id': 'me', 'followee_id': 'them'});
      expect(FollowService.followingIds.value, contains('them'));
    },
  );

  test('follow of a public profile is active at once', () async {
    setFakeSupabaseHandler((req) {
      if (req.method == 'POST') return {'status': 'active'};
      return null;
    });
    expect(await FollowService.follow('them'), FollowState.following);
  });

  test('unfollow deletes only my row and clears the menu state', () async {
    FollowService.followingIds.value = {'them'};
    setFakeSupabaseHandler((_) => null);
    await FollowService.unfollow('them');
    final del = fakeSupabaseRequests.singleWhere((r) => r.method == 'DELETE');
    expect(del.url.queryParameters['follower_id'], 'eq.me');
    expect(del.url.queryParameters['followee_id'], 'eq.them');
    expect(FollowService.followingIds.value, isNot(contains('them')));
  });

  test('stats parse counts and relationship', () async {
    setFakeSupabaseHandler((req) {
      if (req.url.path.endsWith('/rpc/profile_follow_stats')) {
        return [
          {
            'followers': 12,
            'following': 3,
            'i_follow': 'pending',
            'follows_me': true,
          },
        ];
      }
      return null;
    });
    final s = await FollowService.stats('them');
    expect(s.followers, 12);
    expect(s.following, 3);
    expect(s.state, FollowState.requested);
    expect(s.followsMe, isTrue);
  });

  test('approve throws when nothing changed (no silent success)', () async {
    setFakeSupabaseHandler((_) => <Object>[]);
    expect(() => FollowService.approve('them'), throwsStateError);
  });

  test(
    'before patch_274, a missing function marks following unavailable',
    () async {
      setFakeSupabaseHandler(
        (_) => const FakeError(404, {
          'code': 'PGRST202',
          'message': 'Could not find the function public.profile_follow_stats',
        }),
      );
      await expectLater(FollowService.stats('them'), throwsA(anything));
      expect(FollowService.available, isFalse);
    },
  );

  group('website', () {
    test('adds https and accepts plain domains', () {
      expect(
        UserProfileService.normalizeWebsite('example.org'),
        'https://example.org',
      );
      expect(
        UserProfileService.normalizeWebsite(' http://a.co/x '),
        'http://a.co/x',
      );
      expect(UserProfileService.normalizeWebsite('  '), isNull);
    });

    test('rejects non-links', () {
      expect(
        () => UserProfileService.normalizeWebsite('not a link'),
        throwsFormatException,
      );
      expect(
        () => UserProfileService.normalizeWebsite('localhost'),
        throwsFormatException,
      );
    });
  });

  test(
    'profile still opens before patch_274 (falls back without the new columns)',
    () async {
      var calls = 0;
      setFakeSupabaseHandler((req) {
        if (!req.url.path.endsWith('/profiles')) return null;
        calls++;
        final select = req.url.queryParameters['select'] ?? '';
        if (select.contains('is_private')) {
          return const FakeError(400, {
            'code': '42703',
            'message': 'column profiles.is_private does not exist',
          });
        }
        return {'id': 'them', 'full_name': 'Rudo Moyo', 'username': 'rudo'};
      });
      final p = await UserProfileService.fetch('them');
      expect(p?.fullName, 'Rudo Moyo');
      expect(p?.username, 'rudo');
      expect(p?.isPrivate, isFalse);
      expect(calls, 2);
    },
  );
}
