import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/library_item_model.dart';
import 'cache_service.dart';

/// Local, offline persistence for the Music player's personal state:
/// liked tracks, recently played, user playlists and playback preferences.
///
/// Mirrors [BiblePrefsService] — Hive-backed, per-device, no server round
/// trip, so everything works with no connection. Bumping [revision] lets any
/// open list rebuild when the user likes a track from the full player.
class MusicPrefsService {
  MusicPrefsService._();

  // ## Which of these survive a sign-out, and why
  //
  // [CacheService.clearUserData] deletes every key that does NOT start with
  // `pref:`, and it runs on sign-out. That is the RIGHT outcome for the four
  // keys below: likes, history, playlists and the resume queue are personal,
  // they live only on this device, and on a shared phone the next account
  // must not inherit them. They are deliberately left unprefixed so sign-out
  // clears them — this is a decision, not an oversight. Do not "tidy" them
  // into the `pref:` namespace.
  static const _kLiked = 'music_liked_v1'; // List<String> trackIds
  static const _kRecent = 'music_recent_v1'; // List<String> trackIds, newest first
  static const _kPlaylists = 'music_playlists_v1'; // Map<name, List<trackId>>
  static const _kLastQueue = 'music_last_queue_v1'; // JSON of last queue

  // Playback speed is a DEVICE setting, like volume — it describes how this
  // person listens, not who they are logged in as. Prefixed so sign-out
  // leaves it alone. Same reasoning as the downloads index in
  // [MusicDownloadService].
  static const _kSpeed = 'pref:music_speed_v1'; // double
  static const _kSpeedLegacy = 'music_speed_v1';

  /// How many recently-played entries to keep.
  static const _recentCap = 40;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _bump() => revision.value++;

  // ---- Liked --------------------------------------------------------------

  static Set<String> liked() {
    final raw = CacheService.readPref(_kLiked);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static bool isLiked(String trackId) => liked().contains(trackId);

  static Future<void> toggleLike(String trackId) async {
    final set = liked();
    set.contains(trackId) ? set.remove(trackId) : set.add(trackId);
    await CacheService.writePref(_kLiked, jsonEncode(set.toList()));
    _bump();
  }

  // ---- Recently played ----------------------------------------------------

  static List<String> recentIds() {
    final raw = CacheService.readPref(_kRecent);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Records [trackId] as just played — moved to the front, deduped, capped.
  static Future<void> notePlayed(String trackId) async {
    final list = recentIds().toList()..remove(trackId);
    list.insert(0, trackId);
    if (list.length > _recentCap) list.removeRange(_recentCap, list.length);
    await CacheService.writePref(_kRecent, jsonEncode(list));
    _bump();
  }

  static Future<void> clearRecent() async {
    await CacheService.writePref(_kRecent, jsonEncode(const <String>[]));
    _bump();
  }

  // ---- Playlists ----------------------------------------------------------

  /// name → ordered trackIds. Plain names as keys keeps the storage readable
  /// and means rename == delete + create, which is fine at this scale.
  static Map<String, List<String>> playlists() {
    final raw = CacheService.readPref(_kPlaylists);
    if (raw == null) return <String, List<String>>{};
    try {
      return (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(
          k.toString(),
          (v as List).map((e) => e.toString()).toList(),
        ),
      );
    } catch (_) {
      return <String, List<String>>{};
    }
  }

  static Future<void> _writePlaylists(Map<String, List<String>> map) async {
    await CacheService.writePref(_kPlaylists, jsonEncode(map));
    _bump();
  }

  static Future<void> createPlaylist(String name) async {
    final map = playlists();
    if (map.containsKey(name)) return;
    map[name] = <String>[];
    await _writePlaylists(map);
  }

  static Future<void> deletePlaylist(String name) async {
    final map = playlists()..remove(name);
    await _writePlaylists(map);
  }

  static Future<void> addToPlaylist(String name, String trackId) async {
    final map = playlists();
    final list = map[name] ?? <String>[];
    if (list.contains(trackId)) return;
    map[name] = [...list, trackId];
    await _writePlaylists(map);
  }

  static Future<void> removeFromPlaylist(String name, String trackId) async {
    final map = playlists();
    final list = map[name];
    if (list == null) return;
    map[name] = list.where((id) => id != trackId).toList();
    await _writePlaylists(map);
  }

  // ---- Playback preferences ----------------------------------------------

  static double speed() =>
      double.tryParse(CacheService.readPref(_kSpeed) ?? '') ??
      // Read the pre-prefix key once so an existing choice isn't reset by
      // the update that stops sign-out eating it.
      double.tryParse(CacheService.readPref(_kSpeedLegacy) ?? '') ??
      1.0;

  static Future<void> setSpeed(double v) => CacheService.writePref(
        _kSpeed,
        v.clamp(0.5, 2.0).toStringAsFixed(2),
      );

  // ---- Last queue (resume after restart) ---------------------------------

  /// Persists the active queue so reopening the app can restore the
  /// now-playing bar without the user re-picking a track.
  static Future<void> saveQueue(List<LibraryItem> items, int index) async {
    if (items.isEmpty) return;
    final payload = {
      'index': index,
      'items': [
        for (final i in items)
          {
            'id': i.id,
            'kind': i.kind,
            'title': i.title,
            'file_url': i.fileUrl,
            'author': i.author,
            'cover_url': i.coverUrl,
            'duration_seconds': i.durationSeconds,
          },
      ],
    };
    await CacheService.writePref(_kLastQueue, jsonEncode(payload));
  }

  /// Restores the last queue, or null when there isn't one.
  static (List<LibraryItem>, int)? lastQueue() {
    final raw = CacheService.readPref(_kLastQueue);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final items = (map['items'] as List)
          .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (items.isEmpty) return null;
      final index = (map['index'] as num?)?.toInt() ?? 0;
      return (items, index.clamp(0, items.length - 1));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearQueue() => CacheService.deletePref(_kLastQueue);
}
