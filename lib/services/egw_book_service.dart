import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/egw_book_model.dart';
import 'egw_epub_parser.dart';

/// How far along opening a book is, for the screen that has to wait.
///
/// A book is downloaded once and then parsed, and the two feel completely
/// different to somebody holding the phone: the download is the long,
/// variable part and it has a real percentage; the parse is a fixed second
/// or two with nothing to count. Reporting them as one anonymous spinner is
/// most of why the wait read as broken.
@immutable
class EgwLoadProgress {
  const EgwLoadProgress({
    required this.received,
    required this.total,
    required this.parsing,
  });

  static const idle = EgwLoadProgress(received: 0, total: 0, parsing: false);

  /// Bytes on disk so far, including anything a previous attempt left.
  final int received;

  /// Bytes the server says there are, or 0 when it will not say.
  final int total;

  /// True once the bytes are in hand and the book is being read.
  final bool parsing;

  /// 0..1, or null when the size is unknown and a bar would be a lie.
  double? get fraction {
    if (parsing) return 1;
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }
}

/// Thrown internally when every screen waiting on a load has walked away.
class EgwLoadCancelled implements Exception {
  const EgwLoadCancelled();
  @override
  String toString() => 'EgwLoadCancelled';
}

/// Why a book could not be opened, so the screen can say something true.
enum EgwLoadFailure {
  /// No EPUB for this title — the PDF is the only path and always was.
  noSource,

  /// The download did not finish. Retrying resumes; this is NOT permanent.
  network,

  /// Bytes in hand, but they are not a book we can read.
  unreadable,

  /// Nobody is waiting any more.
  cancelled,
}

/// The outcome of trying to open a book.
@immutable
class EgwLoadResult {
  const EgwLoadResult.ok(EgwBook this.book) : failure = null;
  const EgwLoadResult.failed(EgwLoadFailure this.failure) : book = null;

  final EgwBook? book;
  final EgwLoadFailure? failure;

  bool get isOk => book != null;
}

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

  /// In-flight loads, so two taps do not fetch the same book twice.
  static final inFlight = <String, EgwLoadJob>{};

  static String _hash(String url) => sha1.convert(url.codeUnits).toString();

  /// True when the book is parsed and in memory, so it opens in one frame.
  static bool isReady(String? epubUrl) =>
      _parsed.containsKey((epubUrl ?? '').trim());

  /// Opens the book, reporting progress and honouring a cancel.
  ///
  /// Never throws for a normal failure — every one of them comes back as an
  /// [EgwLoadResult] the caller can act on, because the caller's only other
  /// option is the PDF and a member must never be told a book they can see
  /// on the shelf cannot be opened.
  ///
  /// Two screens waiting on the same book share one download; cancelling one
  /// of them does NOT abandon the other.
  static Future<EgwLoadResult> load(
    String? epubUrl, {
    void Function(EgwLoadProgress)? onProgress,
    EgwLoadHandle? handle,
  }) {
    final url = (epubUrl ?? '').trim();
    if (url.isEmpty) {
      return Future.value(
        const EgwLoadResult.failed(EgwLoadFailure.noSource),
      );
    }

    final cached = _parsed[url];
    if (cached != null) return Future.value(EgwLoadResult.ok(cached));

    final job = inFlight[url] ??= EgwLoadJob(url);
    return job.join(onProgress: onProgress, handle: handle);
  }

  static void remember(String url, EgwBook book) {
    _parsed[url] = book;
    _order
      ..remove(url)
      ..add(url);
    while (_order.length > _maxCached) {
      _parsed.remove(_order.removeAt(0));
    }
  }

  /// Where a book's bytes live once they are on the device.
  static Future<File> fileFor(String url) async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/library_${_hash(url)}.epub');
  }

  /// Drops the parsed-book cache. Books are public domain and not
  /// user-scoped, so the DOWNLOADS are deliberately left alone on sign-out
  /// — the next member gets an offline shelf rather than 42 MB of refetch.
  static void clearMemoryCache() {
    _parsed.clear();
    _order.clear();
  }
}

/// A caller's grip on one load, so a screen can let go of it.
///
/// Cancelling is deliberately per-CALLER, not per-download: a second screen
/// still waiting on the same book keeps it going.
///
/// Founder, 18 Aug 2026: *"when tap a book it loads forever but never opens;
/// when click back n tap again it opens"*. The wait had no cancel at all, so
/// backing out of it left the original `await` running, and when that finally
/// resolved it popped whatever route happened to be on top and pushed a
/// reader over it.
///
/// When every caller has let go the transfer does stop — but the part-file
/// is KEPT, so the next tap resumes from where this one reached rather than
/// starting again at byte zero. That is what makes giving up cheap.
class EgwLoadHandle {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// One book being fetched and parsed, shared by everyone who asked for it.
class EgwLoadJob {
  EgwLoadJob(this.url) {
    unawaited(_run());
  }

  final String url;
  final _listeners = <_Listener>[];

  EgwLoadProgress _progress = EgwLoadProgress.idle;

  /// Where the download has got to, for a screen that joins late.
  EgwLoadProgress get progress => _progress;

  Future<EgwLoadResult> join({
    void Function(EgwLoadProgress)? onProgress,
    EgwLoadHandle? handle,
  }) {
    final listener = _Listener(onProgress, handle);
    _listeners.add(listener);
    // Whoever joins late still sees where the download has got to, rather
    // than a bar that sits at zero until the next chunk lands.
    onProgress?.call(_progress);
    return listener.completer.future;
  }

  void _emit(EgwLoadProgress p) {
    _progress = p;
    for (final l in List<_Listener>.of(_listeners)) {
      if (!l.cancelled) l.onProgress?.call(p);
    }
  }

  void _settle(EgwLoadResult result) {
    final waiting = List<_Listener>.of(_listeners);
    _listeners.clear();
    for (final l in waiting) {
      if (l.completer.isCompleted) continue;
      l.completer.complete(
        l.cancelled
            ? const EgwLoadResult.failed(EgwLoadFailure.cancelled)
            : result,
      );
    }
  }

  Future<void> _run() async {
    try {
      final bytes = await _bytes();
      if (bytes == null || bytes.isEmpty) {
        _settle(const EgwLoadResult.failed(EgwLoadFailure.network));
        return;
      }

      final size = _progress.total > 0 ? _progress.total : bytes.length;
      _emit(EgwLoadProgress(received: size, total: size, parsing: true));

      // Parsing a whole book blocks the UI isolate for long enough to drop
      // frames, and this runs while the reader is opening.
      final book = await compute(_parseIsolate, bytes);
      if (book == null || book.isEmpty) {
        // Bytes that will not parse are bytes worth throwing away: keeping
        // them means every future open fails the same way, for ever, with
        // no way for the member to get out of it.
        await _discard();
        _settle(const EgwLoadResult.failed(EgwLoadFailure.unreadable));
        return;
      }

      EgwBookService.remember(url, book);
      _settle(EgwLoadResult.ok(book));
    } on EgwLoadCancelled {
      _settle(const EgwLoadResult.failed(EgwLoadFailure.cancelled));
    } catch (e) {
      debugPrint('EgwBookService.load failed: $e');
      _settle(const EgwLoadResult.failed(EgwLoadFailure.network));
    } finally {
      EgwBookService.inFlight.remove(url);
    }
  }

  Future<void> _discard() async {
    try {
      final file = await EgwBookService.fileFor(url);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Cached bytes, downloading once if they are not already on disk.
  Future<Uint8List?> _bytes() async {
    final file = await EgwBookService.fileFor(url);

    if (await file.exists() && await file.length() > 0) {
      return file.readAsBytes();
    }

    final tmp = File('${file.path}.part');

    // RESUME. A half-finished download is kept, not thrown away, and the
    // next attempt asks for the rest of it.
    //
    // This is the half of "it never opens" that a timeout alone could not
    // fix. On a link where a megabyte takes longer than the ceiling, every
    // attempt used to time out, delete the part-file and start again from
    // byte zero — so on that connection the book could not be opened ever,
    // no matter how many times it was tapped. Resuming means each attempt
    // gets strictly closer, and the tap after the one that gave up is the
    // one that finishes.
    var have = 0;
    try {
      if (await tmp.exists()) have = await tmp.length();
    } catch (_) {}

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url));
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final resp = await req.close().timeout(_headerTimeout);

      // 206 means the server honoured the range and is sending the rest.
      // 200 means it ignored it and is sending the whole file, so what is
      // already on disk is worthless and appending to it would corrupt.
      final resuming = resp.statusCode == HttpStatus.partialContent;
      if (resp.statusCode != HttpStatus.ok && !resuming) {
        debugPrint('EgwBookService: HTTP ${resp.statusCode} for $url');
        return null;
      }
      if (!resuming) have = 0;

      final total = resp.contentLength > 0 ? resp.contentLength + have : 0;
      var received = have;
      _emit(EgwLoadProgress(received: received, total: total, parsing: false));

      sink = tmp.openWrite(mode: resuming ? FileMode.append : FileMode.write);

      // A STALL timeout, not a whole-transfer one.
      //
      // The ceiling this replaces was 60 seconds for the ENTIRE download,
      // which on a slow Zimbabwean mobile link is an ordinary time for a
      // megabyte — so it failed transfers that were working perfectly, and
      // from the outside that is the book never opening. What deserves to
      // fail is a connection that has stopped MOVING, and that is what this
      // measures: fine to be slow, not fine to be dead.
      await for (final chunk in resp.timeout(_stallTimeout)) {
        if (_allCancelled) throw const EgwLoadCancelled();
        sink.add(chunk);
        received += chunk.length;
        _emit(
          EgwLoadProgress(received: received, total: total, parsing: false),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;

      // media2.egwwritings.org TRUNCATES SILENTLY — the trap the seed
      // script already had to defend against, and this path never did. A
      // short file renamed into place is cached forever, fails to parse on
      // every future open, and silently drops the member back to the PDF
      // reader with no explanation. Note it is now KEPT rather than
      // deleted: a short file is a resumable file.
      final actual = await tmp.length();
      if (actual == 0 || (total > 0 && actual != total)) {
        debugPrint(
          'EgwBookService: incomplete download for $url '
          '($actual of $total bytes) — keeping it to resume',
        );
        return null;
      }

      await tmp.rename(file.path);
      return file.readAsBytes();
    } on TimeoutException {
      debugPrint('EgwBookService: stalled fetching $url');
      return null;
    } on SocketException catch (e) {
      debugPrint('EgwBookService: no connection for $url ($e)');
      return null;
    } on HttpException catch (e) {
      debugPrint('EgwBookService: transfer failed for $url ($e)');
      return null;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// True once every screen that asked for this book has walked away.
  bool get _allCancelled =>
      _listeners.isNotEmpty && _listeners.every((l) => l.cancelled);

  /// Long enough for a slow handshake on 3G, short enough that a dead
  /// connection surfaces as an error the reader can act on rather than a
  /// spinner that never resolves.
  static const _headerTimeout = Duration(seconds: 20);

  /// No bytes at all for this long means the connection is dead, not slow.
  static const _stallTimeout = Duration(seconds: 25);
}

class _Listener {
  _Listener(this.onProgress, this.handle);

  final void Function(EgwLoadProgress)? onProgress;
  final EgwLoadHandle? handle;
  final completer = Completer<EgwLoadResult>();

  bool get cancelled => handle?.isCancelled ?? false;
}

/// Top-level so it can run in a background isolate.
EgwBook? _parseIsolate(Uint8List bytes) {
  try {
    return EgwEpubParser.parse(bytes);
  } catch (_) {}
  return null;
}
