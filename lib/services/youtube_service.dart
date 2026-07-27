import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/youtube_channel.dart';
import '../models/youtube_playlist.dart';
import '../models/youtube_video.dart';
import 'cache_service.dart';

/// A paused video the user can resume (from youtube_watch_history).
class ResumeItem {
  const ResumeItem({
    required this.video,
    required this.positionSeconds,
    required this.durationSeconds,
  });
  final YoutubeVideo video;
  final int positionSeconds;
  final int durationSeconds;

  /// 0–1 progress for the resume bar.
  double get progress =>
      durationSeconds > 0 ? (positionSeconds / durationSeconds).clamp(0, 1) : 0;
}

/// How far into a series the user has got, assembled from watch history
/// plus playlist membership — no table of its own.
class SeriesProgress {
  const SeriesProgress({
    required this.playlist,
    required this.reachedPosition,
  });

  final YoutubePlaylist playlist;

  /// Zero-based position of the furthest episode they've opened.
  final int reachedPosition;

  /// One-based episode number to resume at.
  int get nextEpisode => (reachedPosition + 2).clamp(1, playlist.itemCount);

  /// Zero-based index the series screen should resume from.
  int get nextPosition => reachedPosition + 1;

  /// "Episode 4 of 36"
  String get label => 'Episode $nextEpisode of ${playlist.itemCount}';

  double get progress => playlist.itemCount <= 0
      ? 0
      : (nextPosition / playlist.itemCount).clamp(0, 1);
}

/// A user's timestamped sermon note (youtube_video_notes).
class YoutubeNote {
  const YoutubeNote({
    required this.id,
    required this.videoId,
    required this.positionSeconds,
    required this.note,
    this.createdAt,
  });
  final int id;
  final String videoId;
  final int positionSeconds;
  final String note;
  final DateTime? createdAt;

  factory YoutubeNote.fromJson(Map<String, dynamic> j) => YoutubeNote(
        id: (j['id'] as num).toInt(),
        videoId: j['video_id'].toString(),
        positionSeconds: (j['position_seconds'] as num?)?.toInt() ?? 0,
        note: (j['note'] ?? '') as String,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'].toString())?.toLocal(),
      );
}

/// Read/write layer for the Watch feature. All CONTENT is read from the
/// metadata tables synced by the youtube-sync edge function; the app never
/// calls the YouTube API. Per-user state (bookmarks, history, notes) is
/// RLS-scoped to the signed-in user.
class YoutubeService {
  YoutubeService._();
  static final SupabaseClient _c = Supabase.instance.client;
  static String? get _uid => _c.auth.currentUser?.id;

  static const _feedKey = 'yt_feed_v1';
  static const _channelsKey = 'yt_channels_v1';
  static const _playlistsKey = 'yt_playlists_v1';
  static const _liveKey = 'yt_live_v1';
  // Rails caches — without these the Live now / Continue watching /
  // Upcoming rails started empty on every Watch open and "popped in"
  // ~2s later when the network returned.
  static const _liveNowKey = 'yt_live_now_v1';
  static const _upcomingKey = 'yt_upcoming_v1';
  static const _continueKey = 'yt_continue_v1';
  static const _savedIdsKey = 'yt_saved_ids_v1';
  static const _shortsKey = 'yt_shorts_v1';
  static const _seriesKey = 'yt_series_v1';
  static const _subsKey = 'yt_subs_v1';

  // ----------------------------- Feed --------------------------------
  /// Newest videos for the infinite Watch / Home feed. Excludes scheduled
  /// 'upcoming' items (those have their own rail). Page 0 is cached so the
  /// feed paints instantly + works offline.
  static Future<List<YoutubeVideo>> fetchFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _c
          .from('youtube_videos')
          .select()
          .neq('live_status', 'upcoming')
          .order('published_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 15));
      final list = (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
      if (offset == 0) {
        await CacheService.writeString(
          _feedKey,
          jsonEncode(list.map((v) => v.toJson()).toList()),
        );
      }
      return list;
    } catch (_) {
      if (offset == 0) return _cachedList(_feedKey);
      return const [];
    }
  }

  static DateTime? get feedCachedAt => CacheService.cachedAt(_feedKey);

  /// Synchronously-read cached feed (page 0) so the Watch tab can paint
  /// instantly on open, then refresh in the background — no spinner on a
  /// warm cache, no long shimmer on a slow network.
  static List<YoutubeVideo> cachedFeed() => _cachedList(_feedKey);

  static List<YoutubeVideo> _cachedList(String key) {
    final raw = CacheService.readStringStale(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // --------------------------- Categories ----------------------------
  static Future<List<YoutubePlaylist>> fetchPlaylists() async {
    try {
      final rows = await _c
          .from('youtube_playlists')
          .select()
          .eq('is_category', true)
          .order('sort_order');
      final list = (rows as List)
          .map((e) => YoutubePlaylist.fromJson(e as Map<String, dynamic>))
          .toList();
      await CacheService.writeString(
          _playlistsKey, jsonEncode(list.map((p) => p.toJson()).toList()));
      return list;
    } catch (_) {
      final raw = CacheService.readStringStale(_playlistsKey);
      if (raw == null) return const [];
      try {
        return (jsonDecode(raw) as List)
            .map((e) => YoutubePlaylist.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }

  /// Videos in a playlist (category), in playlist order. Two-step because
  /// youtube_playlist_items.video_id isn't a FK (items may reference a
  /// not-yet-synced video).
  static Future<List<YoutubeVideo>> fetchByPlaylist(
    String playlistId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final items = await _c
          .from('youtube_playlist_items')
          .select('video_id, position')
          .eq('playlist_id', playlistId)
          .order('position')
          .range(offset, offset + limit - 1);
      final ids = (items as List)
          .map((e) => (e as Map<String, dynamic>)['video_id'].toString())
          .toList();
      if (ids.isEmpty) return const [];
      final rows = await _c.from('youtube_videos').select().inFilter('video_id', ids);
      final byId = {
        for (final r in rows as List)
          (r as Map<String, dynamic>)['video_id'].toString():
              YoutubeVideo.fromJson(r)
      };
      // Preserve playlist order.
      return [for (final id in ids) if (byId[id] != null) byId[id]!];
    } catch (_) {
      return const [];
    }
  }

  // ----------------------------- Live --------------------------------
  /// The single currently-live video (for the Home LIVE banner), or null.
  /// Cached so the banner paints instantly on open instead of popping in
  /// late after the network call; the fresh result corrects it immediately.
  static Future<YoutubeVideo?> fetchCurrentLive() async {
    try {
      final rows = await _c.rpc('youtube_current_live');
      final list = rows as List;
      final v = list.isEmpty
          ? null
          : YoutubeVideo.fromJson(list.first as Map<String, dynamic>);
      await CacheService.writeString(
          _liveKey, v == null ? '' : jsonEncode(v.toJson()));
      return v;
    } catch (_) {
      return cachedLive();
    }
  }

  /// Last-known live video, read synchronously for an instant banner paint.
  static YoutubeVideo? cachedLive() {
    final raw = CacheService.readStringStale(_liveKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return YoutubeVideo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// ALL currently-live videos (one per live channel) — for the "Live now"
  /// rail when more than one channel is streaming at once.
  static Future<List<YoutubeVideo>> fetchLiveNow() async {
    try {
      final rows = await _c
          .from('youtube_videos')
          .select()
          .eq('live_status', 'live')
          .order('actual_start_at', ascending: false);
      final list = (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
      await CacheService.writeString(
        _liveNowKey,
        jsonEncode(list.map((v) => v.toJson()).toList()),
      );
      return list;
    } catch (_) {
      return cachedLiveNow();
    }
  }

  /// Cached "Live now" rail, readable synchronously for the first paint.
  static List<YoutubeVideo> cachedLiveNow() => _cachedList(_liveNowKey);

  /// Scheduled-but-not-started broadcasts (Upcoming rail).
  ///
  /// Only broadcasts still in the FUTURE. YouTube leaves `live_status`
  /// on 'upcoming' forever when a scheduled stream never airs, so without
  /// this filter the rail advertised dead 2023 prayer meetings as though
  /// they were about to start — every one of the 27 flagged rows was in
  /// the past. A countdown to a date that has already gone is worse than
  /// an empty rail.
  static Future<List<YoutubeVideo>> fetchUpcoming({int limit = 10}) async {
    try {
      final rows = await _c
          .from('youtube_videos')
          .select()
          .eq('live_status', 'upcoming')
          .gt('scheduled_start_at', DateTime.now().toUtc().toIso8601String())
          .order('scheduled_start_at')
          .limit(limit);
      final list = (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
      await CacheService.writeString(
        _upcomingKey,
        jsonEncode(list.map((v) => v.toJson()).toList()),
      );
      return list;
    } catch (_) {
      return cachedUpcoming();
    }
  }

  /// Cached Upcoming rail, readable synchronously for the first paint.
  static List<YoutubeVideo> cachedUpcoming() => _cachedList(_upcomingKey);

  // ----------------------------- Shorts ------------------------------
  /// Clips a minute or under — the vertical Shorts feed. Derived from
  /// `duration_seconds`, so this costs nothing in schema: ~4.7k of the
  /// synced videos already qualify.
  ///
  /// `duration_seconds > 0` matters: live and not-yet-processed rows
  /// store 0, and those would otherwise flood the rail.
  static Future<List<YoutubeVideo>> fetchShorts({
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final rows = await _c
          .from('youtube_videos')
          .select()
          .eq('live_status', 'none')
          .gt('duration_seconds', 0)
          .lte('duration_seconds', shortMaxSeconds)
          .order('published_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 15));
      final list = (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
      if (offset == 0) {
        await CacheService.writeString(
          _shortsKey,
          jsonEncode(list.map((v) => v.toJson()).toList()),
        );
      }
      return list;
    } catch (_) {
      return offset == 0 ? _cachedList(_shortsKey) : const [];
    }
  }

  /// Cached Shorts rail, readable synchronously for the first paint.
  static List<YoutubeVideo> cachedShorts() => _cachedList(_shortsKey);

  /// Longest a clip can be and still count as a Short.
  static const int shortMaxSeconds = 60;

  // ----------------------------- Series ------------------------------
  /// Playlists worth presenting as a bingeable series. Ordered by size —
  /// a two-item playlist isn't a series, so [minItems] filters the noise.
  ///
  /// 1,424 playlists and 22,585 items have been syncing since patch_154
  /// without any screen ever reading them.
  static Future<List<YoutubePlaylist>> fetchSeries({
    int limit = 40,
    int offset = 0,
    int minItems = 3,
  }) async {
    try {
      final rows = await _c
          .from('youtube_playlists')
          .select()
          .gte('item_count', minItems)
          .order('item_count', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 15));
      final list = (rows as List)
          .map((e) => YoutubePlaylist.fromJson(e as Map<String, dynamic>))
          .toList();
      if (offset == 0) {
        await CacheService.writeString(
          _seriesKey,
          jsonEncode(list.map((p) => p.toJson()).toList()),
        );
      }
      return list;
    } catch (_) {
      if (offset != 0) return const [];
      final raw = CacheService.readStringStale(_seriesKey);
      if (raw == null || raw.isEmpty) return const [];
      try {
        return (jsonDecode(raw) as List)
            .map((e) => YoutubePlaylist.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }

  /// Cached series shelf, readable synchronously for the first paint.
  static List<YoutubePlaylist> cachedSeries() {
    final raw = CacheService.readStringStale(_seriesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => YoutubePlaylist.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// One channel's own series, for the channel page.
  static Future<List<YoutubePlaylist>> fetchChannelSeries(
    String channelId, {
    int limit = 20,
    int minItems = 3,
  }) async {
    try {
      final rows = await _c
          .from('youtube_playlists')
          .select()
          .eq('channel_id', channelId)
          .gte('item_count', minItems)
          .order('item_count', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => YoutubePlaylist.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// One playlist's metadata (for the series screen header).
  static Future<YoutubePlaylist?> fetchPlaylist(String playlistId) async {
    try {
      final row = await _c
          .from('youtube_playlists')
          .select()
          .eq('playlist_id', playlistId)
          .maybeSingle();
      return row == null ? null : YoutubePlaylist.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Series the user is partway through — "Episode 4 of 36".
  ///
  /// Built from data that already exists: take what they've been
  /// watching, find which playlists those videos belong to, and report
  /// how far in they got. No new table.
  static Future<List<SeriesProgress>> fetchContinueSeries({
    int limit = 6,
  }) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final history = await _c
          .from('youtube_watch_history')
          .select('video_id, watched_at')
          .eq('user_id', uid)
          .order('watched_at', ascending: false)
          .limit(40);
      final ids = [
        for (final r in history as List)
          (r as Map<String, dynamic>)['video_id'].toString(),
      ];
      if (ids.isEmpty) return const [];

      // Which series do those videos belong to, and at what position?
      final items = await _c
          .from('youtube_playlist_items')
          .select('playlist_id, video_id, position')
          .inFilter('video_id', ids);

      // Keep the FURTHEST position reached in each series.
      final bestPosition = <String, int>{};
      for (final e in items as List) {
        final m = e as Map<String, dynamic>;
        final pid = m['playlist_id'].toString();
        final pos = (m['position'] as num?)?.toInt() ?? 0;
        if (pos > (bestPosition[pid] ?? -1)) bestPosition[pid] = pos;
      }
      if (bestPosition.isEmpty) return const [];

      final playlists = await _c
          .from('youtube_playlists')
          .select()
          .inFilter('playlist_id', bestPosition.keys.toList());

      final out = <SeriesProgress>[];
      for (final r in playlists as List) {
        final p = YoutubePlaylist.fromJson(r as Map<String, dynamic>);
        final reached = bestPosition[p.playlistId] ?? 0;
        // Finished series shouldn't nag; nor should a one-item playlist.
        if (p.itemCount < 2 || reached >= p.itemCount - 1) continue;
        out.add(SeriesProgress(playlist: p, reachedPosition: reached));
      }
      out.sort((a, b) => b.playlist.itemCount.compareTo(a.playlist.itemCount));
      return out.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The videos of a series from a given position onward, so "continue"
  /// resumes at the next episode instead of episode one.
  static Future<List<YoutubeVideo>> fetchSeriesFrom(
    String playlistId, {
    required int fromPosition,
    int limit = 20,
  }) =>
      fetchByPlaylist(playlistId, limit: limit, offset: fromPosition);

  // -------------------------- Sabbath lineup -------------------------
  /// Worship-shaped viewing for the Sabbath hours. Nothing new is
  /// stored — this is the existing search RPC pointed at worship
  /// keywords, with anything short filtered out so the lineup is
  /// services and sermons rather than clips.
  static Future<List<YoutubeVideo>> fetchSabbathLineup({
    int limit = 12,
  }) async {
    const terms = ['divine service', 'sabbath worship', 'sermon'];
    final seen = <String>{};
    final out = <YoutubeVideo>[];
    for (final term in terms) {
      final rows = await search(term, limit: limit);
      for (final v in rows) {
        if (v.durationSeconds <= shortMaxSeconds) continue;
        if (!seen.add(v.videoId)) continue;
        out.add(v);
      }
      if (out.length >= limit) break;
    }
    return out.take(limit).toList();
  }

  // ---------------------------- Channels -----------------------------
  static Future<List<YoutubeChannel>> fetchChannels() async {
    try {
      final rows = await _c.from('youtube_channels').select().order('title');
      final list = (rows as List)
          .map((e) => YoutubeChannel.fromJson(e as Map<String, dynamic>))
          .toList();
      await CacheService.writeString(
          _channelsKey, jsonEncode(list.map((c) => c.toJson()).toList()));
      return list;
    } catch (_) {
      final raw = CacheService.readStringStale(_channelsKey);
      if (raw == null) return const [];
      try {
        return (jsonDecode(raw) as List)
            .map((e) => YoutubeChannel.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }

  static Future<List<YoutubeVideo>> fetchByChannel(
    String channelId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _c
          .from('youtube_videos')
          .select()
          .eq('channel_id', channelId)
          .order('published_at', ascending: false)
          .range(offset, offset + limit - 1);
      return (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // --------------------------- Single video --------------------------
  static Future<YoutubeVideo?> fetchVideo(String videoId) async {
    try {
      final row = await _c
          .from('youtube_videos')
          .select()
          .eq('video_id', videoId)
          .maybeSingle();
      return row == null ? null : YoutubeVideo.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  // ----------------------------- Search ------------------------------
  static Future<List<YoutubeVideo>> search(
    String query, {
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final rows = await _c.rpc('youtube_search', params: {
        'p_query': query,
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------- Up next ------------------------------
  static Future<List<YoutubeVideo>> upNext(
    String videoId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _c.rpc('youtube_up_next', params: {
        'p_video_id': videoId,
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ------------------------- Subscriptions ---------------------------
  /// Channel ids the signed-in user follows (patch_164).
  ///
  /// Every call here degrades to the cache on failure, so the app keeps
  /// working unchanged if patch_164 hasn't been applied yet.
  static Future<Set<String>> fetchSubscriptionIds() async {
    final uid = _uid;
    if (uid == null) return <String>{};
    try {
      final rows = await _c
          .from('youtube_subscriptions')
          .select('channel_id')
          .eq('user_id', uid);
      final ids = {
        for (final r in rows as List)
          (r as Map<String, dynamic>)['channel_id'].toString(),
      };
      await CacheService.writeString(_subsKey, jsonEncode(ids.toList()));
      return ids;
    } catch (_) {
      return cachedSubscriptionIds();
    }
  }

  /// Cached follow list, readable synchronously for the first paint.
  static Set<String> cachedSubscriptionIds() {
    final raw = CacheService.readStringStale(_subsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> setSubscribed(String channelId, bool subscribed) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      if (subscribed) {
        await _c.from('youtube_subscriptions').upsert(
          {'user_id': uid, 'channel_id': channelId},
          onConflict: 'user_id,channel_id',
        );
      } else {
        await _c
            .from('youtube_subscriptions')
            .delete()
            .eq('user_id', uid)
            .eq('channel_id', channelId);
      }
      // Keep the synchronous cache honest so the next paint is correct.
      final ids = cachedSubscriptionIds();
      subscribed ? ids.add(channelId) : ids.remove(channelId);
      await CacheService.writeString(_subsKey, jsonEncode(ids.toList()));
    } catch (_) {/* best effort */}
  }

  /// Newest videos from the channels the user follows.
  static Future<List<YoutubeVideo>> fetchSubscriptionFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    if (_uid == null) return const [];
    try {
      final rows = await _c.rpc('youtube_subscription_feed', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // --------------------------- Bookmarks -----------------------------
  static Future<Set<String>> fetchBookmarkIds() async {
    final uid = _uid;
    if (uid == null) return <String>{};
    try {
      final rows =
          await _c.from('youtube_bookmarks').select('video_id').eq('user_id', uid);
      final ids = {
        for (final r in rows as List)
          (r as Map<String, dynamic>)['video_id'].toString()
      };
      await CacheService.writeString(_savedIdsKey, jsonEncode(ids.toList()));
      return ids;
    } catch (_) {
      return cachedBookmarkIds();
    }
  }

  /// Cached saved-video ids, readable synchronously for the first paint.
  static Set<String> cachedBookmarkIds() {
    final raw = CacheService.readStringStale(_savedIdsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<List<YoutubeVideo>> fetchBookmarks() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _c
          .from('youtube_bookmarks')
          .select('created_at, youtube_videos(*)')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => YoutubeVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> setBookmarked(String videoId, bool saved) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      if (saved) {
        await _c.from('youtube_bookmarks').upsert(
          {'user_id': uid, 'video_id': videoId},
          onConflict: 'user_id,video_id',
        );
      } else {
        await _c
            .from('youtube_bookmarks')
            .delete()
            .eq('user_id', uid)
            .eq('video_id', videoId);
      }
    } catch (_) {/* best effort */}
  }

  // -------------------------- Watch history --------------------------
  /// Save the resume position (debounce calls from the player).
  static Future<void> recordProgress(
    String videoId, {
    required int positionSeconds,
    required int durationSeconds,
    bool completed = false,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _c.from('youtube_watch_history').upsert({
        'user_id': uid,
        'video_id': videoId,
        'position_seconds': positionSeconds,
        'duration_seconds': durationSeconds,
        'completed': completed,
        'watched_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,video_id');
    } catch (_) {/* best effort */}
  }

  static Future<List<ResumeItem>> fetchContinueWatching({int limit = 12}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _c
          .from('youtube_watch_history')
          .select('position_seconds, duration_seconds, watched_at, youtube_videos(*)')
          .eq('user_id', uid)
          .eq('completed', false)
          .order('watched_at', ascending: false)
          .limit(limit);
      final out = <ResumeItem>[];
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        if (m['youtube_videos'] == null) continue;
        out.add(ResumeItem(
          video: YoutubeVideo.fromJson(m),
          positionSeconds: (m['position_seconds'] as num?)?.toInt() ?? 0,
          durationSeconds: (m['duration_seconds'] as num?)?.toInt() ?? 0,
        ));
      }
      await CacheService.writeString(
        _continueKey,
        jsonEncode([
          for (final item in out)
            {
              'position_seconds': item.positionSeconds,
              'duration_seconds': item.durationSeconds,
              'video': item.video.toJson(),
            },
        ]),
      );
      return out;
    } catch (_) {
      return cachedContinueWatching();
    }
  }

  /// Cached Continue-watching rail, readable synchronously.
  static List<ResumeItem> cachedContinueWatching() {
    final raw = CacheService.readStringStale(_continueKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          ResumeItem(
            video: YoutubeVideo.fromJson(
              (e as Map<String, dynamic>)['video'] as Map<String, dynamic>,
            ),
            positionSeconds: (e['position_seconds'] as num?)?.toInt() ?? 0,
            durationSeconds: (e['duration_seconds'] as num?)?.toInt() ?? 0,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Drop a video from the Keep-watching shelf without losing the fact
  /// that it was watched — marking it complete is what the shelf already
  /// filters on, so no new column is needed.
  static Future<void> dismissFromContinueWatching(String videoId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _c
          .from('youtube_watch_history')
          .update({'completed': true})
          .eq('user_id', uid)
          .eq('video_id', videoId);
    } catch (_) {/* best effort */}
  }

  /// Resume position (seconds) for one video, or 0.
  static Future<int> resumePosition(String videoId) async {
    final uid = _uid;
    if (uid == null) return 0;
    try {
      final row = await _c
          .from('youtube_watch_history')
          .select('position_seconds, completed')
          .eq('user_id', uid)
          .eq('video_id', videoId)
          .maybeSingle();
      if (row == null) return 0;
      final m = row;
      if (m['completed'] == true) return 0;
      return (m['position_seconds'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------ Notes ------------------------------
  static Future<List<YoutubeNote>> fetchNotes(String videoId) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _c
          .from('youtube_video_notes')
          .select()
          .eq('user_id', uid)
          .eq('video_id', videoId)
          .order('position_seconds');
      return (rows as List)
          .map((e) => YoutubeNote.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> addNote(
      String videoId, int positionSeconds, String note) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _c.from('youtube_video_notes').insert({
        'user_id': uid,
        'video_id': videoId,
        'position_seconds': positionSeconds,
        'note': note,
      });
    } catch (_) {/* best effort */}
  }

  static Future<void> deleteNote(int id) async {
    try {
      await _c.from('youtube_video_notes').delete().eq('id', id);
    } catch (_) {/* best effort */}
  }

  // ------------------------- Channel submission ----------------------
  static Future<void> submitChannel({
    required String link,
    String? name,
    String? contact,
    String? note,
  }) async {
    await _c.rpc('submit_youtube_channel', params: {
      'p_link': link,
      'p_name': name,
      'p_contact': contact,
      'p_note': note,
    });
  }
}
