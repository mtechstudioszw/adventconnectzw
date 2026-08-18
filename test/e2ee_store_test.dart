import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:advent_connect_zw/services/e2ee/e2ee_store.dart';

/// The persistence half of E2EE.
///
/// The protocol tests prove the maths works. These prove the state
/// SURVIVES — which is the half that actually breaks in an app. A session
/// that does not reload is not a degraded experience; it is a thread of
/// messages nobody can ever open again, and it would not be noticed until
/// a member reopened a chat the next morning.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('e2ee_store_test');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// A store over a real on-disk box, without touching the platform
  /// keystore (which has no implementation in a unit test).
  Future<E2eeStore> storeFor(String userId, {IdentityKeyPair? identity}) async {
    final box = await Hive.openBox<String>(E2eeStore.boxName(userId));
    return E2eeStore.forTesting(
      userId: userId,
      box: box,
      identity: identity ?? generateIdentityKeyPair(),
      registrationId: generateRegistrationId(false),
    );
  }

  group('sessions survive a restart', () {
    test('a conversation opened before the "restart" still decrypts '
        'after it', () async {
      final aliceIdentity = generateIdentityKeyPair();
      final alice = await storeFor('alice', identity: aliceIdentity);

      // Bob is a plain in-memory party — only Alice's persistence is
      // under test here.
      final bobIdentity = generateIdentityKeyPair();
      final bobRegistration = generateRegistrationId(false);
      final bob = InMemorySignalProtocolStore(bobIdentity, bobRegistration);
      final bobPreKey = generatePreKeys(0, 1).first;
      final bobSigned = generateSignedPreKey(bobIdentity, 0);
      await bob.storePreKey(bobPreKey.id, bobPreKey);
      await bob.storeSignedPreKey(bobSigned.id, bobSigned);

      final bobAddress = SignalProtocolAddress('bob', 1);
      final aliceAddress = SignalProtocolAddress('alice', 1);

      await SessionBuilder.fromSignalStore(
        alice,
        bobAddress,
      ).processPreKeyBundle(
        PreKeyBundle(
          bobRegistration,
          1,
          bobPreKey.id,
          bobPreKey.getKeyPair().publicKey,
          bobSigned.id,
          bobSigned.getKeyPair().publicKey,
          bobSigned.signature,
          bobIdentity.getPublicKey(),
        ),
      );

      final opener = await SessionCipher.fromStore(
        alice,
        bobAddress,
      ).encrypt(Uint8List.fromList(utf8.encode('first')));
      await SessionCipher.fromStore(bob, aliceAddress).decryptWithCallback(
        PreKeySignalMessage(opener.serialize()),
        (_) {},
      );

      // THE RESTART. Close the box and open a brand new store over the
      // same files, exactly as a cold launch does.
      await Hive.close();
      Hive.init(tempDir.path);
      final aliceAgain = await storeFor('alice', identity: aliceIdentity);

      expect(
        await aliceAgain.containsSession(bobAddress),
        isTrue,
        reason: 'the session must reload, or the thread is unreadable',
      );

      final laterMessage = await SessionCipher.fromStore(
        aliceAgain,
        bobAddress,
      ).encrypt(Uint8List.fromList(utf8.encode('after a restart')));

      // Alice keeps sending PreKeySignalMessages until Bob's first reply
      // reaches her, so the recipient MUST branch on the type rather than
      // assume. This is precisely why patch_211 stores ciphertext_type
      // alongside the payload: the bytes do not say which they are, and
      // guessing wrong throws InvalidMessageException.
      final bobCipher = SessionCipher.fromStore(bob, aliceAddress);
      final got = laterMessage.getType() == CiphertextMessage.prekeyType
          ? await bobCipher.decryptWithCallback(
              PreKeySignalMessage(laterMessage.serialize()),
              (_) {},
            )
          : await bobCipher.decryptFromSignal(
              SignalMessage.fromSerialized(laterMessage.serialize()),
            );
      expect(utf8.decode(got), 'after a restart');
    });
  });

  group('per-user namespacing', () {
    test('two members on one phone get different boxes, so neither can '
        'read the other', () async {
      expect(E2eeStore.boxName('alice'), isNot(E2eeStore.boxName('bob')));
      expect(
        E2eeStore.identityStorageKey('alice'),
        isNot(E2eeStore.identityStorageKey('bob')),
      );
    });

    test('one member storing a session leaves the other empty', () async {
      final alice = await storeFor('alice');
      final bobAddress = SignalProtocolAddress('bob', 1);
      await alice.storeSession(bobAddress, SessionRecord());

      final other = await storeFor('carol');
      expect(await other.containsSession(bobAddress), isFalse);
    });
  });

  group('identity changes are detectable', () {
    test('a first sighting is not a change — otherwise every new contact '
        'would be announced as one', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      final bob = generateIdentityKeyPair().getPublicKey();

      expect(store.isKnownDifferentIdentity(address, bob), isFalse);
      expect(await store.saveIdentity(address, bob), isFalse);
    });

    test('the same key again is not a change', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      final bob = generateIdentityKeyPair().getPublicKey();

      await store.saveIdentity(address, bob);
      expect(store.isKnownDifferentIdentity(address, bob), isFalse);
      expect(await store.saveIdentity(address, bob), isFalse);
    });

    test('a reinstall IS a change — this is what drives the "security '
        'code changed" line', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      final bob = generateIdentityKeyPair().getPublicKey();
      final bobReinstalled = generateIdentityKeyPair().getPublicKey();

      await store.saveIdentity(address, bob);
      expect(store.isKnownDifferentIdentity(address, bobReinstalled), isTrue);
      expect(await store.saveIdentity(address, bobReinstalled), isTrue);
    });

    test('a changed identity is still TRUSTED — refusing would break the '
        'thread of anyone who simply got a new phone', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());

      expect(
        await store.isTrustedIdentity(
          address,
          generateIdentityKeyPair().getPublicKey(),
          Direction.sending,
        ),
        isTrue,
      );
    });
  });

  group('group sender keys', () {
    test('survive a restart', () async {
      final store = await storeFor('alice');
      final name = SenderKeyName('convo-1', SignalProtocolAddress('alice', 1));
      await GroupSessionBuilder(store).create(name);

      await Hive.close();
      Hive.init(tempDir.path);
      final again = await storeFor('alice');

      final reloaded = await again.loadSenderKey(name);
      expect(reloaded.isEmpty, isFalse);
    });

    test('clearing a group forgets its keys — the rotation that makes '
        '"removed from the group" mean something', () async {
      final store = await storeFor('alice');
      final kept = SenderKeyName('convo-2', SignalProtocolAddress('alice', 1));
      final cleared = SenderKeyName(
        'convo-1',
        SignalProtocolAddress('alice', 1),
      );
      await GroupSessionBuilder(store).create(kept);
      await GroupSessionBuilder(store).create(cleared);

      await store.clearGroupSenderKeys('convo-1');

      expect((await store.loadSenderKey(cleared)).isEmpty, isTrue);
      expect(
        (await store.loadSenderKey(kept)).isEmpty,
        isFalse,
        reason: 'clearing one group must not touch another',
      );
    });
  });

  group('security code changes are recorded', () {
    // libsignal calls saveIdentity from inside BOTH the send path
    // (processPreKeyBundle) and the receive path (decrypting a
    // PreKeySignalMessage), swallowing the return value in both. Recording
    // inside saveIdentity is therefore the only hook that sees every key
    // change, in either direction.
    test('a first sighting records nothing — a new contact is not a '
        'security event', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());
      expect(store.readIdentityChange('bob'), isNull);
    });

    test('re-saving the same key records nothing', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      final bob = generateIdentityKeyPair().getPublicKey();
      await store.saveIdentity(address, bob);
      await store.saveIdentity(address, bob);
      expect(store.readIdentityChange('bob'), isNull);
    });

    test('a replaced key IS recorded', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());
      expect(store.readIdentityChange('bob'), isA<DateTime>());
    });

    test('it is per contact — one person reinstalling says nothing about '
        'anyone else', () async {
      final store = await storeFor('alice');
      final bob = SignalProtocolAddress('bob', 1);
      await store.saveIdentity(bob, generateIdentityKeyPair().getPublicKey());
      await store.saveIdentity(bob, generateIdentityKeyPair().getPublicKey());
      expect(store.readIdentityChange('carol'), isNull);
    });

    test('dismissing clears it, and it does not come back', () async {
      final store = await storeFor('alice');
      final address = SignalProtocolAddress('bob', 1);
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());

      await store.clearIdentityChange('bob');
      expect(store.readIdentityChange('bob'), isNull);
    });

    test('survives a restart, so a change that happened while the app was '
        'closed is still announced', () async {
      final identity = generateIdentityKeyPair();
      final store = await storeFor('alice', identity: identity);
      final address = SignalProtocolAddress('bob', 1);
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());
      await store.saveIdentity(address, generateIdentityKeyPair().getPublicKey());

      await Hive.close();
      Hive.init(tempDir.path);
      final again = await storeFor('alice', identity: identity);

      expect(again.readIdentityChange('bob'), isA<DateTime>());
    });
  });

  group('the local plaintext store', () {
    // The Double Ratchet opens a given message exactly ONCE. This app
    // reads every message several times — fetchMessages on open,
    // streamMessages over realtime, _reconcileTicks on a timer — so with
    // nowhere to keep the result, a message would render correctly and
    // then flip to "Waiting for this message" seconds later.
    test('a decrypted body is readable again without the ratchet', () async {
      final store = await storeFor('alice');
      await store.writePlaintext('msg-1', 'Happy Sabbath');
      expect(store.readPlaintext('msg-1'), 'Happy Sabbath');
    });

    test('survives a restart, so reopening a chat offline still reads', () async {
      final store = await storeFor('alice');
      await store.writePlaintext('msg-2', 'see you at vespers');

      await Hive.close();
      Hive.init(tempDir.path);
      final again = await storeFor('alice');

      expect(again.readPlaintext('msg-2'), 'see you at vespers');
    });

    test('an unknown id reads null, not empty — the caller has to tell '
        '"never opened" apart from "opened, and it was blank"', () async {
      final store = await storeFor('alice');
      expect(store.readPlaintext('never-seen'), isNull);
    });

    test('delete-for-me forgets it', () async {
      final store = await storeFor('alice');
      await store.writePlaintext('msg-3', 'regrettable');
      await store.deletePlaintext('msg-3');
      expect(store.readPlaintext('msg-3'), isNull);
    });

    test('one member cannot read another\'s plaintext', () async {
      final alice = await storeFor('alice');
      await alice.writePlaintext('msg-4', 'private');
      final carol = await storeFor('carol');
      expect(carol.readPlaintext('msg-4'), isNull);
    });
  });

  group('prekeys', () {
    test('store, load and remove round-trip on disk', () async {
      final store = await storeFor('alice');
      final preKey = generatePreKeys(0, 1).first;

      await store.storePreKey(preKey.id, preKey);
      expect(await store.containsPreKey(preKey.id), isTrue);
      expect((await store.loadPreKey(preKey.id)).id, preKey.id);

      // Consumed prekeys must actually go: reusing one weakens the
      // forward secrecy of the session it opened.
      await store.removePreKey(preKey.id);
      expect(await store.containsPreKey(preKey.id), isFalse);
    });

    test('a missing prekey throws rather than returning something '
        'plausible', () async {
      final store = await storeFor('alice');
      expect(
        () => store.loadPreKey(4242),
        throwsA(isA<InvalidKeyIdException>()),
      );
    });
  });
}
