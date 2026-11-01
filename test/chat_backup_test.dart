// End-to-end encrypted chat backup: the file format and its password.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/e2ee/chat_backup_service.dart';

void main() {
  // Fewer rounds in tests; the format stores the count it was made with.
  Uint8List key(String pw, Uint8List salt) =>
      SealedBackup.deriveKey(pw, salt, 1000);

  final entries = {
    'plain/101': 'See you at choir practice',
    'plain/102': '{"e2m":1,"t":"image","k":"a","n":"b"}',
    'preview/7': 'Amen 🙏',
  };

  test('a backup opens with the right password and gives everything back',
      () {
    final salt = SealedBackup.random(16);
    final file = SealedBackup.seal(entries, key('correct horse', salt), salt);
    final head = SealedBackup.header(file)!;
    expect(head.salt, salt);
    expect(SealedBackup.open(file, key('correct horse', head.salt)), entries);
  });

  test('a wrong password is refused, not turned into garbage', () {
    final salt = SealedBackup.random(16);
    final file = SealedBackup.seal(entries, key('right one', salt), salt);
    expect(
      () => SealedBackup.open(file, key('wrong one', salt)),
      throwsA(anything),
    );
  });

  test('the server copy holds no readable text', () {
    final salt = SealedBackup.random(16);
    final file = SealedBackup.seal(entries, key('pw', salt), salt);
    expect(String.fromCharCodes(file).contains('choir'), isFalse);
  });

  test('a file that is not a backup is recognised as such', () {
    expect(SealedBackup.header(Uint8List.fromList([1, 2, 3])), isNull);
    expect(
      SealedBackup.header(Uint8List(80)),
      isNull,
    );
  });
}
