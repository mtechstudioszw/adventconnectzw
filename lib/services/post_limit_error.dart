import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps the server-side `enforce_daily_post_limit` trigger raise into
/// a user-friendly error and a per-section label so screens can show
/// "3 prayers today — try again in 24 hours" instead of the raw
/// Postgres "Daily post limit reached" string.
///
/// The trigger (database/patch_036_daily_post_limits.sql) raises with
/// HINT set to the action key (`post_product`, `post_prayer`, etc.)
/// and the message starts with the literal "Daily post limit". We
/// look for that prefix on PostgrestException and translate.
class PostLimitError {
  PostLimitError._();

  /// True when [error] is the server-side daily post limit raise OR
  /// the friendly exception we already wrapped it in (so re-running
  /// the same error through `matches` after `guard` still detects it).
  static bool matches(Object error) {
    if (error is _PostLimitException) return true;
    if (error is PostgrestException) {
      return error.message.toLowerCase().contains('daily post limit');
    }
    final s = error.toString().toLowerCase();
    return s.contains('daily post limit') ||
        s.contains('try again in 24 hours');
  }

  /// Human-readable description of [section] for the snackbar.
  /// Falls through to a generic copy for unknown sections so a future
  /// trigger we forget to register here still gets a sensible message.
  static String friendly(PostSection section) {
    switch (section) {
      case PostSection.product:
        return 'You\'ve listed 3 products today. Try again in 24 hours.';
      case PostSection.prayer:
        return 'You\'ve shared 3 prayers today. Try again in 24 hours.';
      case PostSection.adventNews:
        return 'You\'ve posted 3 news items today. Try again in 24 hours.';
      case PostSection.job:
        return 'You\'ve posted 3 jobs today. Try again in 24 hours.';
      case PostSection.feedPost:
        return 'You\'ve shared 3 posts today. Try again in 24 hours.';
      case PostSection.story:
        return 'You\'ve posted 3 stories today. Try again in 24 hours.';
      case PostSection.event:
        return 'You\'ve posted 3 events today. Try again in 24 hours.';
    }
  }

  /// Wraps [action] and rethrows a friendly message when the trigger
  /// raised the daily-limit exception. All other errors pass through.
  static Future<T> guard<T>(
    PostSection section,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (e) {
      if (matches(e)) {
        throw _PostLimitException(friendly(section));
      }
      rethrow;
    }
  }
}

enum PostSection { product, prayer, adventNews, job, feedPost, story, event }

class _PostLimitException implements Exception {
  _PostLimitException(this.message);
  final String message;

  @override
  String toString() => message;
}
