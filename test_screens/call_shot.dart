// Render harness for calls (not shipped).
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/screens/calls/call_history_screen.dart';
import 'package:advent_connect_zw/screens/calls/call_screen.dart';
import 'package:advent_connect_zw/services/calls/call_service.dart';
import 'package:advent_connect_zw/services/calls/call_state.dart';

import '../test/helpers/fake_supabase.dart';
import 'shot.dart';

void main() {
  setUpAll(() async {
    await loadShotFonts();
    final mm = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in [
      'flutter_callkit_incoming',
      'FlutterWebRTC.Method',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      mm.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    await initFakeSupabase();
    await signInFake('me', metadata: {'full_name': 'Tanatswa Mikuwa'});
    setFakeSupabaseHandler((req) {
      final path = req.url.path;
      if (path.endsWith('/rpc/call_history')) {
        String ago(int m) => DateTime.now()
            .subtract(Duration(minutes: m))
            .toUtc()
            .toIso8601String();
        return [
          {
            'call_id': 'a', 'kind': 'direct', 'direction': 'outgoing',
            'outcome': 'completed', 'started_at': ago(30),
            'duration_seconds': 754, 'peer_name': 'Rudo Moyo',
            'peer_id': 'u1',
          },
          {
            'call_id': 'b', 'kind': 'direct', 'direction': 'incoming',
            'outcome': 'missed', 'started_at': ago(200),
            'duration_seconds': 0, 'peer_name': 'Tendai Chikwanha',
            'peer_id': 'u2',
          },
        ];
      }
      return [];
    });
  });

  for (final phase in [CallPhase.incoming, CallPhase.connected]) {
    testWidgets('call ${phase.name}', (t) async {
      CallService.debugSetState(
        CallUiState(
          phase: phase,
          outgoing: phase != CallPhase.incoming,
          peerName: 'Rudo Moyo',
          elapsed: const Duration(minutes: 3, seconds: 12),
        ),
      );
      await pumpShot(t, const CallScreen());
      await saveShot(t, 'call_${phase.name}');
    });
  }

  testWidgets('call history', (t) async {
    await pumpShot(t, const CallHistoryScreen());
    await saveShot(t, 'call_history');
  });
}
