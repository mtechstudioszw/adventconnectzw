// The security code has to read the same on BOTH phones.
//
// `E2eeService.securityCode` hands the generator (me, myKey) as the local
// pair and (them, theirKey) as the remote pair. On the other handset those
// arguments are necessarily swapped. If the display text depended on that
// order, two people comparing codes would see a mismatch and — because the
// app tells them a mismatch means someone is intercepting — would conclude
// they were being attacked when nothing was wrong.
//
// That symmetry is a property of libsignal's DisplayableFingerprint, not of
// our code, which is exactly why it is worth pinning: it is an assumption
// we depend on, borrowed from a package that could change it in a bump.
//
// Nothing here touches E2eeService, whose store is private static state; it
// exercises the generator with the same arguments, in the same order, that
// securityCode uses.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Matches `E2eeService._fingerprintIterations` / `_fingerprintVersion`.
/// Kept low here on purpose — 5200 rounds is the shipping value, but this
/// test is about argument ORDER, and 5200 would make it needlessly slow.
const _version = 1;
const _iterations = 64;

String _display(
  String localId,
  IdentityKey localKey,
  String remoteId,
  IdentityKey remoteKey,
) {
  return NumericFingerprintGenerator(_iterations)
      .createFor(
        _version,
        Uint8List.fromList(utf8.encode(localId)),
        localKey,
        Uint8List.fromList(utf8.encode(remoteId)),
        remoteKey,
      )
      .displayableFingerprint
      .getDisplayText();
}

void main() {
  // Two fixed identities standing in for two members' devices.
  final alice = generateIdentityKeyPair();
  final bob = generateIdentityKeyPair();
  const aliceId = '11111111-1111-4111-8111-111111111111';
  const bobId = '22222222-2222-4222-8222-222222222222';

  test('both sides derive the same code from swapped arguments', () {
    final onAlicesPhone = _display(
      aliceId,
      alice.getPublicKey(),
      bobId,
      bob.getPublicKey(),
    );
    final onBobsPhone = _display(
      bobId,
      bob.getPublicKey(),
      aliceId,
      alice.getPublicKey(),
    );

    expect(onAlicesPhone, onBobsPhone);
  });

  test('the code is 60 digits', () {
    final code = _display(
      aliceId,
      alice.getPublicKey(),
      bobId,
      bob.getPublicKey(),
    );

    expect(code.length, 60);
    expect(RegExp(r'^\d{60}$').hasMatch(code), isTrue);
  });

  test('a different peer key gives a different code', () {
    // The whole point: if someone swaps in their own key, the digits move.
    final impostor = generateIdentityKeyPair();

    final real = _display(
      aliceId,
      alice.getPublicKey(),
      bobId,
      bob.getPublicKey(),
    );
    final intercepted = _display(
      aliceId,
      alice.getPublicKey(),
      bobId,
      impostor.getPublicKey(),
    );

    expect(real, isNot(intercepted));
  });
}
