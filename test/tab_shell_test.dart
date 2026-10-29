// The five tabs live in one StatefulShellRoute and TabShell draws the only
// island (27 Oct 2026). Before that every tab screen drew its own, and each
// tab switch disposed the screen being left.
//
// Source scans, like ads_never_in_chat_test.dart: a regression here is a
// second island or a lost tab state, and both are easy to reintroduce by
// copying an old screen's build method.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tabScreens = <String>[
  'lib/screens/home/home_screen.dart',
  'lib/screens/library/library_hub_screen.dart',
  'lib/screens/messaging/conversations_screen.dart',
  'lib/screens/marketplace/marketplace_screen.dart',
  'lib/screens/profile/profile_screen.dart',
];

void main() {
  test('no tab screen draws its own island', () {
    for (final path in _tabScreens) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('MainBottomNav('),
        isFalse,
        reason: '$path would render a second island over TabShell\'s',
      );
      expect(
        source.contains('NavVisibilityMixin'),
        isFalse,
        reason: '$path: hide-on-scroll belongs to TabShell',
      );
    }
  });

  test('the tabs are a StatefulShellRoute rendered by TabShell', () {
    final router = File('lib/config/router_config.dart').readAsStringSync();
    expect(router.contains('StatefulShellRoute.indexedStack('), isTrue);
    expect(router.contains('TabShell(shell: shell)'), isTrue);
  });

  test('every tab route is declared exactly once', () {
    // A leftover top-level copy of a tab route would shadow the shell one.
    final router = File('lib/config/router_config.dart').readAsStringSync();
    for (final path in const [
      "'/home'",
      "'/library'",
      "'/messages'",
      "'/marketplace'",
      "'/profile'",
    ]) {
      expect(
        RegExp('path: ${RegExp.escape(path)},').allMatches(router).length,
        1,
        reason: path,
      );
    }
  });

  test('nothing pushes a tab route on top of the shell', () {
    // Pushing a shell branch duplicates its navigator. Switch with goNamed
    // (or ConversationsScreen.openRequests for Chat → Requests).
    final offenders = <String>[];
    final push = RegExp(
      // Library's tab is `library_hub`; `library` (no suffix) is the
      // reader, a full-screen route that is pushed on purpose.
      r"push(Named)?\(\s*'(/?(home|messages|marketplace|profile)|library_hub|/library)['?]",
      multiLine: true,
    );
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      if (push.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
    expect(offenders, isEmpty);
  });
}
