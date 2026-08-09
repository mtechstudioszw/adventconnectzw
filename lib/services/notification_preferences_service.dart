import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Table 22 (notification_preferences). Per-church preference
/// rows let users mute or downgrade churches without unfollowing them.
class NotificationPreferencesService {
  NotificationPreferencesService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'notification_preferences';

  static Future<List<NotificationPreference>> fetchMyPreferences() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final response = await _client
        .from(_table)
        .select('*, churches(name)')
        .eq('user_id', user.id);
    return (response as List)
        .map(
          (row) => NotificationPreference.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  /// Update the level for a specific church. `level` is one of
  /// 'all' / 'urgent' / 'none' — we translate to the three booleans
  /// the DB uses so older queries keep working.
  static Future<void> setChurchLevel({
    required String churchId,
    required String level,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to change notification settings.');
    }
    await _client.from(_table).upsert({
      'user_id': user.id,
      'church_id': churchId,
      'all_notifications': level == 'all',
      'urgent_only': level == 'urgent',
      'none': level == 'none',
    }, onConflict: 'user_id,church_id');
  }

  /// Fetch the signed-in user's per-category toggles from
  /// `profiles.notif_categories` (patch_018). Falls back to all-on
  /// when the row is missing or the column hasn't been migrated yet.
  static Future<NotificationCategoryPrefs> fetchCategories() async {
    final user = _client.auth.currentUser;
    if (user == null) return NotificationCategoryPrefs.defaults;
    try {
      final row = await _client
          .from('profiles')
          .select('notif_categories')
          .eq('id', user.id)
          .maybeSingle();
      final raw = row?['notif_categories'];
      if (raw is Map) {
        return NotificationCategoryPrefs.fromJson(
          Map<String, dynamic>.from(raw),
        );
      }
      return NotificationCategoryPrefs.defaults;
    } catch (_) {
      return NotificationCategoryPrefs.defaults;
    }
  }

  /// Save the full per-category bundle. Best-effort — failures are
  /// swallowed so a flaky network doesn't fight the user's toggle.
  static Future<void> saveCategories(NotificationCategoryPrefs prefs) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('profiles')
          .update({'notif_categories': prefs.toJson()})
          .eq('id', user.id);
    } catch (_) {
      // best-effort; UI keeps the optimistic value either way.
    }
  }
}

/// Per-category notification preferences stored on the auth user's
/// profile row (`profiles.notif_categories`, patch_018). Distinct
/// from per-church levels above — this is the Settings screen's
/// global "events / prayers / messages / marketplace / announcements"
/// toggles. The `notify-fcm` Edge Function reads the same column to
/// short-circuit pushes for muted categories.
class NotificationCategoryPrefs {
  const NotificationCategoryPrefs({
    this.events = true,
    this.prayers = true,
    this.messages = true,
    this.marketplace = true,
    this.announcements = true,
    this.news = true,
    this.social = true,
    this.watch = true,
    this.quiz = true,
  });

  final bool events;
  final bool prayers;
  final bool messages;
  final bool marketplace;
  final bool announcements;
  final bool news;

  /// Likes & comments on your posts/comments (engagement pushes).
  final bool social;

  /// Watch-tab pushes: new uploads + live streams from followed
  /// channels. notify-fcm reads the same JSON key server-side.
  final bool watch;

  /// Quiz REMINDERS — the nightly "the arena is open" nudge and the "you
  /// have been overtaken" one.
  ///
  /// NOT live-match invites from a real person: those stay on `type =
  /// 'quiz_challenge'`, which maps to no category and always sends.
  /// Somebody asking to play you right now is closer to a friend request
  /// than to marketing, and a switch labelled "reminders" must not
  /// silently swallow it.
  final bool quiz;

  static const defaults = NotificationCategoryPrefs();

  factory NotificationCategoryPrefs.fromJson(Map<String, dynamic> json) {
    bool read(String key, bool fallback) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        if (value.toLowerCase() == 'false') return false;
        if (value.toLowerCase() == 'true') return true;
      }
      return fallback;
    }

    return NotificationCategoryPrefs(
      events: read('events', true),
      prayers: read('prayers', true),
      messages: read('messages', true),
      marketplace: read('marketplace', true),
      announcements: read('announcements', true),
      news: read('news', true),
      social: read('social', true),
      watch: read('watch', true),
      quiz: read('quiz', true),
    );
  }

  Map<String, dynamic> toJson() => {
    'events': events,
    'prayers': prayers,
    'messages': messages,
    'marketplace': marketplace,
    'announcements': announcements,
    'news': news,
    'social': social,
    'watch': watch,
    'quiz': quiz,
  };

  NotificationCategoryPrefs copyWith({
    bool? events,
    bool? prayers,
    bool? messages,
    bool? marketplace,
    bool? announcements,
    bool? news,
    bool? social,
    bool? watch,
    bool? quiz,
  }) {
    return NotificationCategoryPrefs(
      events: events ?? this.events,
      prayers: prayers ?? this.prayers,
      messages: messages ?? this.messages,
      marketplace: marketplace ?? this.marketplace,
      announcements: announcements ?? this.announcements,
      news: news ?? this.news,
      social: social ?? this.social,
      watch: watch ?? this.watch,
      quiz: quiz ?? this.quiz,
    );
  }
}

class NotificationPreference {
  const NotificationPreference({
    required this.id,
    required this.churchId,
    required this.churchName,
    required this.level,
  });

  final String id;
  final String churchId;
  final String churchName;
  final String level; // 'all' / 'urgent' / 'none'

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    final church = json['churches'];
    final churchMap = church is Map<String, dynamic> ? church : null;
    String level = 'all';
    if (json['none'] == true) {
      level = 'none';
    } else if (json['urgent_only'] == true) {
      level = 'urgent';
    }
    return NotificationPreference(
      id: json['id'].toString(),
      churchId: (json['church_id'] ?? '').toString(),
      churchName: (churchMap?['name'] as String?) ?? 'Church',
      level: level,
    );
  }
}
