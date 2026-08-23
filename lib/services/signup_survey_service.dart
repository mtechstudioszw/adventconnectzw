import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';

/// First-run signup survey ("how did you hear about us"). Stored once per user
/// (patch_136) and read by the super admin in the User insights view.
class SignupSurveyService {
  SignupSurveyService._();
  static final SupabaseClient _client = Supabase.instance.client;

  // Local one-shot flag so we never nag a user who already answered or
  // dismissed it, without a DB round-trip on every launch.
  //
  // Two things about this key are load-bearing, and v1 got both wrong:
  //
  //  1. **It starts with `pref:`.** `CacheService.writePref` does NOT add
  //     that prefix for you, and `clearUserData()` deletes every key that
  //     lacks it on sign-out. v1 was `signup_survey_shown_v1`, so signing
  //     out threw the flag away and the next launch asked again. That is
  //     the "it keeps asking me, I already filled it in" report.
  //
  //  2. **It carries the user id.** Prefixing alone would have swung the
  //     bug the other way: the flag would survive sign-out for the PHONE,
  //     so a second member signing in on the same handset would be counted
  //     as already-answered and never asked at all. Namespacing keeps both
  //     properties — this account is never asked twice, a different account
  //     reads a different key, finds nothing, and gets its turn.
  //
  // Same shape as `biometric_enabled:<id>` in SecureStorageService, and for
  // the same reason. Bumped to v2 so nobody inherits a v1 value.
  static String _shownKey(String userId) =>
      'pref:signup_survey_shown_v2:$userId';

  static bool get shownLocally {
    final id = _client.auth.currentUser?.id;
    if (id == null) return false;
    return CacheService.readPref(_shownKey(id)) == '1';
  }

  static Future<void> markShown() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return;
    await CacheService.writePref(_shownKey(id), '1');
  }

  /// Only ask accounts that are genuinely new. Anything older than this is
  /// an existing member who reinstalled, cleared data, or just signed in
  /// on a second device — asking them "how did you hear about us?" months
  /// later is the bug people reported.
  static const _newAccountWindow = Duration(days: 14);

  /// Whether to prompt this launch.
  ///
  /// Was a one-line local-flag check, which is why existing members kept
  /// getting the sheet on every fresh install: the flag lives in local
  /// storage, so a reinstall looks exactly like a brand-new account. Now
  /// it also requires the account to actually BE new, and checks whether
  /// an answer already exists server-side (readable since patch_180).
  static Future<bool> shouldPrompt() async {
    final user = _client.auth.currentUser;
    if (user == null || shownLocally) return false;

    // Old account, new device → never ask.
    final created = DateTime.tryParse(user.createdAt);
    if (created != null &&
        DateTime.now().toUtc().difference(created.toUtc()) >
            _newAccountWindow) {
      await markShown();
      return false;
    }

    // Already answered before (other device / previous install).
    try {
      final row = await _client
          .from('signup_surveys')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (row != null) {
        await markShown();
        return false;
      }
    } catch (_) {
      // Offline or unreadable — better to ask a new account twice than
      // to lose the answer entirely.
    }
    return true;
  }

  /// Save the response (upsert on user_id).
  ///
  /// Marks "shown" only AFTER the write lands. It used to mark first and
  /// swallow the failure, so when the write was rejected the answer was
  /// gone for good and the prompt never came back to retry. Every
  /// non-admin submission WAS being rejected — `signup_surveys` had no
  /// SELECT policy for members, and PostgREST's upsert returns the row,
  /// so RLS raised 42501 on the RETURNING. See patch_180.
  static Future<void> submit({
    required String source,
    Map<String, dynamic> answers = const {},
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('signup_surveys').upsert({
      'user_id': user.id,
      'source': source,
      'answers': answers,
    }, onConflict: 'user_id');
    await markShown();
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
