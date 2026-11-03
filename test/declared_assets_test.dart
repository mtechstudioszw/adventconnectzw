import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every bundled file the code plays or loads must be declared in
/// pubspec.yaml, or it is simply not in the app — and audio/image loaders
/// fail SILENTLY. That is how the call ringback went missing: the WAV was
/// in the repo, `assets/sounds/call/` was never declared, and callers heard
/// nothing while the other phone rang (found 3 Nov 2026).
void main() {
  test('every asset path in lib/ exists and is declared', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^\s+- (assets/\S+)$',
      multiLine: true,
    ).allMatches(pubspec).map((m) => m.group(1)!).toList();

    // 'assets/…' literals, plus audioplayers' AssetSource paths, which
    // drop the leading 'assets/'.
    final literal = RegExp(
      r'''['"]((?:assets/)?(?:sounds|icon|bible|hymns|fonts|geo|images)/[\w/.\-]+\.\w+)['"]''',
    );
    final problems = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        var path = m.group(1)!;
        if (!path.startsWith('assets/')) path = 'assets/$path';
        if (path.contains(r'$')) continue; // interpolated, can't check
        final ok = declared.any(
          (d) => d.endsWith('/') ? path.startsWith(d) : path == d,
        );
        if (!ok) problems.add('${f.path}: $path is not declared in pubspec');
        if (!File(path).existsSync()) {
          problems.add('${f.path}: $path does not exist');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
