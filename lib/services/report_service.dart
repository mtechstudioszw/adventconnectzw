import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Table 25 (reports). All in-app "Report this …" flows funnel
/// here so the moderation queue stays canonical.
class ReportService {
  ReportService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'reports';

  /// `contentType` is one of: 'seller', 'product', 'event', 'church',
  /// 'prayer', 'prayer_comment', 'job', 'profile', 'notice', 'message',
  /// 'post', 'comment', 'story', 'news', 'group', 'user', 'page'. The column is
  /// free text (no CHECK), so admin-web shows whatever is sent.
  static Future<void> submit({
    required String contentType,
    required String contentId,
    required String reason,
    String? details,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to report content.');
    }
    try {
      await _client.from(_table).insert({
        'reported_by': user.id,
        'content_type': contentType,
        'content_id': contentId,
        'reason': reason,
        'details': ?details?.trim(),
      });
    } on PostgrestException catch (e) {
      // patch_279 keeps one open report per member per item. Reporting it
      // again is already done, not a failure.
      if (e.code == '23505') return;
      rethrow;
    }
  }
}
