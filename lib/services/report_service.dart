import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Table 25 (reports). All in-app "Report this …" flows funnel
/// here so the moderation queue stays canonical.
class ReportService {
  ReportService._();

  static final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'reports';

  /// `contentType` is one of: 'seller', 'product', 'event', 'church',
  /// 'prayer', 'job', 'profile', 'notice', 'message'.
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
    await _client.from(_table).insert({
      'reported_by': user.id,
      'content_type': contentType,
      'content_id': contentId,
      'reason': reason,
      'details': ?details?.trim(),
    });
  }
}
