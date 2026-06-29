/// A YouTube playlist — doubles as a Watch-tab category chip
/// (public.youtube_playlists, patch_154).
class YoutubePlaylist {
  const YoutubePlaylist({
    required this.playlistId,
    required this.channelId,
    required this.title,
    this.thumbnailUrl,
    this.itemCount = 0,
    this.isCategory = true,
    this.sortOrder = 0,
  });

  final String playlistId;
  final String channelId;
  final String title;
  final String? thumbnailUrl;
  final int itemCount;
  final bool isCategory;
  final int sortOrder;

  factory YoutubePlaylist.fromJson(Map<String, dynamic> json) => YoutubePlaylist(
        playlistId: json['playlist_id'].toString(),
        channelId: (json['channel_id'] ?? '').toString(),
        title: (json['title'] ?? '') as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
        isCategory: json['is_category'] != false,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'playlist_id': playlistId,
        'channel_id': channelId,
        'title': title,
        'thumbnail_url': thumbnailUrl,
        'item_count': itemCount,
        'is_category': isCategory,
        'sort_order': sortOrder,
      };
}
