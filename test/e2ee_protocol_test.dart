import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Proof that the Signal protocol works end to end in this project,
/// before a single message is wired through it.
///
/// This is not a test of our code — it is a test of the assumption the
/// whole feature rests on, run on a machine with no phone attached. There
/// is no device to try E2EE on here (see the build notes), and a ratchet
/// that is subtly wrong does not throw: it silently produces messages
/// nobody can ever read again. So the round trips get pinned in CI.
///
/// Covers the two shapes the app needs, which are the two WhatsApp uses:
///   * 1:1 — X3DH to establish, Double Ratchet thereafter;
///   * groups — Sender Keys, one encryption per message regardless of how
///     many members there are.
void main() {
  /// A whole party: identity, registration id, prekeys and a store.
  ({
    InMemorySignalProtocolStore store,
    PreKeyBundle bundle,
    int registrationId,
  }) party({required int deviceId}) {
    final identity = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    final store = InMemorySignalProtocolStore(identity, registrationId);

    final preKey = generatePreKeys(0, 1).first;
    final signedPreKey = generateSignedPreKey(identity, 0);
    store.storePreKey(preKey.id, preKey);
    store.storeSignedPreKey(signedPreKey.id, signedPreKey);

    return (
      store: store,
      registrationId: registrationId,
      bundle: PreKeyBundle(
        registrationId,
        deviceId,
        preKey.id,
        preKey.getKeyPair().publicKey,
        signedPreKey.id,
        signedPreKey.getKeyPair().publicKey,
        signedPreKey.signature,
        identity.getPublicKey(),
      ),
    );
  }

  group('1:1 — X3DH + Double Ratchet', () {
    test('a message survives the round trip, and only the recipient can '
        'read it', () async {
      final alice = party(deviceId: 1);
      final bob = party(deviceId: 1);
      final bobAddress = SignalProtocolAddress('bob', 1);
      final aliceAddress = SignalProtocolAddress('alice', 1);

      // Alice builds a session from Bob's published bundle. No round trip
      // to Bob is needed — this is the point of X3DH, and it is what lets
      // someone message an offline member.
      await SessionBuilder.fromSignalStore(
        alice.store,
        bobAddress,
      ).processPreKeyBundle(bob.bundle);

      final aliceCipher = SessionCipher.fromStore(alice.store, bobAddress);
      final plaintext = 'Makadii, tinosangana neSvondo.';
      final ciphertext = await aliceCipher.encrypt(
        Uint8List.fromList(utf8.encode(plaintext)),
      );

      // The wire must not carry the message.
      expect(
        utf8.decode(ciphertext.serialize(), allowMalformed: true),
        isNot(contains('Makadii')),
      );

      final bobCipher = SessionCipher.fromStore(bob.store, aliceAddress);
      final decrypted = await bobCipher.decryptWithCallback(
        PreKeySignalMessage(ciphertext.serialize()),
        (_) {},
      );
      expect(utf8.decode(decrypted), plaintext);
    });

    test('the ratchet turns — consecutive messages get different '
        'ciphertext for identical plaintext', () async {
      final alice = party(deviceId: 1);
      final bob = party(deviceId: 1);
      final bobAddress = SignalProtocolAddress('bob', 1);

      await SessionBuilder.fromSignalStore(
        alice.store,
        bobAddress,
      ).processPreKeyBundle(bob.bundle);
      final cipher = SessionCipher.fromStore(alice.store, bobAddress);

      final body = Uint8List.fromList(utf8.encode('same words'));
      final first = await cipher.encrypt(body);
      final second = await cipher.encrypt(body);

      expect(first.serialize(), isNot(equals(second.serialize())));
    });

    test('a reply flows back the other way on the same session', () async {
      final alice = party(deviceId: 1);
      final bob = party(deviceId: 1);
      final bobAddress = SignalProtocolAddress('bob', 1);
      final aliceAddress = SignalProtocolAddress('alice', 1);

      await SessionBuilder.fromSignalStore(
        alice.store,
        bobAddress,
      ).processPreKeyBundle(bob.bundle);
      final aliceCipher = SessionCipher.fromStore(alice.store, bobAddress);
      final bobCipher = SessionCipher.fromStore(bob.store, aliceAddress);

      final opener = await aliceCipher.encrypt(
        Uint8List.fromList(utf8.encode('are you coming?')),
      );
      await bobCipher.decryptWithCallback(
        PreKeySignalMessage(opener.serialize()),
        (_) {},
      );

      final reply = await bobCipher.encrypt(
        Uint8List.fromList(utf8.encode('yes, after vespers')),
      );
      final got = await aliceCipher.decryptFromSignal(
        SignalMessage.fromSerialized(reply.serialize()),
      );
      expect(utf8.decode(got), 'yes, after vespers');
    });

    test('a stranger holding the ciphertext cannot decrypt it', () async {
      final alice = party(deviceId: 1);
      final bob = party(deviceId: 1);
      final eve = party(deviceId: 1);
      final bobAddress = SignalProtocolAddress('bob', 1);
      final aliceAddress = SignalProtocolAddress('alice', 1);

      await SessionBuilder.fromSignalStore(
        alice.store,
        bobAddress,
      ).processPreKeyBundle(bob.bundle);
      final ciphertext = await SessionCipher.fromStore(
        alice.store,
        bobAddress,
      ).encrypt(Uint8List.fromList(utf8.encode('private')));

      // Eve has her own keys and the bytes off the wire. That is exactly
      // what a compromised server would have.
      final eveCipher = SessionCipher.fromStore(eve.store, aliceAddress);
      await expectLater(
        eveCipher.decryptWithCallback(
          PreKeySignalMessage(ciphertext.serialize()),
          (_) {},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('groups — Sender Keys', () {
    test('one encryption reaches every member', () async {
      final senderAddress = SignalProtocolAddress('tendai', 1);
      final groupId = 'conversation-4821';
      final senderKeyName = SenderKeyName(groupId, senderAddress);

      final senderStore = InMemorySenderKeyStore();
      final memberOneStore = InMemorySenderKeyStore();
      final memberTwoStore = InMemorySenderKeyStore();

      // The sender creates its chain and distributes it ONCE per member,
      // over the pairwise channel. Messages afterwards are encrypted a
      // single time no matter how many members there are — the property
      // that makes group E2EE affordable.
      final distribution = await GroupSessionBuilder(
        senderStore,
      ).create(senderKeyName);

      for (final store in [memberOneStore, memberTwoStore]) {
        await GroupSessionBuilder(store).process(
          senderKeyName,
          SenderKeyDistributionMessageWrapper.fromSerialized(
            distribution.serialize(),
          ),
        );
      }

      final ciphertext = await GroupCipher(
        senderStore,
        senderKeyName,
      ).encrypt(Uint8List.fromList(utf8.encode('Choir practice at 4')));

      for (final store in [memberOneStore, memberTwoStore]) {
        final got = await GroupCipher(store, senderKeyName).decrypt(ciphertext);
        expect(utf8.decode(got), 'Choir practice at 4');
      }
    });

    test('a member who never received the distribution cannot read it — '
        'this is what makes removing someone from a group mean '
        'something', () async {
      final senderKeyName = SenderKeyName(
        'conversation-4821',
        SignalProtocolAddress('tendai', 1),
      );
      final senderStore = InMemorySenderKeyStore();
      await GroupSessionBuilder(senderStore).create(senderKeyName);

      final ciphertext = await GroupCipher(
        senderStore,
        senderKeyName,
      ).encrypt(Uint8List.fromList(utf8.encode('members only')));

      final outsider = InMemorySenderKeyStore();
      await expectLater(
        GroupCipher(outsider, senderKeyName).decrypt(ciphertext),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('safety numbers', () {
    test('both sides compute the SAME fingerprint — this is the number a '
        'member reads out to verify a contact', () async {
      final alice = generateIdentityKeyPair();
      final bob = generateIdentityKeyPair();
      final generator = NumericFingerprintGenerator(5200);

      final aliceView = generator.createFor(
        2,
        Uint8List.fromList(utf8.encode('alice')),
        alice.getPublicKey(),
        Uint8List.fromList(utf8.encode('bob')),
        bob.getPublicKey(),
      );
      final bobView = generator.createFor(
        2,
        Uint8List.fromList(utf8.encode('bob')),
        bob.getPublicKey(),
        Uint8List.fromList(utf8.encode('alice')),
        alice.getPublicKey(),
      );

      expect(
        aliceView.displayableFingerprint.getDisplayText(),
        bobView.displayableFingerprint.getDisplayText(),
      );
    });

    test('a different identity produces a different number, which is how '
        'a key change is noticed at all', () async {
      final alice = generateIdentityKeyPair();
      final bob = generateIdentityKeyPair();
      final bobReinstalled = generateIdentityKeyPair();
      final generator = NumericFingerprintGenerator(5200);

      String numberFor(IdentityKeyPair theirs) {
        final fp = generator.createFor(
          2,
          Uint8List.fromList(utf8.encode('alice')),
          alice.getPublicKey(),
          Uint8List.fromList(utf8.encode('bob')),
          theirs.getPublicKey(),
        );
        return fp.displayableFingerprint.getDisplayText();
      }

      expect(numberFor(bob), isNot(numberFor(bobReinstalled)));
    });
  });
}
