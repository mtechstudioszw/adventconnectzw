import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/library_item_model.dart';
import 'cache_service.dart';

/// Real offline reading for EGW books (Library PDFs).
///
/// The deliberate twin of [MusicDownloadService], and written to mirror it
/// closely on purpose — same directory strategy, same index shape, same
/// `.part` discipline — because that service already solved every one of
/// these problems once and a second, subtly different implementation is how
/// they drift apart.
///
/// ## Why this had to exist
///
/// Until now `egw_tab.dart` opened `PdfViewerScreen(url: item.fileUrl)`,
/// streaming the book from Supabase on EVERY open. The only download in that
/// screen was [DownloadService.downloadAndShare], which hands a copy to the
/// OS share sheet — it does not keep anything the app can later read. So the
/// Library was unreadable offline in exactly the tab that now holds the most
/// content: the shelf went from 2 books to 61 (~80 MB) in August 2026, all of
/// it re-fetched over Zimbabwean mobile data every single time.
///
/// Files live at `<appSupport>/egw/<itemId>.pdf` and never expire; the reader
/// removes them explicitly. Application *support*, not cache, so the OS never
/// reclaims a book someone downloaded on purpose before a journey.
class EgwDownloadService {
  EgwDownloadService._();

  /// The `pref:` prefix is load-bearing, not decoration.
  ///
  /// `CacheService.writePref` does NOT add it, and `clearUserData()` deletes
  /// every key that lacks it on EVERY sign-out. An unprefixed index here
  /// would silently orphan every downloaded book the first time someone
  /// signed out — which is precisely how the music index broke before it was
  /// moved under `pref:`.
  ///
  /// Kept OUT of the user-scoped `pref:music_u:` style namespace for the same
  /// reason music is: a downloaded file belongs to the DEVICE, not to the
  /// account that happened to fetch it. Two members sharing a phone should
  /// not re-download the Conflict of the Ages series each.
  static const _kIndex = 'pref:egw_downloads_v1';

  /// Pre-`pref:` key. Read once as a fallback so an install that predates
  /// this service keeps its files; rewritten under [_kIndex] on first write.
  static const _kIndexLegacy = 'egw_downloads_v1';

  /// Bumps whenever the downloaded set changes, so tabs and the reader can
  /// rebuild their "available offline" affordances without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Directory? _dir;
  static final Map<String, Completer<bool>> _active = {};
  static final Map<String, String> _pathCache = {};

  static Future<Directory> _egwDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/egw');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  // ---- Index --------------------------------------------------------------

  static Map<String, String> _index() {
    final raw =
        CacheService.readPref(_kIndex) ?? CacheService.readPref(_kIndexLegacy);
    if (raw == null) return <String, String>{};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> _writeIndex(Map<String, String> map) async {
    await CacheService.writePref(_kIndex, jsonEncode(map));
    revision.value++;
  }

  static bool isDownloaded(String itemId) => _index().containsKey(itemId);

  static Set<String> downloadedIds() => _index().keys.toSet();

  static bool isDownloading(String itemId) => _active.containsKey(itemId);

  /// Absolute path of the downloaded book, or null when not downloaded.
  ///
  /// Verified lazily: if the file vanished the index entry is dropped, so the
  /// UI stops promising an offline copy that is not there.
  static Future<String?> localPath(String itemId) async {
    final name = _index()[itemId];
    if (name == null) return null;
    final dir = await _egwDir();
    final file = File('${dir.path}/$name');
    if (await file.exists() && await file.length() > 0) return file.path;
    final map = _index()..remove(itemId);
    await _writeIndex(map);
    return null;
  }

  /// Synchronous path, valid only after [warmPaths] has resolved this id.
  ///
  /// The PDF reader opens on a synchronous build, so it cannot await a disk
  /// check without flashing the network path first.
  static String? cachedPathSync(String itemId) => _pathCache[itemId];

  /// Resolves and memoises local paths for [items]. Call before building the
  /// shelf so each row knows whether it can offer "Read offline".
  static Future<void> warmPaths(Iterable<LibraryItem> items) async {
    for (final item in items) {
      final path = await localPath(item.id);
      if (path != null) {
        _pathCache[item.id] = path;
      } else {
        _pathCache.remove(item.id);
      }
    }
  }

  // ---- Download / remove --------------------------------------------------

  /// Downloads [item]'s PDF. Returns true on success.
  ///
  /// Safe to call twice: an in-flight download for the same id is joined
  /// rather than restarted, and an already-downloaded book returns true.
  static Future<bool> download(LibraryItem item) async {
    if (isDownloaded(item.id)) return true;
    final existing = _active[item.id];
    if (existing != null) return existing.future;

    final job = Completer<bool>();
    _active[item.id] = job;

    File? partial;
    try {
      final dir = await _egwDir();
      // Download to `.part` first. A book interrupted halfway is a valid PDF
      // prefix, so without this an aborted transfer would be indexed as
      // complete and then open as a corrupt file with no way to tell why.
      partial = File('${dir.path}/${item.id}.pdf.part');
      final target = File('${dir.path}/${item.id}.pdf');

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(item.fileUrl));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode}');
      }
      await resp.pipe(partial.openWrite());
      if (!await partial.exists() || await partial.length() == 0) {
        throw const FileSystemException('empty download');
      }
      await partial.rename(target.path);

      final map = _index()..[item.id] = '${item.id}.pdf';
      await _writeIndex(map);
      _pathCache[item.id] = target.path;
      job.complete(true);
      return true;
    } catch (e) {
      debugPrint('EgwDownloadService.download failed for ${item.id}: $e');
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      job.complete(false);
      return false;
    } finally {
      _active.remove(item.id);
    }
  }

  /// Removes the downloaded copy. Idempotent.
  static Future<void> remove(String itemId) async {
    final name = _index()[itemId];
    _pathCache.remove(itemId);
    if (name != null) {
      try {
        final dir = await _egwDir();
        final file = File('${dir.path}/$name');
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('EgwDownloadService.remove failed for $itemId: $e');
      }
    }
    final map = _index()..remove(itemId);
    await _writeIndex(map);
  }

  /// Total bytes held on disk, for a "Downloads" line in settings.
  static Future<int> bytesOnDisk() async {
    try {
      final dir = await _egwDir();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
