// Guards against mojibake creeping back into the source.
//
// On 2 Aug 2026 the founder reported "a word I can't even read" in
// Settings. The string was `Made with care â€¢ MyTech Studios Zw` — a
// `•` that had been written as UTF-8, read back as cp1252, and saved
// again as UTF-8. A sweep found 28 of them across three screens, eight
// of which were user-visible (a notification label, the support email
// subject, the WhatsApp prefill, two theme descriptions, a button's
// busy state).
//
// The corruption is mechanical: every UTF-8 byte of the original
// character becomes its own cp1252 character, so the run always starts
// with one of the UTF-8 lead bytes Â (U+00C2), Ã (U+00C3) or â (U+00E2)
// followed by a character from cp1252's high range. That signature is
// what this test looks for. It costs a few milliseconds and it runs on
// every branch push via `.github/workflows/analyze.yml`.
//
// If this fails: do not hand-retype the character. Find the run, decode
// it (UTF-8 bytes misread as cp1252) and write the real character back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The three characters a mojibake run can begin with, as escapes so
/// that this file stays clean of the thing it is testing for.
const _leads = 'ÂÃâ';

/// The characters cp1252 maps its 0x80–0xBF bytes to. A UTF-8
/// continuation byte lands in exactly this set, so a lead followed by
/// one of these is corruption rather than prose.
const _followers = {
  // 0x80–0x9F: cp1252's "smart" punctuation block.
  '€', '‚', 'ƒ', '„', '…', '†', '‡',
  'ˆ', '‰', 'Š', '‹', 'Œ', 'Ž', '‘',
  '’', '“', '”', '•', '–', '—', '˜',
  '™', 'š', '›', 'œ', 'ž', 'Ÿ',
};

bool _isFollower(int rune) =>
    (rune >= 0xA0 && rune <= 0xBF) ||
    _followers.contains(String.fromCharCode(rune));

/// Returns `line:column` for every mojibake run in [source].
List<String> _findMojibake(String source) {
  final found = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (var j = 0; j < line.length - 1; j++) {
      if (_leads.contains(line[j]) && _isFollower(line.codeUnitAt(j + 1))) {
        final run = line.substring(j, (j + 3).clamp(0, line.length));
        found.add('${i + 1}:${j + 1} ${jsonish(run)}');
      }
    }
  }
  return found;
}

/// The offending run, printed as escapes — printing it raw would just
/// produce more unreadable output in the test log.
String jsonish(String run) =>
    run.runes.map((r) => '\\u${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join();

void main() {
  test('no source file contains mojibake', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue,
        reason: 'run this from the package root');

    final offenders = <String, List<String>>{};
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final hits = _findMojibake(entity.readAsStringSync());
      if (hits.isNotEmpty) offenders[entity.path] = hits;
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Mojibake found. Each entry is line:column and the runes '
          'of the corrupt run:\n'
          '${offenders.entries.map((e) => '  ${e.key}\n    ${e.value.join('\n    ')}').join('\n')}',
    );
  });
}
