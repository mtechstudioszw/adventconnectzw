// End-to-end verified calls: the DTLS fingerprint check.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/calls/call_e2ee.dart';

const _sdpA = 'v=0\r\n'
    'o=- 1 2 IN IP4 127.0.0.1\r\n'
    'a=fingerprint:sha-256 AB:CD:EF:01:23\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';

const _sdpAttacker = 'v=0\r\n'
    'a=fingerprint:sha-256 99:88:77:66:55\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';

void main() {
  test('reads and normalises the fingerprint lines', () {
    expect(CallE2ee.fingerprintsOf(_sdpA), 'sha-256 AB:CD:EF:01:23');
    expect(
      CallE2ee.fingerprintsOf('a=fingerprint:SHA-256 ab:cd:ef:01:23\n'),
      'sha-256 AB:CD:EF:01:23',
    );
    expect(CallE2ee.fingerprintsOf('v=0\r\n'), '');
  });

  test('the same keys over both channels verify', () {
    final sealed = CallE2ee.fingerprintsOf(_sdpA);
    expect(CallE2ee.compare(sealed, _sdpA), CallKeyCheck.verified);
  });

  test('a swapped fingerprint (man in the middle) is caught', () {
    final sealed = CallE2ee.fingerprintsOf(_sdpA);
    expect(CallE2ee.compare(sealed, _sdpAttacker), CallKeyCheck.mismatch);
  });

  test('an offer with its fingerprint stripped is not trusted', () {
    final sealed = CallE2ee.fingerprintsOf(_sdpA);
    expect(CallE2ee.compare(sealed, 'v=0\r\n'), CallKeyCheck.mismatch);
  });

  test('no sealed fingerprint (older app) is unverified, not refused', () async {
    expect(await CallE2ee.verify('peer', _sdpA, null), CallKeyCheck.unverified);
  });
}
