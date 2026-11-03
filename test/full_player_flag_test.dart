import 'package:advent_connect_zw/services/music_player_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mini bar hides only while a full player is on screen. When this
/// flag stuck on true, Bible audio kept playing with no in-app controls
/// (owner, 3 Nov 2026). The flag follows a count, so out-of-order close /
/// reopen events can no longer strand it.
void main() {
  setUp(() {
    while (MusicPlayerService.fullPlayerOpen.value) {
      MusicPlayerService.fullPlayerUnmounted();
    }
  });

  test('open then close shows the bar again', () {
    MusicPlayerService.fullPlayerOpen.value = true; // the bar pre-hides
    MusicPlayerService.fullPlayerMounted();
    MusicPlayerService.fullPlayerRouteClosed(); // pop completes first
    expect(
      MusicPlayerService.fullPlayerOpen.value,
      isTrue,
      reason: 'still animating out',
    );
    MusicPlayerService.fullPlayerUnmounted();
    expect(MusicPlayerService.fullPlayerOpen.value, isFalse);
  });

  test('reopen while the old one animates out stays hidden, then shows', () {
    MusicPlayerService.fullPlayerMounted(); // first
    MusicPlayerService.fullPlayerRouteClosed();
    MusicPlayerService.fullPlayerMounted(); // reopened quickly
    MusicPlayerService.fullPlayerUnmounted(); // old one's late dispose
    expect(MusicPlayerService.fullPlayerOpen.value, isTrue);
    MusicPlayerService.fullPlayerUnmounted(); // the new one closes
    MusicPlayerService.fullPlayerRouteClosed();
    expect(MusicPlayerService.fullPlayerOpen.value, isFalse);
  });

  test('a route that never built does not strand the flag', () {
    MusicPlayerService.fullPlayerOpen.value = true;
    MusicPlayerService.fullPlayerRouteClosed();
    expect(MusicPlayerService.fullPlayerOpen.value, isFalse);
  });

  test('an extra unmount cannot go negative', () {
    MusicPlayerService.fullPlayerUnmounted();
    MusicPlayerService.fullPlayerMounted();
    expect(MusicPlayerService.fullPlayerOpen.value, isTrue);
    MusicPlayerService.fullPlayerUnmounted();
    expect(MusicPlayerService.fullPlayerOpen.value, isFalse);
  });
}
