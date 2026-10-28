// A Supabase client whose HTTP goes to an in-test handler instead of the
// network, so screens that read through the static services can be pumped.
//
// Usage: `await initFakeSupabase((req) => ...)` once in `setUpAll`. The
// handler sees every REST call (`/rest/v1/<table>?...`); return JSON bodies
// shaped like PostgREST's. Anything unhandled gets `[]`, which PostgREST
// clients read as "no rows".

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// May return a Future, to simulate a slow response.
typedef FakeHandler = FutureOr<Object?> Function(http.Request request);

/// Every request the fake has seen, newest last.
final List<http.Request> fakeSupabaseRequests = [];

FakeHandler _handler = (_) => null;

/// Replace the handler between tests without re-initialising.
void setFakeSupabaseHandler(FakeHandler handler) {
  _handler = handler;
  fakeSupabaseRequests.clear();
}

/// Signs in as [userId] by answering GoTrue's password grant locally, so
/// services that need `auth.currentUser` work. Call after [initFakeSupabase].
Future<void> signInFake(String userId, {String country = 'ZW'}) async {
  final previous = _handler;
  _handler = (req) {
    if (req.url.path.endsWith('/auth/v1/token')) {
      return {
        'access_token': 'fake-access-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'refresh_token': 'fake-refresh-token',
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': '$userId@example.test',
          'app_metadata': <String, Object?>{},
          'user_metadata': {'country': country},
          'created_at': '2026-01-01T00:00:00Z',
        },
      };
    }
    return previous(req);
  };
  await Supabase.instance.client.auth.signInWithPassword(
    email: '$userId@example.test',
    password: 'x',
  );
  _handler = previous;
}

Future<void> initFakeSupabase([FakeHandler? handler]) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  if (handler != null) _handler = handler;
  await Supabase.initialize(
    url: 'https://fake.supabase.test',
    anonKey: 'fake-anon-key',
    debug: false,
    httpClient: MockClient((request) async {
      fakeSupabaseRequests.add(request);
      final body = await _handler(request) ?? const <Object>[];
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
        // postgrest reads the method back off the response.
        request: request,
      );
    }),
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
      autoRefreshToken: false,
    ),
  );
}
