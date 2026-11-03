import 'package:advent_connect_zw/services/quiz_generator_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hard templates appear, are valid and are marked hard', () async {
    final qs = await QuizGenerator.generate(count: 400, seed: 7);
    expect(qs.length, greaterThan(300));
    final kinds = <String, int>{};
    for (final q in qs) {
      final kind = q.id.split(':')[1];
      kinds[kind] = (kinds[kind] ?? 0) + 1;
      expect(q.options.length, 4, reason: q.id);
      expect(q.options.toSet().length, 4, reason: 'duplicate option ${q.id}');
      expect(q.correctIndex, inInclusiveRange(0, 3), reason: q.id);
      if (kind == 'finish' || kind == 'next' || kind == 'chapter') {
        expect(q.difficulty, 'hard');
      }
    }
    for (final k in ['finish', 'next', 'chapter', 'after']) {
      expect(kinds[k] ?? 0, greaterThan(5), reason: '$k missing: $kinds');
    }
    // ignore: avoid_print
    print(kinds);
    for (final k in ['finish', 'next', 'chapter', 'after']) {
      final q = qs.firstWhere((q) => q.id.split(':')[1] == k);
      // ignore: avoid_print
      print('--- ${q.question}\n    ${q.options}\n    answer: ${q.options[q.correctIndex]} (${q.reference})');
    }
  });
}
