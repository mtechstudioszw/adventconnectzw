import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';

/// First-run signup survey ("how did you hear about us"). Stored once per user
/// (patch_136) and read by the super admin in the User insights view.
class SignupSurveyService {
  SignupSurveyService._();
  static final SupabaseClient _client = Supabase.instance.client;

  // Local one-shot flag so we never nag a user who already answered or
  // dismissed it, without a DB round-trip on every launch.
  static const _kShownPref = 'signup_survey_shown_v1';

  static bool get shownLocally => CacheService.readPref(_kShownPref) == '1';

  static Future<void> markShown() => CacheService.writePref(_kShownPref, '1');

  /// True when we should prompt: signed in and not yet shown locally.
  static bool shouldPrompt() =>
      _client.auth.currentUser != null && !shownLocally;

  /// Save the response (upsert on user_id). Always marks shown locally so the
  /// prompt won't reappear even if the network write fails.
  static Future<void> submit({
    required String source,
    Map<String, dynamic> answers = const {},
  }) async {
    await markShown();
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('signup_surveys').upsert({
      'user_id': user.id,
      'source': source,
      'answers': answers,
    }, onConflict: 'user_id');
  }

  // ---- Super-admin insights ------------------------------------------------

  /// Counts by source. Empty for non-admins (RLS / RPC gated).
  static Future<List<({String source, int total})>> fetchSummary() async {
    final rows = await _client.rpc('admin_survey_summary');
    return (rows as List)
        .map((r) => (
              source: (r['source'] ?? 'Not specified').toString(),
              total: (r['total'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// Recent individual responses (super admin only via RLS). Joins the
  /// responder's name where readable.
  static Future<List<SurveyResponse>> fetchRecent({int limit = 100}) async {
    final rows = await _client
        .from('signup_surveys')
        .select('source, answers, created_at, profiles(full_name)')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => SurveyResponse.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}

class SurveyResponse {
  const SurveyResponse({
    required this.source,
    required this.name,
    required this.answers,
    required this.createdAt,
  });

  final String source;
  final String name;
  final Map<String, dynamic> answers;
  final DateTime createdAt;

  factory SurveyResponse.fromJson(Map<String, dynamic> json) {
    final p = json['profiles'];
    final pm = p is Map<String, dynamic> ? p : null;
    return SurveyResponse(
      source: (json['source'] ?? 'Not specified').toString(),
      name: (pm?['full_name'] as String?)?.trim().isNotEmpty == true
          ? pm!['full_name'] as String
          : 'Member',
      answers: (json['answers'] as Map?)?.cast<String, dynamic>() ?? const {},
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}
