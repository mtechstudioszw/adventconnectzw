// Guards the Opus SDP munging in MeshCallTransport.
//
// The class of bug this protects against is the worst kind to debug: a
// silently malformed session description. Hand-editing SDP is how these
// codec parameters have to be set — there is no cross-platform API — and
// a regex that is one character out does not throw. It produces a
// description the far end cannot parse, and the call fails to connect
// with no error anywhere near the cause.
//
// The two rules being pinned:
//
//   * IT MUST IMPROVE OR DO NOTHING. Anything it does not recognise is
//     returned byte-for-byte unchanged, so a flutter_webrtc upgrade that
//     changes the SDP format degrades to default Opus rather than
//     breaking calling outright.
//
//   * IT MUST NOT DROP WHAT WAS ALREADY THERE. `minptime=10` is the
//     browser/OS's own value; appending ours must extend the fmtp line,
//     not replace it.
//
// Every fixture below is a realistic multi-line SDP with CRLF endings,
// because that is what a real offer looks like and line endings are
// exactly where this kind of bug hides.
//
// Pure Dart: debugTuneOpus is a static string function. No peer
// connection, no platform channels, no device.

import 'package:flutter_test/flutter_test.dart';

import 'package:advent_connect_zw/services/calls/mesh_call_transport.dart';

/// SDP lines are CRLF-terminated (RFC 4566). Build fixtures that way.
String sdp(List<String> lines) => '${lines.join('\r\n')}\r\n';

/// Split the way a tolerant SDP parser does, so a stray bare CR left in
/// the middle of a line shows up as a broken line here rather than
/// hiding inside a `contains` over the whole blob.
List<String> linesOf(String s) =>
    s.split(RegExp(r'\r\n|\r|\n')).where((l) => l.isNotEmpty).toList();

String? fmtpFor(String s, String payload) {
  for (final line in linesOf(s)) {
    if (line.startsWith('a=fmtp:$payload ')) return line;
  }
  return null;
}

const _preamble = [
  'v=0',
  'o=- 4611731400430051336 2 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'a=group:BUNDLE 0',
  'a=msid-semantic: WMS stream0',
  'm=audio 9 UDP/TLS/RTP/SAVPF 111 103 104 9 0 8 106 105 13 110 112 113 126',
  'c=IN IP4 0.0.0.0',
  'a=rtcp:9 IN IP4 0.0.0.0',
  'a=ice-ufrag:4ZcD',
  'a=ice-pwd:2/1muCWoOi3uLifh0NuRHlZ7',
  'a=ice-options:trickle',
  'a=fingerprint:sha-256 '
      '4A:AD:B9:B1:3F:82:18:3B:54:02:12:DF:3E:5D:49:6B:19:E5:7C:AB:3B:'
      '95:1C:73:6C:22:0C:33:22:D9:36:AA',
  'a=setup:actpass',
  'a=mid:0',
  'a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level',
  'a=sendrecv',
  'a=msid:stream0 audio0',
  'a=rtcp-mux',
];

const _tail = [
  'a=rtpmap:103 ISAC/16000',
  'a=rtpmap:104 ISAC/32000',
  'a=rtpmap:9 G722/8000',
  'a=rtpmap:0 PCMU/8000',
  'a=rtpmap:8 PCMA/8000',
  'a=rtpmap:106 CN/32000',
  'a=rtpmap:105 CN/16000',
  'a=rtpmap:13 CN/8000',
  'a=rtpmap:110 telephone-event/48000',
  'a=rtpmap:112 telephone-event/32000',
  'a=rtpmap:113 telephone-event/16000',
  'a=rtpmap:126 telephone-event/8000',
  'a=ssrc:2231627014 cname:4TOk42mSjXCkVIa6',
  'a=ssrc:2231627014 msid:stream0 audio0',
];

void main() {
  final withFmtp = sdp([
    ..._preamble,
    'a=rtpmap:111 opus/48000/2',
    'a=rtcp-fb:111 transport-cc',
    'a=fmtp:111 minptime=10;useinbandfec=1',
    ..._tail,
  ]);

  final withoutFmtp = sdp([
    ..._preamble,
    'a=rtpmap:111 opus/48000/2',
    'a=rtcp-fb:111 transport-cc',
    ..._tail,
  ]);

  final noOpus = sdp([
    ..._preamble,
    'a=rtpmap:9 G722/8000',
    'a=fmtp:9 bitrate=64000',
    ..._tail,
  ]);

  group('an existing fmtp line is extended, never replaced', () {
    test('our parameters are appended to the browser\'s own', () {
      final out = MeshCallTransport.debugTuneOpus(withFmtp);
      final line = fmtpFor(out, '111');

      expect(line, isNotNull, reason: 'the opus fmtp line vanished');
      expect(line, contains('maxaveragebitrate=24000'));
      expect(line, contains('usedtx=1'));
      expect(line, contains('useinbandfec=1'));
    });

    test('minptime=10 survives — we must not drop what was already set', () {
      final out = MeshCallTransport.debugTuneOpus(withFmtp);
      expect(
        fmtpFor(out, '111'),
        contains('minptime=10'),
        reason: 'the platform\'s own packetisation setting was thrown away',
      );
    });

    test('everything lands on ONE fmtp line, not spilled across two', () {
      // The failure mode if a bare CR gets captured into the parameter
      // string: the second half becomes an orphan line that no parser
      // understands.
      final out = MeshCallTransport.debugTuneOpus(withFmtp);
      final fmtps =
          linesOf(out).where((l) => l.startsWith('a=fmtp:111')).toList();
      expect(fmtps, hasLength(1));
      expect(
        linesOf(out).where((l) => l.startsWith(';')),
        isEmpty,
        reason: 'a parameter fragment escaped onto its own line',
      );
    });

    test('every line still looks like an SDP line', () {
      final out = MeshCallTransport.debugTuneOpus(withFmtp);
      for (final line in linesOf(out)) {
        expect(
          RegExp(r'^[a-z]=').hasMatch(line),
          isTrue,
          reason: 'malformed SDP line: "$line"',
        );
      }
    });

    test('no other line is touched', () {
      final out = MeshCallTransport.debugTuneOpus(withFmtp);
      final before = linesOf(withFmtp)
          .where((l) => !l.startsWith('a=fmtp:111'))
          .toList();
      final after =
          linesOf(out).where((l) => !l.startsWith('a=fmtp:111')).toList();
      expect(after, before);
    });

    test('the fmtp line keeps its place in the media section', () {
      final out = linesOf(MeshCallTransport.debugTuneOpus(withFmtp));
      expect(
        out.indexOf(out.firstWhere((l) => l.startsWith('a=fmtp:111'))),
        greaterThan(out.indexWhere((l) => l.startsWith('a=rtpmap:111'))),
      );
    });
  });

  group('a missing fmtp line is inserted', () {
    test('an a=fmtp line appears for the opus payload', () {
      final out = MeshCallTransport.debugTuneOpus(withoutFmtp);
      final line = fmtpFor(out, '111');
      expect(line, isNotNull);
      expect(line, contains('maxaveragebitrate=24000'));
      expect(line, contains('usedtx=1'));
      expect(line, contains('useinbandfec=1'));
    });

    test('it is inserted directly after the rtpmap it belongs to', () {
      // An fmtp line that drifts out of its media section applies to
      // nothing.
      final out = linesOf(MeshCallTransport.debugTuneOpus(withoutFmtp));
      final rtpmapAt = out.indexWhere((l) => l.startsWith('a=rtpmap:111 opus'));
      expect(rtpmapAt, isNonNegative);
      expect(out[rtpmapAt + 1], startsWith('a=fmtp:111 '));
    });

    test('exactly one line is added', () {
      final out = MeshCallTransport.debugTuneOpus(withoutFmtp);
      expect(linesOf(out).length, linesOf(withoutFmtp).length + 1);
    });

    test('every line still looks like an SDP line', () {
      final out = MeshCallTransport.debugTuneOpus(withoutFmtp);
      for (final line in linesOf(out)) {
        expect(
          RegExp(r'^[a-z]=').hasMatch(line),
          isTrue,
          reason: 'malformed SDP line: "$line"',
        );
      }
    });
  });

  group('anything it does not recognise is returned untouched', () {
    test('an SDP with no opus payload comes back byte for byte', () {
      expect(MeshCallTransport.debugTuneOpus(noOpus), noOpus);
    });

    test('an empty string comes back empty', () {
      expect(MeshCallTransport.debugTuneOpus(''), '');
    });

    test('a video-only SDP is untouched', () {
      final video = sdp([
        'v=0',
        'o=- 1 2 IN IP4 127.0.0.1',
        's=-',
        't=0 0',
        'm=video 9 UDP/TLS/RTP/SAVPF 96',
        'a=rtpmap:96 VP8/90000',
        'a=fmtp:96 max-fs=12288',
      ]);
      expect(MeshCallTransport.debugTuneOpus(video), video);
    });

    test('an SDP that is already tuned is not tuned twice', () {
      // Re-running over an answer we already munged must be a no-op —
      // duplicated parameters are how an fmtp line grows without bound.
      final once = MeshCallTransport.debugTuneOpus(withFmtp);
      final twice = MeshCallTransport.debugTuneOpus(once);
      expect(twice, once);
      expect(
        'maxaveragebitrate='.allMatches(fmtpFor(twice, '111')!),
        hasLength(1),
      );
    });

    test('an SDP that already sets maxaveragebitrate is left alone', () {
      final tuned = sdp([
        ..._preamble,
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=64000',
        ..._tail,
      ]);
      expect(
        MeshCallTransport.debugTuneOpus(tuned),
        tuned,
        reason: 'a deliberate bitrate set elsewhere was overwritten',
      );
    });

    test('a non-48k opus line is not matched', () {
      // opus is only ever 48000; anything else is not what we tuned for.
      final odd = sdp([
        ..._preamble,
        'a=rtpmap:111 opus/16000/2',
        ..._tail,
      ]);
      expect(MeshCallTransport.debugTuneOpus(odd), odd);
    });
  });

  group('it finds opus wherever the payload number lands', () {
    test('a non-standard payload number still gets tuned', () {
      // 111 is conventional, not guaranteed.
      final odd = sdp([
        ..._preamble,
        'a=rtpmap:120 opus/48000/2',
        'a=fmtp:120 minptime=20',
        ..._tail,
      ]);
      final out = MeshCallTransport.debugTuneOpus(odd);
      final line = fmtpFor(out, '120');
      expect(line, contains('maxaveragebitrate=24000'));
      expect(line, contains('minptime=20'));
      expect(fmtpFor(out, '111'), isNull);
    });

    test('a mono opus offer (no /2) is still tuned', () {
      final mono = sdp([
        ..._preamble,
        'a=rtpmap:111 opus/48000',
        ..._tail,
      ]);
      final out = MeshCallTransport.debugTuneOpus(mono);
      expect(fmtpFor(out, '111'), contains('maxaveragebitrate=24000'));
    });

    test('the fmtp of a DIFFERENT payload is not mistaken for opus\'s', () {
      final other = sdp([
        ..._preamble,
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:126 0-15',
        ..._tail,
      ]);
      final out = MeshCallTransport.debugTuneOpus(other);
      expect(fmtpFor(out, '111'), contains('maxaveragebitrate=24000'));
      expect(
        fmtpFor(out, '126'),
        'a=fmtp:126 0-15',
        reason: 'the telephone-event fmtp was overwritten',
      );
    });

    test('LF-only line endings do not produce a corrupt line', () {
      final lf = withFmtp.replaceAll('\r\n', '\n');
      final out = MeshCallTransport.debugTuneOpus(lf);
      final line = fmtpFor(out, '111');
      expect(line, contains('minptime=10'));
      expect(line, contains('maxaveragebitrate=24000'));
      expect(
        linesOf(out).where((l) => l.startsWith(';')),
        isEmpty,
        reason: 'a parameter fragment escaped onto its own line',
      );
    });
  });

  group('it never throws, whatever it is handed', () {
    test('garbage does not blow up the offer path', () {
      const junk = <String>[
        ' ',
        '\r\n',
        '\n\n\n',
        'a=rtpmap:',
        'a=rtpmap:111',
        'a=rtpmap:111 opus',
        'a=rtpmap:111 opus/48000/2', // no trailing newline, no m= line
        'a=fmtp:111 minptime=10',
        'a=rtpmap:abc opus/48000/2',
        r'a=rtpmap:111 opus/48000/2\na=fmtp:111 $()[]{}*+?|^',
        'opus/48000',
        'maxaveragebitrate=24000',
        '((((',
        '\u{FFFD}\u{0000}\u{FEFF}',
        '\u{16A0}\u{16A2}\u{16A6} nonsense unicode',
        'a=rtpmap:111 OPUS/48000/2',
      ];
      for (final s in junk) {
        expect(
          () => MeshCallTransport.debugTuneOpus(s),
          returnsNormally,
          reason: 'threw on: ${s.replaceAll('\r', r'\r').replaceAll('\n', r'\n')}',
        );
      }
    });

    test('a very long SDP is handled', () {
      final huge = sdp([
        ..._preamble,
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:111 minptime=10;useinbandfec=1',
        ...List<String>.generate(2000, (i) => 'a=ssrc:$i cname:filler$i'),
      ]);
      final out = MeshCallTransport.debugTuneOpus(huge);
      expect(fmtpFor(out, '111'), contains('maxaveragebitrate=24000'));
    });

    test('an offer with two m= sections keeps both', () {
      final bundled = sdp([
        ..._preamble,
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:111 minptime=10;useinbandfec=1',
        'm=video 9 UDP/TLS/RTP/SAVPF 96',
        'a=mid:1',
        'a=rtpmap:96 VP8/90000',
      ]);
      final out = MeshCallTransport.debugTuneOpus(bundled);
      expect(linesOf(out).where((l) => l.startsWith('m=')), hasLength(2));
      expect(out, contains('a=rtpmap:96 VP8/90000'));
      expect(fmtpFor(out, '111'), contains('usedtx=1'));
    });
  });
}
