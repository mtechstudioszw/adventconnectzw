import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/egw_book_model.dart';
import 'egw_epub_parser.dart';

/// Fetches, caches and parses EGW EPUBs for the reflowable reader.
///
/// Mirrors the PDF path deliberately: download once into the application
/// cache directory keyed by a hash of the URL, then read from disk forever
/// after. That is what makes an opened book readable with no signal, which
/// is the strongest reason to have the app at all.
class EgwBookService {
  EgwBookService._();

  /// Parsed books, kept for the session.
  ///
  /// Parsing is not free — the shelf is 46M characters — and the reader
  /// re-reads the book whenever the reading settings change. Bounded to a
  /// few entries because a whole parsed book is a large object and nobody
  /// reads five at once.
  static final _parsed = <String, EgwBook>{};
  static final _order = <String>[];
  static const _maxCached = 3;

  /// In-flight downloads, so two taps do not fetch the same book twice.
  static final _inFlight = <String, Future<EgwBook?>>{};

  static String _hash(String url) => sha1.convert(url.codeUnits).toString();

  /// Returns the parsed book, or null when it cannot be had — no EPUB, no
  /// network on a first open, or a file that will not parse. Every null is
  /// a signal for the caller to fall back to the PDF reader, so this never
  /// throws.
  static Future<EgwBook?> load(String? epubUrl) {
    final url = (epubUrl ?? '').trim();
    if (url.isEmpty) return Future.value(null);

    final cached = _parsed[url];
    if (cached != null) return Future.value(cached);

    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _load(url).whenComplete(() => _inFlight.remove(url));
    _inFlight[url] = future;
    return future;
  }

  static Future<EgwBook?> _load(String url) async {
    try {
      final bytes = await _bytes(url);
      if (bytes == null || bytes.isEmpty) return null;

      // Parsing a whole book blocks the UI isolate for long enough to drop
      // frames, and this runs while the reader is opening.
      final book = await compute(_parseIsolate, bytes);
      if (book == null || book.isEmpty) return null;

      _remember(url, book);
      return book;
    } catch (e) {
      debugPrint('EgwBookService.load failed: $e');
      return null;
    }
  }

  static void _remember(String url, EgwBook book) {
    _parsed[url] = book;
    _order
      ..remove(url)
      ..add(url);
    while (_order.length > _maxCached) {
      _parsed.remove(_order.removeAt(0));
    }
  }

  /// Cached bytes, downloading once if they are not already on disk.
  static Future<Uint8List?> _bytes(String url) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/library_${_hash(url)}.epub');

    if (await file.exists() && await file.length() > 0) {
      return file.readAsBytes();
    }

    final tmp = File('${file.path}.part');
    final client = HttpClient()
      // Founder, 18 Aug 2026: *"takes long to open a book it loads for
      // ever"*. There was no timeout of ANY kind here — not on the
      // connection, not on the transfer — so a stalled socket on mobile
      // data hung the open screen indefinitely with no way out. An
      // HttpClient with no connectionTimeout waits on the OS, which on
      // Android is minutes.
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(_headerTimeout);
      if (resp.statusCode != 200) {
        debugPrint('EgwBookService: HTTP ${resp.statusCode} for $url');
        return null;
      }

      // Write to a temporary file first and rename on success, so an
      // interrupted download can never leave a truncated EPUB that the
      // parser would then reject on every future open.
      final sink = tmp.openWrite();
      await resp.pipe(sink).timeout(_transferTimeout);

      // media2.egwwritings.org TRUNCATES SILENTLY — that is the trap the
      // seed script already had to defend against, and this path never
      // did. A short file renamed into place is cached forever, fails to
      // parse on every future open, and silently drops the member back to
      // the PDF reader with no explanation.
      final expected = resp.contentLength;
      final actual = await tmp.length();
      if (actual == 0 || (expected > 0 && actual != expected)) {
        debugPrint(
          'EgwBookService: truncated download for $url '
          '($actual of $expected bytes) — not caching',
        );
        return null;
      }

      await tmp.rename(file.path);
      return file.readAsBytes();
    } on TimeoutException {
      debugPrint('EgwBookService: timed out fetching $url');
      return null;
    } finally {
      client.close(force: true);
      // Never leave a `.part` behind. Without this a timed-out transfer
      // leaves a growing pile of half-books in the cache directory, and
      // the retry writes over one it cannot trust.
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Long enough for a slow handshake on 3G, short enough that a dead
  /// connection surfaces as an error the reader can act on rather than a
  /// spinner that never resolves.
  static const _headerTimeout = Duration(seconds: 20);

  /// Whole-transfer ceiling. The books are ~0.6–1 MB, so a minute is
  /// generous even on a bad connection — past that something is wrong and
  /// saying so beats spinning.
  static const _transferTimeout = Duration(seconds: 60);

  /// Drops the parsed-book cache. Books are public domain and not
  /// user-scoped, so the DOWNLOADS are deliberately left alone on sign-out
  /// — the next member gets an offline shelf rather than 42 MB of refetch.
  static void clearMemoryCache() {
    _parsed.clear();
    _order.clear();
  }
}

/// Top-level so it can run in a background isolate.
EgwBook? _parseIsolate(Uint8List bytes) {
  try {
    return EgwEpubParser.parse(bytes);
  } catch (_) {
    return null;
  }
}
