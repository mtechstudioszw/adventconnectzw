// Founder rule, 27 Oct 2026: **Advent AI has exactly one entry point — the
// Chat tab's inbox.**
//
// It used to be an app-wide floating bubble that hid itself on a route
// blocklist. The blocklist read `currentConfiguration.uri.path`, which a
// go_router `push` does not update, so a chat pushed from a profile
// (`/users/<id>` → push `/messages/<id>`) still reported `/users/<id>` and
// the bubble floated over a private conversation. The bubble was removed
// rather than patched: no layer above the Navigator can know reliably
// which screen is on top.
//
// Same shape of test as `ads_never_in_chat_test.dart`: source scans, so a
// regression is caught without needing a device.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _messagingDir = 'lib/screens/messaging';
const _inbox = 'lib/screens/messaging/conversations_screen.dart';

/// Files allowed to name the Advent AI route: its definition, the screen
/// itself, and the one entry point.
const _routeAllowed = <String>{
  'lib/config/router_config.dart',
  'lib/screens/advent_ai/advent_ai_screen.dart',
  _inbox,
};

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String _norm(String path) => path.replaceAll(r'\', '/');

void main() {
  test('no floating Advent AI layer exists', () {
    expect(File('lib/widgets/advent_ai_bubble.dart').existsSync(), isFalse,
        reason: 'the app-wide bubble was removed — founder, 27 Oct 2026');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('AdventAi'), isFalse,
        reason: 'nothing AI-related belongs in MaterialApp.builder');
  });

  test('only the inbox navigates to Advent AI', () {
    final offenders = <String>[];
    for (final file in _dartFiles('lib')) {
      final path = _norm(file.path);
      if (_routeAllowed.contains(path)) continue;
      final source = file.readAsStringSync();
      if (source.contains("'/advent-ai") ||
          source.contains("Named('advent_ai'") ||
          source.contains('AdventAiScreen(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'Advent AI is reachable from the Chat tab only');
  });

  test('no conversation screen carries Advent AI', () {
    // Everything under messaging except the inbox is a conversation or
    // something opened from inside one.
    final offenders = <String>[];
    for (final file in _dartFiles(_messagingDir)) {
      final path = _norm(file.path);
      if (path == _inbox) continue;
      final source = file.readAsStringSync();
      if (source.contains('AdventAi') ||
          source.contains('advent_ai') ||
          source.contains('/advent-ai')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'a private conversation must never show Advent AI');
  });

  test('the inbox still offers Advent AI', () {
    // The positive half — a cleanup that removed this would otherwise look
    // like a tidy-up rather than the feature losing its only door.
    expect(File(_inbox).readAsStringSync().contains("'/advent-ai'"), isTrue);
  });
}
