import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:advent_connect_zw/services/e2ee/e2ee_service.dart';

/// The wire format between `claim_prekey_bundle()` and libsignal.
///
/// This is the seam nothing else covers. The protocol tests build bundles
/// from live objects; the real app rebuilds them from base64 strings that
/// have been through Postgres, PostgREST and JSON. A wrong offset or a
/// missing decode does not throw here — it produces a bundle that quietly
/// fails to establish a session, on a phone that is not this one.
///
/// The maps below are shaped exactly like the RPC's `RETURNS TABLE`.
void main() {
  /// Publishes a party's keys the way `_publishDevice` / `_topUpPrekeys`
  /// do, then hands back the JSON the RPC would return for them.
  ({
    InMemorySignalProtocolStore store,
    Map<String, dynamic> row,
    int deviceId,
  }) published({required int deviceId, bool withOneTimePreKey = true}) {
    final identity = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    final store = InMemorySignalProtocolStore(identity, registrationId);

    final signed = generateSignedPreKey(identity, 1);
    store.storeSignedPreKey(signed.id, signed);

    PreKeyRecord? preKey;
    if (withOneTimePreKey) {
      preKey = generatePreKeys(42, 1).first;
      store.storePreKey(preKey.id, preKey);
    }

    return (
      store: store,
      deviceId: deviceId,
      row: <String, dynamic>{
        'device_id': deviceId,
        'registration_id': registrationId,
        'identity_key': base64Encode(identity.getPublicKey().serialize()),
        'signed_key_id': signed.id,
        'signed_key': base64Encode(signed.getKeyPair().publicKey.serialize()),
        'signed_sig': base64Encode(signed.signature),
        'prekey_id': preKey?.id,
        'prekey': preKey == null
            ? null
            : base64Encode(preKey.getKeyPair().publicKey.serialize()),
      },
    );
  }

  test('a bundle rebuilt from the RPC row establishes a real session', () async {
    final bob = published(deviceId: 7);
    final aliceIdentity = generateIdentityKeyPair();
    final alice = InMemorySignalProtocolStore(
      aliceIdentity,
      generateRegistrationId(false),
    );

    final bundle = ClaimedBundle.fromJson(bob.row).toPreKeyBundle();
    final bobAddress = SignalProtocolAddress('bob', bob.deviceId);
    await SessionBuilder.fromSignalStore(
      alice,
      bobAddress,
    ).processPreKeyBundle(bundle);

    // The proof is not that it parsed — it is that a message crosses.
    final ciphertext = await SessionCipher.fromStore(
      alice,
      bobAddress,
    ).encrypt(Uint8List.fromList(utf8.encode('over the wire')));

    final got = await SessionCipher.fromStore(
      bob.store,
      SignalProtocolAddress('alice', 1),
    ).decryptWithCallback(PreKeySignalMessage(ciphertext.serialize()), (_) {});
    expect(utf8.decode(got), 'over the wire');
  });

  test('a bundle with NO one-time prekey still works — running out must '
      'degrade, not break', () async {
    // claim_prekey_bundle() returns nulls for prekey_id/prekey when the
    // peer's stock is exhausted. X3DH falls back to the signed prekey.
    final bob = published(deviceId: 3, withOneTimePreKey: false);
    final alice = InMemorySignalProtocolStore(
      generateIdentityKeyPair(),
      generateRegistrationId(false),
    );

    final bundle = ClaimedBundle.fromJson(bob.row).toPreKeyBundle();
    final bobAddress = SignalProtocolAddress('bob', bob.deviceId);
    await SessionBuilder.fromSignalStore(
      alice,
      bobAddress,
    ).processPreKeyBundle(bundle);

    final ciphertext = await SessionCipher.fromStore(
      alice,
      bobAddress,
    ).encrypt(Uint8List.fromList(utf8.encode('no prekeys left')));
    final got = await SessionCipher.fromStore(
      bob.store,
      SignalProtocolAddress('alice', 1),
    ).decryptWithCallback(PreKeySignalMessage(ciphertext.serialize()), (_) {});
    expect(utf8.decode(got), 'no prekeys left');
  });

  test('the row carries the device id through, so the recipient is '
      'addressed on the device that published the keys', () {
    final bob = published(deviceId: 91234);
    expect(ClaimedBundle.fromJson(bob.row).deviceId, 91234);
    expect(ClaimedBundle.fromJson(bob.row).toPreKeyBundle().getDeviceId(), 91234);
  });

  test('Postgres numerics arrive as num, not int — the cast must not '
      'assume', () {
    final bob = published(deviceId: 5);
    // PostgREST hands back JSON numbers; a `as int` on a double would
    // throw at runtime on a device and nowhere in analysis.
    final loose = Map<String, dynamic>.from(bob.row)
      ..['device_id'] = 5.0
      ..['registration_id'] = (bob.row['registration_id'] as int).toDouble();
    expect(() => ClaimedBundle.fromJson(loose), returnsNormally);
    expect(ClaimedBundle.fromJson(loose).deviceId, 5);
  });
}
