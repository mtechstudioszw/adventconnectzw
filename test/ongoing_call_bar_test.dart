import 'package:advent_connect_zw/screens/calls/call_screen.dart';
import 'package:advent_connect_zw/services/calls/call_service.dart';
import 'package:advent_connect_zw/services/calls/call_state.dart';
import 'package:advent_connect_zw/widgets/ongoing_call_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back on the call screen now leaves it (owner, 3 Nov 2026: "you have to
/// close the entire app"). The way back is this bar: shown while a call is
/// live and its screen is not on top, never otherwise.
void main() {
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: OngoingCallBar())),
    );
    await t.pump(const Duration(milliseconds: 300));
  }

  tearDown(() {
    CallService.state.value = CallUiState.idle;
    CallScreen.onScreen.value = false;
  });

  testWidgets('hidden with no call', (t) async {
    await pump(t);
    expect(find.textContaining('return to call'), findsNothing);
  });

  testWidgets('shown during a live call off the call screen', (t) async {
    CallService.state.value = const CallUiState(
      phase: CallPhase.connecting,
      peerName: 'Rudo',
    );
    await pump(t);
    expect(find.text('Tap to return to call · Rudo'), findsOneWidget);
    expect(find.text('Connecting…'), findsOneWidget);
  });

  testWidgets('hidden while the call screen is on top', (t) async {
    CallService.state.value = const CallUiState(
      phase: CallPhase.connected,
      peerName: 'Rudo',
    );
    CallScreen.onScreen.value = true;
    await pump(t);
    expect(find.textContaining('return to call'), findsNothing);
  });

  testWidgets('hidden once the call has ended', (t) async {
    CallService.state.value = const CallUiState(phase: CallPhase.ended);
    await pump(t);
    expect(find.textContaining('return to call'), findsNothing);
  });
}
