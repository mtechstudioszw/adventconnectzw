// Offline-first chat (1 Nov 2026): pins, reactions, stars and pinned
// messages are kept on the phone and queued, so they never "forget".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:advent_connect_zw/models/message_model.dart';
import 'package:advent_connect_zw/services/cache_service.dart';
import 'package:advent_connect_zw/services/chat_sync_service.dart';

import 'helpers/fake_supabase.dart';

const _me = '00000000-0000-4000-8000-0000000000aa';

void main() {
  late Directory dir;
  var seq = 0;

  setUpAll(() async {
    // Every network call fails, as if offline.
    await initFakeSupabase(
      (req) => FakeError(503, {'message': 'offline'}),
    );
    await signInFake(_me);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chat_sync_test');
    Hive.init(dir.path);
    // ignore: invalid_use_of_visible_for_testing_member
    await CacheService.debugUseBox(await Hive.openBox<String>('c${seq++}'));
    // ignore: invalid_use_of_visible_for_testing_member
    await ChatSync.debugUseBox(await Hive.openBox<String>('o${seq++}'));
  });

  tearDown(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    await CacheService.debugUseBox(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  group('chat pins survive a restart', () {
    test('a pin made offline shows on the next cold start', () async {
      await ChatSync.setFlags('12', pinned: true);
      // A "restart" reads only the phone's copy.
      final states = ChatSync.cachedStates();
      expect(states['12']?.pinned, isTrue);
    });

    test('a failed server read falls back to the cache, not to nothing',
        () async {
      await ChatSync.cacheStates({
        '7': const ConversationState(pinned: true),
      });
      final states = await ChatSync.loadStates();
      expect(states['7']?.pinned, isTrue);
    });

    test('later flag changes merge instead of replacing', () async {
      await ChatSync.setFlags('3', pinned: true);
      await ChatSync.setFlags('3', muted: true);
      final s = ChatSync.cachedStates()['3']!;
      expect(s.pinned, isTrue);
      expect(s.muted, isTrue);
    });
  });

  group('reactions made offline stay', () {
    test('a queued reaction is drawn on top of the cached ones', () async {
      final r = ChatSync.withPendingReactions('9', {
        '100': {'👍': 2},
      });
      expect(r['100'], {'👍': 2});
      await ChatSync.setReaction('9', '100', '❤️');
      final after = ChatSync.cachedReactions('9');
      expect(after['100']?['❤️'], 1);
      expect(after['100']?['_mine_❤️'], 1);
    });

    test('switching emoji replaces the old one, latest choice wins',
        () async {
      await ChatSync.setReaction('9', '200', '❤️');
      await ChatSync.setReaction('9', '200', '👍');
      final r = ChatSync.withPendingReactions('9', {
        '200': {'❤️': 1, '_mine_❤️': 1},
      });
      expect(r['200']?.containsKey('❤️'), isFalse);
      expect(r['200']?['👍'], 1);
      expect(r['200']?['_mine_👍'], 1);
    });

    test('removing a reaction offline takes it off', () async {
      await ChatSync.setReaction('9', '300', null);
      final r = ChatSync.withPendingReactions('9', {
        '300': {'🙏': 3, '_mine_🙏': 1},
      });
      expect(r['300'], {'🙏': 2});
    });

    test('nothing is lost while the server is unreachable', () async {
      await ChatSync.setReaction('9', '400', '🙏');
      expect(await ChatSync.flush(), 0);
      expect(ChatSync.pendingCount, greaterThan(0));
      expect(ChatSync.cachedReactions('9')['400']?['_mine_🙏'], 1);
    });
  });

  group('what counts as a real refusal', () {
    test('overload and timeouts are retried, not dropped', () {
      bool refused(String? code) => ChatSync.isPermanentRefusal(
        PostgrestException(message: 'x', code: code),
      );
      expect(refused(null), isFalse); // a 503 with no SQLSTATE
      expect(refused('503'), isFalse);
      expect(refused('57014'), isFalse); // statement timeout
      expect(refused('PGRST301'), isFalse); // expired token
      expect(refused('53300'), isFalse); // too many connections
      expect(refused('23503'), isTrue); // message was deleted
      expect(refused('42501'), isTrue); // not allowed
    });
  });

  group('stars and pinned messages', () {
    test('a star made offline is remembered', () async {
      await ChatSync.setStar('5', '50', true);
      expect(ChatSync.cachedStars('5'), contains('50'));
      await ChatSync.setStar('5', '50', false);
      expect(ChatSync.cachedStars('5'), isNot(contains('50')));
    });

    test('a pinned message set offline wins until it syncs', () async {
      expect(ChatSync.pendingPinned('5'), isNull);
      await ChatSync.setPinnedMessage('5', '77');
      expect(ChatSync.pendingPinned('5'), '77');
      await ChatSync.setPinnedMessage('5', null);
      expect(ChatSync.pendingPinned('5'), '');
    });
  });
}
