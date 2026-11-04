import 'package:advent_connect_zw/services/quiz_music.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner, 4 Nov 2026: quiz music kept playing after leaving the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(QuizMusic.resetForTest);

  test('leaving the quiz forgets the music, so returning to the app '
      'does not restart it', () async {
    await QuizMusic.start(); // no audio platform here; wanted is what counts
    expect(QuizMusic.debugWanted, isTrue);
    await QuizMusic.stop();
    expect(QuizMusic.debugWanted, isFalse);
    await QuizMusic.handleLifecycle(AppLifecycleState.resumed);
    expect(QuizMusic.debugWanted, isFalse);
  });

  test('backgrounding keeps the arena wanting music for when it returns',
      () async {
    await QuizMusic.start();
    await QuizMusic.handleLifecycle(AppLifecycleState.paused);
    expect(QuizMusic.debugWanted, isTrue);
    await QuizMusic.handleLifecycle(AppLifecycleState.hidden);
    await QuizMusic.handleLifecycle(AppLifecycleState.resumed);
    expect(QuizMusic.debugWanted, isTrue);
  });
}
