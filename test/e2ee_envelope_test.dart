import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/e2ee/e2ee_envelope.dart';
import 'package:advent_connect_zw/services/e2ee/e2ee_service.dart';

/// The envelope's job is to be un-breakable.
///
/// Every one of these cases is a real row that will exist in production:
/// a message from before the feature, a message from a member on a newer
/// build, a message encrypted to an install that no longer exists. None
/// of them may throw, and none may leak base64 into a bubble — a chat
/// screen that will not paint is far worse than one unreadable message.
///
/// These run with NO Supabase and NO key store, which is the point:
/// every branch below has to reach its verdict without decrypting.
void main() {
  Map<String, dynamic> row({
    Object? version,
    String content = 'AAAA',
    String sender = 'bob',
    Object? device = 1,
    Object? type = 2,
  }) => <String, dynamic>{
    'id': 1,
    'sender_id': sender,
    'content': content,
    'e2ee_version': ?version,
    'sender_device_id': ?device,
    'ciphertext_type': ?type,
  };

  Future<String> contentOf(
    Map<String, dynamic> input, {
    bool isGroup = false,
    String? me = 'alice',
  }) async {
    final out = await E2eeEnvelope.decryptRow(
      input,
      conversationId: 'c1',
      isGroup: isGroup,
      myUserId: me,
    );
    return out['content'].toString();
  }

  group('rows that are not encrypted pass straight through', () {
    test('a message from before the feature keeps its plaintext — this is '
        'what makes every existing thread stay readable forever', () async {
      final legacy = <String, dynamic>{
        'id': 1,
        'sender_id': 'bob',
        'content': 'Happy Sabbath',
      };
      expect(await contentOf(legacy), 'Happy Sabbath');
      expect(E2eeEnvelope.isEncrypted(legacy), isFalse);
    });

    test('an explicit version 0 is not encrypted', () async {
      expect(await contentOf(row(version: 0, content: 'plain')), 'plain');
    });

    test('the row object is returned unchanged, not rebuilt', () async {
      final legacy = <String, dynamic>{'id': 1, 'content': 'x'};
      final out = await E2eeEnvelope.decryptRow(
        legacy,
        conversationId: 'c1',
        isGroup: false,
        myUserId: 'alice',
      );
      expect(identical(out, legacy), isTrue);
    });
  });

  group('unreadable rows become the placeholder, never base64', () {
    test('a NEWER wire version than this build knows', () async {
      expect(
        await contentOf(row(version: E2eeService.wireVersion + 1)),
        E2eeEnvelope.placeholder,
      );
    });

    test('a missing sender_device_id', () async {
      expect(
        await contentOf(row(version: 1, device: null)),
        E2eeEnvelope.placeholder,
      );
    });

    test('a missing ciphertext_type — the recipient cannot guess which '
        'kind of message it is', () async {
      expect(
        await contentOf(row(version: 1, type: null)),
        E2eeEnvelope.placeholder,
      );
    });

    test('a missing sender', () async {
      expect(
        await contentOf(row(version: 1, sender: '')),
        E2eeEnvelope.placeholder,
      );
    });

    test('undecryptable ciphertext with no key store at all', () async {
      // E2eeService has never been started here, so decryptDirect returns
      // null. The bubble must still be renderable.
      expect(
        await contentOf(row(version: 1, content: 'bm90LXJlYWw=')),
        E2eeEnvelope.placeholder,
      );
    });

    test('garbage that is not even base64 does not throw', () async {
      expect(
        await contentOf(row(version: 1, content: '!!!not base64!!!')),
        E2eeEnvelope.placeholder,
      );
    });
  });

  group('our own outgoing messages', () {
    test('are flagged rather than attempted — the ratchet cannot decrypt '
        'what it encrypted', () async {
      final out = await E2eeEnvelope.decryptRow(
        row(version: 1, sender: 'alice'),
        conversationId: 'c1',
        isGroup: false,
        myUserId: 'alice',
      );
      expect(out['_e2ee_own'], isTrue);
      expect(out['content'], E2eeEnvelope.placeholder);
    });

    test('someone else\'s message is not flagged as ours', () async {
      final out = await E2eeEnvelope.decryptRow(
        row(version: 1, sender: 'bob'),
        conversationId: 'c1',
        isGroup: false,
        myUserId: 'alice',
      );
      expect(out.containsKey('_e2ee_own'), isFalse);
    });
  });

  group('version gating', () {
    test('the current version is readable', () {
      expect(
        E2eeEnvelope.isReadableVersion(row(version: E2eeService.wireVersion)),
        isTrue,
      );
    });

    test('a future version is not', () {
      expect(
        E2eeEnvelope.isReadableVersion(
          row(version: E2eeService.wireVersion + 1),
        ),
        isFalse,
      );
    });
  });

  group('batches', () {
    test('every row comes back, in order, whatever state each is in', () async {
      final rows = [
        <String, dynamic>{'id': 1, 'sender_id': 'bob', 'content': 'old'},
        row(version: 1, content: 'bm90LXJlYWw='),
        <String, dynamic>{'id': 3, 'sender_id': 'bob', 'content': 'also old'},
      ];
      final out = await E2eeEnvelope.decryptRows(
        rows,
        conversationId: 'c1',
        isGroup: false,
        myUserId: 'alice',
      );
      expect(out.length, 3);
      expect(out[0]['content'], 'old');
      expect(out[1]['content'], E2eeEnvelope.placeholder);
      expect(out[2]['content'], 'also old');
    });
  });
}
