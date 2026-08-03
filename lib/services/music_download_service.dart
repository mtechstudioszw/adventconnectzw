import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/library_item_model.dart';
import 'cache_service.dart';

/// Real offline downloads for Library audio (Music + Audio Bible).
///
/// Distinct from [DownloadService], which only hands a file to the OS share
/// sheet ("save a copy"). This one keeps the file INSIDE the app's own
/// directory and records it in an index, so [MusicPlayerService] can play
/// straight off disk with no network — the "Downloaded" experience users
/// expect from a music app.
///
/// Files live at `<appSupport>/music/<trackId>.<ext>` and never expire; the
/// user removes them explicitly. The index (`music_downloads_v1`) maps
/// trackId → relative filename so a reinstall-free app update keeps them.
class MusicDownloadService {
  MusicDownloadService._();

  /// The `pref:` prefix is load-bearing, not decoration.
  ///
  /// [CacheService.clearUserData] deletes **every** key that does not start
  /// with `pref:`, and it runs on every sign-out. This index used to be a
  /// bare `music_downloads_v1`, so signing out wiped the app's entire memory
  /// of what had been downloaded: the files stayed on disk, orphaned and
  /// invisible, the "Downloaded" filter went to zero, every Save button
  /// reverted to un-saved and playback silently went back to streaming. That
  /// is the "download for offline doesn't work" report — it worked, then a
  /// sign-out ate the receipts.
  ///
  /// Downloads are DEVICE-level: the bytes belong to the phone, not to the
  /// account, so this key stays out of the user-scoped `pref:music_u:`
  /// namespace that [SessionReset] clears by prefix.
  ///
  /// Same trap as the sound settings — see the `settings-read-unloaded-statics`
  /// note and [QuizSfx].
  static const _kIndex = 'pref:music_downloads_v1';

  /// The pre-fix key, read once so nobody who already had downloads loses
  /// them on the update that fixes this.
  static const _kIndexLegacy = 'music_downloads_v1';

  /// Bumped whenever a download completes or is removed, so lists that show a
  /// downloaded badge can rebuild without polling.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// trackId → 0.0–1.0 while a download is in flight. Absent when idle.
  static final ValueNotifier<Map<String, double>> progress =
      ValueNotifier<Map<String, double>>(const {});

  static Directory? _dir;
  static final Map<String, CancelableDownload> _active = {};

  /// `<appSupport>/music`, created on first use. Application *support*
  /// (not cache) so the OS never reclaims a track the user downloaded on
  /// purpose.
  static Future<Directory> _musicDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/music');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  // ---- Index --------------------------------------------------------------

  static Map<String, String> _index() {
    final raw = CacheService.readPref(_kIndex) ??
        // One-time fallback for anyone whose index is still under the old
        // unprefixed key AND who has not signed out since. Rewritten under
        // the new key by the first [_writeIndex].
        CacheService.readPref(_kIndexLegacy);
    if (raw == null) return <String, String>{};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Moves a legacy index under the `pref:` key so it stops being deleted on
  /// sign-out. Cheap and idempotent; called from `main()` at startup.
  ///
  /// Also re-adopts orphans: files that are still sitting in the music
  /// directory from before the key was fixed, whose index entry a sign-out
  /// already deleted. Without this, everything the founder downloaded before
  /// this build stays invisible and keeps occupying storage forever.
  static Future<void> migrate() async {
    final legacy = CacheService.readPref(_kIndexLegacy);
    if (legacy != null) {
      if (CacheService.readPref(_kIndex) == null) {
        await CacheService.writePref(_kIndex, legacy);
      }
      await CacheService.deletePref(_kIndexLegacy);
    }
    await _adoptOrphans();
  }

  /// Rebuilds index entries for completed files the index has forgotten.
  ///
  /// A filename is `<trackId>.<ext>`, and `.part` files are ignored — an
  /// interrupted transfer must never be adopted as a complete track.
  static Future<void> _adoptOrphans() async {
    try {
      final dir = await _musicDir();
      if (!await dir.exists()) return;
      final map = _index();
      var changed = false;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.endsWith('.part')) continue;
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        final trackId = name.substring(0, dot);
        if (map.containsKey(trackId)) continue;
        if (await entity.length() <= 0) continue;
        map[trackId] = name;
        changed = true;
      }
      if (changed) await _writeIndex(map);
    } catch (_) {
      // Best-effort housekeeping — never let it break startup.
    }
  }

  static Future<void> _writeIndex(Map<String, String> map) async {
    await CacheService.writePref(_kIndex, jsonEncode(map));
    revision.value++;
  }

  /// True when [trackId] has a completed local copy. Synchronous so list rows
  /// can read it during build.
  static bool isDownloaded(String trackId) => _index().containsKey(trackId);

  /// How many tracks are held offline.
  static int get downloadedCount => _index().length;

  /// Every downloaded track id.
  static Set<String> downloadedIds() => _index().keys.toSet();

  /// True while [trackId] is actively downloading.
  static bool isDownloading(String trackId) => _active.containsKey(trackId);

  /// Absolute path of the downloaded file, or null when not downloaded.
  ///
  /// Verified lazily: if the file vanished (OS cleanup, manual delete) the
  /// index entry is dropped so the UI stops claiming it's available offline.
  static Future<String?> localPath(String trackId) async {
    final name = _index()[trackId];
    if (name == null) return null;
    final dir = await _musicDir();
    final file = File('${dir.path}/$name');
    if (await file.exists() && await file.length() > 0) return file.path;
    final map = _index()..remove(trackId);
    await _writeIndex(map);
    return null;
  }

  /// Synchronous best-effort path used when building an audio source. Returns
  /// null unless [warmPaths] has already resolved this track.
  static String? cachedPathSync(String trackId) => _pathCache[trackId];
  static final Map<String, String> _pathCache = {};

  /// Resolves and memoises local paths for [items] so queue building can pick
  /// local files synchronously. Call before handing a queue to the player.
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

  /// Downloads [item] to local storage. Returns true on success.
  ///
  /// Safe to call twice — an in-flight download for the same id is joined
  /// rather than restarted, and an already-downloaded track returns true
  /// immediately.
  static Future<bool> download(LibraryItem item) async {
    if (isDownloaded(item.id)) return true;
    final existing = _active[item.id];
    if (existing != null) return existing.done;

    final job = CancelableDownload();
    _active[item.id] = job;
    _setProgress(item.id, 0);

    try {
      final dir = await _musicDir();
      final ext = _extOf(item.fileUrl);
      // Download to a .part file first so an interrupted transfer can never
      // be mistaken for a complete track.
      final partial = File('${dir.path}/${item.id}.$ext.part');
      final target = File('${dir.path}/${item.id}.$ext');

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(item.fileUrl));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode}');
      }

      final total = resp.contentLength;
      var received = 0;
      final sink = partial.openWrite();
      await for (final chunk in resp) {
        if (job.cancelled) break;
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) _setProgress(item.id, received / total);
      }
      await sink.flush();
      await sink.close();
      client.close();

      if (job.cancelled) {
        if (await partial.exists()) await partial.delete();
        job.complete(false);
        return false;
      }

      await partial.rename(target.path);
      final map = _index()..[item.id] = '${item.id}.$ext';
      await _writeIndex(map);
      _pathCache[item.id] = target.path;
      job.complete(true);
      return true;
    } catch (e) {
      debugPrint('MusicDownloadService.download failed for ${item.id}: $e');
      job.complete(false);
      return false;
    } finally {
      _active.remove(item.id);
      _clearProgress(item.id);
    }
  }

  /// Aborts an in-flight download.
  static void cancel(String trackId) => _active[trackId]?.cancelled = true;

  /// Deletes the local copy of [trackId].
  static Future<void> remove(String trackId) async {
    final name = _index()[trackId];
    if (name == null) return;
    try {
      final dir = await _musicDir();
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Index removal below still applies — a stale file is harmless.
    }
    _pathCache.remove(trackId);
    final map = _index()..remove(trackId);
    await _writeIndex(map);
  }

  /// Total bytes held offline, for the "Downloads" storage row.
  static Future<int> totalBytes() async {
    try {
      final dir = await _musicDir();
      if (!await dir.exists()) return 0;
      var sum = 0;
      await for (final e in dir.list()) {
        if (e is File) sum += await e.length();
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  /// Deletes every downloaded track.
  static Future<void> removeAll() async {
    try {
      final dir = await _musicDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {
      // Fall through — clearing the index is what the UI reads.
    }
    _pathCache.clear();
    await _writeIndex(<String, String>{});
  }

  static void _setProgress(String id, double value) {
    progress.value = {...progress.value, id: value.clamp(0.0, 1.0)};
  }

  static void _clearProgress(String id) {
    final next = {...progress.value}..remove(id);
    progress.value = next;
  }

  static String _extOf(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'mp3';
    final ext = path.substring(dot + 1).toLowerCase();
    return ext.length > 5 ? 'mp3' : ext;
  }
}

/// Handle for an in-flight download so a second caller can await the same
/// job and the user can cancel it.
class CancelableDownload {
  final Completer<bool> _completer = Completer<bool>();
  bool cancelled = false;

  Future<bool> get done => _completer.future;

  void complete(bool ok) {
    if (!_completer.isCompleted) _completer.complete(ok);
  }
}
