// Only ONE Supabase client may refresh tokens.
//
// Supabase rotates refresh tokens: every refresh issues a new one and
// REVOKES the old one. So a second GoTrue client pointed at the same
// persisted session is destructive, not merely wasteful — it revokes the
// token the foreground app is holding, and the app's next refresh is
// rejected, which supabase_flutter surfaces as AuthChangeEvent.signedOut.
//
// That is what signed the founder out of a production build on 16-17 Aug
// 2026. The signature is unmistakable once you know it: auth.sessions shows
// the session present and recently refreshed, auth.refresh_tokens shows a
// token issued and never used, and the audit log has no logout — because
// nobody logged out.
//
// The FCM background handler runs in its own isolate with its own globals,
// so it built its own client. These checks pin the rule at the only place
// it is expressible without a device: the source itself.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('background isolate must not refresh tokens', () {
    test('the FCM background handler uses the non-refreshing bootstrap', () {
      final src = _read('lib/services/push_service.dart');
      expect(
        src.contains('startSupabaseInitForBackgroundIsolate'),
        isTrue,
        reason: 'the background handler must not build a refreshing client',
      );
      // The bare call is what caused the bug. It must not reappear here.
      final bareCall = RegExp(r'AppBootstrap\.startSupabaseInit\s*\(\s*\)');
      expect(
        bareCall.hasMatch(src),
        isFalse,
        reason: 'AppBootstrap.startSupabaseInit() in a background isolate '
            'rotates the same refresh token as the app and signs the user out',
      );
    });

    test('exactly one place opts into token refresh, and it is main()', () {
      final lib = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final bareCall = RegExp(r'AppBootstrap\.startSupabaseInit\s*\(\s*\)');
      final callers = <String>[
        for (final f in lib)
          if (bareCall.hasMatch(f.readAsStringSync())) f.path,
      ];

      expect(
        callers.length,
        1,
        reason: 'only the UI isolate may own token refresh; found: $callers',
      );
      expect(callers.single.replaceAll(r'\', '/'), endsWith('lib/main.dart'));
    });

    test('the defensive fallback does not silently enable refresh', () {
      // awaitSupabaseReady() kicks off init if nothing has yet. If that
      // fallback defaults to refreshing, any future background caller
      // re-introduces the bug without touching push_service.dart.
      final src = _read('lib/config/app_bootstrap.dart');
      final fallback = RegExp(
        r'if\s*\(\s*ready\s*==\s*null\s*\)\s*\{[^}]*startSupabaseInit\(\s*autoRefreshToken:\s*false\s*\)',
        dotAll: true,
      );
      expect(
        fallback.hasMatch(src),
        isTrue,
        reason: 'awaitSupabaseReady must fall back to a NON-refreshing client',
      );
    });
  });
}
