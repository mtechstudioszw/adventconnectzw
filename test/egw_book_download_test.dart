// Founder, 18 Aug 2026: *"in egw tab when tap a book it loads forever but
// never opens; when click back n tap again it opens"*.
//
// Both halves of that sentence are one story. The download was slow (a
// megabyte over Zimbabwean mobile data), there was nothing on screen to say
// so, and there was no way to stop it — so he backed out. The bytes had
// already landed by the time he tapped again, which is why the SECOND tap
// worked.
//
// A timeout alone could not fix it, and the first attempt at this shipped
// one: a 60-second ceiling on the WHOLE transfer, with the part-file deleted
// on failure. On a link where a megabyte legitimately takes longer than
// that, every attempt timed out and restarted from byte zero — so the book
// could never be opened on that connection, no matter how many times it was
// tapped. That is the literal "never opens".
//
// So what is tested here is the shape that actually fixes it:
//
//   * a part-file is KEPT and RESUMED with a Range request, so every attempt
//     gets strictly closer;
//   * a server that ignores the Range and sends the whole file again does
//     not get its bytes appended onto the old ones (silent corruption);
//   * a short file is never renamed into place — media2.egwwritings.org
//     truncates silently, and a truncated EPUB cached forever fails to parse
//     on every future open;
//   * progress is reported, because a bar that moves is the difference
//     between "slow" and "broken";
//   * cancelling stops the transfer without throwing away what it had.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:advent_connect_zw/services/egw_book_service.dart';

/// Hands the service a real temp directory instead of an Android cache dir.
class _FakePaths extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationCachePath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// A server that can be told to hang up part-way through, and that records
/// what was asked of it.
class _Server {
  _Server(this.body);

  final List<int> body;
  late HttpServer _http;

  /// Bytes to send before dropping the connection. Null sends everything.
  int? cutAfter;

  /// Set false to make the server pretend it does not understand Range.
  bool honourRange = true;

  final rangeHeaders = <String?>[];

  Future<Uri> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
    return Uri.parse('http://127.0.0.1:${_http.port}/book.epub');
  }

  Future<void> _serve() async {
    await for (final req in _http) {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      rangeHeaders.add(range);

      var from = 0;
      if (range != null && honourRange) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = HttpStatus.partialContent;
      }

      final rest = body.sublist(from);
      final send = cutAfter == null || cutAfter! >= rest.length
          ? rest
          : rest.sublist(0, cutAfter!);
      req.response.contentLength = rest.length;
      req.response.add(send);
      if (send.length < rest.length) {
        // Hang up mid-body: the transfer the founder's connection keeps
        // doing to him.
        await req.response.close().catchError((_) {});
        await req.response.done.catchError((Object _) {});
      } else {
        await req.response.close();
      }
    }
  }

  Future<void> stop() => _http.close(force: true);
}

/// A real, minimal White-Estate-shaped EPUB.
///
/// It has to be a genuine one. Random bytes would exercise the transfer and
/// then be thrown away by the parser — which is correct behaviour and would
/// hide the very thing under test, because a resumed file that arrives
/// CORRUPT and a resumed file that never arrives both end up as "no book".
/// Only a fixture that parses can tell those apart.
///
/// [padding] makes the archive big enough to be cut in half convincingly.
///
/// Stored, not deflated. Repetitive padding compresses about a hundred to
/// one, which produced a one-kilobyte "book" — small enough that the whole
/// body arrived in a single TCP segment and an interruption could not be
/// staged at all. The download this is testing is a megabyte.
List<int> _epub({required int padding}) {
  final archive = Archive();

  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(
      ArchiveFile(name, bytes.length, bytes)
        ..compression = CompressionType.none,
    );
  }

  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>Steps to Christ</dc:title>'
    '<dc:creator>Ellen G. White</dc:creator>'
    '</metadata>'
    '<manifest>'
    '<item id="c1" href="content01.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '</manifest>'
    '<spine><itemref idref="c1"/></spine>'
    '</package>',
  );
  add(
    'OEBPS/content01.xhtml',
    '<?xml version="1.0"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml">'
    '<body>'
    '<h2 class="chapterhead">Chapter 1</h2>'
    '<p class="standard">The love of God. ${'Padding sentence. ' * padding}</p>'
    '</body></html>',
  );

  return ZipEncoder().encode(archive);
}

void main() {
  late Directory dir;
  late _Server server;
  late Uri url;

  // Big enough that cutting it in half is a real interruption, and a real
  // EPUB so a corrupt resume is distinguishable from a failed one.
  final body = _epub(padding: 12000);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('egw_download');
    PathProviderPlatform.instance = _FakePaths(dir.path);
    EgwBookService.clearMemoryCache();
    server = _Server(body);
    url = await server.start();
  });

  tearDown(() async {
    await server.stop();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  // The service's own on-disk names, asked for rather than reimplemented —
  // a second copy of the hashing scheme here would pass while the app looked
  // somewhere else entirely.
  Future<File> wholeFile() => EgwBookService.fileFor(url.toString());
  Future<File> partFile() async =>
      File('${(await wholeFile()).path}.part');

  test('an interrupted download keeps what it got', () async {
    server.cutAfter = body.length ~/ 3;

    final result = await EgwBookService.load(url.toString());

    // It failed — but it failed FORWARD.
    expect(result.isOk, isFalse);
    expect(result.failure, EgwLoadFailure.network);
    expect(
      await (await wholeFile()).exists(),
      isFalse,
      reason: 'a short file must never be renamed into place — it would be '
          'cached forever and fail to parse on every future open',
    );
    expect(await (await partFile()).exists(), isTrue);
    expect(await (await partFile()).length(), body.length ~/ 3);
  });

  test('the next attempt resumes instead of restarting', () async {
    server.cutAfter = body.length ~/ 3;
    await EgwBookService.load(url.toString());
    expect(await (await partFile()).length(), body.length ~/ 3);

    // Second tap: the connection holds this time.
    server.cutAfter = null;
    await EgwBookService.load(url.toString());

    expect(
      server.rangeHeaders.last,
      'bytes=${body.length ~/ 3}-',
      reason: 'the retry must ask for the REST, not the whole file again',
    );
    expect(await (await wholeFile()).exists(), isTrue);
    expect(await (await wholeFile()).readAsBytes(), body);
  });

  test('a server that ignores Range does not get appended onto', () async {
    // Silent corruption if this is wrong: 12000 stale bytes followed by a
    // complete file, which is the right LENGTH for nothing and parses as
    // nothing.
    server.cutAfter = body.length ~/ 3;
    await EgwBookService.load(url.toString());

    server.cutAfter = null;
    server.honourRange = false; // replies 200 with the whole body
    await EgwBookService.load(url.toString());

    expect(await (await wholeFile()).exists(), isTrue);
    expect(await (await wholeFile()).readAsBytes(), body);
  });

  test('progress is reported, and in bytes that mean something', () async {
    final seen = <EgwLoadProgress>[];
    await EgwBookService.load(url.toString(), onProgress: seen.add);

    expect(seen, isNotEmpty);
    expect(
      seen.any((p) => p.total == body.length),
      isTrue,
      reason: 'the size has to be known or the bar is a lie',
    );
    expect(seen.last.received, body.length);
    // Monotonic: a bar that goes backwards is worse than none.
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i].received, greaterThanOrEqualTo(seen[i - 1].received));
    }
  });

  test('progress resumes from what is already on disk', () async {
    server.cutAfter = body.length ~/ 3;
    await EgwBookService.load(url.toString());

    server.cutAfter = null;
    final seen = <EgwLoadProgress>[];
    await EgwBookService.load(url.toString(), onProgress: seen.add);

    // The FIRST event is the idle snapshot handed to a joiner before the
    // response headers are back — nothing is known yet, so it cannot say
    // anything. The first event that knows the size is the one the bar
    // actually draws, and that one must already be a third of the way in.
    final firstReal = seen.firstWhere((p) => p.total > 0);
    expect(
      firstReal.received,
      body.length ~/ 3,
      reason: 'a resumed download must not show 0% — it is already a third '
          'of the way there, and saying otherwise is why it felt endless',
    );
    expect(firstReal.total, body.length);
  });

  test('a book with no EPUB fails as noSource, not as a network error',
      () async {
    final result = await EgwBookService.load('  ');
    expect(result.failure, EgwLoadFailure.noSource);
  });

  test('two screens asking for the same book share one download', () async {
    final a = EgwBookService.load(url.toString());
    final b = EgwBookService.load(url.toString());
    await Future.wait([a, b]);

    expect(
      server.rangeHeaders,
      hasLength(1),
      reason: 'a second tap while the first is in flight must join it, not '
          'start a competing download over the same connection',
    );
  });

  test('cancelling one caller does not abandon the other', () async {
    final handle = EgwLoadHandle();
    final quitter = EgwBookService.load(url.toString(), handle: handle);
    final stayer = EgwBookService.load(url.toString());

    handle.cancel();

    expect((await quitter).failure, EgwLoadFailure.cancelled);
    // The other screen still gets its bytes.
    final kept = await stayer;
    expect(kept.failure, isNot(EgwLoadFailure.cancelled));
    expect(await (await wholeFile()).exists(), isTrue);
  });
}

