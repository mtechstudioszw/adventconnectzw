/// A single YouTube video's METADATA (never the media). Mirrors the
/// public.youtube_videos row (patch_154). The app reads these from
/// Supabase and plays the video via the official IFrame player by id —
/// nothing is downloaded or re-hosted.
class YoutubeVideo {
  const YoutubeVideo({
    required this.videoId,
    required this.channelId,
    required this.channelTitle,
    required this.title,
    this.channelThumbUrl,
    this.description,
    this.thumbnailUrl,
    this.publishedAt,
    this.durationSeconds = 0,
    this.kind = 'video',
    this.liveStatus = 'none',
    this.scheduledStartAt,
    this.actualStartAt,
    this.viewCount,
  });

  final String videoId;
  final String channelId;
  final String channelTitle;
  final String? channelThumbUrl;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final DateTime? publishedAt;
  final int durationSeconds;

  /// 'video' | 'live' | 'upcoming'
  final String kind;

  /// 'none' | 'live' | 'upcoming' | 'ended'
  final String liveStatus;
  final DateTime? scheduledStartAt;
  final DateTime? actualStartAt;
  final int? viewCount;

  bool get isLive => liveStatus == 'live';
  bool get isUpcoming => liveStatus == 'upcoming';

  /// mm:ss or h:mm:ss; empty for live (no fixed duration).
  String get durationLabel {
    final s = durationSeconds;
    if (s <= 0 || isLive) return '';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  /// "2d ago" style relative time of publication.
  String get publishedLabel {
    final d = publishedAt;
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  /// "1.2K views" style count.
  String get viewsLabel {
    final v = viewCount;
    if (v == null) return '';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M views';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K views';
    return '$v views';
  }

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  factory YoutubeVideo.fromJson(Map<String, dynamic> json) {
    // A nested youtube_videos(*) (from a playlist-item join) unwraps here.
    final v = json['youtube_videos'] is Map<String, dynamic>
        ? json['youtube_videos'] as Map<String, dynamic>
        : json;
    return YoutubeVideo(
      videoId: v['video_id'].toString(),
      channelId: (v['channel_id'] ?? '').toString(),
      channelTitle: (v['channel_title'] ?? '') as String,
      channelThumbUrl: v['channel_thumb_url'] as String?,
      title: (v['title'] ?? '') as String,
      description: v['description'] as String?,
      thumbnailUrl: v['thumbnail_url'] as String?,
      publishedAt: _date(v['published_at']),
      durationSeconds: _int(v['duration_seconds']),
      kind: (v['kind'] ?? 'video') as String,
      liveStatus: (v['live_status'] ?? 'none') as String,
      scheduledStartAt: _date(v['scheduled_start_at']),
      actualStartAt: _date(v['actual_start_at']),
      viewCount: v['view_count'] == null ? null : _int(v['view_count']),
    );
  }

  Map<String, dynamic> toJson() => {
        'video_id': videoId,
        'channel_id': channelId,
        'channel_title': channelTitle,
        'channel_thumb_url': channelThumbUrl,
        'title': title,
        'description': description,
        'thumbnail_url': thumbnailUrl,
        'published_at': publishedAt?.toIso8601String(),
        'duration_seconds': durationSeconds,
        'kind': kind,
        'live_status': liveStatus,
        'scheduled_start_at': scheduledStartAt?.toIso8601String(),
        'actual_start_at': actualStartAt?.toIso8601String(),
        'view_count': viewCount,
      };
}
