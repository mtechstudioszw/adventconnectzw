import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/friendship_model.dart';
import '../models/post_comment_model.dart';
import '../models/post_model.dart';
import '../models/story_model.dart';

/// All Supabase calls behind the Facebook-style home feed:
///   - posts            (CRUD + likes + comments)
///   - stories          (24h ephemeral)
///   - friendships      (request / accept / decline)
class FeedService {
  FeedService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static const _postsTable = 'posts';
  static const _likesTable = 'post_likes';
  static const _commentsTable = 'post_comments';
  static const _storiesTable = 'stories';
  static const _friendshipsTable = 'friendships';

  static String? get _viewerId => _client.auth.currentUser?.id;

  // ===================================================================
  // POSTS
  // ===================================================================

  /// Newest-first page of posts. Each row joins the author profile and
  /// embeds likes + comments so the card has everything it needs in one
  /// round-trip.
  static Future<List<Post>> fetchFeed({int limit = 40}) async {
    final response = await _client
        .from(_postsTable)
        .select(
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .order('created_at', ascending: false)
        .limit(limit);
    return (response as List)
        .map((row) => Post.fromJson(
              row as Map<String, dynamic>,
              viewerId: _viewerId,
            ))
        .toList();
  }

  static Future<Post> createPost({
    String? body,
    String? imageUrl,
    PostVisibility visibility = PostVisibility.public,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post.');
    }
    final cleanBody = body?.trim();
    if ((cleanBody == null || cleanBody.isEmpty) &&
        (imageUrl == null || imageUrl.isEmpty)) {
      throw ArgumentError('Either body or imageUrl must be non-empty.');
    }
    final inserted = await _client
        .from(_postsTable)
        .insert({
          'author_id': user.id,
          if (cleanBody != null && cleanBody.isNotEmpty) 'body': cleanBody,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
          'visibility': visibility == PostVisibility.friendsOnly
              ? 'friends_only'
              : 'public',
        })
        .select(
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .single();
    return Post.fromJson(inserted, viewerId: _viewerId);
  }

  static Future<void> deletePost(String postId) async {
    await _client.from(_postsTable).delete().eq('id', postId);
  }

  /// Body-text search across the feed. Respects visibility via RLS so
  /// friends-only posts are only returned to friends / the author.
  static Future<List<Post>> searchPosts(String query, {int limit = 20}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final response = await _client
        .from(_postsTable)
        .select(
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .ilike('body', '%$term%')
        .order('created_at', ascending: false)
        .limit(limit);
    return (response as List)
        .map((row) => Post.fromJson(
              row as Map<String, dynamic>,
              viewerId: _viewerId,
            ))
        .toList();
  }

  /// Update the body and/or visibility of a post the viewer owns.
  /// RLS already restricts updates to the author so we don't have to
  /// guard client-side. Returns the refreshed Post.
  static Future<Post> updatePost(
    String postId, {
    String? body,
    PostVisibility? visibility,
  }) async {
    final patch = <String, dynamic>{};
    if (body != null) patch['body'] = body.trim().isEmpty ? null : body.trim();
    if (visibility != null) {
      patch['visibility'] = visibility == PostVisibility.friendsOnly
          ? 'friends_only'
          : 'public';
    }
    if (patch.isEmpty) {
      throw ArgumentError('Nothing to update.');
    }
    final updated = await _client
        .from(_postsTable)
        .update(patch)
        .eq('id', postId)
        .select(
          '*, '
          'profiles!posts_author_id_fkey(id, full_name, profile_photo_url), '
          'post_likes(user_id), '
          'post_comments(id)',
        )
        .single();
    return Post.fromJson(updated, viewerId: _viewerId);
  }

  // ---- Likes --------------------------------------------------------

  static Future<void> likePost(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to like.');
    }
    await _client.from(_likesTable).upsert(
      {'post_id': postId, 'user_id': user.id},
      onConflict: 'post_id,user_id',
      ignoreDuplicates: true,
    );
  }

  static Future<void> unlikePost(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from(_likesTable)
        .delete()
        .eq('post_id', postId)
        .eq('user_id', user.id);
  }

  // ---- Comments -----------------------------------------------------

  static Future<List<PostComment>> fetchComments(String postId) async {
    final response = await _client
        .from(_commentsTable)
        .select(
          '*, '
          'profiles!post_comments_author_id_fkey(id, full_name, profile_photo_url)',
        )
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return (response as List)
        .map((row) => PostComment.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<PostComment> addComment({
    required String postId,
    required String body,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to comment.');
    }
    final clean = body.trim();
    if (clean.isEmpty) {
      throw ArgumentError('Comment body cannot be empty.');
    }
    final inserted = await _client
        .from(_commentsTable)
        .insert({
          'post_id': postId,
          'author_id': user.id,
          'body': clean,
        })
        .select(
          '*, '
          'profiles!post_comments_author_id_fkey(id, full_name, profile_photo_url)',
        )
        .single();
    return PostComment.fromJson(inserted);
  }

  // ===================================================================
  // STORIES
  // ===================================================================

  /// All active stories (RLS filters expired rows). One row per story —
  /// the UI groups by author when rendering the rail.
  static Future<List<Story>> fetchStories() async {
    final response = await _client
        .from(_storiesTable)
        .select(
          '*, '
          'profiles!stories_author_id_fkey(id, full_name, profile_photo_url)',
        )
        .order('created_at', ascending: false)
        .limit(200);
    return (response as List)
        .map((row) => Story.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Story> createStory({
    required String mediaUrl,
    String? caption,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to post a story.');
    }
    final inserted = await _client
        .from(_storiesTable)
        .insert({
          'author_id': user.id,
          'media_url': mediaUrl,
          if (caption != null && caption.trim().isNotEmpty)
            'caption': caption.trim(),
        })
        .select(
          '*, '
          'profiles!stories_author_id_fkey(id, full_name, profile_photo_url)',
        )
        .single();
    return Story.fromJson(inserted);
  }

  // ===================================================================
  // FRIENDSHIPS
  // ===================================================================

  /// Every friendship row that involves the viewer, in either direction.
  /// The home screen uses this to decide which suggestion cards to show
  /// the right CTA on ("Add friend" / "Pending" / "Accept").
  static Future<List<Friendship>> fetchMyFriendships() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_friendshipsTable)
        .select()
        .or('requester_id.eq.${user.id},addressee_id.eq.${user.id}');
    return (response as List)
        .map((row) => Friendship.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Count of incoming pending requests for the badge on the chat
  /// bubble / bottom nav.
  static Future<int> pendingRequestCount() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;
    final response = await _client
        .from(_friendshipsTable)
        .select('id')
        .eq('addressee_id', user.id)
        .eq('status', 'pending');
    return (response as List).length;
  }

  static Future<Friendship> sendRequest(String addresseeId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to send a friend request.');
    }
    if (user.id == addresseeId) {
      throw ArgumentError('Cannot friend yourself.');
    }
    final inserted = await _client
        .from(_friendshipsTable)
        .insert({
          'requester_id': user.id,
          'addressee_id': addresseeId,
          'status': 'pending',
        })
        .select()
        .single();
    return Friendship.fromJson(inserted);
  }

  static Future<void> acceptRequest(String friendshipId) async {
    await _client
        .from(_friendshipsTable)
        .update({'status': 'accepted'}).eq('id', friendshipId);
  }

  static Future<void> declineRequest(String friendshipId) async {
    await _client
        .from(_friendshipsTable)
        .update({'status': 'declined'}).eq('id', friendshipId);
  }

  static Future<void> removeFriendship(String friendshipId) async {
    await _client.from(_friendshipsTable).delete().eq('id', friendshipId);
  }
}
