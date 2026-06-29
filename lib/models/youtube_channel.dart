/// A monitored YouTube channel's metadata (public.youtube_channels, patch_154).
class YoutubeChannel {
  const YoutubeChannel({
    required this.channelId,
    required this.title,
    this.handle,
    this.thumbnailUrl,
    this.isLive = false,
    this.liveVideoId,
    this.subscriberCount,
  });

  final String channelId;
  final String title;
  final String? handle;
  final String? thumbnailUrl;
  final bool isLive;
  final String? liveVideoId;
  final int? subscriberCount;

  factory YoutubeChannel.fromJson(Map<String, dynamic> json) => YoutubeChannel(
        channelId: json['channel_id'].toString(),
        title: (json['title'] ?? '') as String,
        handle: json['handle'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        isLive: json['is_live'] == true,
        liveVideoId: json['live_video_id'] as String?,
        subscriberCount: json['subscriber_count'] == null
            ? null
            : (json['subscriber_count'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'channel_id': channelId,
        'title': title,
        'handle': handle,
        'thumbnail_url': thumbnailUrl,
        'is_live': isLive,
        'live_video_id': liveVideoId,
        'subscriber_count': subscriberCount,
      };
}
