import 'package:flutter/foundation.dart';

import '../e2ee/e2ee_service.dart';

/// Result of checking one peer's call keys.
enum CallKeyCheck {
  /// Their DTLS fingerprint arrived over our Signal session and matches
  /// the offer/answer — nobody in the middle can be listening.
  verified,

  /// The fingerprints DIFFER: someone altered the offer on the way
  /// (a man-in-the-middle). The call to this person is refused.
  mismatch,

  /// No sealed fingerprint (an older app, or encryption not set up). The
  /// audio is still encrypted (DTLS-SRTP); it just isn't verified.
  unverified,
}

/// End-to-end verified calls (1 Nov 2026).
///
/// Call audio is always encrypted phone-to-phone by WebRTC (DTLS-SRTP);
/// a TURN relay only ever sees ciphertext. The weak point is the
/// handshake: the DTLS certificate fingerprints travel inside the SDP
/// offer/answer, and that goes through our signalling server — which
/// could in principle swap them and sit in the middle.
///
/// WhatsApp's answer, and ours: each side also sends its fingerprint
/// sealed with the 1:1 Signal session chat already uses. The other phone
/// opens it and compares it with the SDP. A mismatch ends the call.
class CallE2ee {
  const CallE2ee._();

  /// The `a=fingerprint:` lines of an SDP, normalised and sorted, so the
  /// same certificate always gives the same string.
  @visibleForTesting
  static String fingerprintsOf(String sdp) {
    final out = <String>{};
    for (final raw in sdp.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (!line.toLowerCase().startsWith('a=fingerprint:')) continue;
      final v = line.substring('a=fingerprint:'.length).trim();
      final parts = v.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      out.add('${parts[0].toLowerCase()} ${parts[1].toUpperCase()}');
    }
    final list = out.toList()..sort();
    return list.join('|');
  }

  /// The sealed fingerprint to attach to an offer/answer for [peerId], or
  /// null when that can't be done (they have no keys; encryption off).
  static Future<Map<String, Object>?> seal(String peerId, String sdp) async {
    final fp = fingerprintsOf(sdp);
    if (fp.isEmpty || !E2eeService.isReady) return null;
    try {
      final sealed = await E2eeService.encryptForUser(
        userId: peerId,
        plaintext: 'callfp:$fp',
      );
      if (sealed == null) return null;
      return {
        'c': sealed.payload.ciphertext,
        't': sealed.payload.type,
        's': sealed.payload.senderDeviceId,
      };
    } catch (e) {
      debugPrint('CallE2ee.seal: $e');
      return null;
    }
  }

  /// Checks a received offer/answer from [peerId] against its sealed
  /// fingerprint ([sealed] is the `fp` field of the signal, may be null).
  static Future<CallKeyCheck> verify(
    String peerId,
    String sdp,
    Object? sealed,
  ) async {
    if (sealed is! Map) return CallKeyCheck.unverified;
    try {
      final plain = await E2eeService.decryptDirect(
        senderUserId: peerId,
        senderDeviceId: (sealed['s'] as num).toInt(),
        ciphertextB64: '${sealed['c']}',
        type: (sealed['t'] as num).toInt(),
      );
      if (plain == null || !plain.startsWith('callfp:')) {
        return CallKeyCheck.unverified;
      }
      return compare(plain.substring('callfp:'.length), sdp);
    } catch (e) {
      debugPrint('CallE2ee.verify: $e');
      return CallKeyCheck.unverified;
    }
  }

  /// The comparison itself, separate so it can be tested.
  @visibleForTesting
  static CallKeyCheck compare(String sealedFingerprints, String sdp) {
    final inSdp = fingerprintsOf(sdp);
    if (inSdp.isEmpty) return CallKeyCheck.mismatch;
    return sealedFingerprints == inSdp
        ? CallKeyCheck.verified
        : CallKeyCheck.mismatch;
  }
}
